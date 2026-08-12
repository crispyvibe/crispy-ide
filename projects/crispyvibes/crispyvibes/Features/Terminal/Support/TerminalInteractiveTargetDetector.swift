import Foundation

struct TerminalInteractiveCell {
    let text: String
    let width: Int
    let payload: String?
}

struct TerminalFileSystemTarget: Equatable {
    let url: URL
    let line: Int?
    let column: Int?

    var standardizedFileURL: URL {
        url.standardizedFileURL
    }
}

struct TerminalInteractiveTargetSegment: Equatable {
    let row: Int
    let columns: Range<Int>
}

struct TerminalInteractiveTargetHit: Equatable {
    let target: TerminalInteractiveTarget
    let row: Int
    let columns: Range<Int>
    let segments: [TerminalInteractiveTargetSegment]

    init(
        target: TerminalInteractiveTarget,
        row: Int,
        columns: Range<Int>,
        segments: [TerminalInteractiveTargetSegment]? = nil
    ) {
        self.target = target
        self.row = row
        self.columns = columns
        self.segments = segments ?? [TerminalInteractiveTargetSegment(row: row, columns: columns)]
    }
}

protocol TerminalInteractiveTextGrid {
    var cols: Int { get }
    var rows: Int { get }

    func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell?
    func isWrappedContinuation(upperRow: Int, lowerRow: Int) -> Bool?
}

extension TerminalInteractiveTextGrid {
    func isWrappedContinuation(upperRow: Int, lowerRow: Int) -> Bool? {
        nil
    }
}

enum TerminalInteractiveTarget: Equatable {
    case link(String)
    case fileSystem(TerminalFileSystemTarget)

    var contextMenuTitle: String {
        switch self {
        case .link:
            return "Open Link"
        case .fileSystem(let target):
            return target.url.hasDirectoryPath ? "Open Folder" : "Open File"
        }
    }

    var hoverHint: String {
        switch self {
        case .link:
            return "Cmd-click to open link"
        case .fileSystem(let target):
            return target.url.hasDirectoryPath ? "Cmd-click to open folder" : "Cmd-click to open file"
        }
    }
}

enum TerminalInteractiveTargetDetector {
    private struct LineComponent {
        let text: String
        let columns: Range<Int>
        let row: Int
    }

    private struct TokenMatch {
        let rawToken: String
        let columns: Range<Int>
        let rows: Set<Int>
        let segments: [TerminalInteractiveTargetSegment]
    }

    private struct TargetMatch {
        let target: TerminalInteractiveTarget
        let candidate: String
    }

    private static let rawURLSchemes: Set<String> = [
        "file",
        "ftp",
        "ftps",
        "http",
        "https",
        "mailto",
        "vscode",
        "ws",
        "wss",
        "xcode"
    ]
    private static let commonBareFileNames: Set<String> = [
        "Brewfile",
        "Dockerfile",
        "Gemfile",
        "Justfile",
        "LICENSE",
        "Makefile",
        "Podfile",
        "Procfile",
        "README",
        "Rakefile",
        "Vagrantfile"
    ]
    private static let bareFileReferenceCharacters = CharacterSet(charactersIn: "._-+@%~=,")
    private static let maximumInteractiveTokenLength = 512
    private static let maximumCorrelatedRows = 8
    private static let maximumRawPathWords = 6
    private static let maximumCandidateCount = 24
    private static let continuationLeadingColumnLimit = 1
    private static let continuationMatchingIndentLimit = 8
    private static let continuationTrailingColumnTolerance = 2

    static func detectTarget(
        in grid: any TerminalInteractiveTextGrid,
        visibleColumn: Int,
        visibleRow: Int,
        currentDirectory: URL?
    ) -> TerminalInteractiveTarget? {
        detectHit(
            in: grid,
            visibleColumn: visibleColumn,
            visibleRow: visibleRow,
            currentDirectory: currentDirectory
        )?.target
    }

