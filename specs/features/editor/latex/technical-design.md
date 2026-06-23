# LaTeX Editor — Technical Design

## Overview

F057 adds a `DocumentType.latex` and binds LaTeX source to Crispy's document buffer, exactly like markdown. A LaTeX document is shown in one of three panes selected by the markup view-mode toggle (`MarkupViewMode { rich, source, compiled }`):

- **Edit** (`.rich`) → `LaTeXPreviewView`, an `NSViewRepresentable` hosting the vendored offline KaTeX runtime (`Resources/LaTeXRuntime/`) in a `WKWebView`, loaded over `file://`. Source is pushed into a single `contenteditable` canvas (`latex-bridge.js`); edits serialize back to LaTeX and flow into the buffer.
- **Source** → the standard `CodeEditorView` with a LaTeX `GenericCodeLanguage` and an insert-at-caret hook driving the math palette.
- **PDF** (`.compiled`, LaTeX-only) → `LaTeXCompiledPane`, which gates on toolchain availability: when a local TeX install is present it shows `LaTeXCompiledPreviewView` (offline `pdflatex` compile → `PDFView` with SyncTeX on-page editing + select-to-comment); otherwise it shows an actionable install-BasicTeX empty-state.

The default mode is computed by `MarkdownViewModel.defaultMarkupViewMode`: `.compiled` for LaTeX when `LaTeXNativeCompiler.isToolchainAvailable`, else `.rich`. The same vendored KaTeX runtime is referenced by the markdown editor (`Resources/MarkdownRuntime/editor.html`) to typeset inline/display math in markdown. The compiled-preview scaffold (`CompiledPreviewContainerView`, `CompiledPDFPreviewView`, `HTMLDocPreviewView`, `ExternalTool`) is shared with the Typst/Graphviz/AsciiDoc document types (`DocumentFormatPreviews.swift`).

## Architecture

```
Open .tex/.latex/.ltx
  └─ MarkdownViewModelDetection.detectDocumentType  → DocumentType.latex   (before plainText/code)
        └─ MarkdownViewModel → DocumentBuffer → AutosaveScheduler          (buffer holds raw LaTeX)
              └─ EditorPluginRegistry → LaTeXEditorPlugin (supportedTypes: [.latex])
                    │
       currentMarkupViewMode == .source ─────────────┐         currentMarkupViewMode == .rich ──┐
                    ▼                                  │                          ▼                │
         CodeEditorView (LaTeX)                        │              LaTeXPreviewView             │
         + EditorInsertionRequest (palette)            │              (NSViewRepresentable)        │
         content get: displayContent                   │     content: viewModel.displayContent     │
         onContentChange → userDidEdit                 │     onEdit → userDidEdit                   │
                                                       │                  ▼                         │
                                                       │            WKWebView (file://)             │
                                                       │     Resources/LaTeXRuntime/index.html      │
                                                       │       → katex.min.css / katex.min.js        │
                                                       │       → auto-render.min.js / latex-bridge.js│
                                                       │                  ▼                         │
                                                       │      #content contenteditable canvas       │
                                                       │   (prose/headings/lists editable; math &    │
                                                       │    comments & unknown envs = read-only atoms)│
                                                       └──────────────────────────────────────────────┘

Toolbar (MarkdownEditorView.markupToolbar, documentType == .latex):
  Source mode → latexMathPalette        Edit mode → latexRichToolbar (formatting + palette)
        └─ insertLatexSnippet(snippet) → viewModel.latexInsertionRequest = EditorInsertionRequest(snippet)

Markdown inline math (F008 extension):
  MarkdownRuntime/editor.html → katex.min.js + auto-render.min.js (co-located, same-dir 'self')
        renderMathInArticle() → renderMathInElement (delimiters $$ display / $ inline), math marked non-editable
        save: TurndownService rule "katexMath" recovers TeX from <annotation> → "$…$" / "$$…$$",
              and from a .katex-error span's text on parse failure (delimiters preserved)
```

## Data Flow

