# LaTeX Editor — Spec

Status: implemented

## Overview

F057 makes LaTeX a first-class document type in Crispy. Files with a `.tex`, `.latex`, or `.ltx` extension open in a dedicated editor with three modes the user toggles between:

- **Edit** — the document body is rendered by a vendored, fully **offline** KaTeX runtime in a `WKWebView`. Prose, headings, lists, and the `abstract` / `IEEEkeywords` blocks are edited in place; math is typeset by KaTeX and edited through a popup equation editor with a clickable symbol grid. Every edit round-trips back to LaTeX source, **preserving the preamble, postamble, comments, and any environment Crispy does not model (e.g. `tikzpicture`, `tabular`, `thebibliography`) byte-for-byte verbatim**. This mode needs no LaTeX installation.
- **PDF** — the **full-TeX compiled preview**. When a local TeX toolchain (BasicTeX / MacTeX) is installed, Crispy compiles the document **offline** with `pdflatex -synctex=1` and shows the real, fully typeset PDF (document-class layout, two-column papers, author blocks, tables, bibliography) in a `PDFView`. You **edit on the page**: double-click any rendered text to open an inline editor for the surrounding source block; on save the document is rewritten and the page re-renders. You can also **select text and comment** directly on the PDF, and **double-click** the page to jump into the source. If no toolchain is present, this mode shows an actionable "install BasicTeX" empty-state.
- **Source** — the code editor (syntax-aware, find/replace, the usual text-editing affordances) with a math-symbol **palette** that inserts LaTeX snippets at the caret.

The default mode when opening a `.tex` file is **smart**: it opens in **PDF** when a local TeX toolchain is detected, otherwise in the dependency-free **Edit** view. The chosen mode is then remembered per document.

The same KaTeX runtime also powers a second, smaller capability: **inline math in the existing markdown editor** (F008). `$…$` and `$$…$$` in a markdown document now typeset via KaTeX in the rendered view and round-trip back to their delimiters on save via a Turndown rule.

The feature reuses Crispy's existing file-backed editor plumbing end to end — document-type detection → editor plugin → `DocumentBuffer`/autosave — exactly like markdown and the F052 whiteboard. The net-new infrastructure is the vendored offline KaTeX runtime (`Resources/LaTeXRuntime/`), the WYSIWYG bridge (`latex-bridge.js`), the `LaTeXPreviewView` host, and — for the PDF mode — the native, offline `LaTeXNativeCompiler` plus the `LaTeXCompiledPreviewView` / `CompiledPreviewSupportViews` PDF surface that drives compile, SyncTeX-based on-page editing, and select-to-comment. The same compiled-preview scaffold is shared by the sibling Typst (`typst`), Graphviz (`dot`), and AsciiDoc (`asciidoctor`) document types.

> **As-built note.** An earlier full-TeX approach (a SwiftLaTeX WASM engine fetching packages from a remote server) was **abandoned** — the package server was permanently unreachable and the approach could not satisfy the offline-first requirement. The shipped design compiles with the user's **locally installed** TeX toolchain via `Process`, fully offline. The app is **not sandboxed** (`get-task-allow` only), which is what permits launching `pdflatex`/`synctex`. See `specs/planning/2026-06-20-latex-full-tex-offline-handover.md`.

## Dependencies

- F007 (Editing) — the Source mode is the standard `CodeEditorView`; the buffer + autosave pipeline is shared.
- F008 (Markdown) — the inline-KaTeX-in-markdown capability extends the markdown rich editor and its Turndown serialization. LaTeX reuses the markup view-mode toggle built for markdown.
- F039 (Document Buffer) — the LaTeX source flows through `DocumentBuffer` and `AutosaveScheduler`; the buffer holds raw LaTeX so it autosaves like any text file. On-page edits in the PDF mode write back through this same path.
- F049 (File Comments) — the PDF mode posts the **same** `.commentsRequestAddForSelection` notification and `CommentAnchor` schema used by Source/Edit, so comments thread through the shared `VibeSpaceCommentStore` regardless of which surface created them.
- F006 (Content Viewer) — hosts the LaTeX document as an editor tab.
- **External toolchain (runtime, optional):** a local TeX Live install (BasicTeX / MacTeX) providing `pdflatex`, `bibtex`, and `synctex`. Discovered on disk; not bundled. The PDF mode is gated on its presence; Edit and Source never require it.

