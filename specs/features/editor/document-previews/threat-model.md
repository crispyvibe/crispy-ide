# Document Render Previews — Threat Model

## Overview

F058 renders untrusted document content (`.typ`, `.adoc`, `.dot`) by writing it to a scratch file and invoking the user's locally-installed CLI converter (`typst`, `asciidoctor`, `dot`), then displaying the result in a `PDFView` (Typst/Graphviz) or a JavaScript-disabled `WKWebView` (AsciiDoc). The app is **not sandboxed** (entitlements grant only `get-task-allow`), so these helpers run with the user's full privileges. The security goals are: (1) untrusted document content cannot be turned into arbitrary **shell command** execution; (2) the rendered HTML cannot execute script or exfiltrate over the network; (3) the document's own renderer features (e.g. AsciiDoc includes) have a bounded, understood file-read surface; (4) a hostile or malformed document cannot exhaust resources or hang the app; (5) scratch files are handled cleanly.

## Trust Boundaries

- **App ↔ external converter process:** the converter is a separate, user-installed binary spawned by the app. The document content it processes is fully untrusted (shared, agent-authored, downloaded). The converter itself is trusted to the extent the user trusts what they installed.
- **App ↔ document contents:** a `.typ`/`.adoc`/`.dot` file may come from anywhere; its bytes are written to a scratch file and fed to the converter.
- **App ↔ rendered output:** the produced PDF is shown in `PDFView`; the produced HTML (AsciiDoc) is shown in a `WKWebView`.
- **App ↔ local toolchain / PATH:** which binary runs is determined by resolving a tool name against a fixed list of directories.

## Attack Surfaces