**Open / edit (Edit mode).** `LaTeXEditorPlugin` builds `LaTeXPreviewView` bound to `viewModel.displayContent` (get) and `viewModel.userDidEdit` (set, via `onEdit`). The view loads `LaTeXRuntime/index.html` with `loadFileURL(_:allowingReadAccessTo:)` scoped to the runtime directory (so `katex.min.css`, the JS, and the `fonts/` subtree all resolve over `file://`). On `latexReady`, Swift pushes the source via `crispyvibesSetLatex(jsonString)`. `latex-bridge.js` splits the document into preamble / body / postamble, renders the body into one `contenteditable` canvas, and typesets math with KaTeX. On every canvas edit the bridge debounces (220 ms), serializes the DOM back to LaTeX, and posts `latexChanged`; the coordinator forwards it to `onEdit` → `userDidEdit` → buffer dirty → `AutosaveScheduler` writes the file. An echo guard (`lastInjectedContent`) prevents the buffer update from bouncing back as a re-injection that would rebuild the DOM and reset the caret mid-edit.

**Source ↔ DOM ↔ LaTeX round-trip (the core mechanism).**

1. **Split:** `splitDocument` finds `\begin{document}` / `\end{document}`; `model.pre` (preamble, through `\begin{document}`) and `model.post` (`\end{document}` onward) are held aside verbatim. If there is no `document` environment the whole file is treated as body.
2. **Blockify:** the body is split on blank lines (without splitting inside environments — `envBalance` tracks `\begin`/`\end` depth), then `peelBlocks` separates leading comments and sectioning commands. Each block is `classify`-ed: `heading`, `list` (flat only — a nested list falls back to `raw`), `para`, `abstract`, `keywords` (editable HTML) or `dmath` / `comment` / `maketitle` / `table` / `bib` / `raw` (read-only **atoms** carrying their original source in `dataset.src`). `abstract`/`IEEEkeywords` are editable blocks tagged with `dataset.env`; `table`/`tabular` renders a read-only `<table>` (with caption) and `thebibliography` a read-only numbered list, both preserving `dataset.src` verbatim.
3. **Render:** editable blocks become `<h*>` / `<ul|ol>` / `<p>` / abstract & keywords `<div>`s with an inline LaTeX→HTML subset (`\textbf`→`<strong>`, `\emph`→`<em>`, `\texttt`→`<code>`, inline `$…$` left for KaTeX, plus text-mode niceties: `\TeX`/`\LaTeX`, `` `` ``/`''`→curly quotes, `--`/`---`→en/em-dash, `\,`→thin space, `{,}`→`,`, and `\%`/`\&`/`\#`/`\_`/`\$` unescaped for display). The title block unwraps IEEE `\IEEEauthorblockN/A`. Each editable block records a `dataset.srcOriginal` and a `dataset.pristine` snapshot of its rendered HTML. A render error in one block falls back to a read-only raw atom (the whole render never aborts), and sync is always re-enabled in a `finally` so edits never silently stop saving.
4. **Serialize:** `serializeCanvas` walks the canvas in document order. **Untouched** editable blocks (where current `innerHTML === dataset.pristine`) are re-emitted from `dataset.srcOriginal` byte-for-byte; touched blocks and atoms are converted (`blockToLatex` / `serializeInline`). `serializeInline` applies a **reversible re-escape** (`reescapeInlineText`) to edited text nodes — `&`→`\&`, `%`→`\%`, `#`→`\#`, `_`→`\_`, curly quotes/dashes/thin-space back to their LaTeX forms — so editing prose can't emit characters that would break compilation; the `tex-esc` span round-trips back to `\$`. Edited `abstract`/`keywords` re-wrap with their `\begin…\end` markers. Atoms emit their `dataset.src` verbatim. The result is `model.pre + body + model.post`.

This is what guarantees F057-R07/R08: a single edit reflows nothing else, environments stay environments, and source Crispy doesn't model (preamble, `tikzpicture`, comments) is never rewritten. Validated by `web/latex-runtime/roundtrip.test.js` (jsdom, 14 checks).

