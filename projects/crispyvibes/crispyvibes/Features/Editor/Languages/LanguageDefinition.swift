import Foundation
import AppKit

/// Represents a syntax pattern for highlighting
public struct SyntaxPattern {
    public enum TokenType {
        case keyword
        case string
        case comment
        case number
        case function
        case `class`
        case `operator`
        case variable
    }
    
    public let pattern: String
    public let tokenType: TokenType
    public let options: NSRegularExpression.Options
    
    public init(pattern: String, tokenType: TokenType, options: NSRegularExpression.Options = []) {
        self.pattern = pattern
        self.tokenType = tokenType
        self.options = options
    }
}

/// Protocol for language-specific syntax definitions
public protocol LanguageDefinition {
    var name: String { get }
    var fileExtensions: Set<String> { get }
    var patterns: [SyntaxPattern] { get }
}

extension LanguageDefinition {
    /// Apply syntax highlighting to a text view
    public func applySyntaxHighlighting(
        to textView: NSTextView,
        theme: SyntaxTheme,
        baseFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    ) {
        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        guard let textStorage = textView.textStorage else { return }
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        // Reset to default
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: theme.text
        ], range: fullRange)

        if fullRange.length > SyntaxHighlightingLimits.characterLimit {
            return
        }

        // Apply patterns
        for syntaxPattern in patterns {
            guard let regex = SyntaxRegexCache.regex(
                pattern: syntaxPattern.pattern,
                options: syntaxPattern.options
            ) else {
                continue
            }

            let color = colorForTokenType(syntaxPattern.tokenType, theme: theme)

            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                textStorage.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }
    
    private func colorForTokenType(_ type: SyntaxPattern.TokenType, theme: SyntaxTheme) -> NSColor {
        switch type {
        case .keyword: return theme.keyword
        case .string: return theme.string
        case .comment: return theme.comment
        case .number: return theme.number
        case .function: return theme.function
        case .class: return theme.class
        case .operator: return theme.operator
        case .variable: return theme.variable
        }
    }
}

private enum SyntaxHighlightingLimits {
    static let characterLimit = 180_000
}

private enum SyntaxRegexCache {
    private static let cacheLock = NSLock()
    private static var regexByKey: [String: NSRegularExpression] = [:]
    private static let maxCacheEntries = 256

    static func regex(pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue)::\(pattern)"

        cacheLock.lock()
        if let cached = regexByKey[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        cacheLock.lock()
        if regexByKey.count >= maxCacheEntries {
            regexByKey.removeAll(keepingCapacity: true)
        }
        regexByKey[key] = compiled
        cacheLock.unlock()
        return compiled
    }
}

/// Fallback language with lightweight tokenization for general-purpose code files.
public struct GenericCodeLanguage: LanguageDefinition {
    public let name: String
    public let fileExtensions: Set<String>

    public var patterns: [SyntaxPattern] {
        [
            SyntaxPattern(
                pattern: #"\"[^\"]*\"|'[^']*'"#,
                tokenType: .string
            ),
            SyntaxPattern(
                pattern: #"\b\d+(\.\d+)?\b"#,
                tokenType: .number
            ),
            SyntaxPattern(
                pattern: #"//.*$|#.*$"#,
                tokenType: .comment,
                options: .anchorsMatchLines
            ),
            SyntaxPattern(
                pattern: #"[+\-*/%=<>!&|^~?:]"#,
                tokenType: .operator
            )
        ]
    }

    public init(name: String = "Code", fileExtensions: Set<String> = []) {
        self.name = name
        self.fileExtensions = fileExtensions
    }
}

public struct KeywordLanguage: LanguageDefinition {
    public let name: String
    public let fileExtensions: Set<String>
    private let keywords: [String]
    private let lineCommentPrefixes: [String]
    private let blockCommentPattern: String?

    public init(
        name: String,
        fileExtensions: Set<String>,
        keywords: [String],
        lineCommentPrefixes: [String] = [],
        blockCommentPattern: String? = nil
    ) {
        self.name = name
        self.fileExtensions = fileExtensions
        self.keywords = keywords
        self.lineCommentPrefixes = lineCommentPrefixes
        self.blockCommentPattern = blockCommentPattern
    }

    public var patterns: [SyntaxPattern] {
        var collected: [SyntaxPattern] = []

        if !keywords.isEmpty {
            let escapedKeywords = keywords.map(NSRegularExpression.escapedPattern(for:))
            let pattern = "\\b(\(escapedKeywords.joined(separator: "|")))\\b"
            collected.append(SyntaxPattern(pattern: pattern, tokenType: .keyword))
        }

        collected.append(
            SyntaxPattern(
                pattern: #"\"[^\"]*\"|'[^']*'"#,
                tokenType: .string
            )
        )
        collected.append(
            SyntaxPattern(
                pattern: #"\b\d+(\.\d+)?\b"#,
                tokenType: .number
            )
        )
        collected.append(
            SyntaxPattern(
                pattern: #"[+\-*/%=<>!&|^~?:]"#,
                tokenType: .operator
            )
        )

        for prefix in lineCommentPrefixes {
            let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
            collected.append(
                SyntaxPattern(
                    pattern: "\(escapedPrefix).*$",
                    tokenType: .comment,
                    options: .anchorsMatchLines
                )
            )
        }

        if let blockCommentPattern {
            collected.append(
                SyntaxPattern(
                    pattern: blockCommentPattern,
                    tokenType: .comment
                )
            )
        }

        return collected
    }
}
