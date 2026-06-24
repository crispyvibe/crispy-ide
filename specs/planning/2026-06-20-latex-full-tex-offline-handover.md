# Handover — Full-TeX, Offline, Editable LaTeX Editor

> **UPDATE (2026-06-23): SHIPPED via native pdflatex, not WASM.** The feature was
> implemented using the **local TeX toolchain** (`pdflatex -synctex=1`), not the
> SwiftLaTeX WASM engine. The WASM engine's package server was down (522) and the
> approach was abandoned; its EPL-2.0 assets were removed from the repo. Sections
> §3–§9 below document the *exploration* (including the abandoned WASM path) for
> history — the **as-built** design is: native compile (`LaTeXNativeCompiler`),
> PDFKit render + SyncTeX double-click block editing + select-to-comment
> (`LaTeXCompiledPreviewView` / `CompiledPreviewSupportViews`), a smart default
> (PDF when a TeX toolchain is detected, else the KaTeX Edit view), and an
> actionable "install BasicTeX" empty-state. Typst/AsciiDoc/Graphviz previews
> share the same scaffold (`DocumentFormatPreviews`).


Date: 2026-06-20
Branch: `whiteboard`
Status: research complete; engine + wrapper vendored; implementation BLOCKED on
bundle-priming (see §5 Stage 1) — no code beyond vendored assets.
Author: pairing session notes

> TL;DR for whoever picks this up: the architecture is decided (SwiftLaTeX WASM +
> curated offline bundle). The one unsolved gate is **how to prime the offline
> package closure** — this machine has no system TeX, and the engine is built for
> on-demand network fetch. Resolve §5 "Priming options" first; everything else is
> straightforward wiring. Also clear the **EPL-2.0 license** gate (§6) before shipping.

---

## 1. Goal

Make the LaTeX editor render **real, full TeX** (so documents like the IEEE
paper actually typeset: two-column layout, author blocks, abstract, bib),
while keeping an **editable preview** and staying **offline-first**.

These three are the hard constraints, in priority order the user gave:
1. **Offline-first — non-negotiable.** No network at runtime.
2. **Editable preview** — "like we have right now" (you interact with the
   rendered view to edit, not a separate read-only pane).
3. **Full TeX fidelity** — real document-class layout, arbitrary packages.

---

## 2. Where things stand today (already shipped on `whiteboard`)

The current LaTeX feature is **F057 — LaTeX Editor** (renumbered from F055 on
merge; main took F055=Git Worktrees, F056=Unified Panel). Commits:
- `4f261a9` feat(editor): offline LaTeX editor with KaTeX preview (F057, was F055)
- `1aad9c9` feat(editor): LaTeX file comments in the WYSIWYG view + editing fixes
- `9fa0452` docs(showcase): sample docs (resume, IEEE paper) + demo fix
- `de3e9c1` merge of `origin/main` (brought the Workspace unified panel + git worktrees)

What it does **today**:
- `.tex/.latex/.ltx` open in a split **Source** (code) / **Edit** (WYSIWYG) editor.
- The Edit view is a `WKWebView` running `Resources/LaTeXRuntime/latex-bridge.js`
  which renders a **KaTeX subset**: prose, headings, lists, inline formatting,
  and **math**. Everything it doesn't model (preamble, `tabular`,
  `IEEEauthorblock`, `abstract`, `thebibliography`, `tikzpicture`, …) is
  preserved **verbatim** as read-only blocks.
- File comments (F049) work in both Source and the WYSIWYG (source-line anchoring).

### The limitation that triggered this work
KaTeX only does **math**, not page layout. So an IEEE paper shows the title +
prose + the one equation rendered, and the IEEE-specific machinery as raw
blocks. That's **correct, non-destructive behavior for a subset renderer** — but
it is **not** full TeX. A KaTeX WYSIWYG can never produce IEEE/ACM/Beamer layout;
that requires a real TeX engine.

---