    static func detectHit(
        in grid: any TerminalInteractiveTextGrid,
        visibleColumn: Int,
        visibleRow: Int,
        currentDirectory: URL?
    ) -> TerminalInteractiveTargetHit? {
        guard visibleColumn >= 0, visibleColumn < grid.cols else { return nil }
        guard visibleRow >= 0, visibleRow < grid.rows else { return nil }

        if let payload = grid.cell(atColumn: visibleColumn, row: visibleRow)?.payload,
           let payloadValue = linkFromPayload(payload) {
            let target = detectTargetWithCandidate(
                fromRawToken: payloadValue,
                currentDirectory: currentDirectory,
                allowsRawWhitespace: false
            )?.target ?? .link(payloadValue)
            return TerminalInteractiveTargetHit(
                target: target,
                row: visibleRow,
                columns: visibleColumn..<(visibleColumn + 1)
            )
        }

        // When an adapter cannot provide exact wrap metadata, correlate only bounded
        // edge cases: the upper row reaches the trailing edge and the lower row
        // either starts near column zero or preserves a shallow TUI content indent.
        if let correlatedComponents = correlatedComponents(
            in: grid,
            clickedRow: visibleRow
        ),
           let hit = detectHit(
               in: correlatedComponents,
               visibleColumn: visibleColumn,
               visibleRow: visibleRow,
               currentDirectory: currentDirectory,
               requiresMultipleRows: true
           ) {
            return hit
        }

        let lineComponents = meaningfulComponents(
            buildLineComponents(in: grid, visibleRow: visibleRow)
        )
        return detectHit(
            in: lineComponents,
            visibleColumn: visibleColumn,
            visibleRow: visibleRow,
            currentDirectory: currentDirectory,
            requiresMultipleRows: false
        )
    }

    static func detectTarget(
        fromRawToken rawToken: String,
        currentDirectory: URL?
    ) -> TerminalInteractiveTarget? {
        detectTargetWithCandidate(
            fromRawToken: rawToken,
            currentDirectory: currentDirectory,
            allowsRawWhitespace: true
        )?.target
    }

    private static func detectHit(
        in components: [LineComponent],
        visibleColumn: Int,
        visibleRow: Int,
        currentDirectory: URL?,
        requiresMultipleRows: Bool
    ) -> TerminalInteractiveTargetHit? {
        guard let clickedIndex = componentIndex(
            at: visibleColumn,
            row: visibleRow,
            in: components
        ) else {
            return nil
        }

        let syntaxMatch = syntaxAwareTokenMatch(
            around: clickedIndex,
            clickedRow: visibleRow,
            in: components
        )
        let eligibleSyntaxMatch = syntaxMatch.flatMap {
            !requiresMultipleRows || $0.rows.count > 1 ? $0 : nil
        }
        var ordinaryFileMatch: (match: TargetMatch, token: TokenMatch)?

        if let eligibleSyntaxMatch,
           let match = detectTargetWithCandidate(
               fromRawToken: eligibleSyntaxMatch.rawToken,
               currentDirectory: currentDirectory,
               allowsRawWhitespace: false
           ) {
            switch match.target {
            case .link:
                return makeHit(match: match, token: eligibleSyntaxMatch, row: visibleRow)
            case .fileSystem:
                if containsQuotedOrEscapedWhitespace(eligibleSyntaxMatch.rawToken) {
                    return makeHit(match: match, token: eligibleSyntaxMatch, row: visibleRow)
                }
                ordinaryFileMatch = (match, eligibleSyntaxMatch)
            }
        }

        let rawMatches = rawWhitespaceTokenMatches(
            around: clickedIndex,
            clickedRow: visibleRow,
            in: components
        ).filter { !requiresMultipleRows || $0.rows.count > 1 }

        var fileMatches: [(match: TargetMatch, token: TokenMatch)] = []
        if let ordinaryFileMatch {
            fileMatches.append(ordinaryFileMatch)
        }
        for rawMatch in rawMatches {
            guard let match = detectTargetWithCandidate(
                fromRawToken: rawMatch.rawToken,
                currentDirectory: currentDirectory,
                allowsRawWhitespace: true
            ), case .fileSystem = match.target else {
                continue
            }
            fileMatches.append((match, rawMatch))
        }

        var distinctTargets: [TerminalInteractiveTarget] = []
        for fileMatch in fileMatches where !distinctTargets.contains(fileMatch.match.target) {
            distinctTargets.append(fileMatch.match.target)
        }
        guard distinctTargets.count <= 1 else {
            // Multiple existing interpretations make an unquoted whitespace expansion unsafe.
            return nil
        }
        if let preferred = fileMatches.max(by: { $0.token.rawToken.count < $1.token.rawToken.count }) {
            return makeHit(match: preferred.match, token: preferred.token, row: visibleRow)
        }

        return nil
    }

