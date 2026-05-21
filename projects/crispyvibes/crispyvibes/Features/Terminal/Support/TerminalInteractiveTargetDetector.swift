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

struct TerminalInteractiveTargetHit: Equatable {
    let target: TerminalInteractiveTarget
    let row: Int
    let columns: Range<Int>
}

protocol TerminalInteractiveTextGrid {
    var cols: Int { get }
    var rows: Int { get }

    func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell?
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
    }

    private struct TokenMatch {
        let rawToken: String
        let columns: Range<Int>
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
           let link = linkFromPayload(payload) {
            return TerminalInteractiveTargetHit(
                target: .link(link),
                row: visibleRow,
                columns: visibleColumn..<(visibleColumn + 1)
            )
        }

        let lineComponents = buildLineComponents(in: grid, visibleRow: visibleRow)
        guard let tokenMatch = tokenMatch(around: visibleColumn, in: lineComponents) else { return nil }
        guard let match = detectTargetWithCandidate(fromRawToken: tokenMatch.rawToken, currentDirectory: currentDirectory) else {
            return nil
        }

        let columns = narrowedColumns(
            rawToken: tokenMatch.rawToken,
            matchedCandidate: match.candidate,
            fullRange: tokenMatch.columns
        )

        return TerminalInteractiveTargetHit(
            target: match.target,
            row: visibleRow,
            columns: columns
        )
    }

    static func detectTarget(
        fromRawToken rawToken: String,
        currentDirectory: URL?
    ) -> TerminalInteractiveTarget? {
        detectTargetWithCandidate(fromRawToken: rawToken, currentDirectory: currentDirectory)?.target
    }

    private static func detectTargetWithCandidate(
        fromRawToken rawToken: String,
        currentDirectory: URL?
    ) -> (target: TerminalInteractiveTarget, candidate: String)? {
        let trimmedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty,
              (trimmedToken as NSString).length <= maximumInteractiveTokenLength,
              mayContainInteractiveTarget(trimmedToken) else {
            return nil
        }

        for candidate in candidateTokens(from: trimmedToken) {
            if let link = parseLink(from: candidate) {
                return (.link(link), candidate)
            }
            if let fileReference = parseFileReference(from: candidate, currentDirectory: currentDirectory) {
                return (fileReference, candidate)
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
            let normalizedText = normalizedText(for: cell.text)

            components.append(
                LineComponent(
                    text: normalizedText,
                    columns: column..<(column + width)
                )
            )

            column += width
        }

        return components
    }

    private static func normalizedText(for value: String) -> String {
        if value.unicodeScalars.allSatisfy({ $0.value == 0 }) {
            return " "
        }
        return value
    }

    private static func tokenMatch(
        around clickedColumn: Int,
        in components: [LineComponent]
    ) -> TokenMatch? {
        guard !components.isEmpty else { return nil }

        var componentIndex = components.firstIndex(where: { $0.columns.contains(clickedColumn) })
        if componentIndex == nil, clickedColumn > 0 {
            componentIndex = components.firstIndex(where: { $0.columns.contains(clickedColumn - 1) })
        }
        guard let centerIndex = componentIndex else { return nil }
        guard !components[centerIndex].text.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) else {
            return nil
        }

        var lowerBound = centerIndex
        while lowerBound > 0,
              !components[lowerBound - 1].text.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
            lowerBound -= 1
        }

        var upperBound = centerIndex
        while upperBound + 1 < components.count,
              !components[upperBound + 1].text.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
            upperBound += 1
        }

        let token = components[lowerBound...upperBound]
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        return TokenMatch(
            rawToken: token,
            columns: components[lowerBound].columns.lowerBound..<components[upperBound].columns.upperBound
        )
    }

    private static func candidateTokens(from rawToken: String) -> [String] {
        let wrapperCharacters = CharacterSet(charactersIn: "\"'`()[]{}<>")
        let trailingPunctuation = CharacterSet(charactersIn: ".,;")

        var candidates: [String] = []
        func append(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        append(rawToken)

        let unwrapped = rawToken.trimmingCharacters(in: wrapperCharacters)
        append(unwrapped)

        let unwrappedWithoutTrailingPunctuation = unwrapped.trimmingCharacters(in: trailingPunctuation)
        append(unwrappedWithoutTrailingPunctuation)

        return candidates
    }

    private static func mayContainInteractiveTarget(_ token: String) -> Bool {
        if token.contains("://") || token.lowercased().hasPrefix("www.") {
            return true
        }

        if let components = parseFileReferenceComponents(from: token),
           looksLikeFileReference(components.path, allowsBareName: components.line != nil || components.column != nil) {
            return true
        }

        return false
    }

    private static func linkFromPayload(_ payload: String) -> String? {
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let link = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return link.isEmpty ? nil : link
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
              !scheme.isEmpty else {
            return nil
        }

        guard normalizedCandidate.contains("://") || rawURLSchemes.contains(scheme) else {
            return nil
        }

        return url.absoluteString
    }

    private static func parseFileReference(
        from candidate: String,
        currentDirectory: URL?
    ) -> TerminalInteractiveTarget? {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = parseFileReferenceComponents(from: trimmedCandidate),
              looksLikeFileReference(
                components.path,
                allowsBareName: components.line != nil || components.column != nil
              ) else {
            return nil
        }
        guard let resolvedURL = resolveFileURL(from: components.path, currentDirectory: currentDirectory) else {
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

        guard candidate.allSatisfy({ $0.isLetter || $0.isNumber || bareFileReferenceCharacters.contains($0) }) else {
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
        guard !candidate.isEmpty else { return nil }
        guard !candidate.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
            return nil
        }
        guard !candidate.hasSuffix(":") else { return nil }

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

        guard !path.isEmpty else { return nil }
        guard !path.contains(":") else { return nil }
        return (
            path: path,
            line: line,
            column: column
        )
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
        guard digits.allSatisfy(\.isNumber),
              let number = Int(digits) else {
            return (candidate, nil)
        }

        return (String(candidate[..<colonIndex]), number)
    }

    private static func resolveFileURL(from rawPath: String, currentDirectory: URL?) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if path.hasPrefix("~/") {
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
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