## 3. Research findings (the important part)

### Engine options
| Approach | Full TeX? | Editable preview | Offline | Fit for Crispy |
|---|---|---|---|---|
| **KaTeX (current)** | No (math only) | Yes (instant, DOM) | Yes | shipped |
| **Tectonic** (native Rust binary, XeTeX+TeXLive) | Yes | No (PDF is read-only) | Yes, with a local bundle | native; reuses PDFKit preview |
| **SwiftLaTeX** (pdfTeX/XeTeX → WASM, runs in a WebView) | Yes | Yes (its "true WYSIWYG" edits the rendered output via **SyncTeX**) | Only if packages are bundled (default = network fetch) | reuses our existing WKWebView |

**Conclusion:** the only thing that satisfies *editable preview + full TeX* is
the **SwiftLaTeX WASM engine** with its SyncTeX edit-in-output layer. Tectonic
gives full TeX but a read-only PDF.

### Size reality (corrected — earlier "hundreds of MB" was wrong)
- Full TeX Live / MacTeX: **~5–7 GB** (everything + docs).
- `scheme-basic`: ~265 MB; **minimal scheme** (no docs/sources): **~64 MB**.
- A single document touches **far** less. SwiftLaTeX fetches *only* the files a
  document references.
- **A curated closure for article/IEEE-class docs + Computer Modern / Latin
  Modern fonts is realistically ~30–80 MB.** Not hundreds of MB, not GBs.

### The offline mechanism (key insight)
SwiftLaTeX's engine (`swiftlatexpdftex.js`) defaults to fetching packages from
`https://texlive2.swiftlatex.com/` at compile time. To go offline we use the
standard **"prime the cache, ship the cache"** pattern:
1. **Build time (online, once):** compile each supported template and capture the
   exact list of files the engine requests.
2. **Vendor that closure** (~tens of MB).
3. **Runtime:** intercept the engine's file lookups and serve from the bundled
   files; keep `connect-src 'none'`. Unknown package → clear "not bundled" error;
   grow the bundle as needed.

### Engine already vendored
`projects/crispyvibes/web/swiftlatex-runtime/` (currently **untracked**):
- `swiftlatexpdftex.js` (~85 KB) — the **worker** engine. Verified header: it's a
  Web Worker (`self`, `onmessage`), `self.texlive_endpoint = "https://texlive2.swiftlatex.com/"`.
- `swiftlatexpdftex.wasm` (~1.77 MB) — valid WASM (`0061 736d`).
- `PdfTeXEngine.js` (~12 KB) — the **main-thread wrapper** that spawns the worker.
  **License: EPL-2.0** (Eclipse Public License v2.0) + an optional secondary
  license. Copyright Elliott Wen, 2019. → see §6, must clear before shipping.

### Engine file-fetch protocol (the offline hook — verified from source)
When the engine needs a file it can't find locally it calls
`kpse_find_file_js` / `kpse_find_pk_js`, which issue an `XMLHttpRequest`/`fetch`
**GET** to:
- `texlive_endpoint + "pdftex/" + cacheKey`  (packages: `.cls`, `.sty`, fonts metrics…)
- `texlive_endpoint + "pdftex/pk/" + cacheKey`  (PK bitmap fonts)

**To make it offline:** override these callbacks (or a same-origin/`file://`
shim) so they resolve `cacheKey` against the **bundled** texmf tree instead of
the network. Keep `connect-src 'none'`. This is the single integration seam.

---

## 4. Recommended architecture

Adopt the **SwiftLaTeX WASM pdfTeX engine** inside a WebView, with a **curated,
build-time-primed offline package bundle**. Keep the existing KaTeX WYSIWYG as
the lightweight editor; introduce real compilation for the full-TeX view.

CSP / security: the LaTeX runtime keeps `connect-src 'none'`. WASM needs
`script-src` to allow `wasm-unsafe-eval` (or equivalent) — verify against the
existing strict CSP and add a regression test (mirror `EditorHTMLSecurityTests`).

