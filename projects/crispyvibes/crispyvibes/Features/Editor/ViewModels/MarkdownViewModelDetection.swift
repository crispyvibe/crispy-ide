import Foundation
import UniformTypeIdentifiers

extension MarkdownViewModel {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdx"]
    static let htmlExtensions: Set<String> = ["html", "htm"]
    static let pythonExtensions: Set<String> = ["py", "pyw", "pyi"]
    static let jsonExtensions: Set<String> = ["json", "jsonl", "jsonc"]
    /// F050: Jupyter notebook documents. Detected ahead of JSON so `.ipynb`
    /// routes to the notebook editor rather than the raw JSON code view.
    static let notebookExtensions: Set<String> = ["ipynb"]
    /// F052: Excalidraw whiteboards. Detected ahead of JSON so `.excalidraw`
    /// routes to the whiteboard canvas rather than the raw JSON code view.
    static let excalidrawExtensions: Set<String> = ["excalidraw"]
    /// LaTeX documents. Routed ahead of `plainText` so `.tex`/`.latex`/`.ltx`
    /// open in the split source + KaTeX math-preview editor.
    static let latexExtensions: Set<String> = ["tex", "latex", "ltx"]
    static let rExtensions: Set<String> = ["r", "R", "rmd", "Rmd"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif", "svg"]
    /// Microsoft Office document extensions previewed via Quick Look (F045).
    static let officeExtensions: Set<String> = ["docx", "doc", "pptx", "ppt", "xlsx", "xls"]
    static let plainTextExtensions: Set<String> = [
        "txt", "text", "log", "bib", "rst", "adoc",
        "csv", "tsv"
    ]
    static let codeLanguageByExtension: [String: CodeLanguageKind] = [
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "swift": .swift, "m": .swift, "mm": .swift,
        "sh": .shell, "zsh": .shell, "bash": .shell, "fish": .shell,
        "rb": .ruby,
        "go": .go,
        "rs": .rust,
        "java": .java,
        "kt": .kotlin, "kts": .kotlin,
        "c": .cpp, "h": .cpp, "cc": .cpp, "cpp": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp,
        "cs": .csharp,
        "dart": .dart,
        "zig": .zig,
        "php": .php,
        "lua": .lua,
        "css": .css, "scss": .css, "sass": .css, "less": .css,
        "sql": .sql,
        "yaml": .yaml, "yml": .yaml,
        "xml": .xml, "xsl": .xml, "xslt": .xml, "svg": .xml, "plist": .xml,
        "astro": .javascript, "svelte": .javascript, "vue": .javascript,
        "gitignore": .shell, "dockerignore": .shell,
        "toml": .config, "ini": .config, "cfg": .config, "conf": .config, "env": .config,
        "properties": .config, "tf": .config, "tfvars": .config, "proto": .config,
        "graphql": .config, "gql": .config, "gradle": .config, "cmake": .config
    ]

    static func isSupportedMarkdownFile(_ url: URL) -> Bool {
        detectDocumentType(for: url) == .markdown
    }

    static func detectDocumentType(for url: URL) -> DocumentType {
        let ext = url.pathExtension.lowercased()

        if markdownExtensions.contains(ext) {
            return .markdown
        }

        if notebookExtensions.contains(ext) {
            return .notebook
        }

        if excalidrawExtensions.contains(ext) {
            return .whiteboard
        }

        if latexExtensions.contains(ext) {
            return .latex
        }

        if pythonExtensions.contains(ext) {
            return .python
        }

        if jsonExtensions.contains(ext) {
            return .json
        }

        if rExtensions.contains(ext) {
            return .r
        }

        if ext == "pdf" {
            return .pdf
        }

        if officeExtensions.contains(ext) {
            return .office
        }

        if htmlExtensions.contains(ext) {
            return .html
        }

        if imageExtensions.contains(ext) {
            return .image
        }

        if plainTextExtensions.contains(ext) {
            return .plainText
        }

        if codeLanguageByExtension[ext] != nil {
            return .plainText
        }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) {
                return .pdf
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .html) {
                return .html
            }
            if type.conforms(to: .plainText) || type.conforms(to: .text) {
                return .plainText
            }
        }

        return .unsupported
    }

    static func detectCodeLanguage(for extensionToken: String) -> CodeLanguageKind? {
        codeLanguageByExtension[extensionToken]
    }
}
