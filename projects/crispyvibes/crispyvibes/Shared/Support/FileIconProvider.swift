import SwiftUI

/// Maps file extensions to Seti UI icon names
struct FileIconProvider {
    private static let extensionToIconName: [String: String] = [
        // Programming languages
        "py": "python",
        "pyw": "python",
        "pyi": "python",
        "js": "javascript",
        "jsx": "react",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "react",
        "swift": "swift",
        "rs": "rust",
        "go": "go",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "rb": "ruby",
        "php": "php",
        "lua": "lua",
        "r": "R",
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "hh": "cpp",
        "cs": "c-sharp",
        "fs": "f-sharp",
        "scala": "scala",
        "clj": "clojure",
        "ex": "elixir",
        "exs": "elixir",
        "elm": "elm",
        "hs": "haskell",
        "ml": "ocaml",
        "nim": "nim",
        "pl": "perl",
        "jl": "julia",
        "dart": "dart",
        "zig": "zig",

        // Web
        "html": "html",
        "htm": "html",
        "css": "css",
        "scss": "sass",
        "sass": "sass",
        "less": "less",
        "vue": "vue",
        "svelte": "svelte",

        // Markup/Data
        "md": "markdown",
        "markdown": "markdown",
        "json": "json",
        "jsonl": "json",
        "jsonc": "json",
        "ipynb": "notebook",
        "yaml": "yml",
        "yml": "yml",
        "toml": "config",
        "xml": "xml",
        "csv": "csv",
        "bib": "tex",
        "tex": "tex",
        "rst": "default",
        "adoc": "default",

        // Config
        "ini": "config",
        "cfg": "config",
        "conf": "config",
        "env": "config",
        "editorconfig": "editorconfig",
        "properties": "config",

        // Shell
        "sh": "shell",
        "bash": "shell",
        "zsh": "shell",
        "fish": "shell",

        // Build/Package
        "dockerfile": "docker",
        "makefile": "makefile",
        "gradle": "gradle",
        "maven": "maven",
        "lock": "lock",

        // Git
        "gitignore": "git_ignore",
        "gitattributes": "git",

        // Other
        "sql": "db",
        "db": "db",
        "pdf": "pdf",
        "zip": "zip",
        "wasm": "wasm",
        "graphql": "graphql",
        "prisma": "prisma",
        "proto": "config",
        "log": "default",
        "txt": "default"
    ]

    private static let iconImageCache = NSCache<NSString, NSImage>()

    static func iconName(for fileExtension: String) -> String? {
        extensionToIconName[fileExtension.lowercased()]
    }
    
    static func iconImage(for fileExtension: String) -> NSImage? {
        guard let iconName = iconName(for: fileExtension) else { return nil }
        let cacheKey = iconName as NSString
        if let cached = iconImageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let url = Bundle.main.url(forResource: iconName, withExtension: "svg", subdirectory: "SetiIcons") else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Monochrome glyphs (no explicit color) render as a template so the host
        // can tint them for the current theme; colored icons render as-is.
        image.isTemplate = needsTemplateTint(for: url)
        iconImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func needsTemplateTint(for url: URL) -> Bool {
        guard let svg = try? String(contentsOf: url, encoding: .utf8).lowercased() else { return false }
        let hasExplicitColor = svg.contains("fill=") || svg.contains("stroke=")
            || svg.contains("fill:") || svg.contains("stroke:") || svg.contains("currentcolor")
        return !hasExplicitColor
    }
}