Licensing: the wrapper is **EPL-2.0** (confirmed). EPL-2.0 is a weak/file-level
copyleft — generally OK to distribute alongside proprietary code, but
modifications to the EPL'd files must be shared, and attribution is required.
**Get a yes from legal before bundling/shipping.** Also confirm the license of
the WASM engine + any vendored texmf files (texmf content is mostly LPPL).

---

## 5. Staged implementation plan (each stage shippable)

**Stage 0 — done:** vendored pdfTeX worker + wasm + `PdfTeXEngine.js` wrapper
into `web/swiftlatex-runtime/`.

**Stage 1 — offline compile core**  ← *currently blocked here; start by picking a priming option*

The whole stage hinges on **priming the offline package closure** (the set of
texmf files our templates need). The blocker found this session: **no system TeX
is installed** (`tectonic`, `pdflatex`, `kpsewhich`, `tlmgr` all MISSING), and
the WASM worker can't be run headless easily (browser/worker APIs). Priming
options, best-first:

1. **Install Tectonic as a build-time tool** (`brew install tectonic`), compile
   each template, and harvest the files it pulls into its cache — that cache *is*
   the closure. Caveat: Tectonic's bundle layout/naming differs from SwiftLaTeX's
   `cacheKey` scheme, so files must be re-mapped to what `kpse_find_file_js`
   expects (by filename). Cleanest if you instead use a real `pdflatex
   -recorder` run (the `.fls` lists every input file by name → 1:1 with cacheKey).
2. **Headless-browser capture** (Playwright/Puppeteer): load the engine with
   network on, compile each template, log every `cacheKey` requested, then fetch
   those from `texlive2.swiftlatex.com/pdftex/<cacheKey>` and vendor them. Most
   faithful to what the engine actually asks for; needs a browser + one online run.
3. **In-app dev capture**: ship the engine pointed at the live endpoint behind a
   debug flag, compile the templates once in `CrispyLocal.app`, log + dump the
   fetched files, vendor them. No extra tooling, but manual.

Then:
- Vendor the closure into `Resources/SwiftLaTeXRuntime/texmf/` (+ `SHA256SUMS`,
  mirroring the KaTeX `latex-runtime` build).
- Add `web/swiftlatex-runtime/build.sh` to reproduce the priming.
- Host page + worker; override `kpse_find_*` to read bundled files; `connect-src 'none'`.
- **Verify:** compile `ieee-paper.tex` → PDF with the network **off**.

**Stage 2 — live full-TeX preview (offline)**
- New view (extend the LaTeX editor): keep the editable Source/WYSIWYG, render
  the real compiled PDF beside/within it, recompiling (debounced) on edit.
- Render PDF via PDFKit (pass bytes back to Swift) or pdf.js in the web view.
- Surface the TeX log/errors in a panel.

**Stage 3 — edit-in-output (SyncTeX) — the big one**
- Use SyncTeX to map clicks/edits in the rendered page back to source positions;
  type in the output, recompile. This is the "true WYSIWYG" piece and the
  largest/riskiest stage.

---

## 6. Open decisions / blockers
- [ ] **Licensing (EPL-2.0 confirmed for `PdfTeXEngine.js`)** — get legal sign-off
      before bundling; also confirm the WASM engine + vendored texmf (LPPL) licenses.