    private static func makeHit(
        match: TargetMatch,
        token: TokenMatch,
        row: Int
    ) -> TerminalInteractiveTargetHit {
        let columns: Range<Int>
        let segments: [TerminalInteractiveTargetSegment]
        if token.rows.count == 1 {
            columns = narrowedColumns(
                rawToken: token.rawToken,
                matchedCandidate: match.candidate,
                fullRange: token.columns
            )
            segments = [TerminalInteractiveTargetSegment(row: row, columns: columns)]
        } else {
            columns = token.columns
            segments = token.segments
        }
        return TerminalInteractiveTargetHit(
            target: match.target,
            row: row,
            columns: columns,
            segments: segments
        )
    }

    private static func detectTargetWithCandidate(
        fromRawToken rawToken: String,
        currentDirectory: URL?,
        allowsRawWhitespace: Bool
    ) -> TargetMatch? {
        let trimmedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty,
              (trimmedToken as NSString).length <= maximumInteractiveTokenLength,
              mayContainInteractiveTarget(trimmedToken, allowsRawWhitespace: allowsRawWhitespace) else {
            return nil
        }

        for candidate in candidateTokens(from: trimmedToken) {
            if let fileURLTarget = parseFileURL(from: candidate) {
                return TargetMatch(target: fileURLTarget, candidate: candidate)
            }
            if let link = parseLink(from: candidate) {
                return TargetMatch(target: .link(link), candidate: candidate)
            }
            if let fileReference = parseFileReference(
                from: candidate,
                currentDirectory: currentDirectory,
                allowsRawWhitespace: allowsRawWhitespace
            ) {
                return TargetMatch(target: fileReference, candidate: candidate)
            }
        }

        return nil
    }

    private static func narrowedColumns(
        rawToken: String,
        matchedCandidate: String,
        fullRange: Range<Int>
    ) -> Range<Int> {
        guard matchedCandidate.count < rawToken.count,
              let candidateRange = rawToken.range(of: matchedCandidate) else {
            return fullRange
        }
        let prefixStripped = rawToken.distance(from: rawToken.startIndex, to: candidateRange.lowerBound)
        let suffixStripped = rawToken.distance(from: candidateRange.upperBound, to: rawToken.endIndex)
        let newLower = fullRange.lowerBound + prefixStripped
        let newUpper = fullRange.upperBound - suffixStripped
        guard newLower < newUpper else { return fullRange }
        return newLower..<newUpper
    }

