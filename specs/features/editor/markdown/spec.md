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

### F008-R12: Stable Rich-Editor Selection and Sync
Rich-mode content synchronization MUST preserve the user's caret or selection. Native content echoes and comment-decoration refreshes MUST NOT trigger recursive view updates or replace the live editing DOM.

### F008-R13: Currency-Safe Math Rendering
Numeric currency tokens beginning with `$` (including comma/decimal amounts and `K`/`M`/`B`/`T` suffixes) MUST remain literal editable prose in the rich Markdown editor and MUST NOT be consumed as `$…$` inline math. Symbolic single-dollar equations and explicit `\\(…\\)` Markdown-source math remain supported.

### F008-R14: Target-Aware Rich Markdown Links
Rich-mode Markdown links MUST be classified without navigating the editor WebView. Same-document fragments navigate to stable duplicate-safe heading IDs with visual feedback and document-local back history. Relative and `file:` links open through the current Crispy editor context and apply a fragment after a linked Markdown document loads. HTTP(S) links offer Crispy Browser, default browser, edit, copy, and remove actions when the saved preference is `Ask Each Time`; saved Crispy/default choices route directly while the context menu retains all actions. Option-click MUST place the caret for editing rather than navigate. Unsupported schemes, embedded web credentials, missing files, and malformed destinations MUST be blocked.

### F008-R15: Live Global Text Scale
Markdown and HTML rich-mode WKWebViews MUST apply the global current/default code-size ratio through shared, clamped presentation scaling during creation and update. Text, tables, Mermaid, KaTeX, dialogs, and authored HTML iframe content scale without reloading or replacing the live editing DOM.

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
And rendered tables are stored as GFM pipe-table syntax rather than HTML table elements

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

### F008-S14: Rich editing preserves the caret during synchronization
Given a markdown document is open in rich mode
And the caret is within editable text or a table cell
When edited content synchronizes to the native document buffer
Or native content is rendered back into the rich editor
Then the caret remains at the equivalent text offset
And repeated bridge registration or unchanged decoration payloads do not publish another view update

### F008-S15: Financial prose with multiple dollar amounts remains literal
Given a markdown document contains `**Objective 3: Modernize AA's EDP** \[$8M ARR by 2028, 2027 in year $2M\]`
When the document renders in rich mode
Then the objective text and both currency amounts remain visible with their original spacing
And no portion of the financial prose is rendered as KaTeX math
And symbolic inline math such as `$E = mc^2$` continues to render through KaTeX

### F008-S16: Same-document link navigates to a heading
Given rich Markdown contains `[Install](#installation)` and an `Installation` heading
When the link is clicked
Then the editor scrolls to the generated `installation` heading ID
And briefly highlights the heading
And ⌘[ returns to the previous document position
And no native URL navigation replaces the editor

### F008-S17: Relative Markdown link opens in Crispy at its fragment
Given `docs/index.md` contains `[Setup](../guide.md#setup)`
And the linked file exists
When the link is clicked in rich mode
Then the path resolves relative to `docs/index.md`
And `guide.md` opens in the current Crispy editor group
And its `setup` heading is scrolled into view after rendering

### F008-S18: Web link offers or applies the configured destination
Given a valid HTTP(S) link
When the saved preference is `Ask Each Time` and the link is clicked
Then an anchored popover offers `Open in Crispy`, `Default Browser`, `Edit`, `Copy`, and `Remove`
When the saved preference is `Crispy Browser` or `Default Browser`
Then a normal click routes directly to that destination
And a context-menu invocation still exposes all actions

### F008-S19: Existing link can be edited without accidental navigation
Given a rendered Markdown link
When the user Option-clicks it
Then the caret remains available for rich-text editing
When the user selects `Edit` from its action popover
Then the current destination is prefilled and can be updated
And `Remove` unwraps the link while preserving its visible content
And the canonical Markdown synchronizes through the normal Turndown bridge

### F008-S20: Unsafe or unavailable link is blocked
Given a link uses `javascript:`, `data:`, protocol-relative syntax, an unsupported scheme, embedded HTTP credentials, a malformed destination, or a missing local file
When the user activates it
Then the editor WebView does not navigate
And no unsafe native open action is performed
And a concise user-facing explanation is shown

### F008-S21: Global text size updates rich Markdown without reload
Given a Markdown or HTML document is open in rich mode
When the user invokes Cmd+, Cmd=, Cmd-, Cmd0, or a text-size menu action
Then the existing WKWebView page zoom updates to the clamped global document-size ratio
And rendered prose, tables, code, Mermaid/KaTeX, link UI, and HTML iframe content scale together
And content, caret/selection, scroll state, and unsaved edits remain intact

## Acceptance Criteria

- Headings receive deterministic IDs; duplicate headings receive `-2`, `-3`, and subsequent suffixes.
- Same-document navigation is immediate, highlighted, and reversible with ⌘[.
- Relative links resolve against the current document directory and preserve fragments across file opening.
- Web-link preference defaults to `Ask Each Time` and persists through `AppPreferences`.
- Crispy Browser routing uses the existing mode-aware browser-open path; default-browser routing uses the injected interaction service.
- Link editing, copying, removal, keyboard activation, context-menu activation, Escape dismissal, and Option-click caret placement work in rich mode.
- Native and WebView layers independently reject unsafe targets, and `WKNavigationDelegate` blocks link-activated replacement navigation.

### F008-R16: Optional Rich Logical Source Lines

When the global line-number mode is `All Text Views`, Markdown rich mode MUST label each annotated top-level logical block with its 1-based starting source line. Labels MUST use theme tokens and WebView presentation scaling, coexist with the independent comment gutter, add no serializable child nodes, and leave Turndown output unchanged. Source annotations MUST be cleared and recomputed after rich edits. Arbitrary HTML iframe mode MUST NOT display Markdown source-line labels.

### F008-S22: Rich line labels preserve Markdown

Given a Markdown document is open in rich mode and `All Text Views` is selected
When labels are toggled or rich blocks are edited
Then labels show current logical source-block starting lines
And wrapped visual rows receive no additional labels
And Turndown produces the same Markdown it would produce without labels
And switching to HTML mode removes the Markdown line-number presentation class.