- [ ] **Priming method** (pick one of §5 Stage 1's three options) — the gating unknown.
- [ ] Exact supported-template set that defines the bundled closure (start:
      `article`, IEEE; add ACM/beamer later).
- [ ] Acceptable bundle size budget (target ~30–80 MB; confirm).
- [ ] Recompile latency UX (debounce interval; incremental compile feasibility).
- [ ] Is Stage 3 (type-inside-PDF) required for v1, or is Stage 2
      (edit-in-WYSIWYG/Source + live true preview) acceptable for v1?

---

## 7. Key files / pointers
- Current WYSIWYG bridge: `projects/crispyvibes/crispyvibes/Resources/LaTeXRuntime/latex-bridge.js`
- Current edit view: `projects/crispyvibes/crispyvibes/Features/Editor/Views/LaTeXPreviewView.swift`
- Plugin wiring: `…/Features/Editor/Views/MarkdownEditorPlugins.swift` (`LaTeXEditorPlugin`)
- Doc-type detection: `…/Features/Editor/ViewModels/MarkdownViewModelDetection.swift`
- Vendored engine: `projects/crispyvibes/web/swiftlatex-runtime/` — `swiftlatexpdftex.js`,
  `swiftlatexpdftex.wasm`, `PdfTeXEngine.js` (all **untracked / not committed**;
  EPL-2.0 license unresolved — do not commit until §6 cleared).
- PDF preview to reuse: Crispy already previews `.pdf` (PDFKit) via the content viewer.
- F057 docs: `specs/features/editor/latex/`
- Sample docs: `projects/showcase-vibespaces/showcase-live/writing-studio/publishing-assets/{ieee-paper,sample-resume,katex-demo}.tex`

## 8. Build / run
- Build: `xcodebuild build -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes-local -configuration DebugLocal -destination 'platform=macOS'`
- Run (never kill the main `Crispy.app`): `./scripts/run-local.sh` → `CrispyLocal.app`
- JS round-trip tests: `cd projects/crispyvibes/web/latex-runtime && node roundtrip.test.js`

---

## 9. Session 2 — feature BUILT; blocked by an upstream outage

Implemented the full-TeX compiled preview end-to-end. **Build SUCCEEDED**; all
runtime assets are bundled into `CrispyLocal.app`. What exists now:

- **New `.compiled` view mode** (`MarkupViewMode.compiled`) — a 3rd segment ("PDF")
  in the LaTeX editor's mode toggle, alongside Edit (WYSIWYG) / Source. The
  editable views are untouched; the PDF view recompiles (debounced 0.6s) as you edit.
- **`LaTeXCompiledPreviewView.swift`** — offscreen compiler `WKWebView` +
  `PDFView` (PDFKit) + `LaTeXRuntimeSchemeHandler` serving the runtime over the
  custom **`crispylatex://`** scheme (Workers/WASM need a real origin, not file://).
- **`Resources/SwiftLaTeXRuntime/`** — `index.html`, `latex-compile.js` (glue:
  `window.crispyCompile(src)` → engine → posts `latexCompiled{pdf:base64,log}`),
  `PdfTeXEngine.js`, `swiftlatexpdftex.js`, `swiftlatexpdftex.wasm`.

### Verified this session
- `** BUILD SUCCEEDED **` with all the above wired into `project.pbxproj`.
- Runtime files copied into `CrispyLocal.app/Contents/Resources/SwiftLaTeXRuntime/`.
- The engine **loads and runs** (headless-Chrome harness: logged `engine-ready`,
  `Engine compilation start/finish`).

### THE BLOCKER (external, verified)
The engine fetches its format file + every package from
`https://texlive2.swiftlatex.com/pdftex/<cacheKey>` at compile time. That host is
**currently DOWN — HTTP 522 (Cloudflare: origin unreachable)** on every path,
both retries, and there is no working alternative subdomain
(`texlive`, `texlive3` don't resolve; `www` 404s). So the engine compiles to
**status=1, 0 PDF bytes** purely because it can't obtain `swiftlatexpdftex.fmt`
or `article.cls`. The integration is sound; the dependency is offline.

Also confirmed: a browser fetching that endpoint **cross-origin is CORS-blocked**
(no `Access-Control-Allow-Origin`). So even when the server is up, texlive
requests **must be proxied same-origin** — route them through the
`crispylatex://` scheme handler (native `URLSession` fetch, no CORS), which is
*also* exactly where offline caching/bundling plugs in. Set the engine endpoint
via `engine.latexWorker.postMessage({cmd:'settexliveurl', url:'crispylatex://…/'})`
(do NOT use `setTexliveEndpoint()` — it nulls the worker).

### Path forward (pick one — server outage forces the issue)
1. **Self-host / bundle the texmf closure.** Offline needs this anyway. Source the
   files from a real TeX Live (BasicTeX ~100 MB) instead of the dead server, and
   either ship them or generate `swiftlatexpdftex.fmt` locally via the engine's
   `compileFormat()` from base sources. Scheme handler serves them; `connect-src 'none'`.
2. **Pivot the compile backend to a native TeX** (Tectonic / BasicTeX `pdflatex`)
   invoked via `Process`, rendered in the same `PDFView`. Since editing already
   lives in the Source/Edit views and the PDF is read-only, this needs no WASM and
   no SwiftLaTeX server — the most reliable offline route. Trade-off: bundles a
   native engine + texmf (the unavoidable "ship a TeX distribution" cost).
3. **Wait for `texlive2.swiftlatex.com` to recover** — not viable for offline-first
   regardless; only useful to prime a bundle once.

Recommended: **(1) or (2)** — both are genuinely offline. The current WASM wiring
is reusable for (1); (2) swaps the compile call but keeps the PDFView/mode UI.

---

## 10. Session 3 — DONE: native offline engine + editable page (chosen path)

Pivoted to **path (2)** (native TeX) — the WASM path stayed dead (SwiftLaTeX's
package server is down) and native is the reliable offline route. The user's
real requirement was clarified: **one editable page, full LaTeX, not side-by-side**
— i.e. click the rendered page and edit *there*. Built exactly that.

### Implemented & verified
- **`LaTeXNativeCompiler.swift`** — runs local `pdflatex -synctex=1` in a temp
  dir (`TEXINPUTS` includes the doc's folder); returns PDF + SyncTeX + log.
  `sourceLocation(forPDFAt:page:x:y:)` does the SyncTeX reverse map. Fully offline.
- **`LaTeXCompiledPreviewView.swift`** — the **"PDF" mode**: renders the real PDF
  in a `PDFView`; **clicking the page → SyncTeX → the exact source line → an
  inline editor opens right there**; on commit the line is rewritten, pushed to
  the buffer (`onEdit`), and the page **re-renders** (debounced 0.7s). That's the
  "edit on the page" loop. Drops the WKWebView/WASM/scheme-handler entirely.
- Toolchain discovery at `/Library/TeX/texbin` (+ TeX Live bin dirs). App is
  **not sandboxed** (`crispyvibesDebug.entitlements` has only `get-task-allow`),
  so launching `pdflatex` via `Process` is allowed.

### Verified evidence
- Shell: `pdflatex -synctex=1` + `synctex edit` both work offline; reverse map
  returns correct `Line:`.
- **Real samples compile**: `ieee-paper.pdf` (89,476 B) and `sample-resume.pdf`
  (76,890 B) — fully offline.
- `** BUILD SUCCEEDED **`; `CrispyLocal.app` launches and runs.

### Packages (offline, no sudo)
`tlmgr init-usertree` then `tlmgr --usermode install <pkg>` installs into
`~/Library/texmf` (`TEXMFHOME`) without admin rights. Installed: enumitem,
IEEEtran, titlesec, algorithms, algorithmicx, fontawesome5. Add more the same way
as documents need them.

### Remaining cleanup (non-blocking)
- Remove the now-dead `Resources/SwiftLaTeXRuntime/` + `web/swiftlatex-runtime/`
  (EPL-licensed WASM, unused) from `project.pbxproj` and the bundle.
- Couldn't drive the in-app click→edit→re-render GUI headlessly; every underlying
  piece is shell-verified and the app builds + launches. Needs a manual click-test.
- BasicTeX ships system-wide; for a turnkey app, bundle a curated `texmf` so users
  don't need their own TeX install.