    private static func correlatedComponents(
        in grid: any TerminalInteractiveTextGrid,
        clickedRow: Int
    ) -> [LineComponent]? {
        var lowerRow = clickedRow
        var upperRow = clickedRow

        while lowerRow > 0,
              upperRow - lowerRow + 1 < maximumCorrelatedRows,
              isConservativeContinuation(in: grid, upperRow: lowerRow - 1, lowerRow: lowerRow) {
            lowerRow -= 1
        }
        while upperRow + 1 < grid.rows,
              upperRow - lowerRow + 1 < maximumCorrelatedRows,
              isConservativeContinuation(in: grid, upperRow: upperRow, lowerRow: upperRow + 1) {
            upperRow += 1
        }

        guard lowerRow != upperRow else { return nil }
        var components: [LineComponent] = []
        var logicalCharacterCount = 0
        for row in lowerRow...upperRow {
            let rowComponents = meaningfulComponents(
                buildLineComponents(in: grid, visibleRow: row)
            )
            logicalCharacterCount += rowComponents.reduce(0) { $0 + $1.text.count }
            guard logicalCharacterCount <= maximumInteractiveTokenLength else { return nil }
            components.append(contentsOf: rowComponents)
        }
        return components
    }

    private static func isConservativeContinuation(
        in grid: any TerminalInteractiveTextGrid,
        upperRow: Int,
        lowerRow: Int
    ) -> Bool {
        if let isWrapped = grid.isWrappedContinuation(
            upperRow: upperRow,
            lowerRow: lowerRow
        ) {
            return isWrapped
        }

        let upper = meaningfulComponents(buildLineComponents(in: grid, visibleRow: upperRow))
        let lower = meaningfulComponents(buildLineComponents(in: grid, visibleRow: lowerRow))
        guard let upperFirst = upper.first,
              let upperLast = upper.last,
              let lowerFirst = lower.first else { return false }
        let reachesTrailingEdge = upperLast.columns.upperBound
            >= grid.cols - continuationTrailingColumnTolerance
        let startsAtLeadingEdge = lowerFirst.columns.lowerBound <= continuationLeadingColumnLimit
        let preservesBoundedIndent = lowerFirst.columns.lowerBound > continuationLeadingColumnLimit
            && lowerFirst.columns.lowerBound <= continuationMatchingIndentLimit
            && lowerFirst.columns.lowerBound == upperFirst.columns.lowerBound
        return reachesTrailingEdge && (startsAtLeadingEdge || preservesBoundedIndent)
    }

    private static func buildLineComponents(
        in grid: any TerminalInteractiveTextGrid,
        visibleRow: Int
    ) -> [LineComponent] {
        var components: [LineComponent] = []
        components.reserveCapacity(grid.cols)

        var column = 0
        while column < grid.cols {
            guard let cell = grid.cell(atColumn: column, row: visibleRow) else {
                break
            }

            let width = max(cell.width, 1)
            components.append(
                LineComponent(
                    text: normalizedText(for: cell.text),
                    columns: column..<(column + width),
                    row: visibleRow
                )
            )
            column += width
        }

        return components
    }

    private static func meaningfulComponents(_ components: [LineComponent]) -> [LineComponent] {
        guard let first = components.firstIndex(where: { !isWhitespace($0.text) }),
              let last = components.lastIndex(where: { !isWhitespace($0.text) }) else {
            return []
        }
        return Array(components[first...last])
    }

    private static func normalizedText(for value: String) -> String {
        if value.unicodeScalars.allSatisfy({ $0.value == 0 }) {
            return " "
        }
        return value
    }

    private static func componentIndex(
        at clickedColumn: Int,
        row: Int,
        in components: [LineComponent]
    ) -> Int? {
        var index = components.firstIndex {
            $0.row == row && $0.columns.contains(clickedColumn)
        }
        if index == nil, clickedColumn > 0 {
            index = components.firstIndex {
                $0.row == row && $0.columns.contains(clickedColumn - 1)
            }
        }
        return index
    }

