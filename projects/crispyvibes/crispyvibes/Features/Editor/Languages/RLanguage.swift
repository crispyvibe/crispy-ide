import Foundation

public struct RLanguage: LanguageDefinition {
    public let name = "R"
    public let fileExtensions: Set<String> = ["r", "R", "rmd", "Rmd"]
    
    public var patterns: [SyntaxPattern] {
        [
            // Keywords
            SyntaxPattern(
                pattern: "\\b(function|if|else|for|while|repeat|in|next|break|return|TRUE|FALSE|NULL|NA|NaN|Inf|library|require|source|setwd|getwd)\\b",
                tokenType: .keyword
            ),
            
            // Strings
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
                pattern: "\\b\\d+\\.?\\d*([eE][+-]?\\d+)?\\b",
                tokenType: .number
            ),
            
            // Function definitions
            SyntaxPattern(
                pattern: "\\w+(?=\\s*<-\\s*function)",
                tokenType: .function
            ),
            
            // Function calls
            SyntaxPattern(
                pattern: "\\w+(?=\\s*\\()",
                tokenType: .function
            ),
            
            // Operators
            SyntaxPattern(
                pattern: "(<-|->|<<-|->>|==|!=|<=|>=|&&|\\|\\||[+\\-*/%^<>=!&|~$:])",
                tokenType: .operator
            )
        ]
    }
    
    public init() {}
}
