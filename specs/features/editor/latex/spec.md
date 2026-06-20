# LaTeX Editor — Spec

Status: implemented

## Overview

F057 makes LaTeX a first-class document type in Crispy. Files with a `.tex`, `.latex`, or `.ltx` extension open in a dedicated split editor with two modes the user toggles between:

- **Source** — the code editor (syntax-aware, find/replace, the usual text-editing affordances) with a math-symbol **palette** that inserts LaTeX snippets at the caret.
- **Edit** (the default rich/WYSIWYG mode) — the document body is rendered by a vendored, fully **offline** KaTeX runtime in a `WKWebView`. Prose, headings, and lists are edited in place; math is typeset by KaTeX and edited through a popup equation editor with a clickable symbol grid. Every edit round-trips back to LaTeX source, **preserving the preamble, postamble, comments, and any environment Crispy does not model (e.g. `tikzpicture`) byte-for-byte verbatim**.

The same KaTeX runtime also powers a second, smaller capability: **inline math in the existing markdown editor** (F008). `$…$` and `$$…$$` in a markdown document now typeset via KaTeX in the rendered view and round-trip back to their delimiters on save via a Turndown rule.

The feature reuses Crispy's existing file-backed editor plumbing end to end — document-type detection → editor plugin → `DocumentBuffer`/autosave — exactly like markdown and the F052 whiteboard. The only net-new infrastructure is the vendored offline KaTeX runtime (`Resources/LaTeXRuntime/`), the WYSIWYG bridge (`latex-bridge.js`), and the `LaTeXPreviewView` host.

## Dependencies

- F007 (Editing) — the Source mode is the standard `CodeEditorView`; the buffer + autosave pipeline is shared.
- F008 (Markdown) — the inline-KaTeX-in-markdown capability extends the markdown rich editor and its Turndown serialization. LaTeX reuses the markup view-mode (Source/Edit) toggle built for markdown.
- F039 (Document Buffer) — the LaTeX source flows through `DocumentBuffer` and `AutosaveScheduler`; the buffer holds raw LaTeX so it autosaves like any text file.
- F006 (Content Viewer) — hosts the LaTeX document as an editor tab.

## Requirements

### F057-R01: LaTeX document type
`.tex`, `.latex`, and `.ltx` files MUST be detected as a distinct `DocumentType.latex` and routed to the LaTeX editor. Detection MUST take precedence over the generic plain-text/code path so these extensions never fall back to a raw code view by accident.

### F057-R02: Source / Edit toggle
A LaTeX document MUST offer the same markup view-mode toggle as markdown: a **Source** mode (editable code) and an **Edit** (rich/WYSIWYG) mode. The default on open is the Edit mode. The chosen mode is remembered per open document.

### F057-R03: Offline KaTeX rendering
The Edit mode MUST render math with a runtime vendored in the app bundle. It MUST function with no network access and MUST NOT contact any remote origin at runtime (no CDN, no telemetry, no remote fonts).

### F057-R04: Math symbol palette
Both modes MUST expose a palette of common math templates and symbols (fraction, superscript/subscript, root, sum, integral, Greek letters, relations, matrix, …). Activating a palette item inserts the corresponding LaTeX snippet at the caret. In Source mode the snippet is inserted as text; in Edit mode it is inserted and immediately typeset.

### F057-R05: In-place prose editing
In Edit mode, prose, section headings, and `itemize`/`enumerate` lists MUST be editable directly in the rendered surface (typing, Enter for new paragraphs, the formatting toolbar for bold/italic/headings/lists/code).

### F057-R06: Math editing via popup
In Edit mode, display equations and inline math MUST be rendered read-only and open a popup equation editor on click. The popup MUST show a live KaTeX preview and a clickable symbol grid so a user can build math without knowing LaTeX; it MUST also expose the raw TeX for power users. Committing the popup updates the document.

### F057-R07: Lossless round-trip
Editing MUST round-trip back to LaTeX without destroying source Crispy cannot represent. The preamble (everything up to and including `\begin{document}`) and postamble (`\end{document}` onward), comments, `\maketitle`, and unmodeled environments MUST be preserved verbatim. Editable blocks the user did **not** touch MUST be re-emitted byte-for-byte (a single edit never reflows or normalizes the rest of the document).

### F057-R08: Display vs inline math is preserved
A round-trip MUST NOT demote display math (`\[…\]`, `$$…$$`, `equation`/`align`/`gather`/…) to inline `$…$`, nor promote inline to display. Math environments MUST stay environments, not be wrapped in `\[…\]`.

### F057-R09: File-backed, autosaving
A LaTeX document is a real text file. Edits (from either mode) MUST be persisted through the standard document buffer + autosave path. No separate database.

### F057-R10: Inline KaTeX in markdown
The markdown rich editor MUST typeset `$…$` (inline) and `$$…$$` (display) math via KaTeX, mark the rendered math non-editable, and round-trip it back to the original delimiters on save by recovering the embedded TeX (not by serializing rendered spans).

### F057-R11: Navigation containment
The Edit-mode web view MUST be confined to the bundled `file://` runtime. External links MUST open in the system browser; in-app navigation to remote, `data:`, or other origins MUST be denied.

### F057-R12: Theme-aware
The Edit-mode surface MUST follow the app's light/dark appearance.

### F057-R13: Graceful degradation
If the vendored runtime is missing from the build, the Edit mode MUST show an explanatory message rather than a blank pane.