- The `Process` invocation of each converter (executable URL + argument array + environment).
- The scratch directory and the files written into it; the AsciiDoc `--base-dir` (the document's own directory).
- The AsciiDoc converter's `include::`/file-read/macro capabilities running with the user's privileges.
- The `WKWebView` that renders the converter's HTML output.
- The captured stderr log surfaced in the error UI.
- Tool resolution from the fixed search paths.

## Threats

### F058-T01: Shell command injection via document content
- Vector: hostile document text or a file name is interpolated into a shell command line, letting metacharacters (`;`, `` ` ``, `$()`, `|`) execute arbitrary commands.
- Impact: arbitrary code execution with the user's privileges (the app is unsandboxed).
- Likelihood: Low, given the mitigation.
- Mitigation: converters are launched via `Process` with `executableURL` + an **argument array** — there is no shell, so document content and paths are inert arguments, never parsed as a command line. The document body is passed by **file path**, not on the command line. Aligns with **SEC-1** (typed/validated invocation) and **SEC-3**.

### F058-T02: AsciiDoc include / file-read surface
- Vector: a malicious `.adoc` uses `include::`, image, or other file-referencing directives to read files outside the document's directory (e.g. `include::/etc/...[]` or `../` traversal) and embed their contents in the rendered HTML, or otherwise abuse `asciidoctor`'s macro features. Because the app is unsandboxed, `asciidoctor` runs with the user's full file access.
- Impact: local file disclosure into the preview; potential abuse of any `asciidoctor` feature that touches the filesystem.
- Likelihood: Low–Medium (depends on the document source).
- Mitigation: the render passes `--base-dir <document-directory>`, anchoring relative includes to the document's own directory. The converter runs on a copy of the source in a scratch dir and its output is captured from stdout (no files persisted). **Residual:** `--safe-mode` is **not** set, so the default `asciidoctor` safe mode applies; constraining includes/macros with an explicit restricted safe mode is a recommended follow-up (see spec Open Question 2). This is a property of the user's own trusted toolchain operating on a document the user chose to open. Relates to **SEC-7** (file-system scope) and **SEC-3a** (path handling).

### F058-T03: Script execution / network exfiltration from rendered AsciiDoc HTML
- Vector: the converter output, or injected markup within it, contains `<script>` or remote resource references that run code or beacon out, exfiltrating content or fingerprinting the user.
- Impact: script execution in the preview / passive network egress.
- Likelihood: Low.
- Mitigation: the AsciiDoc `WKWebView` is configured with `allowsContentJavaScript = false`, so no script in the rendered HTML executes. PDF formats render in `PDFView`, which executes no document script. **Residual:** the rendered HTML carries no CSP, so a remote resource reference (e.g. `<img src="https://…">` embedded by a hostile document) could still be fetched by `WKWebView` as a passive beacon; adding a CSP / blocking remote loads is a recommended follow-up (spec Open Question 3). Relates to **SEC-3**/**SEC-6**.

### F058-T04: Resource exhaustion / denial of service
- Vector: a document triggers an infinite or pathological compile (huge output, expansion bomb, hang), consuming CPU/disk or wedging the preview.
- Impact: app slowdown, disk fill, or an unresponsive preview pane.
- Likelihood: Low–Medium.
- Mitigation: every compile runs in a cancellable `Task` off the main thread with a 30 s **watchdog** that terminates the child process; a new edit cancels the in-flight task (which terminates the process), and view dismantling cancels it too. Edits are debounced (0.5 s) so compiles don't pile up. The main actor is never blocked on the converter. Aligns with **REL** and **PERF**.

### F058-T05: Scratch-file handling / temp leakage
- Vector: source content written to temp files lingers or leaks, or a stale PDF directory accumulates.
- Impact: disclosure of document content via leftover temp files; disk growth.
- Likelihood: Low.
- Mitigation: each compile uses a fresh per-invocation scratch dir under `<temp>/crispyvibes-preview/<uuid>/`. PDF formats delete the previous render's directory when a newer render replaces it and on shutdown, and delete the scratch dir on a failed compile; AsciiDoc always removes its scratch dir (`defer`) since output is stdout. Files live only under the OS temp directory.

### F058-T06: Untrusted binary resolution via PATH
- Vector: the wrong/malicious binary named `typst`/`dot`/`asciidoctor` is picked up and executed.
- Impact: execution of an unexpected binary.
- Likelihood: Low.
- Mitigation: tools are resolved only from a fixed, ordered list of standard install directories (`/opt/homebrew/bin`, `/usr/local/bin`, `/Library/TeX/texbin`, `/usr/bin`) and must be executable files; the inherited shell `PATH` is appended **after** these trusted directories for the child's environment, not used to discover the executable. The resolved binary is the user's own install on their own machine. Relates to **SEC-4**.

### F058-T07: Stderr log disclosure / injection in the error UI
- Vector: the converter's stderr (surfaced on failure) contains attacker-influenced text that could be misrendered (e.g. as HTML) in the error view.
- Impact: minor UI spoofing.
- Likelihood: Low.
- Mitigation: the PDF host shows the log as plain text (last 40 lines) in an `NSTextView`; the HTML host's error page HTML-escapes `&` and `<` before embedding the log, and that page is itself rendered with JavaScript disabled. No code path treats the log as executable.

## Residual Risks

- AsciiDoc `include`/file-read runs in the converter's default safe mode (T02) and the rendered HTML has no CSP for remote resources (T03) — both accepted for now, bounded by JavaScript being disabled and by the document being one the user chose to open; tightening (`--safe-mode`, CSP) is tracked as a follow-up.
- Previews depend entirely on the user's locally-installed, trusted toolchain; Crispy bundles nothing and verifies nothing about those binaries beyond resolving them from standard directories.
- The app is unsandboxed by design; converters run with the user's privileges.

## NFR Compliance

- **SEC-1** — converters invoked via `Process` with an argument array (no shell); inbound results are typed (`status`/`Data`/`String`).
- **SEC-3 / SEC-3a** — no shell interpolation of untrusted content; AsciiDoc HTML rendered with JavaScript disabled; AsciiDoc anchored with `--base-dir`.
- **SEC-4** — tools resolved only from fixed standard directories; no remote/bundled engine.
- **SEC-6** — fully offline; rendering is local CLI execution with no network dependency.
- **SEC-7** — converter input/output confined to per-invocation scratch dirs under the OS temp directory; AsciiDoc base directory scoped to the document's own directory.
- **REL / PERF** — debounced, cancellable, watchdog-bounded compiles off the main thread; previews never block the UI; PDF page/scroll preserved across recompiles.
- **A11Y** — Source mode is the standard accessible code editor; previews expose accessibility identifiers (`editor.typst.preview`, `editor.asciidoc.preview`, `editor.diagram.preview`).