## Requirements

### F057-R01: LaTeX document type
`.tex`, `.latex`, and `.ltx` files MUST be detected as a distinct `DocumentType.latex` and routed to the LaTeX editor. Detection MUST take precedence over the generic plain-text/code path so these extensions never fall back to a raw code view by accident.

### F057-R02: Source / Edit / PDF toggle
A LaTeX document MUST offer a markup view-mode toggle with three segments: **Edit** (rich/WYSIWYG KaTeX), **Source** (editable code), and **PDF** (full-TeX compiled preview). The PDF segment is LaTeX-only (the markdown/HTML toggle remains two-segment). The default mode is **smart** (see F057-R16). The chosen mode is remembered per open document.

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
The offline KaTeX runtime MUST be produced from a pinned dependency by a checked-in build script, with a committed SHA256 checksum manifest of the vendored assets.

### F057-R15: Full-TeX compiled PDF preview (PDF mode)
The PDF mode MUST compile the document to a real PDF using the **local** TeX toolchain and render it in a `PDFView`. Compilation MUST run `pdflatex -synctex=1 -interaction=nonstopmode -output-directory=<temp>` in a fresh temporary build directory, with `TEXINPUTS` extended to include the document's own folder so its `\input`/`\includegraphics`/local classes resolve. It MUST run multiple passes (up to 4) until cross-references stabilize, and MUST run `bibtex` when the document declares a bibliography (`\bibliography{…}` or `\addbibresource`). The preview re-compiles, debounced (~0.7 s), as the source changes.

### F057-R16: Smart default mode
On open, a `.tex`/`.latex`/`.ltx` document MUST default to the **PDF** mode when a local TeX toolchain is detected (`LaTeXNativeCompiler.isToolchainAvailable`, probing `/Library/TeX/texbin` and known TeX Live `bin` dirs for `pdflatex`), and otherwise to the dependency-free **Edit** (KaTeX) mode. The per-document remembered mode (F057-R02) overrides the default once the user changes it.

### F057-R17: Offline, bounded compilation
Compilation MUST function with **no network access** — it uses only the locally installed engine and packages. Each external process MUST be bounded: a watchdog terminates a `pdflatex` pass after 30 s (and a `synctex` query after 10 s), and cancelling the enclosing task (e.g. a superseding edit or closing the view) MUST terminate the running process. Because the app is **not sandboxed**, these processes run with the user's own privileges.

### F057-R18: On-page (edit-in-PDF) editing
In PDF mode, **double-clicking** rendered text MUST map the click back to a source line via the SyncTeX reverse map (`synctex edit`), expand that line to its surrounding blank-line-delimited source block, and open a multi-line floating editor (`BlockEditTextView`) prefilled with the block and headed "Editing line N" / "Editing lines N–M". Committing (Save button or ⌘↩) MUST replace exactly that block in the source — guarded so a drifted block (changed by a concurrent edit/recompile) is **not** overwritten — push the updated document to the buffer, and trigger a re-compile. Cancelling (Esc or Cancel) MUST discard.

### F057-R19: Mapped-region highlight
When an on-page edit begins, Crispy MUST forward-map the edited block's source line(s) to PDF box(es) via SyncTeX (`synctex view`) and draw a translucent `PDFAnnotation` over that region so the user sees which area the edit affects. The highlight MUST be cleared when the editor closes and on each re-render.

### F057-R20: Non-destructive compile errors & stable view
A compile failure MUST be non-destructive: if a previously good PDF is displayed, Crispy MUST keep showing it and surface a **dismissible** "compilation failed — showing the last successful render" banner; only when there is no prior PDF does it show the error log. A re-render MUST preserve the reader's page **and scroll position** (not jump to the top). A one-time first-run hint ("Double-click any text to edit · ⌘↩ to save") MUST be shown the first time a PDF renders.

### F057-R21: Comments on the PDF
In PDF mode, selecting text MUST surface a floating **Comment** affordance. Activating it MUST map the selection to its source line(s) via SyncTeX and post the **same** `.commentsRequestAddForSelection` request used by the Source and Edit surfaces, with a `CommentAnchor` whose anchor text is the selected text (falling back to the mapped source lines) — so comments created on the PDF thread through the shared comment store identically to comments created elsewhere (F049).

