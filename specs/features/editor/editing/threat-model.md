# Editing — Threat Model

## Overview

The Editing feature provides code and plain-text editing with syntax highlighting, find/replace, formatting ribbon for rich text, and language-aware editor hosts. It opens files from the local file system, applies syntax highlighting based on extension detection, and saves content back to disk. The threat surface is limited to file content handling, syntax highlighting performance, and WKWebView-based rich text editing. No network I/O is performed.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Editor | File content is read from disk and displayed. Edits are saved back atomically. |
| Editor ↔ WKWebView (rich text) | Markdown/HTML documents use a WKWebView for rendered editing. Content is injected via JavaScript; edits are synchronized back via Turndown. |
| Editor ↔ Syntax highlighter | File content is parsed for syntax tokens. Large files bypass highlighting. |
| Formatting ribbon ↔ WKWebView | Formatting commands are sent as JavaScript payloads to the web editor. |

## Attack Surfaces

1. **File content loaded into editor** — arbitrary file content (including binary-as-text fallback) is rendered in the editor surface.
2. **Syntax highlighting on large files** — files exceeding 180K characters disable highlighting, but the threshold check itself processes the file.
3. **WKWebView content injection** — markdown/HTML content is injected into a web view for rendering. Malicious content could exploit the web process.
4. **Formatting command payloads** — ribbon actions send command IDs to the web editor via `evaluateJavaScript`.
5. **Find/replace with regex-like patterns** — search queries are used for case-insensitive string matching.
6. **External file change reload** — files modified externally are reloaded, potentially replacing user edits.

## Threats

### F007-T01: Script execution via malicious file content in WKWebView

- **Vector:** A file containing crafted HTML/JavaScript is opened in the markdown/HTML editor. The WKWebView renders the content, potentially executing embedded scripts.
- **Impact:** Script execution within the WKWebView sandbox. Could access local file references if the web view has file access grants.
- **Likelihood:** Medium — developers routinely open untrusted HTML files.
- **Mitigation:** WKWebView runs in a separate process with macOS sandbox restrictions. The editor injects content into a controlled iframe/template rather than loading raw files directly. `editorReady` gating ensures content is only injected into the prepared runtime. File access is scoped to the project root (not the entire filesystem). Linked NFR: SEC-Input-Sanitization.

### F007-T02: Denial of service via syntax highlighting on adversarial input

- **Vector:** A crafted file with pathological patterns (e.g., deeply nested brackets, extremely long lines) causes the syntax highlighter to consume excessive CPU time.
- **Impact:** UI freeze; editor becomes unresponsive.
- **Likelihood:** Low — the 180K character limit prevents processing very large files, but pathological patterns in smaller files could still cause issues.
- **Mitigation:** Syntax highlighting is disabled beyond 180,000 characters. The code editor uses language definitions with bounded regex patterns. Consider adding a per-line character limit for highlighting. Linked NFR: PERF-Responsiveness.

### F007-T03: Data loss via external reload race condition

- **Vector:** An external process modifies a file while the user has unsaved edits. The editor reloads the external content, potentially discarding user changes without warning.
- **Impact:** Loss of unsaved user edits.
- **Likelihood:** Medium — common in multi-tool workflows (e.g., git operations, formatters).
- **Mitigation:** External reload preserves editor view state (selection, scroll position) per F007-R13. The editor reconciles unsaved changes or notifies the user per F006-R08. The reload does not silently discard unsaved content. Linked NFR: SEC-Data-Protection.

### F007-T04: JavaScript injection via formatting command

- **Vector:** A formatting ribbon action constructs a JavaScript payload that includes user-controlled content (e.g., link URL from user input). If not properly escaped, this could inject arbitrary JavaScript into the WKWebView.
- **Impact:** Script execution in the web editor context.
- **Likelihood:** Low — formatting commands use fixed command IDs, not user-interpolated strings.
- **Mitigation:** Formatting commands are sent as structured payloads with fixed command identifiers (bold, italic, heading1, etc.). User-provided values (link URLs, image paths) are passed as data parameters, not interpolated into JavaScript strings. Content sync runs after formatting mutation to capture the result. Linked NFR: SEC-Input-Sanitization.

### F007-T05: Contrast enforcement bypass leaking content

- **Vector:** A malicious theme provides token colors with near-zero contrast against the background, making code content invisible while still present (hidden text attack).
- **Impact:** User cannot see certain code content; potential for hidden malicious code in reviewed files.
- **Likelihood:** Very low — themes are user-selected.
- **Mitigation:** The code editor enforces minimum contrast ratios for syntax token readability (F007-R06). Tokens failing contrast checks are rendered with fallback colors. Linked NFR: A11Y.

## Residual Risks

- WKWebView vulnerabilities are mitigated by Apple's process isolation but remain a theoretical risk.
- The editor opens any file the user has read access to, including potentially sensitive files. This is by design.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Structured command payloads; no string interpolation in JS. |
| SEC-Data-Protection | Compliant | External reload reconciliation; atomic saves. |
| PERF-Responsiveness | Compliant | 180K char highlighting limit; debounced autosave. |
| A11Y | Compliant | Contrast enforcement; accessibility identifiers on editor hosts. |
| OBS | Compliant | File operations logged via existing infrastructure. |
