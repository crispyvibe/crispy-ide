# Previews — Threat Model

## Overview

The Previews feature handles image preview (raster, SVG), PDF viewing, and HTML rendered editing. It uses native image rendering for rasters, PDFKit for PDFs, and WKWebView for HTML/SVG. Remote files are staged locally via SFTP before preview. The threat surface includes local file rendering of untrusted content, WKWebView HTML rendering with project-root file access, and remote file staging.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Image renderer | Raster images are loaded from disk into `NSImage`/`CGImage` for display. SVG files are loaded into a dedicated preview host. |
| File system ↔ PDFKit | PDF files are loaded via PDFKit's native renderer. |
| File system ↔ WKWebView (HTML) | HTML files are loaded into a WKWebView with read access scoped to the project root. A `<base>` tag is injected for relative asset resolution. |
| Remote SFTP ↔ Local staging | Remote files are downloaded to a temporary local file for native rendering. Edits are written back via SFTP. |
| Image editing ↔ Disk | Edited raster images are composited and saved to the original file path. |

## Attack Surfaces

1. **Raster image parsing** — malformed image files (PNG, JPEG, TIFF) could exploit image decoder vulnerabilities in macOS frameworks.
2. **SVG rendering** — SVG files may contain embedded scripts, external references, or XXE payloads.
3. **PDF rendering** — malformed PDFs could exploit PDFKit vulnerabilities. PDFs may contain JavaScript, external links, or embedded files.
4. **HTML rendering with project-root access** — HTML files rendered in WKWebView have read access to the entire project root, enabling local file inclusion.
5. **Remote file staging** — temporary files are created in `NSTemporaryDirectory()` for remote preview. Race conditions or insufficient cleanup could leak data.
6. **Image edit save path** — edited images are saved back to the original file URL. Symlink manipulation could redirect writes.

## Threats

### F009-T01: Arbitrary file read via HTML local file references

- **Vector:** An HTML file contains `<img src="../../.env">` or `<script src="../../secrets.json">`. The WKWebView has read access scoped to the project root (F009-R23), so any file within the project is accessible to the rendered HTML.
- **Impact:** Disclosure of sensitive project files (`.env`, credentials, private keys) to scripts running in the HTML preview.
- **Likelihood:** Medium — developers open HTML files from cloned repositories; project roots commonly contain `.env` files.
- **Mitigation:** WKWebView read access is scoped to the project root (not the entire filesystem). A `<base>` tag is injected to resolve relative paths from the file's parent directory. Consider restricting access to the file's parent directory rather than the full project root for untrusted HTML. Scripts in the WKWebView are sandboxed and cannot exfiltrate data without network access (which is not granted). Linked NFR: SEC-Data-Protection.

### F009-T02: Script execution in SVG preview

- **Vector:** An SVG file contains `<script>` tags or event handlers (`onload`, `onclick`). When rendered in the SVG preview host, scripts execute.
- **Impact:** Script execution in the preview context. Limited by the rendering host's capabilities.
- **Likelihood:** Medium — SVG files from untrusted sources commonly contain scripts.
- **Mitigation:** SVG files are routed to a dedicated `SVGFilePreview` host. The preview SHOULD render SVGs as static images (rasterize or use a non-scripting renderer). If using WKWebView for SVG, disable JavaScript execution via `WKWebViewConfiguration.preferences.javaScriptEnabled = false`. Linked NFR: SEC-Input-Sanitization.

### F009-T03: Image decoder exploitation via malformed raster file

- **Vector:** A crafted PNG/JPEG/TIFF file exploits a vulnerability in macOS image decoding frameworks (ImageIO, CoreGraphics).
- **Impact:** Potential code execution or app crash.
- **Likelihood:** Very low — macOS image decoders are hardened and regularly patched by Apple.
- **Mitigation:** Image decoding uses system frameworks (NSImage, CGImage) which benefit from Apple's security updates. The app does not implement custom image parsing. Load failures show an "Image Unavailable" state rather than crashing. Linked NFR: SEC-Input-Sanitization.

### F009-T04: Remote file staging data leakage

- **Vector:** Remote files are staged in `NSTemporaryDirectory()` for local preview. If temporary files are not cleaned up promptly, sensitive remote file content persists on the local disk.
- **Impact:** Sensitive remote file content accessible on local disk after the preview is closed.
- **Likelihood:** Low — cleanup runs on document change per F009-R17/R20.
- **Mitigation:** Staged preview files are cleaned up when the active document changes (F009-R17). Temporary file paths use UUID-based names to prevent prediction. The staging directory is the system temp directory with standard user permissions. Consider using `FileManager.removeItem` in a `defer` block for guaranteed cleanup. Linked NFR: SEC-Data-Protection.

### F009-T05: Image edit save via symlink redirection

- **Vector:** Between opening an image and saving edits, an attacker replaces the file with a symlink. The save operation writes composited image bytes to the symlink target.
- **Impact:** Overwrite of arbitrary file contents with image data.
- **Likelihood:** Very low — requires concurrent local file manipulation as the same user.
- **Mitigation:** Image save uses the `standardizedFileURL` resolved at open time. Save failure preserves in-memory edits and shows an actionable error (F009-R10). Consider verifying file identity (device/inode) before write. Linked NFR: SEC-Data-Protection.

### F009-T06: PDF JavaScript execution

- **Vector:** A PDF file contains embedded JavaScript (common in interactive forms). PDFKit may execute this JavaScript when rendering.
- **Impact:** Script execution within PDFKit's context; potential for unexpected behavior.
- **Likelihood:** Very low — PDFKit on macOS has limited JavaScript support and runs in-process with restricted capabilities.
- **Mitigation:** PDFKit is used in read-only continuous scrolling mode. No form interaction or JavaScript execution is enabled. The PDF viewer is display-only with auto-scaling. Linked NFR: SEC-Input-Sanitization.

### F009-T07: Resource exhaustion via large image editing

- **Vector:** A very large raster image (e.g., 100MP) is opened for editing. Crop, draw, and annotate operations create multiple in-memory copies of the full-resolution image.
- **Impact:** Memory exhaustion; app crash.
- **Likelihood:** Low — most development images are small; large images are uncommon.
- **Mitigation:** Image editing operates on the working image in-memory. Progressive thumbnail loading (F009-R14) reduces initial memory pressure. The clear edits action (F009-R12) releases edit state. Consider adding a file size warning for images above a threshold. Linked NFR: PERF-Responsiveness.

## Residual Risks

- HTML files with project-root read access can read any file in the project. This is by design for asset resolution but creates a disclosure risk for sensitive project files.
- System image/PDF decoder vulnerabilities are outside the app's control; mitigation depends on macOS updates.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Scoped file access; dedicated SVG host; system decoders. |
| SEC-Data-Protection | Compliant | Temp file cleanup; atomic saves; SFTP write-back. |
| PERF-Responsiveness | Compliant | Progressive loading; bounded preview operations. |
| A11Y | Compliant | Editing controls have accessibility identifiers; keyboard reachable. |
| OBS | Compliant | File operations logged. |