### F057-R22: Toolchain-missing empty state
When PDF mode is selected but no TeX toolchain is found, Crispy MUST show an actionable empty-state (`LaTeXCompiledPane`) that: states a TeX engine is required, shows the install command `brew install --cask basictex` with a copy button, offers a **Recheck** action that re-probes the toolchain, a **Use Edit Tab** action that switches to the dependency-free Edit view, and a **Get BasicTeX** link. It MUST NOT block use of the Edit or Source modes.

### F057-R23: Edit (KaTeX) view fidelity & robustness
The Edit mode MUST additionally:
- render `abstract` and `IEEEkeywords` as **editable** blocks that round-trip through environment markers (`\begin{abstract}…\end{abstract}`, `\begin{IEEEkeywords}…\end{IEEEkeywords}`), emitting the wrapper only for blocks the user actually edited;
- render `table`/`tabular` and `thebibliography` as **read-only rendered atoms** (a real table / numbered reference list) that are preserved verbatim on serialize;
- unwrap IEEE `\IEEEauthorblockN`/`\IEEEauthorblockA` macros in the title block so authors read as names + affiliations;
- expand common text-mode constructs in prose (`\%`, `\&`, `\#`, `\_`, `` `` ``/`''` quotes, `--`/`---` dashes, `\,` thin space, `\TeX`/`\LaTeX`, the `{,}` digit-group idiom, `\$`) and apply a **reversible re-escape** on serialize so editing prose can never corrupt LaTeX specials;
- be hardened so that an error rendering one block falls back to a read-only raw atom rather than aborting the render or leaving the surface non-editable.

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

### Scenario F057-S14: Smart default — toolchain present
- **Given** a machine with BasicTeX installed, **when** the user opens a `.tex` file, **then** it opens in the **PDF** mode and the full document is compiled and shown typeset.

### Scenario F057-S15: Smart default — no toolchain
- **Given** a machine with no TeX install, **when** the user opens a `.tex` file, **then** it opens in the **Edit** (KaTeX) mode; selecting the **PDF** tab shows the "install BasicTeX" empty-state, not an error or a blank pane.

### Scenario F057-S16: Compile a full-TeX document offline
- **Given** an IEEE paper `.tex` (two-column class, author blocks, abstract, `tabular`, bibliography) and BasicTeX installed, **when** it opens in PDF mode with networking disabled, **then** `pdflatex` compiles it locally (running `bibtex` and re-running until references stabilize) and the real, fully typeset PDF renders in the `PDFView`.

### Scenario F057-S17: Edit on the page
- **Given** a rendered PDF, **when** the user double-clicks a paragraph, **then** a floating editor opens prefilled with that source block (headed "Editing lines N–M") with its region highlighted on the page; on **Save** (or ⌘↩) the block is rewritten, the document autosaves, and the page re-renders with the change.

### Scenario F057-S18: Compile error is non-destructive
- **Given** a successfully rendered PDF, **when** the user makes an edit that fails to compile, **then** the last good PDF stays on screen with a dismissible "compilation failed — showing the last successful render" banner, and the reader's scroll position is preserved.

### Scenario F057-S19: Comment on the PDF
- **Given** a rendered PDF and an open comment-capable document, **when** the user selects text and clicks the floating **Comment** button, **then** the selection is mapped to source line(s) via SyncTeX and a comment composer opens with the selected text quoted — threading into the same comment store as comments made in Source/Edit.

### Scenario F057-S20: Toolchain-missing actions
- **Given** the PDF mode with no toolchain, **when** the user clicks the copy button, **then** `brew install --cask basictex` is on the clipboard; **Recheck** re-probes (and switches to the live PDF once TeX is installed); **Use Edit Tab** switches to the Edit view.

### Scenario F057-S21: Cross-references and citations resolve
- **Given** a document with `\ref`/`\cite` and a `\bibliography`, **when** it is compiled in PDF mode, **then** the multi-pass compile + `bibtex` resolves them so the PDF shows real numbers/citations rather than `??`/`[?]` placeholders.

### Scenario F057-S22: Abstract / keywords round-trip in Edit mode
- **Given** a document with `abstract` and `IEEEkeywords` environments in Edit mode, **when** the user edits the abstract text and saves, **then** only the abstract's body changes, it is re-emitted as `\begin{abstract}…\end{abstract}`, and an untouched `IEEEkeywords` is preserved byte-for-byte.

