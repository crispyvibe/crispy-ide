import Foundation

public struct JSONLanguage: LanguageDefinition {
    public let name = "JSON"
    public let fileExtensions: Set<String> = ["json", "jsonl", "jsonc"]
    
    public var patterns: [SyntaxPattern] {
        [
            // String keys (property names)
            SyntaxPattern(
                pattern: #"\"[^\"]+\"\s*:"#,
                tokenType: .variable
            ),
            
            // String values
            SyntaxPattern(
                pattern: #":\s*\"[^\"]*\""#,
                tokenType: .string
            ),
            
            // Numbers
            SyntaxPattern(
                pattern: #"\b-?\d+\.?\d*([eE][+-]?\d+)?\b"#,
                tokenType: .number
            ),
            
            // Boolean and null keywords
            SyntaxPattern(
                pattern: "\\b(true|false|null)\\b",
                tokenType: .keyword
            ),
            
            // Comments (for JSONC - JSON with comments)
            SyntaxPattern(
                pattern: "//.*$",
                tokenType: .comment,
                options: .anchorsMatchLines
            ),
            
            // Multi-line comments
            SyntaxPattern(
                pattern: "/\\*[\\s\\S]*?\\*/",
                tokenType: .comment
            )
        ]
    }
    
    public init() {}
}
