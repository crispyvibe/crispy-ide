# LaTeX Editor — Technical Design

## Overview

F057 adds a `DocumentType.latex` and binds LaTeX source to Crispy's document buffer, exactly like markdown. A LaTeX document is shown in one of two panes selected by the markup view-mode toggle:

- **Source** → the standard `CodeEditorView` with a LaTeX `GenericCodeLanguage` and an insert-at-caret hook driving the math palette.
- **Edit** (default `.rich`) → `LaTeXPreviewView`, an `NSViewRepresentable` hosting the vendored offline KaTeX runtime (`Resources/LaTeXRuntime/`) in a `WKWebView`, loaded over `file://`. Source is pushed into a single `contenteditable` canvas (`latex-bridge.js`); edits serialize back to LaTeX and flow into the buffer.

The same vendored KaTeX runtime is referenced by the markdown editor (`Resources/MarkdownRuntime/editor.html`) to typeset inline/display math in markdown.

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
2. **Blockify:** the body is split on blank lines (without splitting inside environments — `envBalance` tracks `\begin`/`\end` depth), then `peelBlocks` separates leading comments and sectioning commands. Each block is `classify`-ed: `heading`, `list`, `para` (editable HTML), or `dmath` / `comment` / `maketitle` / `raw` (read-only **atoms** carrying their original source in `dataset.src`).
3. **Render:** editable blocks become `<h*>` / `<ul|ol>` / `<p>` with an inline LaTeX→HTML subset (`\textbf`→`<strong>`, `\emph`→`<em>`, `\texttt`→`<code>`, inline `$…$` left for KaTeX). Each editable block records a `dataset.srcOriginal` and a `dataset.pristine` snapshot of its rendered HTML.
4. **Serialize:** `serializeCanvas` walks the canvas in document order. **Untouched** editable blocks (where current `innerHTML === dataset.pristine`) are re-emitted from `dataset.srcOriginal` byte-for-byte; touched blocks and atoms are converted (`blockToLatex` / `serializeInline`). Atoms emit their `dataset.src` verbatim. The result is `model.pre + body + model.post`.

This is what guarantees F057-R07/R08: a single edit reflows nothing else, environments stay environments, and source Crispy doesn't model (preamble, `tikzpicture`, comments) is never rewritten. Validated by `web/latex-runtime/roundtrip.test.js` (jsdom, 14 checks).

**Math editing.** `openMathEditor` builds a fixed-position popup with a live KaTeX preview, a clickable symbol/template grid (`MATH_PALETTE`, `{}` marks the caret landing spot), and an optional raw-TeX `<textarea>`. Click-away or ⌘↩ commits; Escape cancels. Display atoms (`.blk-dmath`) and in-prose math (`.katex` / `.katex-display`, bound read-only) both open it. Inserted math (`crispyvibesInsertMath`) is wrapped (`$…$` for fragments, `\[…\]` for environments) and typeset immediately.

**Markdown inline math (F008 extension).** `MarkdownRuntime/editor.html` loads the vendored KaTeX scripts **co-located in its own directory** (`katex.min.js`, `auto-render.min.js`, vendored by `build.sh`) so they resolve under CSP `'self'` (no `script-src file:`); the `katex.min.css` link and its fonts are loaded cross-directory from `../LaTeXRuntime/` (inert, covered by `style-src`/`font-src file:`). `renderMathInArticle()` runs `renderMathInElement` over the rendered article with delimiters `$$`(display)/`$`(inline), `throwOnError:false`, then marks every `.katex`/`.katex-display`/`.katex-error` non-editable so the `contenteditable` surface can't corrupt the KaTeX DOM. A math parse failure is caught and never breaks markdown rendering. On save, a Turndown rule `katexMath` filters `.katex`/`.katex-display` nodes and recovers the **original** TeX from `<annotation encoding="application/x-tex">`, emitting `$…$` (inline) or `\n\n$$…$$\n\n` (display); for a `.katex-error` span (a parse failure, which has no annotation) it recovers the raw source from the span text and re-emits inline delimiters — so the math delimiters are never silently stripped. Saved markdown carries the exact source, not serialized spans.

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

## State Management

- `MarkdownViewModel.DocumentType.latex` — editable type; routed through the buffer/autosave path.
- `MarkupViewMode { rich, source }`; `supportsMarkupViewModeToggle` includes `.latex`; `defaultMarkupViewMode == .rich`; mode is stored per document in `markupViewModeByDocumentID` and cleared on close.
- `latexInsertionRequest: EditorInsertionRequest?` — the pending palette snippet, consumed by whichever pane is active.
- `LaTeXPreviewView.Coordinator` — `isReady`, `lastInjectedContent` (echo guard), `lastInjectedTheme`, `lastHandledCommandID`, `lastInsertionID`; tears down the three message handlers in `dismantleNSView`; reloads on `webViewWebContentProcessDidTerminate`.
- Bridge: `model {pre, post}` (verbatim), per-block `dataset.srcOriginal`/`dataset.pristine`, `suppressSync` during injection, 220 ms `pendingTimer` for debounced serialize, `activeEditor` for the math popup.

## Dependencies (frameworks, libraries)

