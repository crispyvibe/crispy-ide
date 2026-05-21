import AppKit
import SwiftUI

/// Renders markdown text with syntax-highlighted code blocks, copy buttons, and link detection.
struct ACPSelectableText: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let text: String
    var font: Font = AppTypographyTokens.body
    var foregroundColor: Color? = nil
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    markdownView(markdown)
                case .code(let language, let code):
                    if language?.lowercased() == "mermaid" {
                        MermaidDiagramView(source: code)
                    } else {
                        codeBlockView(language: language, code: code)
                    }
                }
            }
        }
    }

    // MARK: - Markdown

    private func markdownView(_ markdown: String) -> some View {
        MarkdownHTMLView(
            markdown: markdown,
            font: font,
            foregroundColor: foregroundColor ?? palette.primaryTextColor,
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: onFileSystemTargetActivated
        )
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(AppTypographyTokens.caption2Semibold)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(AppTypographyTokens.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryTextColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.secondaryTextColor.opacity(0.08))

            Text(Self.highlightCode(code, language: language))
                .font(.system(size: uiScale.textSize(12), design: .monospaced))
                .foregroundStyle(foregroundColor ?? palette.primaryTextColor)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.secondaryTextColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.secondaryTextColor.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Segment Parsing

    private enum Segment {
        case text(String)
        case code(language: String?, code: String)
    }

    private var segments: [Segment] {
        Self.parseSegments(text)
    }

    private static func parseSegments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }
        let nsText = text as NSString
        var lastEnd = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let matchStart = match.range.location
            if matchStart > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: matchStart - lastEnd)).trimmingCharacters(in: .newlines)
                if !before.isEmpty { segments.append(.text(before)) }
            }
            let language = nsText.substring(with: match.range(at: 1))
            let code = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .newlines)
            segments.append(.code(language: language.isEmpty ? nil : language, code: code))
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd).trimmingCharacters(in: .newlines)
            if !remaining.isEmpty { segments.append(.text(remaining)) }
        }

        return segments.isEmpty ? [.text(text)] : segments
    }

    // MARK: - Markdown Parsing

    static func parseMarkdown(_ text: String) -> AttributedString {
        let normalized = normalizeMarkdownLineBreaks(text)
        var attributed = (try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
        ACPTextLinking.applyDetectedLinks(to: &attributed, original: text)
        return attributed
    }

    /// Ensures single newlines become paragraph breaks for CommonMark compatibility.
    /// CommonMark treats single `\n` as a soft break (same paragraph). Agent responses
    /// often use single newlines to separate paragraphs, list items, and sections.
    private static func normalizeMarkdownLineBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        var result: [String] = [lines[0]]
        for i in 1..<lines.count {
            let prev = lines[i - 1]
            let curr = lines[i]
            let prevTrimmed = prev.trimmingCharacters(in: .whitespaces)
            let currTrimmed = curr.trimmingCharacters(in: .whitespaces)
            // Already a blank line — keep as-is
            if prevTrimmed.isEmpty || currTrimmed.isEmpty {
                result.append(curr)
                continue
            }
            // List items, headings, and blockquotes get a blank line before them
            if currTrimmed.hasPrefix("- ") || currTrimmed.hasPrefix("* ")
                || currTrimmed.hasPrefix("# ") || currTrimmed.hasPrefix("> ")
                || currTrimmed.first?.isNumber == true && currTrimmed.contains(". ") {
                result.append("")
                result.append(curr)
                continue
            }
            // After a list item or heading, add blank line
            if prevTrimmed.hasPrefix("- ") || prevTrimmed.hasPrefix("* ")
                || prevTrimmed.hasPrefix("# ") || prevTrimmed.hasPrefix("> ") {
                result.append("")
                result.append(curr)
                continue
            }
            result.append(curr)
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Syntax Highlighting

    static func highlightCode(_ code: String, language: String?) -> AttributedString {
        var result = AttributedString(code)
        let keywords = languageKeywords(language)
        guard !keywords.isEmpty else { return result }

        let nsCode = code as NSString
        // Highlight keywords
        for keyword in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                guard let range = Range(match.range, in: code),
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[lower..<upper].foregroundColor = .init(red: 0.78, green: 0.36, blue: 0.78)
            }
        }
        // Highlight strings
        if let stringRegex = try? NSRegularExpression(pattern: #"("[^"\\]*(?:\\.[^"\\]*)*"|'[^'\\]*(?:\\.[^'\\]*)*')"#) {
            for match in stringRegex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                guard let range = Range(match.range, in: code),
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[lower..<upper].foregroundColor = .init(red: 0.84, green: 0.55, blue: 0.37)
            }
        }
        // Highlight comments
        if let commentRegex = try? NSRegularExpression(pattern: #"(//.*$|#.*$)"#, options: .anchorsMatchLines) {
            for match in commentRegex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                guard let range = Range(match.range, in: code),
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[lower..<upper].foregroundColor = .init(red: 0.45, green: 0.50, blue: 0.55)
            }
        }
        // Highlight numbers
        if let numberRegex = try? NSRegularExpression(pattern: #"\b\d+\.?\d*\b"#) {
            for match in numberRegex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                guard let range = Range(match.range, in: code),
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                result[lower..<upper].foregroundColor = .init(red: 0.82, green: 0.77, blue: 0.55)
            }
        }
        return result
    }

    private static func languageKeywords(_ language: String?) -> [String] {
        switch language?.lowercased() {
        case "swift":
            return ["func", "var", "let", "class", "struct", "enum", "protocol", "import", "return", "if", "else", "guard", "for", "while", "switch", "case", "default", "break", "continue", "self", "Self", "true", "false", "nil", "async", "await", "throws", "try", "catch", "private", "public", "internal", "static", "final", "override", "init", "deinit", "where", "in", "as", "is"]
        case "javascript", "js", "typescript", "ts", "tsx", "jsx":
            return ["function", "const", "let", "var", "class", "return", "if", "else", "for", "while", "switch", "case", "default", "break", "continue", "import", "export", "from", "async", "await", "try", "catch", "throw", "new", "this", "true", "false", "null", "undefined", "typeof", "instanceof"]
        case "python", "py":
            return ["def", "class", "return", "if", "elif", "else", "for", "while", "import", "from", "as", "try", "except", "raise", "with", "pass", "break", "continue", "and", "or", "not", "in", "is", "True", "False", "None", "self", "lambda", "yield", "async", "await"]
        case "rust", "rs":
            return ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "pub", "use", "mod", "return", "if", "else", "for", "while", "loop", "match", "break", "continue", "self", "Self", "true", "false", "async", "await", "move", "where", "type", "unsafe"]
        case "bash", "sh", "zsh", "shell":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "exit", "echo", "export", "local", "readonly", "set", "unset", "true", "false"]
        case "json":
            return ["true", "false", "null"]
        default:
            return ["function", "const", "let", "var", "class", "return", "if", "else", "for", "while", "import", "true", "false", "null", "nil", "def", "fn", "struct", "enum"]
        }
    }
}

