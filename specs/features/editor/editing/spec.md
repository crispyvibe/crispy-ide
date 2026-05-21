# F007 Editing

**Domain:** Editor
Status: draft

---

## Requirements

### F007-R01: Code and Plain-Text Opening
Plain text, code, and config files open in a monospaced editable surface with language-aware syntax highlighting for recognized extensions.

### F007-R02: Unsupported Type Fallback
Unsupported file types fall back to plain text editing when decodable, or show an unavailable preview when read fails.

### F007-R03: Language-Aware Editors
Common language files route to syntax-aware editor hosts with accessibility identifiers. R files route to a dedicated R editor mode.

### F007-R04: Full Language Family Coverage
The code editor supports 20+ language families including Swift, JavaScript, TypeScript, Python, R, Ruby, Go, Rust, C, C++, Objective-C, Java, Kotlin, SQL, HTML, CSS, YAML, TOML, JSON, Shell, and framework extensions (JSX, TSX, Vue, Svelte, etc.).

### F007-R05: Syntax Highlighting Character Limit
Syntax highlighting is disabled beyond 180K characters; the file remains editable as plain text.

### F007-R06: Contrast Enforcement
The code editor enforces minimum contrast ratios for syntax token readability.

### F007-R07: Code Find and Replace
Find and replace is available in the code editor via Cmd+F with match highlighting.

### F007-R08: JSON Dedicated Editor Plugin
JSON/JSONC files route to a dedicated plugin with formatting and validation features.

### F007-R09: Plain Text Extension Coverage
Recognized plain-text extensions (.txt, .log, .env, .cfg, .ini, .conf) route to the text editor with save/autosave.

### F007-R10: Find and Replace for Rich Text
Find and replace is available for editable markdown and HTML documents with case-insensitive matching, navigation, replace-next, and replace-all.

### F007-R11: Formatting Ribbon
A formatting ribbon with common actions is displayed for editable markdown/HTML documents, sending command payloads to the web editor.

### F007-R12: Rich Text Runtime Readiness
Content injection and format commands are deferred until the web editor signals readiness via `editorReady`.

### F007-R13: External Reload Preserves Editor View State
When an editable file is reloaded because its contents changed outside CrispyVibes, the current editor surface preserves selection and scroll position when the same document remains active.

---

## Scenarios

### F007-S01: Plain text/code/config files open in editable text/code mode
Given selected file is detected as plain text
When file load succeeds
Then text content is displayed in a monospaced editable surface
And recognized code/config extensions route to language-aware syntax highlighting

### F007-S02: Unsupported type fallback to editable text when decodable
Given selected file type is unsupported but readable as text
When file load succeeds
Then document mode downgrades to plain text editor mode
And content is editable and save/autosave behavior remains available

### F007-S03: Unsupported type reports unavailable preview when read fails
Given selected file type is unsupported and read fails
When file load is attempted
Then unsupported file message is shown to the user

### F007-S04: Common language files route to syntax-aware editor hosts
Given selected extension maps to a supported language family (for example Swift, JavaScript, SQL, YAML)
When file is opened
Then editor routes to the language-aware code host
And editor accessibility identifier reflects the language kind for UI automation coverage

### F007-S05: R files route to dedicated R editor mode
Given selected extension is `.r` or `.rmd`
When file is opened
Then document type is R
And editor routes to the dedicated R language renderer

### F007-S06: Code editor supports 20+ language families with framework extensions
Given selected file maps to a supported language family
When file is opened
Then syntax highlighting and language-aware features activate for the detected language
And supported families include Swift, JavaScript, TypeScript, Python, R, Ruby, Go, Rust, C, C++, Objective-C, Java, Kotlin, SQL, HTML, CSS, YAML, TOML, JSON, Shell, and framework extensions (JSX, TSX, Vue, Svelte, etc.)

### F007-S07: Syntax highlighting is disabled beyond 180K characters
Given a code file exceeds 180,000 characters
When the file is opened in the code editor
Then syntax highlighting is not applied
And the file remains editable as plain text

### F007-S08: Code editor enforces minimum contrast for syntax tokens
Given a code file is open with syntax highlighting active
When theme colors are applied to tokens
Then the editor enforces minimum contrast ratios for readability

### F007-S09: Find and replace is available in code editor
Given a code or plain-text document is open
When the user invokes find (Cmd+F)
Then a find and replace bar appears
And search matches are highlighted in the editor

### F007-S10: JSON files route to a dedicated editor plugin
Given selected file extension is `.json` or `.jsonc`
When file is opened
Then the editor activates the JSON-specific plugin
And JSON-aware features (formatting, validation) are available

### F007-S11: Plain text extensions are routed to the text editor
Given selected file has a recognized plain-text extension (e.g. `.txt`, `.log`, `.env`, `.cfg`, `.ini`, `.conf`)
When file is opened
Then the file opens in the plain-text editor mode
And content is editable with save/autosave behavior

### F007-S12: Find command opens find bar for editable docs
Given markdown or HTML document is open
When user triggers find command
Then find bar appears
And find field gets focus

### F007-S13: Replace command opens find+replace controls for editable docs
Given markdown or HTML document is open
When user triggers replace command
Then find bar appears in replace mode
And replace field/actions are available

### F007-S14: Find/replace is blocked for non-editable documents
Given current document is image/pdf/unsupported/none
When user triggers find or replace command
Then editor shows an error message that operation is only for editable text documents

### F007-S15: Find matches are case-insensitive and navigable
Given find query has one or more matches
When user presses `Next`
Then selection index advances cyclically through matches
And status text shows `N of M`

### F007-S16: Replace Next updates one match and preserves navigation
Given find query has matches
When user selects `Replace Next`
Then currently targeted match is replaced
And match state refreshes for updated content

### F007-S17: Replace All updates every case-insensitive match
Given find query has matches
When user selects `Replace All`
Then all matches are replaced
And status message reports number of replaced occurrences

### F007-S18: Done closes find UI
Given find/replace bar is visible
When user clicks `Done` or Escape shortcut for that action
Then find/replace state resets and bar closes

### F007-S19: Formatting ribbon is visible for editable markdown/HTML
Given document type is markdown or html
When editor renders
Then formatting ribbon with common actions is displayed

### F007-S20: Formatting command request is sent to rendering surface
Given user clicks a formatting ribbon button
When command request is created
Then web editor receives a command payload once per unique request id
And content sync runs after formatting mutation

### F007-S21: Supported formatting commands
Given ribbon is active
When user picks a command
Then one of these actions is applied: bold, italic, heading1, heading2, unordered list, ordered list, block quote, code block, link, image, table, horizontal rule

### F007-S22: Renderer readiness gates sync behavior
Given editor web runtime is loading
When `editorReady` has not been received
Then content injection/format command application are deferred
When `editorReady` is received
Then initial content is synchronized immediately

### F007-S23: External file refresh preserves same-document view state (EDT-040)
Given an editable file is already open in source mode
And the user has scrolled away from the top of the document
When the file changes outside CrispyVibes and the current document reloads
Then the editor keeps the same document active
And the existing content remains visible until replacement text is ready
And selection and scroll position are restored after the reload unless an explicit source-selection jump is pending