    private static func syntaxAwareTokenMatch(
        around clickedIndex: Int,
        clickedRow: Int,
        in components: [LineComponent]
    ) -> TokenMatch? {
        var ranges: [Range<Int>] = []
        var tokenStart: Int?
        var activeQuote: Character?
        var escaping = false

        for index in components.indices {
            let text = components[index].text
            let separator = isWhitespace(text) && activeQuote == nil && !escaping
            if separator {
                if let tokenStart {
                    ranges.append(tokenStart..<index)
                    selfReset(&activeQuote, &escaping)
                }
                tokenStart = nil
                continue
            }

            if tokenStart == nil {
                tokenStart = index
            }
            updateShellLiteralState(text: text, activeQuote: &activeQuote, escaping: &escaping)
        }
        if let tokenStart {
            ranges.append(tokenStart..<components.endIndex)
        }

        guard let range = ranges.first(where: { $0.contains(clickedIndex) }) else { return nil }
        return makeTokenMatch(range: range, clickedRow: clickedRow, components: components)
    }

    private static func selfReset(_ activeQuote: inout Character?, _ escaping: inout Bool) {
        activeQuote = nil
        escaping = false
    }

    private static func updateShellLiteralState(
        text: String,
        activeQuote: inout Character?,
        escaping: inout Bool
    ) {
        for character in text {
            if escaping {
                escaping = false
                continue
            }
            if character == "\\", activeQuote != "'" {
                escaping = true
                continue
            }
            if character == "\"" || character == "'" {
                if activeQuote == character {
                    activeQuote = nil
                } else if activeQuote == nil {
                    activeQuote = character
                }
            }
        }
    }

    private static func rawWhitespaceTokenMatches(
        around clickedIndex: Int,
        clickedRow: Int,
        in components: [LineComponent]
    ) -> [TokenMatch] {
        var words: [Range<Int>] = []
        var wordStart: Int?
        for index in components.indices {
            if isWhitespace(components[index].text) {
                if let start = wordStart {
                    words.append(start..<index)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = index
            }
        }
        if let wordStart {
            words.append(wordStart..<components.endIndex)
        }

        var centerWordIndices = words.indices.filter { words[$0].contains(clickedIndex) }
        if centerWordIndices.isEmpty {
            centerWordIndices = words.indices.filter { wordIndex in
                let previousEnd = wordIndex > words.startIndex ? words[wordIndex - 1].upperBound : 0
                return previousEnd <= clickedIndex && clickedIndex < words[wordIndex].lowerBound
            }
            if let preceding = words.indices.last(where: { words[$0].upperBound <= clickedIndex }) {
                centerWordIndices.append(preceding)
            }
        }

        var matches: [TokenMatch] = []
        for center in Set(centerWordIndices) {
            for wordCount in 2...maximumRawPathWords {
                let minimumStart = max(words.startIndex, center - wordCount + 1)
                let maximumStart = min(center, words.endIndex - wordCount)
                guard minimumStart <= maximumStart else { continue }
                for start in minimumStart...maximumStart {
                    let end = start + wordCount - 1
                    let range = words[start].lowerBound..<words[end].upperBound
                    guard range.contains(clickedIndex) || isWhitespace(components[clickedIndex].text) else {
                        continue
                    }
                    guard let match = makeTokenMatch(
                        range: range,
                        clickedRow: clickedRow,
                        components: components
                    ), match.rawToken.unicodeScalars.contains(where: CharacterSet.whitespaces.contains),
                       !containsQuotedOrEscapedWhitespace(match.rawToken),
                       !matches.contains(where: { $0.rawToken == match.rawToken && $0.columns == match.columns }) else {
                        continue
                    }
                    matches.append(match)
                    if matches.count == maximumCandidateCount {
                        return matches
                    }
                }
            }
        }
        return matches
    }

    private static func makeTokenMatch(
        range: Range<Int>,
        clickedRow: Int,
        components: [LineComponent]
    ) -> TokenMatch? {
        let selected = components[range]
        let clickedRowComponents = selected.filter { $0.row == clickedRow }
        guard let first = clickedRowComponents.first, let last = clickedRowComponents.last else {
            return nil
        }
        let rawToken = selected.map(\.text).joined()
        guard !rawToken.isEmpty,
              (rawToken as NSString).length <= maximumInteractiveTokenLength else {
            return nil
        }
        let segments = Dictionary(grouping: selected, by: \.row)
            .compactMap { row, rowComponents -> TerminalInteractiveTargetSegment? in
                guard let first = rowComponents.first,
                      let last = rowComponents.last else { return nil }
                return TerminalInteractiveTargetSegment(
                    row: row,
                    columns: first.columns.lowerBound..<last.columns.upperBound
                )
            }
            .sorted { $0.row < $1.row }
        return TokenMatch(
            rawToken: rawToken,
            columns: first.columns.lowerBound..<last.columns.upperBound,
            rows: Set(selected.map(\.row)),
            segments: segments
        )
    }

    private static func candidateTokens(from rawToken: String) -> [String] {
        let wrapperCharacters = CharacterSet(charactersIn: "\"'`()[]{}<>")
        let trailingPunctuation = CharacterSet(charactersIn: ".,;")

        var candidates: [String] = []
        func append(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed), candidates.count < maximumCandidateCount else {
                return
            }
            candidates.append(trimmed)
        }

        append(rawToken)
        let unwrapped = rawToken.trimmingCharacters(in: wrapperCharacters)
        append(unwrapped)
        append(unwrapped.trimmingCharacters(in: trailingPunctuation))
        return candidates
    }

