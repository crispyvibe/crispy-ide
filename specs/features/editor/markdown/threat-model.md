# Markdown — Threat Model

## Overview

The Markdown feature provides rendered editing of `.md`, `.markdown`, and `.mdx` files using a WKWebView with a bundled markdown runtime. Content is rendered as HTML, edited in-place, and converted back to canonical markdown via Turndown. Theme tokens are injected as CSS custom properties. The primary threat surface is the WKWebView rendering untrusted markdown content that may contain embedded HTML, scripts, or crafted link/image references.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Markdown editor | Markdown source is read from disk and injected into the WKWebView runtime. |
| WKWebView ↔ Native view model | Edited HTML is converted to markdown via Turndown (in-WebView JS) and sent back to the native `MarkdownViewModel` via message handlers. |
| Theme engine ↔ WKWebView | ~50 CSS custom properties are injected into the web view to reflect the active theme. |
| User input ↔ Link/Image/Table dialogs | User-provided URLs, file paths, and dimensions are inserted into markdown syntax. |
| WKWebView crash ↔ Recovery | Web process crashes are detected and content is re-rendered from the in-memory markdown source. |

## Attack Surfaces

1. **Markdown content with embedded HTML/scripts** — markdown files may contain raw HTML blocks including `<script>` tags, `<iframe>`, event handlers (`onclick`), etc.
2. **Image references** — `![alt](path)` syntax can reference local file paths or external URLs. The image picker resolves paths relative to the file.
3. **Link URLs** — user-provided URLs in the link dialog are inserted into markdown without URL validation.
4. **CSS custom property injection** — theme tokens are injected as CSS values. Malformed theme values could break rendering.
5. **Turndown HTML-to-markdown conversion** — the in-WebView Turndown library processes the DOM; crafted DOM structures could produce unexpected markdown.
6. **WKWebView crash recovery** — on crash, content is re-rendered from the last known markdown source held in memory.

## Threats

### F008-T01: Cross-site scripting via embedded HTML in markdown

- **Vector:** A markdown file contains raw HTML with `<script>` tags or event handlers. When rendered in the WKWebView, these scripts execute in the web view context.
- **Impact:** Script execution within the WKWebView process. Could access WKWebView message handlers, manipulate the editor DOM, or exfiltrate content via the native bridge.
- **Likelihood:** Medium — developers commonly open markdown files from untrusted sources (READMEs from cloned repos, downloaded documentation).
- **Mitigation:** The WKWebView runs in a separate sandboxed process. The markdown runtime SHOULD sanitize HTML blocks before rendering (strip `<script>`, event handlers). Message handlers from WebView to native code MUST validate message content structure. File access is scoped to the project root. Linked NFR: SEC-Input-Sanitization.

### F008-T02: Local file disclosure via image path references

- **Vector:** A markdown file contains `![](file:///etc/passwd)` or `![](../../../.ssh/id_rsa)`. If the WKWebView resolves these paths and the image load error reveals file existence, information leaks.
- **Impact:** File existence disclosure; potential content disclosure if the WKWebView renders text files as "broken images" with error details.
- **Likelihood:** Low — WKWebView file access is scoped; image loading of non-image files produces no useful content.
- **Mitigation:** WKWebView file access is scoped to the project root directory. Paths outside this scope are not resolvable. The image picker uses `standardizedFileURL` and resolves paths relative to the document, not the filesystem root. Linked NFR: SEC-Data-Protection.

### F008-T03: JavaScript injection via link URL dialog

- **Vector:** User enters `javascript:alert(1)` as a URL in the link insertion dialog. The resulting `[text](javascript:alert(1))` markdown renders as a clickable link that executes JavaScript when clicked in the preview.
- **Impact:** Script execution in the WKWebView context on link click.
- **Likelihood:** Low — user provides the URL themselves; more relevant for shared/imported markdown.
- **Mitigation:** Link insertion SHOULD validate that URLs use `http:`, `https:`, or relative path schemes. `javascript:` and `data:` scheme URLs SHOULD be rejected or sanitized by the markdown renderer. Linked NFR: SEC-Input-Sanitization.

### F008-T04: Theme token injection causing rendering corruption

- **Vector:** A malicious or corrupted theme provides CSS custom property values containing CSS injection payloads (e.g., `expression()`, `url()` with data URIs, or values that break out of the property context).
- **Impact:** Visual corruption; potential for CSS-based data exfiltration in older WebKit versions.
- **Likelihood:** Very low — themes are user-selected and loaded from app resources.
- **Mitigation:** Theme tokens are injected as CSS custom property values. Values SHOULD be validated as simple color/size tokens before injection. The ~50 properties are set via a controlled injection mechanism, not raw string concatenation into a `<style>` block. Linked NFR: SEC-Input-Sanitization.

### F008-T05: Data loss on WKWebView crash during unsaved edit

- **Vector:** The WKWebView process crashes while the user has unsaved edits that have been converted to markdown but not yet saved to disk.
- **Impact:** Loss of edits between last autosave and crash.
- **Likelihood:** Low — WKWebView crashes are rare; autosave runs every 450ms.
- **Mitigation:** Crash recovery re-renders from the in-memory markdown source held by `MarkdownViewModel`. The native view model always holds the latest markdown (synchronized via Turndown on each edit). Autosave persists to disk every 450ms. Maximum data loss is limited to the autosave interval. Linked NFR: SEC-Data-Protection.

### F008-T06: Table dimension injection causing resource exhaustion

- **Vector:** User enters extremely large row/column counts in the table insertion dialog (e.g., 10000×10000), causing the editor to generate and render a massive markdown table.
- **Impact:** Editor freeze; memory exhaustion.
- **Likelihood:** Low — requires deliberate user action.
- **Mitigation:** Table dialog SHOULD validate dimensions with reasonable upper bounds (e.g., max 100 rows, 20 columns). Invalid values block insertion and show validation feedback per F008-S07. Linked NFR: PERF-Responsiveness.

## Residual Risks

- Markdown files from untrusted sources may contain embedded HTML that executes in the WKWebView sandbox. Full HTML sanitization would break legitimate use cases (embedded widgets, styled content).
- The Turndown library is a third-party dependency; vulnerabilities in its DOM parsing could produce unexpected output.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Scoped file access; structured message handlers; URL validation recommended. |
| SEC-Data-Protection | Compliant | In-memory source retained; crash recovery; autosave. |
| PERF-Responsiveness | Compliant | Table dimensions bounded; code block highlighting scoped. |
| A11Y | Compliant | Rich/source toggle; formatting toolbar keyboard-accessible. |
| OBS | Compliant | File operations logged. |
