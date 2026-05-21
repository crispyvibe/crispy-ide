import Foundation

public struct JavaScriptLanguage: LanguageDefinition {
    public let name = "JavaScript"
    public let fileExtensions: Set<String> = ["js", "jsx", "mjs", "cjs"]
    
    public var patterns: [SyntaxPattern] {
        [
            // Keywords
            SyntaxPattern(
                pattern: "\\b(function|const|let|var|if|else|for|while|return|import|export|from|as|try|catch|finally|async|await|class|extends|new|this|super|static|break|continue|switch|case|default|throw|typeof|instanceof|delete|void|yield|in|of|do|with|debugger|null|undefined|true|false)\\b",
                tokenType: .keyword
            ),
            
            // Template literals
            SyntaxPattern(
                pattern: "`[^`]*`",
                tokenType: .string
            ),
            
            // Regular strings
            SyntaxPattern(
                pattern: #"\"[^\"]*\""#,
                tokenType: .string
            ),
            SyntaxPattern(
                pattern: #"'[^']*'"#,
                tokenType: .string
            ),
            
            // Multi-line comments
            SyntaxPattern(
                pattern: "/\\*[\\s\\S]*?\\*/",
                tokenType: .comment
            ),
            
            // Single-line comments
            SyntaxPattern(
                pattern: "//.*$",
                tokenType: .comment,
                options: .anchorsMatchLines
            ),
            
            // Numbers
            SyntaxPattern(
                pattern: "\\b\\d+\\.?\\d*\\b",
                tokenType: .number
            ),
            
            // Function definitions
            SyntaxPattern(
                pattern: "(?<=function )\\w+",
                tokenType: .function
            ),
            
            // Arrow function names
            SyntaxPattern(
                pattern: "\\b\\w+(?=\\s*=\\s*\\([^)]*\\)\\s*=>)",
                tokenType: .function
            ),
            
            // Class definitions
            SyntaxPattern(
                pattern: "(?<=class )\\w+",
                tokenType: .class
            ),
            
            // Operators
            SyntaxPattern(
                pattern: "[+\\-*/%=<>!&|^~?:]",
                tokenType: .operator
            )
        ]
    }
    
    public init() {}
}