### F057-R14: Reproducible runtime build
The offline runtime MUST be produced from a pinned dependency by a checked-in build script, with a committed SHA256 checksum manifest of the vendored assets.

## Scenarios

### Scenario F057-S01: Open a LaTeX file (Given / When / Then)
- **Given** a `.tex` file in a project, **when** the user opens it, **then** it opens as a LaTeX document in the Edit (rich) mode, with the body typeset by KaTeX and the preamble hidden but preserved.

### Scenario F057-S02: Toggle to Source
- **Given** an open LaTeX document in Edit mode, **when** the user switches to Source, **then** the raw `.tex` is shown in the code editor; switching back to Edit re-renders the (possibly edited) source.

### Scenario F057-S03: Insert a symbol from the palette (Source)
- **Given** the Source mode with the caret in math, **when** the user clicks a palette item (e.g. `\frac{}{}`), **then** the snippet is inserted at the caret and the buffer is marked dirty.

### Scenario F057-S04: Edit prose in place
- **Given** the Edit mode, **when** the user edits a paragraph's text, **then** only that block changes in the serialized source; every other block (lists, math, comments, unknown environments) is re-emitted byte-for-byte.

### Scenario F057-S05: Edit an equation via the popup
- **Given** a display equation in Edit mode, **when** the user clicks it, **then** a popup opens with a live KaTeX preview, a symbol grid, and the raw TeX; on commit the equation re-renders and the source updates.

### Scenario F057-S06: Round-trip preserves unmodeled source
- **Given** a document containing a preamble, `\maketitle`, an `align` environment, a `% comment`, and a `tikzpicture`, **when** the user edits one paragraph and saves, **then** the preamble, `\maketitle`, `align`, comment, and `tikzpicture` are all present unchanged, the `align` stays an environment (not wrapped in `\[…\]`), and display math stays display.

### Scenario F057-S07: Build from a blank document
- **Given** a new empty `.tex` (no `\begin{document}` body content), **when** the user adds a heading and a paragraph in Edit mode, **then** they serialize to `\section{…}` and prose inside the document body.

### Scenario F057-S08: Insert rendered math in Edit mode
- **Given** the Edit mode, **when** the user inserts `\alpha` from the palette, **then** it is rendered as typeset math (not raw LaTeX) and serializes back as `$\alpha$`; inserting a matrix/environment serializes as display `\[…\]`.

### Scenario F057-S09: Offline guarantee
- **Given** no network connectivity, **when** a LaTeX document is opened and edited, **then** KaTeX, its CSS, and all fonts load from the bundle and editing works normally.

### Scenario F057-S10: Inline math in markdown
- **Given** a markdown document containing `$E = mc^2$` and a `$$…$$` block, **when** it is viewed in the markdown rich editor, **then** both render via KaTeX; on save they round-trip back to `$…$` / `$$…$$` with the exact original TeX.

### Scenario F057-S11: Dark mode
- **Given** the app is in dark appearance, **when** a LaTeX document opens in Edit mode, **then** the surface renders with theme-appropriate colors (no white flash).

### Scenario F057-S12: Runtime missing
- **Given** a build without the vendored runtime, **when** a LaTeX document is opened in Edit mode, **then** an "unavailable" message is shown instead of a blank pane.

### Scenario F057-S13: External link
- **Given** a link to a remote URL in the Edit-mode surface, **when** the user activates it, **then** it opens in the system browser, not in the embedded web view.

## Acceptance Criteria

- `.tex`/`.latex`/`.ltx` detect to `DocumentType.latex` ahead of the generic code path (S01); the Source/Edit toggle defaults to Edit and is remembered per document (S02).
- Opening, editing (prose and math), and saving LaTeX works with networking disabled (S01–S09).
- Editing one block leaves all other blocks byte-verbatim; preamble/postamble/comments/`\maketitle`/unknown environments are preserved; display↔inline distinction and math environments are never altered (S04, S06, S08). Verified by `web/latex-runtime/roundtrip.test.js` (14 DOM round-trip checks).
- The palette inserts snippets in both modes; Edit-mode insertion renders immediately (S03, S08).
- Markdown inline/display math renders via KaTeX and round-trips through the Turndown `katexMath` rule (S10).
- No remote origin is reachable from either runtime (CSP + navigation policy); external links open in the system browser (S09, S13).
- `xcodebuild -scheme crispyvibes-local` builds; `web/latex-runtime/build.sh` reproduces the bundle from the pinned KaTeX version and the committed `SHA256SUMS` manifest verifies the vendored assets.

## Open Questions

1. Should additional environments (tables/`tabular`, `figure`, theorem-like) get first-class in-place editing, or remain preserved-verbatim raw atoms (current: raw atoms)?
2. Should the equation popup offer a larger, categorized symbol catalog (current: a fixed 16-key common set)?
3. Is a `latex.*` agent CLI (`new|render|check`) worth adding for automation? (Deferred.)
4. **Resolved:** the markdown editor's KaTeX **scripts** are now co-located in `MarkdownRuntime/` (loaded under `'self'`, no `script-src file:`); the CSS/fonts are still shared from `LaTeXRuntime/`. See technical-design CSP Posture and threat-model F057-T05.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-06-17 | Initial implementation: `.tex/.latex/.ltx` document type, Source/Edit split editor, offline KaTeX WYSIWYG with verbatim-preserving round-trip, math palette + popup equation editor, and inline KaTeX in the markdown editor. Vendored KaTeX 0.16.11 via `web/latex-runtime/build.sh` with a SHA256 manifest. | — |