    private static func mayContainInteractiveTarget(
        _ token: String,
        allowsRawWhitespace: Bool
    ) -> Bool {
        if token.contains("://") || token.lowercased().hasPrefix("www.") {
            return true
        }

        guard let decoded = decodeFileReferenceCandidate(
            token,
            allowsRawWhitespace: allowsRawWhitespace
        ), let components = parseFileReferenceComponents(from: decoded) else {
            return false
        }
        return looksLikeFileReference(
            components.path,
            allowsBareName: components.line != nil || components.column != nil
        )
    }

    private static func containsQuotedOrEscapedWhitespace(_ token: String) -> Bool {
        if let first = token.first, first == "\"" || first == "'" {
            return true
        }
        var previousWasBackslash = false
        for character in token {
            if character.isWhitespace, previousWasBackslash {
                return true
            }
            previousWasBackslash = character == "\\" && !previousWasBackslash
        }
        return false
    }

    private static func isWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private static func linkFromPayload(_ payload: String) -> String? {
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let link = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return link.isEmpty ? nil : link
    }

    private static func parseFileURL(from candidate: String) -> TerminalInteractiveTarget? {
        guard let url = URL(string: candidate), url.isFileURL else { return nil }
        return .fileSystem(
            TerminalFileSystemTarget(url: url.standardizedFileURL, line: nil, column: nil)
        )
    }

    private static func parseLink(from candidate: String) -> String? {
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidate.isEmpty else { return nil }
        let lowercasedCandidate = normalizedCandidate.lowercased()

        if lowercasedCandidate.hasPrefix("www."),
           let url = URL(string: "https://\(normalizedCandidate)"),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return url.absoluteString
        }

