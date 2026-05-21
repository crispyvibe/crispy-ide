import Foundation

public struct PythonLanguage: LanguageDefinition {
    public let name = "Python"
    public let fileExtensions: Set<String> = ["py", "pyw", "pyi"]
    
    public var patterns: [SyntaxPattern] {
        [
            // Keywords
            SyntaxPattern(
                pattern: "\\b(def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|with|lambda|yield|async|await|pass|break|continue|raise|assert|del|global|nonlocal|in|is|not|and|or|None|True|False)\\b",
                tokenType: .keyword
            ),
            
            // Triple-quoted strings (must come before single strings)
            SyntaxPattern(
                pattern: #"\"\"\"[\s\S]*?\"\"\""#,
                tokenType: .string
            ),
            SyntaxPattern(
                pattern: #"'''[\s\S]*?'''"#,
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
            
            // Comments
            SyntaxPattern(
                pattern: "#.*$",
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
                pattern: "(?<=def )\\w+",
                tokenType: .function
            ),
            
            // Class definitions
            SyntaxPattern(
                pattern: "(?<=class )\\w+",
                tokenType: .class
            ),
            
            // Operators
            SyntaxPattern(
                pattern: "[+\\-*/%=<>!&|^~]",
                tokenType: .operator
            )
        ]
    }
    
    public init() {}
}
