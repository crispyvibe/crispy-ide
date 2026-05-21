# F008 Markdown

**Domain:** Editor
Status: draft

---

## Requirements

### F008-R01: Markdown Opening and Editing
Markdown files (.md, .markdown) open in an editable rendered mode with save support.

### F008-R02: Content Sync and Rendering
Edited rich content is converted back to canonical markdown via Turndown and sent to the native view model. Code blocks receive syntax highlighting.

### F008-R03: Guided Link Authoring
Link insertion requires selected text, prompts for a URL, and linkifies the selection with markdown syntax.

### F008-R04: Guided Image Authoring
Image insertion opens a searchable image picker with case-insensitive filtering and inserts markdown image syntax with resolved path and editable alt text.

### F008-R05: Guided Table Authoring
Table insertion prompts for row and column counts and inserts a markdown table with header and separator rows.

### F008-R06: Rich/Source View Mode Toggle
The markdown editor supports toggling between rendered rich view and raw source view with content state preserved.

### F008-R07: Find and Replace
Find and replace is available via Cmd+F with match highlighting in the active view.

### F008-R08: Formatting Toolbar
The full formatting toolbar provides bold, italic, headings, lists, blockquote, code block, and horizontal rule actions.

### F008-R09: MDX Extension Support
Files with .mdx extension open in the markdown editor with identical editing and rendering behavior.

### F008-R10: WKWebView Crash Recovery
The markdown editor detects WKWebView crashes and re-renders content automatically with no data loss.

### F008-R11: Theme Token Injection
Approximately 50 CSS custom properties are injected into the WKWebView to reflect the active theme.

---

## Scenarios

### F008-S01: Markdown files open in editable rendered mode
Given selected file extension is `.md` or `.markdown`
When file load succeeds
Then markdown source is loaded
And rendered editor is shown
And document can be edited and saved

### F008-S02: Markdown mode stores canonical markdown content
Given markdown editor is active
When user edits rendered content
Then HTML is converted back to markdown via Turndown
And markdown source is sent to native view model

### F008-S03: Markdown code blocks are syntax-highlighted
Given markdown content contains code fences
When markdown renders or formatting changes
Then syntax highlighting is applied to code blocks

### F008-S04: Link command requires selected text
Given markdown editor mode is active
When user clicks `Link` and no text is selected
Then editor does not insert a placeholder link
And editor shows a subtle non-blocking notification: `Select text first to add a link.`

#### Assertions for S04
- Assert no markdown mutation occurs when no text is selected.
- Assert notification text equals `Select text first to add a link.`.
- Assert no placeholder anchor is inserted.

### F008-S05: Link command prompts for URL and linkifies selected text
Given markdown editor mode is active
And user has selected text in the editor
When user clicks `Link`
Then editor opens a URL input prompt anchored to the editing context
When user provides a valid URL and confirms
Then the selected text is replaced with markdown link syntax using the provided URL

#### Assertions for S05
- Assert URL prompt opens only when selection exists.
- Assert URL field receives initial focus.
- Assert apply link transforms selected text into markdown link syntax.
- Assert empty URL keeps dialog open and blocks insertion.

### F008-S06: Image command opens searchable image picker
Given markdown editor mode is active
When user clicks `Image`
Then editor opens an image picker instead of inserting a placeholder image tag
And picker provides filename search with case-insensitive filtering
And user can select one image and confirm insertion
Then editor inserts markdown image syntax with resolved file path and editable alt text

#### Assertions for S06
- Assert `Image` opens picker instead of direct placeholder insertion.
- Assert search filters candidates case-insensitively by filename/path.
- Assert confirm inserts markdown image syntax with normalized relative path.
- Assert default alt text derives from filename and can be edited before insert.

### F008-S07: Table command prompts for dimensions before insertion
Given markdown editor mode is active
When user clicks `Table`
Then editor opens a table-size prompt that accepts row and column counts
When user confirms valid dimensions
Then editor inserts a markdown table with matching number of columns and body rows
And inserted table includes a header row and separator row

#### Assertions for S07
- Assert table dialog opens with rows/columns inputs defaulted to `3`.
- Assert invalid row/column values block insertion and show validation feedback.
- Assert valid confirm inserts table containing header and separator rows.
- Assert inserted table column count equals requested columns.

### F008-S08: Markdown editor supports rich/source view mode toggle
Given a markdown document is open
When the user toggles view mode
Then the editor switches between rendered rich view and raw source view
And content state is preserved across toggles

### F008-S09: Find and replace is available in markdown editor via Cmd+F
Given a markdown document is open
When the user invokes find (Cmd+F)
Then a find and replace bar appears
And search matches are highlighted in the active view

### F008-S10: Full formatting toolbar provides bold, italic, headings, lists, quote, code block, and hr
Given a markdown document is open in rich editing mode
When the formatting toolbar is visible
Then actions are available for bold, italic, headings, lists, blockquote, code block, and horizontal rule
And each action inserts or wraps the appropriate markdown syntax

### F008-S11: Files with .mdx extension open in markdown editor
Given selected file extension is `.mdx`
When file load succeeds
Then the file is routed to the markdown editor
And editing and rendering behavior matches `.md` files

### F008-S12: Markdown editor recovers from WKWebView crash
Given a markdown document is rendered in WKWebView
When the web process crashes
Then the editor detects the crash and re-renders content automatically
And no user data is lost

### F008-S13: Theme tokens are injected as CSS custom properties into markdown renderer
Given a markdown document is rendered
When the active theme changes or content loads
Then approximately 50 CSS custom properties are injected into the WKWebView
And rendered content reflects the current theme