        guard let url = URL(string: normalizedCandidate),
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty,
              scheme != "file" else {
            return nil
        }
        guard normalizedCandidate.contains("://") || rawURLSchemes.contains(scheme) else {
            return nil
        }
        return url.absoluteString
    }

    private static func parseFileReference(
        from candidate: String,
        currentDirectory: URL?,
        allowsRawWhitespace: Bool
    ) -> TerminalInteractiveTarget? {
        guard let decodedCandidate = decodeFileReferenceCandidate(
            candidate,
            allowsRawWhitespace: allowsRawWhitespace
        ), let components = parseFileReferenceComponents(from: decodedCandidate),
           looksLikeFileReference(
               components.path,
               allowsBareName: components.line != nil || components.column != nil
           ), let resolvedURL = resolveFileURL(
               from: components.path,
               currentDirectory: currentDirectory
           ) else {
            return nil
        }

        let standardizedURL = resolvedURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return nil }
        return .fileSystem(
            TerminalFileSystemTarget(
                url: standardizedURL,
                line: components.line,
                column: components.column
            )
        )
    }

    private static func decodeFileReferenceCandidate(
        _ candidate: String,
        allowsRawWhitespace: Bool
    ) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            var decoded = ""
            var escaping = false
            var index = trimmed.index(after: trimmed.startIndex)
            var closingIndex: String.Index?
            while index < trimmed.endIndex {
                let character = trimmed[index]
                if escaping {
                    decoded.append(character)
                    escaping = false
                } else if character == "\\", quote == "\"" {
                    escaping = true
                } else if character == quote {
                    closingIndex = index
                    break
                } else {
                    decoded.append(character)
                }
                index = trimmed.index(after: index)
            }
            guard let closingIndex, !escaping else { return nil }
            let suffixStart = trimmed.index(after: closingIndex)
            let suffix = String(trimmed[suffixStart...])
            guard suffix.isEmpty || (!suffix.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
                && suffix.hasPrefix(":")) else {
                return nil
            }
            return decoded + suffix
        }

        var decoded = ""
        var escaping = false
        var containsRawWhitespace = false
        for character in trimmed {
            if escaping {
                decoded.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                if character.isWhitespace {
                    containsRawWhitespace = true
                }
                decoded.append(character)
            }
        }
        guard !escaping, allowsRawWhitespace || !containsRawWhitespace else { return nil }
        return decoded
    }

    private static func looksLikeFileReference(
        _ candidate: String,
        allowsBareName: Bool = false
    ) -> Bool {
        guard !candidate.isEmpty else { return false }

        if candidate.hasPrefix("~/")
            || candidate.hasPrefix("./")
            || candidate.hasPrefix("../")
            || candidate.hasPrefix("/") {
            return true
        }
        if candidate.contains("/") || candidate.contains("\\") {
            return true
        }
        if commonBareFileNames.contains(candidate) {
            return true
        }

        guard candidate.allSatisfy({
            $0.isLetter || $0.isNumber || $0.isWhitespace || bareFileReferenceCharacters.contains($0)
        }) else {
            return false
        }
        if candidate.contains(".") {
            return !candidate.hasSuffix(".") && !candidate.contains("..")
        }
        return allowsBareName
    }

    private static func parseFileReferenceComponents(
        from candidate: String
    ) -> (path: String, line: Int?, column: Int?)? {
        guard !candidate.isEmpty,
              !candidate.unicodeScalars.contains(where: CharacterSet.newlines.contains),
              !candidate.hasSuffix(":") else {
            return nil
        }

        let firstSplit = splitNumericSuffix(in: candidate)
        let path: String
        let line: Int?
        let column: Int?

        if let trailingNumber = firstSplit.number {
            let secondSplit = splitNumericSuffix(in: firstSplit.prefix)
            path = secondSplit.prefix
            if let leadingNumber = secondSplit.number {
                line = leadingNumber
                column = trailingNumber
            } else {
                line = trailingNumber
                column = nil
            }
        } else {
            path = candidate
            line = nil
            column = nil
        }

        guard !path.isEmpty, !path.contains(":") else { return nil }
        return (path: path, line: line, column: column)
    }

    private static func splitNumericSuffix(in candidate: String) -> (prefix: String, number: Int?) {
        guard let colonIndex = candidate.lastIndex(of: ":") else {
            return (candidate, nil)
        }
        let digitsStart = candidate.index(after: colonIndex)
        guard digitsStart < candidate.endIndex else {
            return (candidate, nil)
        }

        let digits = candidate[digitsStart...]
        guard digits.allSatisfy(\.isNumber), let number = Int(digits) else {
            return (candidate, nil)
        }
        return (String(candidate[..<colonIndex]), number)
    }

    private static func resolveFileURL(from rawPath: String, currentDirectory: URL?) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let currentDirectory else { return nil }
        return currentDirectory.appendingPathComponent(path)
    }
}

private extension CharacterSet {
    func contains(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains)
    }
}