- `WebKit` (`WKWebView`, `WKScriptMessageHandler`, `WKNavigationDelegate`). No new Swift package dependencies.
- Vendored, pinned: **KaTeX 0.16.11** (MIT) — `katex.min.js`, `katex.min.css`, `contrib/auto-render.min.js`, and the `fonts/` subtree.
- Build: `projects/crispyvibes/web/latex-runtime/{package.json, package-lock.json, build.sh, SHA256SUMS, roundtrip.test.js}`. `build.sh` runs `npm ci` (lockfile-exact) and copies the prebuilt KaTeX JS/CSS + auto-render + fonts into `Resources/LaTeXRuntime/`. `index.html` and `latex-bridge.js` are hand-authored and **not** overwritten by the build. `SHA256SUMS` pins the checksum of every vendored asset. `npm test` runs the jsdom round-trip suite.
- The runtime folder is bundled as an Xcode **folder reference** so the `fonts/` subtree is preserved; `LaTeXPreviewView.runtimeIndexURL` resolves `index.html` from the `LaTeXRuntime` subdirectory and returns `nil` (→ unavailable HTML) if the build is missing it.

## Platform Considerations

- macOS only; the Edit-mode surface is an AppKit-hosted `WKWebView` with `drawsBackground = false` for theme-transparent rendering.
- Unlike the F052 whiteboard (which needed a custom URL scheme because WebKit blocks `fetch()` of `file://`), KaTeX here loads its assets via plain `<link>`/`<script>` and font `@font-face` over `file://`, so `loadFileURL(_:allowingReadAccessTo:)` with read access scoped to the runtime directory is sufficient — no custom scheme handler.
- Web inspector enabled in DEBUG builds only.

## Performance Constraints

- Serialization is debounced at 220 ms in the bridge to coalesce rapid edits; a `blur` flushes a genuinely pending edit (also typesetting any just-typed `$…$`).
- Incremental serialization (untouched blocks re-emitted from their snapshot) keeps a single edit O(touched-blocks), not O(document).
- The vendored KaTeX bundle (JS/CSS + woff2/woff/ttf fonts) is loaded lazily, only when a LaTeX document opens in Edit mode (or markdown math is rendered).

## CSP Posture

Two runtimes, two CSPs (both enforce **no network**):

- **LaTeX runtime** (`LaTeXRuntime/index.html`) — strict:
  `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; base-uri 'none';`
  No inline/eval script (the bridge is externalized to `latex-bridge.js`); KaTeX needs no `eval`. `style-src 'unsafe-inline'` is required because KaTeX emits inline `style` attributes on its spans (and the page has a `<style>` block). With no `connect-src` directive it falls back to `default-src 'none'` → no network is reachable.
- **Markdown runtime** (`MarkdownRuntime/editor.html`) — the existing markdown CSP, extended to render inline math:
  `default-src 'self' file:; script-src 'self' 'nonce-crispyvibes-editor' 'unsafe-eval'; style-src 'self' 'unsafe-inline' file:; font-src 'self' file:; img-src 'self' file: data: https: http:; connect-src 'none'; frame-src 'self' file: blob:;`
  The two KaTeX **scripts** (`katex.min.js`, `auto-render.min.js`) are **co-located into `MarkdownRuntime/`** (vendored by `build.sh` from the same pinned source as `LaTeXRuntime/`) and loaded same-directory under `'self'` — so `script-src` does **not** grant `file:`. This closes the only code-execution vector: the markdown editor is loaded with root read access, and `script-src file:` would otherwise let injected markdown reference an arbitrary local script. `katex.min.css` and its `fonts/` subtree are still loaded cross-directory from `../LaTeXRuntime/`; `file:` is retained in `style-src`/`font-src` only for those **inert, non-executable** resources (and `style-src 'unsafe-inline'` already exists for KaTeX/markdown inline styles, so a local stylesheet adds negligible risk). `connect-src 'none'` is the offline guarantee. The `'unsafe-eval'` + nonce predate KaTeX (they belong to the existing `marked`/`turndown`/mermaid stack); KaTeX contributes no new `eval`. A regression test (`EditorHTMLSecurityTests.testCSPScriptSrcDisallowsFileScheme`) locks in the no-`file:`-in-`script-src` invariant. See threat-model F057-T05.

## Migration / Rollout Notes

- No persistence migration: LaTeX documents are plain text files routed through the existing buffer; the Source/Edit mode preference reuses the markdown `markupViewModeByDocumentID` map.
- No feature flag — shipped on by default.
- Verification: `xcodebuild -scheme crispyvibes-local` builds; `web/latex-runtime/build.sh` reproduces the bundle from pinned KaTeX; `node web/latex-runtime/roundtrip.test.js` validates the round-trip; `SHA256SUMS` verifies vendored asset integrity.

## Known Gaps / Follow-ups

- Only a subset of LaTeX is modeled for in-place editing (prose, sections, `itemize`/`enumerate`, inline/display math, `\maketitle`). Everything else (tables, figures, `tikzpicture`, custom environments) is preserved verbatim as a read-only raw atom — correct, but not editable in Edit mode.
- The markdown editor references the LaTeX runtime's KaTeX across directories (`../LaTeXRuntime/`) rather than a co-located copy; decoupling the two runtimes is an open question (see spec).
- No `latex.*` agent CLI yet.
- The inline LaTeX→HTML subset for prose is intentionally small; uncommon inline macros fall through as literal text and are preserved on round-trip but not styled.
