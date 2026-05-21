import Foundation

enum CodeLanguageKind: String, Equatable {
    case javascript
    case typescript
    case swift
    case shell
    case ruby
    case go
    case rust
    case java
    case kotlin
    case cpp
    case csharp
    case dart
    case zig
    case php
    case lua
    case css
    case sql
    case yaml
    case xml
    case config

    var editorLanguage: any LanguageDefinition {
        switch self {
        case .javascript:
            return JavaScriptLanguage()
        case .typescript:
            return KeywordLanguage(
                name: "TypeScript",
                fileExtensions: ["ts", "tsx", "mts", "cts"],
                keywords: [
                    "function", "const", "let", "var", "if", "else", "for", "while", "return",
                    "import", "export", "from", "as", "try", "catch", "finally", "async", "await",
                    "class", "extends", "new", "this", "super", "static", "break", "continue",
                    "switch", "case", "default", "throw", "typeof", "instanceof", "delete", "void",
                    "yield", "in", "of", "do", "null", "undefined", "true", "false",
                    "type", "interface", "namespace", "declare", "readonly", "keyof", "infer",
                    "enum", "abstract", "implements", "private", "protected", "public", "override"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .swift:
            return KeywordLanguage(
                name: "Swift",
                fileExtensions: ["swift", "m", "mm"],
                keywords: [
                    "struct", "class", "enum", "protocol", "extension", "func", "var", "let",
                    "if", "else", "switch", "case", "for", "while", "guard", "return",
                    "import", "public", "private", "internal", "fileprivate", "open",
                    "async", "await", "throws", "try", "defer", "where", "in", "is", "as"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .shell:
            return KeywordLanguage(
                name: "Shell",
                fileExtensions: ["sh", "zsh", "bash", "fish"],
                keywords: [
                    "if", "then", "else", "fi", "for", "in", "do", "done", "case", "esac",
                    "function", "while", "until", "export", "local", "readonly", "return"
                ],
                lineCommentPrefixes: ["#"]
            )
        case .ruby:
            return KeywordLanguage(
                name: "Ruby",
                fileExtensions: ["rb"],
                keywords: [
                    "def", "class", "module", "if", "elsif", "else", "end", "do", "while",
                    "until", "for", "in", "begin", "rescue", "ensure", "return", "yield",
                    "self", "super", "require", "include", "extend"
                ],
                lineCommentPrefixes: ["#"]
            )
        case .go:
            return KeywordLanguage(
                name: "Go",
                fileExtensions: ["go"],
                keywords: [
                    "package", "import", "func", "var", "const", "type", "struct", "interface",
                    "if", "else", "switch", "case", "for", "range", "return", "defer",
                    "go", "select", "chan", "map"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .rust:
            return KeywordLanguage(
                name: "Rust",
                fileExtensions: ["rs"],
                keywords: [
                    "fn", "let", "mut", "struct", "enum", "impl", "trait", "mod", "use",
                    "pub", "crate", "if", "else", "match", "loop", "while", "for", "in",
                    "return", "async", "await", "where", "const", "static"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .java:
            return KeywordLanguage(
                name: "Java",
                fileExtensions: ["java"],
                keywords: [
                    "class", "interface", "enum", "public", "private", "protected", "static",
                    "final", "void", "int", "long", "double", "boolean", "if", "else",
                    "switch", "case", "for", "while", "return", "import", "package", "new"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .kotlin:
            return KeywordLanguage(
                name: "Kotlin",
                fileExtensions: ["kt", "kts"],
                keywords: [
                    "fun", "class", "object", "interface", "val", "var", "if", "else", "when",
                    "for", "while", "return", "package", "import", "in", "is", "as",
                    "suspend", "data", "sealed", "open", "companion"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .cpp:
            return KeywordLanguage(
                name: "C/C++",
                fileExtensions: ["c", "h", "cc", "cpp", "cxx", "hpp", "hh"],
                keywords: [
                    "int", "void", "char", "float", "double", "bool", "class", "struct",
                    "enum", "if", "else", "switch", "case", "for", "while", "return",
                    "namespace", "template", "typename", "const", "static", "public", "private"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .csharp:
            return KeywordLanguage(
                name: "C#",
                fileExtensions: ["cs"],
                keywords: [
                    "class", "struct", "interface", "enum", "namespace", "using", "public", "private",
                    "protected", "internal", "static", "void", "int", "string", "bool", "float",
                    "double", "var", "new", "return", "if", "else", "switch", "case", "for",
                    "foreach", "while", "do", "break", "continue", "try", "catch", "finally",
                    "throw", "async", "await", "override", "virtual", "abstract", "sealed",
                    "readonly", "const", "null", "true", "false", "this", "base", "get", "set"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .dart:
            return KeywordLanguage(
                name: "Dart",
                fileExtensions: ["dart"],
                keywords: [
                    "class", "extends", "implements", "mixin", "abstract", "enum", "typedef",
                    "import", "export", "library", "part", "void", "var", "final", "const",
                    "int", "double", "String", "bool", "dynamic", "if", "else", "switch", "case",
                    "for", "while", "do", "return", "break", "continue", "try", "catch", "finally",
                    "throw", "async", "await", "yield", "new", "this", "super", "null", "true", "false",
                    "late", "required", "static", "get", "set"
                ],
                lineCommentPrefixes: ["//"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .zig:
            return KeywordLanguage(
                name: "Zig",
                fileExtensions: ["zig"],
                keywords: [
                    "fn", "pub", "const", "var", "if", "else", "while", "for", "switch",
                    "return", "break", "continue", "struct", "enum", "union", "error",
                    "try", "catch", "defer", "errdefer", "comptime", "inline", "test",
                    "unreachable", "undefined", "null", "true", "false", "import"
                ],
                lineCommentPrefixes: ["//"]
            )
        case .php:
            return KeywordLanguage(
                name: "PHP",
                fileExtensions: ["php"],
                keywords: [
                    "function", "class", "interface", "trait", "public", "private", "protected",
                    "if", "else", "switch", "case", "for", "while", "foreach", "return",
                    "namespace", "use", "new", "static"
                ],
                lineCommentPrefixes: ["//", "#"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .lua:
            return KeywordLanguage(
                name: "Lua",
                fileExtensions: ["lua"],
                keywords: [
                    "function", "local", "if", "then", "else", "elseif", "end", "for", "while",
                    "repeat", "until", "return", "break", "nil", "true", "false"
                ],
                lineCommentPrefixes: ["--"]
            )
        case .css:
            return GenericCodeLanguage(name: "Stylesheet", fileExtensions: ["css", "scss", "sass", "less"])
        case .sql:
            return KeywordLanguage(
                name: "SQL",
                fileExtensions: ["sql"],
                keywords: [
                    "select", "from", "where", "insert", "into", "update", "delete", "join",
                    "left", "right", "inner", "outer", "group", "by", "order", "limit",
                    "create", "alter", "drop", "table", "index", "view", "as", "on"
                ],
                lineCommentPrefixes: ["--", "#"],
                blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
            )
        case .yaml:
            return GenericCodeLanguage(name: "YAML", fileExtensions: ["yaml", "yml"])
        case .xml:
            return GenericCodeLanguage(name: "XML", fileExtensions: ["xml"])
        case .config:
            return GenericCodeLanguage(name: "Config", fileExtensions: ["toml", "ini", "cfg", "conf", "env", "properties"])
        }
    }
}
