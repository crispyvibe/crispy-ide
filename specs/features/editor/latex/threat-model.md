# LaTeX Editor — Threat Model

## Overview

F057 renders untrusted LaTeX in a `WKWebView` via a vendored KaTeX runtime and reads/writes `.tex` files. The same KaTeX runtime is also wired into the markdown editor. The security goals are: (1) both runtimes are **provably offline** — neither can reach the network; (2) the `WKWebView`'s `file://` read access cannot be widened into arbitrary local-file disclosure; (3) untrusted `.tex`/markdown content cannot escalate from rendering into host code execution or unwanted file writes; (4) the Swift→JS bridge cannot be turned into a JS-injection primitive.

## Trust Boundaries

- **App ↔ embedded web content:** KaTeX and the hand-authored bridge run in a `WKWebView`. The KaTeX bundle is third-party code; the document content it renders is fully untrusted. Both are confined by CSP and a navigation policy.
- **App ↔ file contents:** a `.tex`/`.latex`/`.ltx` (or markdown with `$…$`) file may come from anywhere (shared, agent-authored, downloaded). Its text is parsed in the web layer and rendered by KaTeX.
- **Swift ↔ JS bridge:** Swift injects the document source and commands into the page via `evaluateJavaScript`; the page posts serialized source back.
- **Vendored runtime ↔ supply chain:** the bundled KaTeX assets.

## Attack Surfaces

- The `WKWebView` `file://` load and its `allowingReadAccessTo` directory grant.
- The two page CSPs (LaTeX runtime, markdown runtime) and the navigation policy.
- The Swift→JS calls (`crispyvibesSetLatex/SetTheme/ApplyCommand/InsertMath`) and the JS→Swift messages (`latexReady/Changed/Log`).
- The serialized-source path back into the document buffer and autosave (file write).
- The vendored KaTeX bundle.

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

## Residual Risks

- Markdown runtime `'unsafe-eval'` + inline styles (T05/T06) — accepted, contained by the offline bundle-only origin; revisit when the markdown runtime's legacy dependencies allow tightening to match the LaTeX runtime's strict CSP.
- Only a modeled subset of LaTeX is editable; everything else is preserved verbatim but not validated — a malformed unknown environment round-trips unchanged (correct, not a security issue).
- Web inspector is enabled in DEBUG builds only.

## NFR Compliance

- **SEC-1** — typed, validated bridge messages; no untyped `eval` of inbound data.
- **SEC-3 / SEC-3a** — strict CSP on the LaTeX runtime; no remote resource loading; document injected as escaped JSON data (not a `file://` reference); KaTeX renders untrusted content non-destructively.
- **SEC-4 / DEP** — KaTeX pinned (`0.16.11`), lockfile-exact `npm ci`, committed `SHA256SUMS`; no new Swift package dependencies.
- **SEC-6** — fully offline; `connect-src` resolves to `'none'` in both runtimes; external links open in the system browser.
- **SEC-7** — `WKWebView` read access scoped to the runtime directory only; project/home files never granted.
- **REL** — verbatim-preserving, incremental round-trip with automated round-trip tests; edits flow through `DocumentBuffer` + autosave.
- **A11Y** — the Edit-mode surface exposes an accessibility label (`AppStrings.LaTeX.previewAccessibilityLabel`) and follows the app light/dark appearance; Source mode is the standard accessible code editor. See A11Y-1/A11Y-3.
- **PERF** — runtime loaded lazily; serialization debounced; incremental serialization bounds edit cost.