### Scenario F057-S23: Editing prose can't corrupt specials
- **Given** a paragraph rendered in Edit mode containing `&`, `%`, an em-dash, and curly quotes, **when** the user edits and saves it, **then** they serialize back to valid LaTeX (`\&`, `\%`, `---`, `` `` ``/`''`) rather than raw characters that would break compilation.

## Acceptance Criteria

- `.tex`/`.latex`/`.ltx` detect to `DocumentType.latex` ahead of the generic code path (S01); the three-segment Edit/Source/PDF toggle uses the smart default (PDF when a toolchain is present, else Edit) and is remembered per document (S02, S14, S15).
- Opening, editing (prose and math), and saving LaTeX works with networking disabled (S01–S09).
- Editing one block leaves all other blocks byte-verbatim; preamble/postamble/comments/`\maketitle`/unknown environments are preserved; display↔inline distinction and math environments are never altered (S04, S06, S08). Verified by `web/latex-runtime/roundtrip.test.js` (14 DOM round-trip checks).
- The palette inserts snippets in both modes; Edit-mode insertion renders immediately (S03, S08).
- Markdown inline/display math renders via KaTeX and round-trips through the Turndown `katexMath` rule (S10).
- No remote origin is reachable from either runtime (CSP + navigation policy); external links open in the system browser (S09, S13).
- `xcodebuild -scheme crispyvibes-local` builds; `web/latex-runtime/build.sh` reproduces the bundle from the pinned KaTeX version and the committed `SHA256SUMS` manifest verifies the vendored assets.
- The mode toggle shows three segments for LaTeX (Edit/Source/PDF); `.tex` defaults to PDF when a toolchain is present, else Edit (S14, S15). The PDF mode compiles full TeX offline with `pdflatex -synctex=1`, multi-pass + `bibtex`, into a `PDFView` (S16, S21).
- Double-click on the PDF opens an inline block editor mapped via SyncTeX; Save rewrites the block (drift-guarded) and re-renders; the edited region is highlighted (S17). Compile failures keep the last good PDF behind a dismissible banner and preserve scroll position (S18).
- Selecting text on the PDF and clicking Comment posts the shared `.commentsRequestAddForSelection` with a source-line `CommentAnchor` (S19). The toolchain-missing empty-state offers copy/recheck/use-edit/get-BasicTeX (S20).
- Verified by build + by shell-level checks of `pdflatex -synctex=1` and `synctex edit` (the GUI click→edit→re-render loop is shell-verified end to end; see the handover doc). Real samples (`ieee-paper.tex`, `sample-resume.tex`) compile fully offline.

## Open Questions

1. Should additional environments (tables/`tabular`, `figure`, theorem-like) get first-class in-place editing, or remain preserved-verbatim raw atoms (current: raw atoms)?
2. Should the equation popup offer a larger, categorized symbol catalog (current: a fixed 16-key common set)?
3. Is a `latex.*` agent CLI (`new|render|check`) worth adding for automation? (Deferred.)
4. **Resolved:** the markdown editor's KaTeX **scripts** are now co-located in `MarkdownRuntime/` (loaded under `'self'`, no `script-src file:`); the CSS/fonts are still shared from `LaTeXRuntime/`. See technical-design CSP Posture and threat-model F057-T05.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-06-17 | Initial implementation: `.tex/.latex/.ltx` document type, Source/Edit split editor, offline KaTeX WYSIWYG with verbatim-preserving round-trip, math palette + popup equation editor, and inline KaTeX in the markdown editor. Vendored KaTeX 0.16.11 via `web/latex-runtime/build.sh` with a SHA256 manifest. | — |
| 2026-06-20 | Added the **PDF (compiled)** mode: full-TeX, fully offline preview via the local toolchain (`LaTeXNativeCompiler`, `pdflatex -synctex=1`), rendered in a `PDFView` with SyncTeX double-click on-page block editing, mapped-region highlight, select-to-comment, non-destructive compile errors, scroll preservation, and a "TeX engine not installed" empty-state. Smart default (PDF when a toolchain is detected, else Edit). Edit-mode fidelity: editable `abstract`/`IEEEkeywords`, read-only `tabular`/`thebibliography` atoms, IEEE author-block unwrapping, expanded inline escapes with a reversible re-escape on serialize, and render hardening. Replaces the abandoned SwiftLaTeX WASM/remote-server approach (offline-incompatible). (R15–R23, S14–S23, T10–T14.) | — |
