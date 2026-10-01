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
- **Mitigation:** The WKWebView runs in a separate process and the Markdown runtime CSP does not grant untrusted inline scripts or event handlers the required nonce. Native message handlers validate payload structure and link destinations. Markdown/HTML resource rendering currently receives root read access so bundled and file-adjacent assets both resolve; this broad scope is treated as residual risk rather than described as project-scoped. Linked NFR: SEC-Input-Sanitization.

### F008-T02: Local file disclosure via image path references

- **Vector:** A markdown file contains `![](file:///etc/passwd)` or `![](../../../.ssh/id_rsa)`. If the WKWebView resolves these paths and the image load error reveals file existence, information leaks.
- **Impact:** File existence disclosure; potential content disclosure if the WKWebView renders text files as "broken images" with error details.
- **Likelihood:** Medium — the current Markdown runtime uses root read access so bundled and file-adjacent assets can resolve.
- **Mitigation:** The image picker resolves standardized paths relative to the document and returns only supported image extensions. WebKit image decoders do not expose arbitrary text-file contents as images, and CSP blocks `connect-src`; nevertheless, explicit local image references can render any decodable image readable by the app. Tightening the runtime read scope requires a separate resource-loading design and remains residual risk. Linked NFR: SEC-Data-Protection.

### F008-T03: JavaScript or credential injection via link destinations

- **Vector:** Imported Markdown or the link editor supplies `javascript:`, `data:`, another executable/custom scheme, a protocol-relative URL, or an HTTP(S) URL containing embedded credentials.
- **Impact:** Script execution in the editor WebView, credential disclosure, unexpected application launch, or navigation away from the editing runtime.
- **Likelihood:** Medium — developers routinely open Markdown from cloned and generated repositories.
- **Mitigation:** The runtime permits only same-document fragments, relative/`file:` paths, HTTP(S), and `mailto:`; rejects unsupported/protocol-relative/malformed targets and embedded web credentials; and calls `preventDefault()` for every rich-mode anchor activation. Swift independently revalidates HTTP(S)/`mailto:` targets before invoking injected routes. `MarkupRenderedEditor.Coordinator` cancels link-activated and targetless WebKit navigation as a defense-in-depth backstop. Linked NFR: SEC-Input-Sanitization.

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

### F008-T07: Local link path traversal or unavailable target

- **Vector:** A relative Markdown link contains `../` segments, an absolute `file:` URL, a directory, or a nonexistent target and attempts to make Crispy open an unintended filesystem location.
- **Impact:** Unexpected local-file disclosure to the user, incorrect project ownership, broken navigation, or remote/local provider confusion.
- **Likelihood:** Medium — relative cross-document links commonly contain parent traversal.
- **Mitigation:** Before a local action posts, the runtime synchronously flushes pending Turndown content to the native bridge. Swift removes fragments, standardizes file URLs, requires local targets to exist and not be directories for both Crispy and Default App actions, rejects Default App for remote-provider paths, and resolves symlinks before enforcing an available absolute project-root boundary. Standard panes open through `EditorGroupStore`, preserving tabs/providers/comments; remote providers retain their authenticated confinement path. Opening is user-initiated and link content is never transmitted externally by this route.

### F008-T08: WebView navigation bypasses native routing

- **Vector:** A raw HTML anchor, keyboard activation, `_blank` target, or missed JavaScript event attempts to replace the bundled editor page or create an unmanaged WebView.
- **Impact:** Loss of the editing surface, bypass of the Crispy/default-browser choice, or navigation with the editor's broad local read scope.
- **Likelihood:** Low–Medium because Markdown permits embedded HTML.
- **Mitigation:** Delegated click/context-menu handlers prevent default activation for all rendered `a[href]` elements. The native `WKNavigationDelegate` independently cancels `.linkActivated` and target-frame-nil requests. No `WKUIDelegate` creates child WebViews. Browser opening occurs only through validated injected routes.

## Residual Risks

- Markdown/HTML runtime asset loading currently uses `/` as the WKWebView read-access root. Native link routing is separately validated and project-confined when possible, but decodable local images referenced directly by Markdown remain readable to the rendered surface.
- Markdown files from untrusted sources may contain embedded HTML that changes document structure, styling, links, and resource references. Inline script/event execution is constrained by CSP, but full HTML sanitization is not applied because it would break legitimate styled content.
- The Turndown library is a third-party dependency; vulnerabilities in its DOM parsing could produce unexpected output.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Runtime/native target allowlists, credential rejection, project-confined native file-link routing, and structured message handlers. |
| SEC-Data-Protection | Partial | Native file links are validated and confined when a project root is known; broad WKWebView resource read scope remains a documented residual risk. |
| PERF-Responsiveness | Compliant | Table dimensions bounded; code block highlighting scoped. |
| A11Y | Compliant | Rich/source toggle; formatting toolbar keyboard-accessible. |
| OBS | Compliant | File operations logged. |