**Math editing.** `openMathEditor` builds a fixed-position popup with a live KaTeX preview, a clickable symbol/template grid (`MATH_PALETTE`, `{}` marks the caret landing spot), and an optional raw-TeX `<textarea>`. Click-away or ⌘↩ commits; Escape cancels. Display atoms (`.blk-dmath`) and in-prose math (`.katex` / `.katex-display`, bound read-only) both open it. Inserted math (`crispyvibesInsertMath`) is wrapped (`$…$` for fragments, `\[…\]` for environments) and typeset immediately.

**Markdown inline math (F008 extension).** `MarkdownRuntime/editor.html` loads the vendored KaTeX scripts **co-located in its own directory** (`katex.min.js`, `auto-render.min.js`, vendored by `build.sh`) so they resolve under CSP `'self'` (no `script-src file:`); the `katex.min.css` link and its fonts are loaded cross-directory from `../LaTeXRuntime/` (inert, covered by `style-src`/`font-src file:`). `renderMathInArticle()` runs `renderMathInElement` over the rendered article with delimiters `$$`(display)/`$`(inline), `throwOnError:false`, then marks every `.katex`/`.katex-display`/`.katex-error` non-editable so the `contenteditable` surface can't corrupt the KaTeX DOM. A math parse failure is caught and never breaks markdown rendering. On save, a Turndown rule `katexMath` filters `.katex`/`.katex-display` nodes and recovers the **original** TeX from `<annotation encoding="application/x-tex">`, emitting `$…$` (inline) or `\n\n$$…$$\n\n` (display); for a `.katex-error` span (a parse failure, which has no annotation) it recovers the raw source from the span text and re-emits inline delimiters — so the math delimiters are never silently stripped. Saved markdown carries the exact source, not serialized spans.

## Compiled PDF Preview (PDF mode)

The PDF mode is a native, fully-offline pipeline; it does **not** use a WebView, WASM, or any network. (An earlier SwiftLaTeX WASM/remote-server design was abandoned — its package server was unreachable and it could not be offline. See `specs/planning/2026-06-20-latex-full-tex-offline-handover.md`.)

```
PDF mode (MarkupViewMode.compiled)
  └─ LaTeXEditorPlugin → LaTeXCompiledPane
        ├─ toolchain missing → install-BasicTeX empty state (copy cmd / Recheck / Use Edit Tab / Get BasicTeX)
        └─ toolchain present → LaTeXCompiledPreviewView (NSViewRepresentable)
              Coordinator (debounce 0.7s)
                └─ LaTeXNativeCompiler.compile(source, documentURL)        [off-main, ExternalTool.run]
                      pdflatex -synctex=1 -interaction=nonstopmode
                                -output-directory=<tmp>  main.tex
                      TEXINPUTS = "<docDir>//:.//:"   ;  multi-pass (≤4) + bibtex
                      → main.pdf + main.synctex.gz + log
                └─ PDFDocument(url:) → CompiledPreviewContainerView.pdfView (ClickablePDFView)
              double-click → SyncTeX reverse (synctex edit) → source line
                           → expand to blank-line block → BlockEditTextView
                           → drift-guarded replace → onEdit → buffer → re-compile
              forward map (synctex view) → translucent PDFAnnotation (edited region)
              select text → "Comment" → SyncTeX map → .commentsRequestAddForSelection
```

**Compile core (`LaTeXNativeCompiler`).** `compile(source:documentURL:)` resolves `pdflatex` (via `ExternalTool.resolve`, searching `/Library/TeX/texbin`, TeX Live `bin` dirs, Homebrew, `/usr/local/bin`), writes `source` to `main.tex` in a fresh scratch dir (`ExternalTool.makeScratchDir`, under `tmp/crispyvibes-preview/<uuid>/`), and runs `pdflatex -synctex=1 -interaction=nonstopmode -output-directory=<tmp> main.tex` with `TEXINPUTS` prefixed by the document's own folder. It re-runs `bibtex main` when the source contains `\bibliography{`/`\addbibresource`, then re-typesets, and loops (up to 4 passes total) while the log says `Rerun to get…` / `Label(s) may have changed` / `Please rerun`. On success it returns the `main.pdf` + `main.synctex.gz` URLs and the log; on failure (no PDF) it removes the scratch dir immediately to avoid leaking it. `isToolchainAvailable` is the static `pdflatex`-present probe used by the smart default and the pane gate.

