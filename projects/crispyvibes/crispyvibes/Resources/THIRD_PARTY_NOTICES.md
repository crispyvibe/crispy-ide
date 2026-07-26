# Third-Party Notices

This project uses third-party software. License details are listed below.

## Swift packages

### Ghostty
- **Version:** vendored runtime build
- **Local files:** `vendor/GhosttyKit.xcframework`, `Resources/GhosttyRuntime/ghostty`, `Resources/GhosttyRuntime/terminfo`
- **Provisioning:** generated locally via `projects/crispyvibes/scripts/setup-ghostty.sh`
- **Source:** https://github.com/ghostty-org/ghostty
- **License:** MIT

### SwiftTerm
- **Version:** 1.11.2
- **Source:** https://github.com/migueldeicaza/SwiftTerm
- **License:** MIT

### swift-argument-parser (transitive via SwiftTerm)
- **Version:** 1.7.0
- **Source:** https://github.com/apple/swift-argument-parser
- **License:** Apache-2.0

## Bundled markdown runtime assets (offline)

### marked
- **Version:** 17.0.3
- **Local file:** `Resources/MarkdownRuntime/marked.umd.js`
- **Source:** https://github.com/markedjs/marked
- **License:** MIT

### turndown
- **Version:** 7.2.2
- **Local file:** `Resources/MarkdownRuntime/turndown.js`
- **Source:** https://github.com/mixmark-io/turndown
- **License:** MIT

### highlight.js
- **Version:** 11.11.1
- **Local files:** `Resources/MarkdownRuntime/highlight.min.js`, `Resources/MarkdownRuntime/highlight-github-dark.min.css`
- **Source:** https://github.com/highlightjs/highlight.js
- **License:** BSD-3-Clause

### github-markdown-css
- **Version:** 5.8.1
- **Local file:** `Resources/MarkdownRuntime/github-markdown.min.css`
- **Source:** https://github.com/sindresorhus/github-markdown-css
- **License:** MIT

## Skill design references

The bundled Crispy skill packages were informed by the package structures and
workflow patterns in these MIT-licensed projects. They are design references,
not runtime dependencies.

### gstack
- **Copyright:** Copyright (c) 2026 Garry Tan
- **Source:** https://github.com/garrytan/gstack
- **License:** MIT

### skills
- **Copyright:** Copyright (c) 2026 Matt Pocock
- **Source:** https://github.com/mattpocock/skills
- **License:** MIT

---

For full license text, see each dependency's upstream repository.