// MARK: - Link Detection

enum ACPTextLinking {
    private static let filePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(/(?:[^\s:()]+/?)+)(?::(\d+))?(?::(\d+))?"#
    )
    private static let bareURLPattern = try! NSRegularExpression(
        pattern: #"(?<!["=])((?:https?|file)://[^\s<]+)"#
    )
    static let linkTextAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor(red: 232.0 / 255.0, green: 145.0 / 255.0, blue: 45.0 / 255.0, alpha: 1),
        .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]

    static func applyDetectedLinks(to attributed: inout AttributedString, original: String) {
        let nsRange = NSRange(original.startIndex..<original.endIndex, in: original)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: original, options: [], range: nsRange) {
                guard let url = match.url,
                      let range = Range(match.range, in: original),
                      let lower = AttributedString.Index(range.lowerBound, within: attributed),
                      let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
                attributed[lower..<upper].link = url
            }
        }

        for match in filePattern.matches(in: original, options: [], range: nsRange) {
            guard let pathRange = Range(match.range(at: 1), in: original) else { continue }
            let path = String(original[pathRange])
            let line = Range(match.range(at: 2), in: original).flatMap { Int(String(original[$0])) }
            let column = Range(match.range(at: 3), in: original).flatMap { Int(String(original[$0])) }
            guard let linkURL = fileURL(path: path, line: line, column: column) else { continue }
            let wholeRange = Range(match.range, in: original) ?? pathRange
            guard let lower = AttributedString.Index(wholeRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(wholeRange.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = linkURL
        }
    }

    static func applyDetectedLinks(to attributed: NSMutableAttributedString) {
        let original = attributed.string
        let nsRange = NSRange(location: 0, length: (original as NSString).length)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: original, options: [], range: nsRange) {
                guard let url = match.url else { continue }
                addLink(url, range: match.range, to: attributed)
            }
        }

        for match in bareURLPattern.matches(in: original, options: [], range: nsRange) {
            guard let urlRange = Range(match.range(at: 1), in: original) else { continue }
            let rawURL = String(original[urlRange])
            let (urlString, suffix) = splitTrailingPunctuation(from: rawURL)
            guard let url = URL(string: urlString) else { continue }
            let length = match.range(at: 1).length - (suffix as NSString).length
            addLink(url, range: NSRange(location: match.range(at: 1).location, length: length), to: attributed)
        }

        for match in filePattern.matches(in: original, options: [], range: nsRange) {
            guard let pathRange = Range(match.range(at: 1), in: original) else { continue }
            let path = String(original[pathRange])
            let line = Range(match.range(at: 2), in: original).flatMap { Int(String(original[$0])) }
            let column = Range(match.range(at: 3), in: original).flatMap { Int(String(original[$0])) }
            guard let linkURL = fileURL(path: path, line: line, column: column) else { continue }
            let wholeRange = Range(match.range, in: original) ?? pathRange
            let nsWholeRange = NSRange(wholeRange, in: original)
            addLink(linkURL, range: nsWholeRange, to: attributed)
        }
    }

    static func styleLinks(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            attributed.addAttributes(linkTextAttributes, range: range)
        }
    }

    static func handle(
        url: URL,
        onLinkTargetActivated: ((URL) -> Void)?,
        onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    ) -> OpenURLAction.Result {
        if let target = fileTarget(from: url) {
            onFileSystemTargetActivated?(target)
            return .handled
        }
        if url.isFileURL {
            onFileSystemTargetActivated?(TerminalFileSystemTarget(url: url, line: nil, column: nil))
            return .handled
        }
        if let onLinkTargetActivated {
            onLinkTargetActivated(url)
            return .handled
        }
        return .systemAction(url)
    }

    private static func fileURL(path: String, line: Int?, column: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "crispyvibes-file"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "line", value: line.map(String.init)),
            URLQueryItem(name: "column", value: column.map(String.init)),
        ].compactMap { $0.value == nil ? nil : $0 }
        return components.url
    }

    private static func fileTarget(from url: URL) -> TerminalFileSystemTarget? {
        guard url.scheme == "crispyvibes-file",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else { return nil }
        let line = components.queryItems?.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
        let column = components.queryItems?.first(where: { $0.name == "column" })?.value.flatMap(Int.init)
        return TerminalFileSystemTarget(url: URL(fileURLWithPath: path), line: line, column: column)
    }

    private static func addLink(_ url: URL, range: NSRange, to attributed: NSMutableAttributedString) {
        guard range.location != NSNotFound,
              range.length > 0,
              !containsAttribute(.link, in: attributed, range: range) else { return }
        attributed.addAttribute(.link, value: url, range: range)
    }

    private static func containsAttribute(_ key: NSAttributedString.Key, in attributed: NSAttributedString, range: NSRange) -> Bool {
        var foundAttribute = false
        attributed.enumerateAttribute(key, in: range) { value, _, stop in
            if value != nil {
                foundAttribute = true
                stop.pointee = true
            }
        }
        return foundAttribute
    }

    private static func splitTrailingPunctuation(from text: String) -> (url: String, suffix: String) {
        var url = text
        var suffix = ""
        while let last = url.last, ".,;:!?".contains(last) {
            suffix.insert(last, at: suffix.startIndex)
            url.removeLast()
        }
        return (url, suffix)
    }
}

// MARK: - Mermaid Diagram

/// Renders a mermaid diagram source to an image via the shared MermaidRenderer.
struct MermaidDiagramView: View {
    let source: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                // Fallback: show source as code
                Text(source)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: "\(source)|\(colorScheme)") {
            isLoading = true
            image = await MermaidRenderer.shared.render(source: source, isDark: colorScheme == .dark)
            isLoading = false
        }
    }
}