**SyncTeX maps.** `sourceLocation(forPDFAt:page:x:y:)` runs `synctex edit -o "<page>:<x>:<y>:<pdf>"` and parses `Input:`/`Line:` → `SourceLocation(file,line)` (the reverse map behind double-click-to-edit and select-to-comment). `forwardBoxes(forLine:mainTeXPath:pdfURL:)` runs `synctex view -i "<line>:1:<mainTeX>" -o <pdf>` and parses `Page:`/`h:`/`v:`/`W:`/`H:` into `SyncBox`es (the forward map behind the mapped-region highlight). Both queries run with a 10 s timeout; `x`/`y` are PDF points from the page top-left (SyncTeX's convention), which `ClickablePDFView.mouseDown` produces by flipping the page-space point against the media-box height.

**On-page edit loop (`Coordinator` in `LaTeXCompiledPreviewView`).** A double-click → `handlePageClick` → `sourceLocation(...)` → `beginInlineEdit(atSourceLine:)`. That snaps off a blank line to the nearest content line, then expands to the surrounding blank-line-delimited block (`start…end`), forward-maps the block's first/last lines to highlight boxes, and opens `CompiledPreviewContainerView.beginBlockEdit` — a floating `NSView` panel with an "Editing line(s) N–M" header, a `BlockEditTextView` (commits on ⌘↩ via `keyCode 36`+`.command`, cancels on `cancelOperation`/Esc), and Save/Cancel buttons. `commitBlockEdit` re-reads the block from `lastCompiledContent`; a **drift guard** aborts if the block no longer matches what was opened (a concurrent recompile shifted lines), otherwise it `replaceSubrange`s the lines and calls `parent.onEdit` → `userDidEdit` → buffer → debounced re-compile.

**Comments on the PDF.** `attach` wires `ClickablePDFView.onProbableSelection` and observes `PDFViewSelectionChanged`; `selectionChanged` floats the "Comment" button above a non-empty selection (only when a `commentsFilePath` is in the environment). `addCommentForSelection` takes the selection's first/last line rects, converts to SyncTeX top-left coordinates, reverse-maps each end to a source line, builds a `CommentAnchor` (start/end line, `anchorText` = the selected string, `anchorHash`), and posts `.commentsRequestAddForSelection` with `anchor.notificationPayload(filePath:)` — byte-identical to what Source/Edit emit, so the shared `VibeSpaceCommentStore` threads them together.

**Container view (`CompiledPreviewContainerView`, `CompiledPreviewSupportViews.swift`).** Hosts the `PDFView` (`.singlePageContinuous`, `autoScales`), a status/error overlay, the inline block-edit panel, the comment button, the mapped-region highlight, and the first-run hint. `display(document:)` preserves the current page **and scroll point** (`currentDestination.point`) across recompiles. `showCompileError` is non-destructive: if a PDF is already shown it adds a dismissible red banner ("showing the last successful render"); only with no prior PDF does it show the tail-40-lines log. `showHighlight` converts `SyncBox`es (top-left origin) to PDFKit page coordinates (bottom-left) using each page's true media-box height and adds translucent `.square` `PDFAnnotation`s that track zoom/scroll automatically.

**Sibling formats.** `CompiledPDFPreviewView` (Typst, Graphviz) and `HTMLDocPreviewView` (AsciiDoc) reuse `ExternalTool` + `CompiledPreviewContainerView` for read-only previews (Source view does the editing); they share the same debounce/cancel/cleanup pattern but no SyncTeX/on-page editing.

## API / Command Contracts

**LaTeX runtime — Swift → JS** (`evaluateJavaScript`; all string args JSON-escaped via `JSONEncoder`):
- `window.crispyvibesSetLatex(src)` — push full document source; rebuilds the canvas.
- `window.crispyvibesSetTheme("light"|"dark")` — toggles `body.dark`.
- `window.crispyvibesApplyCommand(name)` — toolbar formatting on the selection (`bold`, `italic`, `underline`, `codeBlock`, `heading1`→h2, `heading2`→h3, `unorderedList`, `orderedList`).
- `window.crispyvibesInsertMath(snippet)` — insert + typeset a math snippet at the caret (used by the palette). (`window.crispyvibesInsertText(text)` also exists for plain text insertion.)

**LaTeX runtime — JS → Swift** (`WKScriptMessageHandler`):
- `latexReady` — canvas mounted; Swift then force-syncs theme + content.
- `latexChanged` (String) — debounced serialized LaTeX source.
- `latexLog` — diagnostics (logged under `com.crispyvibe.app` / `latex.preview`).

**Insertion plumbing (Swift):** the palette button calls `MarkdownViewModel.insertLatexSnippet(_:)`, which sets `@Published latexInsertionRequest = EditorInsertionRequest(snippet)` (fresh `UUID` per request so the same snippet fires repeatedly). Both `CodeEditorView` (Source) and `LaTeXPreviewView` (Edit) consume it via identity-guarded `insertionRequest` / `onInsertionConsumed`.

**Navigation policy:** only `file://` and `about:` are allowed; `linkActivated` to any other scheme is handed to `NSWorkspace.shared.open` and the in-view navigation is cancelled.

**PDF mode — process & view contracts (no JS bridge):**
- `LaTeXNativeCompiler.compile(source:documentURL:) async throws -> CompileResult { pdfURL, synctexURL, log, succeeded }` — throws `CompileError.toolchainMissing` if `pdflatex` is absent.
- `sourceLocation(forPDFAt:page:x:y:) async -> SourceLocation?` (SyncTeX reverse) and `forwardBoxes(forLine:mainTeXPath:pdfURL:) async -> [SyncBox]` (SyncTeX forward).
- `LaTeXCompiledPreviewView` inputs: `content`, `isBufferLoading`, `documentURL`, `onEdit: (String) -> Void`, and the `commentsFilePathEnvironment`. `LaTeXCompiledPane` adds `onUseEditTab: () -> Void` (calls `setCurrentMarkupViewMode(.rich)`).
- `ExternalTool.run(tool,args,cwd:env:timeout:)` runs the process off-main via a `CheckedContinuation`, with a `DispatchWorkItem` watchdog (`timeout` default 30 s) and a task-cancellation handler that both call `process.terminate()`.
- Comment path (native, no JS): `addCommentForSelection` posts `NotificationCenter` `.commentsRequestAddForSelection` with `CommentAnchor.notificationPayload(filePath:)` — identical to Source/Edit.

## State Management

- `MarkdownViewModel.DocumentType.latex` — editable type; routed through the buffer/autosave path.
- `MarkupViewMode { rich, source, compiled }`; `supportsMarkupViewModeToggle` includes `.latex` (and `.typst`/`.asciidoc`/`.diagram`); `defaultMarkupViewMode` is `.compiled` for LaTeX when `LaTeXNativeCompiler.isToolchainAvailable`, else `.rich`; mode is stored per document in `markupViewModeByDocumentID` (cleared on close, and the entry is removed when the chosen mode equals the default). The `.compiled` segment is rendered only for `documentType == .latex`.
- `LaTeXCompiledPreviewView.Coordinator` — `lastCompiledContent`, `pendingCompile` (0.7 s debounce `DispatchWorkItem`), `compileTask` (cancelled before each compile and on shutdown), `currentPDFURL` (its scratch dir is removed when superseded or on shutdown), `selectionObserver`; `LaTeXCompiledPane` holds `@State toolchainAvailable` re-evaluated by **Recheck**.
- `latexInsertionRequest: EditorInsertionRequest?` — the pending palette snippet, consumed by whichever pane is active.
- `LaTeXPreviewView.Coordinator` — `isReady`, `lastInjectedContent` (echo guard), `lastInjectedTheme`, `lastHandledCommandID`, `lastInsertionID`; tears down the three message handlers in `dismantleNSView`; reloads on `webViewWebContentProcessDidTerminate`.
- Bridge: `model {pre, post}` (verbatim), per-block `dataset.srcOriginal`/`dataset.pristine`, `suppressSync` during injection, 220 ms `pendingTimer` for debounced serialize, `activeEditor` for the math popup.

## Dependencies (frameworks, libraries)

- `WebKit` (`WKWebView`, `WKScriptMessageHandler`, `WKNavigationDelegate`) for the Edit mode; `PDFKit` (`PDFView`, `PDFDocument`, `PDFAnnotation`) + `Foundation.Process` (via `ExternalTool`) for the PDF mode. No new Swift package dependencies.
- **External, not bundled (PDF mode):** a local TeX Live install (BasicTeX ~100 MB / MacTeX) providing `pdflatex`, `bibtex`, `synctex`, discovered under `/Library/TeX/texbin`, `/usr/local/texlive/<year>basic/bin/universal-darwin`, `/opt/homebrew/bin`, `/usr/local/bin`. The PDF mode is the only part of F057 that depends on it; Edit and Source are fully self-contained. Extra packages install per-user (`tlmgr --usermode`) into `~/Library/texmf`, no admin rights.
- Vendored, pinned: **KaTeX 0.16.11** (MIT) — `katex.min.js`, `katex.min.css`, `contrib/auto-render.min.js`, and the `fonts/` subtree.
- Build: `projects/crispyvibes/web/latex-runtime/{package.json, package-lock.json, build.sh, SHA256SUMS, roundtrip.test.js}`. `build.sh` runs `npm ci` (lockfile-exact) and copies the prebuilt KaTeX JS/CSS + auto-render + fonts into `Resources/LaTeXRuntime/`. `index.html` and `latex-bridge.js` are hand-authored and **not** overwritten by the build. `SHA256SUMS` pins the checksum of every vendored asset. `npm test` runs the jsdom round-trip suite.
- The runtime folder is bundled as an Xcode **folder reference** so the `fonts/` subtree is preserved; `LaTeXPreviewView.runtimeIndexURL` resolves `index.html` from the `LaTeXRuntime` subdirectory and returns `nil` (→ unavailable HTML) if the build is missing it.

## Platform Considerations

- macOS only; the Edit-mode surface is an AppKit-hosted `WKWebView` with `drawsBackground = false` for theme-transparent rendering.
- Unlike the F052 whiteboard (which needed a custom URL scheme because WebKit blocks `fetch()` of `file://`), KaTeX here loads its assets via plain `<link>`/`<script>` and font `@font-face` over `file://`, so `loadFileURL(_:allowingReadAccessTo:)` with read access scoped to the runtime directory is sufficient — no custom scheme handler.
- Web inspector enabled in DEBUG builds only.
- PDF mode launches external processes via `Process`. This is only possible because the app is **not sandboxed** (`crispyvibesDebug.entitlements` carries only `get-task-allow`); a sandboxed build could not exec the toolchain. SyncTeX coordinate conventions differ from PDFKit (top-left vs bottom-left origin), reconciled in `ClickablePDFView`/`showHighlight` using each page's media-box height.

## Performance Constraints

- Serialization is debounced at 220 ms in the bridge to coalesce rapid edits; a `blur` flushes a genuinely pending edit (also typesetting any just-typed `$…$`).
- Incremental serialization (untouched blocks re-emitted from their snapshot) keeps a single edit O(touched-blocks), not O(document).
- The vendored KaTeX bundle (JS/CSS + woff2/woff/ttf fonts) is loaded lazily, only when a LaTeX document opens in Edit mode (or markdown math is rendered).
- PDF mode: compiles are debounced 0.7 s and run off the main thread; each `pdflatex` pass is capped at 30 s by a watchdog and a superseding edit cancels the in-flight `compileTask` (terminating the process). Re-compiles preserve page + scroll position so editing doesn't jank the reader. Multi-pass (≤4) + `bibtex` only run when the log/source require them.

## CSP Posture

Two runtimes, two CSPs (both enforce **no network**):

- **LaTeX runtime** (`LaTeXRuntime/index.html`) — strict:
  `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; base-uri 'none';`
  No inline/eval script (the bridge is externalized to `latex-bridge.js`); KaTeX needs no `eval`. `style-src 'unsafe-inline'` is required because KaTeX emits inline `style` attributes on its spans (and the page has a `<style>` block). With no `connect-src` directive it falls back to `default-src 'none'` → no network is reachable.
- **Markdown runtime** (`MarkdownRuntime/editor.html`) — the existing markdown CSP, extended to render inline math:
  `default-src 'self' file:; script-src 'self' 'nonce-crispyvibes-editor' 'unsafe-eval'; style-src 'self' 'unsafe-inline' file:; font-src 'self' file:; img-src 'self' file: data: https: http:; connect-src 'none'; frame-src 'self' file: blob:;`
  The two KaTeX **scripts** (`katex.min.js`, `auto-render.min.js`) are **co-located into `MarkdownRuntime/`** (vendored by `build.sh` from the same pinned source as `LaTeXRuntime/`) and loaded same-directory under `'self'` — so `script-src` does **not** grant `file:`. This closes the only code-execution vector: the markdown editor is loaded with root read access, and `script-src file:` would otherwise let injected markdown reference an arbitrary local script. `katex.min.css` and its `fonts/` subtree are still loaded cross-directory from `../LaTeXRuntime/`; `file:` is retained in `style-src`/`font-src` only for those **inert, non-executable** resources (and `style-src 'unsafe-inline'` already exists for KaTeX/markdown inline styles, so a local stylesheet adds negligible risk). `connect-src 'none'` is the offline guarantee. The `'unsafe-eval'` + nonce predate KaTeX (they belong to the existing `marked`/`turndown`/mermaid stack); KaTeX contributes no new `eval`. A regression test (`EditorHTMLSecurityTests.testCSPScriptSrcDisallowsFileScheme`) locks in the no-`file:`-in-`script-src` invariant. See threat-model F057-T05.

**PDF mode has no WebView and therefore no CSP** — it is offline by construction: the native pipeline makes no network calls, it only `exec`s the local `pdflatex`/`bibtex`/`synctex` and reads/writes its own scratch dir. Its security surface is process execution, not web content (see threat-model F057-T10–T14).

## Migration / Rollout Notes

- No persistence migration: LaTeX documents are plain text files routed through the existing buffer; the Source/Edit mode preference reuses the markdown `markupViewModeByDocumentID` map.
- No feature flag — shipped on by default.
- Verification: `xcodebuild -scheme crispyvibes-local` builds; `web/latex-runtime/build.sh` reproduces the bundle from pinned KaTeX; `node web/latex-runtime/roundtrip.test.js` validates the round-trip; `SHA256SUMS` verifies vendored asset integrity.

## Known Gaps / Follow-ups

- In the **Edit** (KaTeX) mode, prose, sections, flat `itemize`/`enumerate`, inline/display math, `\maketitle`, `abstract`, and `IEEEkeywords` are editable in place; `tabular`/`table`, `thebibliography`, nested lists, `tikzpicture`, and custom environments render as read-only atoms (a real table / reference list / verbatim block) — preserved, but edited in Source or the **PDF** mode. KaTeX renders math, not page layout: for full document-class fidelity, use the PDF mode (which needs a local toolchain).
- PDF mode requires a local TeX install and is gated behind the install-BasicTeX empty-state when absent; Crispy does not yet bundle a curated `texmf` for a zero-install experience. The in-app click→edit→re-render GUI loop is shell-verified end to end (every underlying `pdflatex`/`synctex` step), per the handover doc.
- The markdown editor references the LaTeX runtime's KaTeX across directories (`../LaTeXRuntime/`) rather than a co-located copy; decoupling the two runtimes is an open question (see spec).
- No `latex.*` agent CLI yet.
- The inline LaTeX→HTML subset for prose is intentionally small; uncommon inline macros fall through as literal text and are preserved on round-trip but not styled.
