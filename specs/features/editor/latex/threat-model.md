# LaTeX Editor — Threat Model

## Overview

F057 renders untrusted LaTeX in a `WKWebView` via a vendored KaTeX runtime and reads/writes `.tex` files. The same KaTeX runtime is also wired into the markdown editor. The **PDF mode** additionally compiles `.tex` with the user's **locally installed** TeX toolchain (`pdflatex`/`bibtex`/`synctex`) via `Process` in an **unsandboxed** app, and renders the result in a `PDFView`. The security goals are: (1) both web runtimes are **provably offline** — neither can reach the network; (2) the `WKWebView`'s `file://` read access cannot be widened into arbitrary local-file disclosure; (3) untrusted `.tex`/markdown content cannot escalate from rendering into host code execution or unwanted file writes; (4) the Swift→JS bridge cannot be turned into a JS-injection primitive; (5) for the PDF mode, the trust model and residual risks of running a full TeX engine on untrusted input are made explicit, since TeX is itself a Turing-complete language with (configurable) shell and file-system access.

## Trust Boundaries

- **App ↔ embedded web content:** KaTeX and the hand-authored bridge run in a `WKWebView`. The KaTeX bundle is third-party code; the document content it renders is fully untrusted. Both are confined by CSP and a navigation policy.
- **App ↔ file contents:** a `.tex`/`.latex`/`.ltx` (or markdown with `$…$`) file may come from anywhere (shared, agent-authored, downloaded). Its text is parsed in the web layer and rendered by KaTeX — and, in PDF mode, **fed to a real TeX engine**.
- **App ↔ local TeX toolchain (PDF mode):** Crispy execs the user's own `pdflatex`/`bibtex`/`synctex` outside any sandbox. The engine runs with the user's full privileges and reads/writes the file system per the document's directives and `TEXINPUTS`. The trust assumption is that the user already trusts their installed TeX distribution; the *document* is the untrusted party.
- **Swift ↔ JS bridge:** Swift injects the document source and commands into the page via `evaluateJavaScript`; the page posts serialized source back.
- **Vendored runtime ↔ supply chain:** the bundled KaTeX assets. (The TeX engine itself is **not** bundled — it is the user's own install.)

## Attack Surfaces

- The `WKWebView` `file://` load and its `allowingReadAccessTo` directory grant.
- The two page CSPs (LaTeX runtime, markdown runtime) and the navigation policy.
- The Swift→JS calls (`crispyvibesSetLatex/SetTheme/ApplyCommand/InsertMath`) and the JS→Swift messages (`latexReady/Changed/Log`).
- The serialized-source path back into the document buffer and autosave (file write).
- The vendored KaTeX bundle.
- **PDF mode:** the TeX compile itself (TeX macro/`\write18` execution), file resolution via `\input`/`\include`/`TEXINPUTS`, the spawned `Process` resource envelope, and the temporary scratch directory under `tmp/crispyvibes-preview/`.

## Threats

### F057-T01: Network exfiltration / phone-home by rendered content
- Vector: a crafted `.tex` or markdown math fragment, or KaTeX itself, attempts to fetch a remote resource (font, image, beacon) to exfiltrate document content or fingerprint the user.
- Impact: data egress; breaks the offline guarantee.
- Likelihood: Low–Medium (KaTeX is self-contained, but content is attacker-controlled).
- Mitigation: **no `connect-src` is granted to a network origin in either runtime.** The LaTeX runtime CSP is `default-src 'none'` with no `connect-src` (→ inherits `'none'`); the markdown runtime sets `connect-src 'none'` explicitly. KaTeX fonts are bundled and loaded over `file://` (`font-src 'self'`/`'self' file:`). No remote origin is reachable. Aligns with **SEC-6** (offline-first) and **SEC-3** (no remote resource loading).

### F057-T02: `file://` read-access widening / local file disclosure
- Vector: the `WKWebView` is granted read access to a directory; a crafted page or relative path (`../../`) tries to read host files outside the runtime into the web context.
- Impact: arbitrary local file disclosure into the (untrusted) web layer.
- Likelihood: Low.
- Mitigation: `loadFileURL(indexURL, allowingReadAccessTo:)` scopes read access to **only the `LaTeXRuntime` directory** (`indexURL.deletingLastPathComponent()`), not the user's project or home. Document content is never loaded as a `file://` URL — it is injected as a JSON string via the bridge, so a malicious document cannot reference arbitrary paths through the loader. Aligns with **SEC-7** (file-system scope) and **SEC-3a** (path-traversal validation).

### F057-T03: JS injection via `evaluateJavaScript`
- Vector: document source (or a theme/command/snippet) is interpolated into an `evaluateJavaScript("window.crispyvibesSetLatex(…)")` string; a payload containing quotes/backslashes/`</script>` breaks out and executes attacker JS in the page.
- Impact: script execution in the web context (which, being offline and sandboxed, still cannot reach the host — but could corrupt the document or the round-trip).
- Likelihood: Medium without escaping (LaTeX is full of backslashes and braces).
- Mitigation: every value crossing the bridge is encoded with `JSONEncoder` (`Self.jsString`) before interpolation, producing a valid JSON string literal — backslashes, quotes, newlines, and control characters are escaped. The argument is therefore inert data, never code. Inbound `latexChanged` is validated as `String` before use. Aligns with **SEC-1** (typed/validated IPC) and **SEC-3** (typed command interface).

### F057-T04: Malicious `.tex` / markdown content (render abuse)
- Vector: hostile input — KaTeX-bombing macros (`\def`-style expansion, deeply nested groups), enormous documents, or malformed math.
- Impact: at worst a render error or slowdown in the sandboxed web view; no host code execution.
- Likelihood: Low.
- Mitigation: KaTeX renders with `throwOnError: false` (errors shown inline, not thrown); KaTeX has no shell/macro-execution capability and a bounded macro model. The Swift side treats the document as an opaque string; the serialized result re-enters through the normal buffer (a plain text write). Unmodeled source is preserved verbatim, never executed. Markdown math failures are caught so they cannot break the markdown render.

### F057-T05: CSP weakness in the markdown runtime (`'unsafe-eval'`, inert `file:`)
- Vector: the markdown editor is loaded with root read access. If `script-src` allowed `file:`, injected markdown (raw HTML passes through `marked`) could reference an arbitrary local script; `'unsafe-eval'` is also retained from the legacy stack.
- Impact: script execution within the offline markdown web view.
- Likelihood: Low.
- Mitigation: the two KaTeX **scripts are co-located into `MarkdownRuntime/`** and loaded same-directory under `'self'`, so **`script-src` no longer grants `file:`** — the code-execution vector is closed (locked by `EditorHTMLSecurityTests.testCSPScriptSrcDisallowsFileScheme`). Only `style-src`/`font-src` retain `file:`, exclusively for the cross-directory `katex.min.css` + fonts, which are **inert, non-executable** resources (and `style-src 'unsafe-inline'` already exists for KaTeX/markdown inline styles, so a local stylesheet adds negligible risk). The `'unsafe-eval'` + nonce predate KaTeX — they belong to the existing `marked`/`turndown`/mermaid stack, not introduced by F057; KaTeX adds no new `eval`. `connect-src 'none'` still blocks exfiltration, and all sources resolve only within the read-only signed app bundle. The LaTeX runtime itself uses the **strict** `script-src 'self'` (no `eval`, no `file:`).
- Residual: `'unsafe-eval'` + `style-src 'unsafe-inline'` + inert `style-src/font-src file:` in the markdown runtime are accepted, contained by the offline, bundle-only origin; revisit if the markdown runtime's legacy dependencies are removed (which would also allow dropping `'unsafe-eval'`). Aligns with **SEC-3**.

### F057-T06: Inert style/font `file:` allowance abused for tracking
- Vector: `style-src 'unsafe-inline'`/`font-src` could in principle let CSS reference a remote font/image as a side channel.
- Impact: passive network beacon.
- Likelihood: Low.
- Mitigation: `font-src` is limited to `'self'`(/`'self' file:`) — no remote font URL is permitted; `img-src` permits `data:` (and, in the pre-existing markdown CSP, `http(s):` for user images) but `connect-src 'none'` plus the navigation policy bound the blast radius. The LaTeX runtime's `img-src` is `'self' data:` only. Inline styles are limited to presentation; they cannot initiate script.

### F057-T07: Lossy / destructive round-trip (data integrity)
- Vector: the WYSIWYG serialization rewrites or drops source it doesn't model (preamble, `tikzpicture`, comments), silently corrupting the user's document on autosave.
- Impact: data loss in a file the user trusts as the source of truth.
- Likelihood: Medium without safeguards (this is the central correctness risk).
- Mitigation: the bridge holds the preamble/postamble verbatim, renders unmodeled constructs as read-only atoms carrying their original `dataset.src`, and re-emits **untouched** editable blocks byte-for-byte from a pristine snapshot. Display↔inline and math environments are preserved. This is covered by `web/latex-runtime/roundtrip.test.js` (14 checks incl. preamble, `tikzpicture`, `align`, comments, and incremental-edit verbatim preservation). Aligns with **REL** (no silent data loss).

### F057-T08: External-link / cross-origin navigation escape
- Vector: a link or scripted navigation in the Edit-mode surface points at a remote URL, `data:text/html` (null origin, no inherited CSP), or another scheme to escape the runtime.
- Impact: navigation to an uncontrolled origin / CSP bypass.
- Likelihood: Low.
- Mitigation: the `WKNavigationDelegate` allows only `file://` and `about:`; any `linkActivated` to another scheme is opened in the system browser (`NSWorkspace`) and cancelled in-view. Aligns with **SEC-3**/**SEC-6**.

### F057-T09: Supply-chain tampering of the vendored KaTeX
- Vector: a compromised or drifting KaTeX version is vendored into the bundle.
- Impact: malicious code shipped in the app.
- Likelihood: Low.
- Mitigation: KaTeX is pinned to `0.16.11` in `package.json` + `package-lock.json`; `build.sh` uses `npm ci` (lockfile-exact, reproducible); a committed `SHA256SUMS` manifest fixes the checksum of every vendored asset (JS, CSS, every font file). The runtime is offline-confined regardless of contents. Aligns with **SEC-4** (supply chain) and **DEP** (pinned, lockfile-reproducible).

### F057-T10: Arbitrary code execution via TeX (`\write18` / shell-escape)
- Vector: a malicious `.tex` opened in **PDF mode** uses `\write18{…}` (shell-escape) — or a package that shells out (e.g. `minted`, `\immediate\write18`) — to execute arbitrary commands when `pdflatex` runs. Because the app is **not sandboxed**, any such command runs with the user's full privileges.
- Impact: host code execution / arbitrary file or network actions outside Crispy's control — the most serious risk in the feature.
- Likelihood: Medium for a hostile document (shell-escape is a well-known TeX attack), Low for ordinary user documents.
- Mitigation: as-built, Crispy invokes the **stock** `pdflatex`, which on a default TeX Live install runs with **restricted** shell-escape (`shell_escape = p` in `texmf.cnf`) — only a small allow-list of helpers (e.g. `bibtex`, `kpsewhich`, `repstopdf`) may run, and unrestricted `\write18` is refused. Crispy does **not** pass `-shell-escape`. **Recommended hardening (not yet applied):** pass `-no-shell-escape` explicitly so the behavior does not depend on the user's `texmf.cnf`, and set `openin_any`/`openout_any` to `p` (paranoid) via the environment. The user is also shown what they are installing (BasicTeX) and compilation only runs on a file they opened. Aligns with **SEC-3** (constrain untrusted execution); tracked as a residual risk below.

### F057-T11: Local file disclosure via `\input` / `TEXINPUTS`
- Vector: a hostile `.tex` uses `\input{/etc/passwd}`, `\include`, `\openin`, or `\lstinputlisting` to read an arbitrary local file and embed its contents into the compiled PDF (which the user may then share), exfiltrating data without any network.
- Impact: local file disclosure into an output the user may distribute.
- Likelihood: Low–Medium for a hostile document.
- Mitigation: `TEXINPUTS` is scoped to the document's own folder plus the scratch dir (`"<docDir>//:.//:"`), not the whole filesystem — though `\input` with an absolute path can still reach outside it under default settings. **Recommended hardening (not yet applied):** set `openin_any=p`/`openout_any=p` so reads/writes are confined to the working tree. As with T10, the compile runs only on a file the user opened, with their own privileges. Aligns with **SEC-7** (file-system scope); tracked as a residual risk below.

### F057-T12: Process resource exhaustion (runaway / pathological compile)
- Vector: a document with an infinite/near-infinite macro loop, deep recursion, or a giant body causes `pdflatex` to spin forever or consume excessive CPU/memory, hanging the preview or piling up processes on every debounced edit.
- Impact: denial of service / unresponsive editor; battery and memory pressure.
- Likelihood: Medium without bounds (TeX is Turing-complete; `-interaction=nonstopmode` won't stop a loop).
- Mitigation: every external process runs through `ExternalTool.run`, which arms a `DispatchWorkItem` **watchdog** that calls `process.terminate()` after 30 s (10 s for `synctex` queries), and a task-cancellation handler that terminates the process when the enclosing `Task` is cancelled. Compiles are **debounced** (0.7 s) and the prior `compileTask` is cancelled before a new one starts, so superseded compiles don't accumulate. Aligns with **PERF** / **REL** (bounded, cancellable work).

### F057-T13: Temp scratch-directory handling
- Vector: each compile writes `main.tex` and its outputs (PDF, `.synctex.gz`, `.aux`, `.log`) to `tmp/crispyvibes-preview/<uuid>/`. Risks: leaking scratch dirs over time, or another local user reading intermediate artifacts of an untrusted/confidential document.
- Impact: disk growth; limited local-only information exposure of document artifacts.
- Likelihood: Low.
- Mitigation: each compile uses a fresh per-UUID directory under the user's `NSTemporaryDirectory()` (user-owned, not world-writable); on compile failure the dir is removed immediately, and the previous successful dir is removed when superseded and on view `shutdown()` (`cleanupPrevious`). No secrets are written by Crispy beyond the user's own document content. Residual: artifacts of the last successful render persist until superseded/closed (standard temp-file behavior).

### F057-T14: Compilation runs the user's local toolchain in an unsandboxed app
- Vector: the entire PDF mode depends on executing external binaries (`pdflatex` et al.) discovered on `PATH`/known dirs, in an app whose entitlements are only `get-task-allow` (no App Sandbox). A compromised or shimmed TeX binary, or a maliciously placed binary earlier in the search path, would run with the user's privileges.
- Impact: code execution / integrity loss via a trusted-path or supply-chain assumption about the local toolchain.
- Likelihood: Low (requires the local environment to already be compromised).
- Mitigation: tools are resolved only from a fixed allow-list of absolute directories (`/Library/TeX/texbin`, known TeX Live `bin` dirs, `/opt/homebrew/bin`, `/usr/local/bin`) via `isExecutableFile`, not from an arbitrary inherited `PATH` lookup for the primary resolve; the toolchain is the user's own install (the same trust they extend to their shell). The lack of sandbox is a deliberate, documented constraint (it is what enables launching the compiler at all); it is not a regression introduced by F057. Edit and Source modes never exec anything. Aligns with **SEC-3**/**SEC-4**; tracked as a residual risk below.

## Residual Risks

- Markdown runtime `'unsafe-eval'` + inline styles (T05/T06) — accepted, contained by the offline bundle-only origin; revisit when the markdown runtime's legacy dependencies allow tightening to match the LaTeX runtime's strict CSP.
- Only a modeled subset of LaTeX is editable in the Edit view; everything else is preserved verbatim but not validated — a malformed unknown environment round-trips unchanged (correct, not a security issue).
- **PDF mode — TeX shell-escape / file-read (T10/T11):** as-built, Crispy relies on TeX Live's default *restricted* shell-escape and does not yet pass `-no-shell-escape` or set `openin_any`/`openout_any=p`. A hostile `.tex` compiled in PDF mode could, on a permissively configured install, execute commands or read files with the user's privileges. Accepted for now under the "user compiles their own/opened documents with their own toolchain" model; the recommended explicit `-no-shell-escape` + paranoid open settings are tracked hardening. Users should treat opening *untrusted* `.tex` in PDF mode like running untrusted code.
- **PDF mode — unsandboxed execution (T14):** the app must remain unsandboxed to exec the toolchain; this is a deliberate constraint, not a defect.
- **PDF mode — scratch artifacts (T13):** the last successful render's temp dir persists until superseded or the view closes.
- Web inspector is enabled in DEBUG builds only.

## NFR Compliance

- **SEC-1** — typed, validated bridge messages; no untyped `eval` of inbound data; PDF mode uses typed `Process` invocations with fixed argument arrays (no shell string interpolation of document content).
- **SEC-3 / SEC-3a** — strict CSP on the LaTeX runtime; no remote resource loading; document injected as escaped JSON data (not a `file://` reference); KaTeX renders untrusted content non-destructively. PDF-mode TeX execution is constrained by restricted shell-escape with explicit `-no-shell-escape`/paranoid-open hardening recommended (T10/T11).
- **SEC-4 / DEP** — KaTeX pinned (`0.16.11`), lockfile-exact `npm ci`, committed `SHA256SUMS`; no new Swift package dependencies; the TeX engine is the user's own install resolved from a fixed allow-list of directories (T14).
- **SEC-6** — fully offline; `connect-src` resolves to `'none'` in both web runtimes; the PDF pipeline makes no network calls (only local `Process` exec); external links open in the system browser.
- **SEC-7** — `WKWebView` read access scoped to the runtime directory only; PDF-mode `TEXINPUTS` scoped to the document folder + scratch dir (with paranoid-open hardening recommended for absolute-path `\input`).
- **REL** — verbatim-preserving, incremental round-trip with automated round-trip tests; on-page edits are drift-guarded; compile failures are non-destructive (last good PDF retained); bounded, cancellable external processes (T12).
- **A11Y** — the Edit-mode surface exposes an accessibility label (`AppStrings.LaTeX.previewAccessibilityLabel`); the PDF surface exposes `AppStrings.LaTeX.compiledAccessibilityLabel`; both follow the app light/dark appearance; Source mode is the standard accessible code editor. See A11Y-1/A11Y-3.
- **PERF** — runtimes loaded lazily; serialization debounced; incremental serialization bounds edit cost; PDF compiles debounced + watchdog-bounded + scroll-preserving.
