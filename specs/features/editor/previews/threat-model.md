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
| Image editing ↔ Disk | Save writes edited raster bytes to the open file after identity checks. Export As writes a flattened copy to a user-selected `NSSavePanel` destination without rebasing the open document. |
| Image editing ↔ Vision | Full-resolution composited pixels are passed to Apple's on-device Vision framework for OCR or foreground masking; the analysis service has no network path. |
| OCR results ↔ Clipboard | Recognized strings remain in editor state until the user explicitly copies selected/all text to the system pasteboard. |

## Attack Surfaces

1. **Raster image parsing** — malformed image files (PNG, JPEG, TIFF) could exploit image decoder vulnerabilities in macOS frameworks.
2. **SVG rendering** — SVG files may contain embedded scripts, external references, or XXE payloads.
3. **PDF rendering** — malformed PDFs could exploit PDFKit vulnerabilities. PDFs may contain JavaScript, external links, or embedded files.
4. **HTML rendering with project-root access** — HTML files rendered in WKWebView have read access to the entire project root, enabling local file inclusion.
5. **Remote file staging** — temporary files are created in `NSTemporaryDirectory()` for remote preview. Race conditions or insufficient cleanup could leak data.
6. **Image edit save path** — edited images are saved back to the original file URL. Symlink manipulation could redirect writes.
7. **Raster flattening** — encoding one 8-bit frame may lose resolution, animation/pages, precision, or HDR auxiliary data.
8. **Concurrent file changes** — an external writer can replace the source while edits are pending or rendering.
9. **Export As destination** — the user may select an existing or sensitive writable path; destination aliases may not compare equal to the standardized open URL.
10. **Visual obscuration markup** — blur or pixelation can look unreadable while retaining recoverable structure; Redact has different export semantics.
11. **Vision analysis and OCR clipboard** — full-resolution pixels consume analysis memory, and copied recognized text enters the system clipboard.
12. **Background-removal transparency** — overwriting a non-alpha or limited-alpha format could destroy the removed-background result.
13. **Stale asynchronous presentation/analysis** — same-revision replacement sessions or drag-time composites could otherwise install results for different pixels.

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
- **Mitigation:** File state includes `fileResourceIdentifier` with size and modification date. Save compares current identity with the loaded baseline before rendering and again immediately before writing, returning `fileChangedDuringSave` if the second check fails. This detects common same-size atomic and symlink replacement at either checkpoint; atomic writing limits partial-file corruption. Linked NFR: SEC-Data-Protection.
- **Residual risk:** The second identity check and URL write remain separate operations, so a same-user attacker can still replace the target in the smaller final TOCTOU window; the code does not open and verify a destination file descriptor atomically.

### F009-T06: PDF JavaScript execution

- **Vector:** A PDF file contains embedded JavaScript (common in interactive forms). PDFKit may execute this JavaScript when rendering.
- **Impact:** Script execution within PDFKit's context; potential for unexpected behavior.
- **Likelihood:** Very low — PDFKit on macOS has limited JavaScript support and runs in-process with restricted capabilities.
- **Mitigation:** PDFKit is used in read-only continuous scrolling mode. No form interaction or JavaScript execution is enabled. The PDF viewer is display-only with auto-scaling. Linked NFR: SEC-Input-Sanitization.

### F009-T07: Resource exhaustion via large image editing

- **Vector:** A very large raster image is opened for editing or full-resolution Save/Copy decoding and composition consumes excessive resources.
- **Impact:** Memory pressure, UI stalls, or app termination.
- **Likelihood:** Low to medium.
- **Mitigation:** Display decode runs on a serial background queue; sources over a 4096-pixel longest edge use a bounded display proxy. Full-resolution Save/Copy/Export As decode, render, and encode run on a separate serial queue. Atomic local Save/Export As writes run on a dedicated I/O queue, remote staged writes use detached tasks, and completions return to the main actor with generation checks. Explicit Resize rejects edges above 16,384 pixels.
- **Residual risk:** Existing full-resolution sources and outputs within the per-edge resize cap can still allocate large source and 8-bit RGBA buffers; a 16,384×16,384 RGBA buffer is itself substantial. Export cancellation is checked between major stages, Vision cancellation reaches `VNRequest.cancel()`, and already-allocated framework buffers may persist until those calls return. True progressive loading is not implemented. Linked NFR: PERF-Responsiveness.

### F009-T08: Silent data loss through lossy raster overwrite

- **Vector:** Saving a display proxy, first frame/page, 8-bit flattening, or SDR image over a higher-fidelity source could discard source data.
- **Impact:** Irreversible loss of resolution, animation/pages, precision, or HDR gain-map data.
- **Likelihood:** Medium without the output separation and gate.
- **Mitigation:** Save never exports the display proxy: `RasterImageExportService` re-decodes the immutable file source at full resolution and replays operations off-main. `RasterImageSavePolicy` disables overwrite Save for multiple frames/pages, >8-bit sources, and HDR gain maps; Copy remains available. Export As is an explicit flatten path to a separate PNG/JPEG/HEIC/TIFF destination and never rebases the protected source (F009-R28/F009-R42).
- **Residual risk:** Save and Export As produce one 8-bit sRGB-or-source-RGB frame with orientation 1. They do not preserve animation/pages, high bit depth, gain maps, EXIF/IPTC/GPS, or ICC beyond the working color space; JPEG/HEIC recompress pixels. No PSD-style layered output exists. Linked NFR: SEC-Data-Protection.

### F009-T09: External modification causes silent edit loss

- **Vector:** Another process changes or atomically replaces a local or remote source while Crispy has edits or background output pending.
- **Impact:** User edits or external changes could be silently discarded.
- **Likelihood:** Medium in development workflows.
- **Mitigation:** Local observation and two Save checks compare size, modification date, and `fileResourceIdentifier`; conflicts require Reload or Keep. Remote materialization captures `remoteImageBaselineToken` before reading. Save fails closed with `remoteChanged` if current-token lookup throws, a version-capable provider lacks a baseline, or tokens differ; providers returning `nil` tokens explicitly receive trusted behavior. A successful write stores its new token. Revision/session/generation checks reject stale completions (F009-R31/F009-R34/F009-R36/F009-R45/F009-R51).
- **Residual risk:** Remote check-then-write is not atomic and `FileContentProviding` has no provider-level compare-and-swap. SFTP tokens contain only file size and mtime with one-second resolution, so same-size edits within one second can evade detection; tokenless providers are trusted by design. Local replacement can likewise occur after the final identity check. Linked NFR: SEC-Data-Protection.


### F009-T10: Export As writes to an unintended destination

- **Vector:** A user selects an existing sensitive file or a path alias to the open image.
- **Impact:** Flattened image bytes replace the selected destination or bypass normal Save conflict handling.
- **Likelihood:** Low — destination choice and overwrite confirmation require user interaction.
- **Mitigation:** Export As uses type-constrained `NSSavePanel`, writes atomically off-main, resolves symlinks, and compares `fileResourceIdentifier` to reject direct, symbolic-link, and hard-link aliases of the open file. It never rebases the document. Linked NFR: SEC-Data-Protection.
- **Residual risk:** Destination identity check and atomic URL write are separate operations, so a same-user attacker can replace or retarget the destination in the final TOCTOU window. Export As intentionally permits another user-confirmed writable destination; no verified destination file descriptor is held through replacement.

### F009-T11: OCR text leaks through implicit sharing

- **Vector:** Recognized text or source pixels are sent to a remote service, or OCR text is placed on the clipboard without the user's intent.
- **Impact:** Sensitive screenshot content could leave the editor or become available to clipboard readers.
- **Likelihood:** Low.
- **Mitigation:** `RasterImageVisionService` uses Apple's on-device Vision requests and contains no network client. OCR results remain revision-scoped editor state; only explicit per-line, Copy Selected, or Copy All actions call `RasterImagePasteboardWriting.writeText`. Document changes clear stale OCR results. Linked NFR: SEC-Data-Protection.
- **Residual risk:** Once explicitly copied, text follows macOS clipboard behavior and may be visible to other apps or clipboard-sync/history tools.

### F009-T12: Blur or Pixelate is mistaken for secure redaction

- **Vector:** A user covers sensitive text with Blur or Pixelate and exports it, assuming the original information is irrecoverable.
- **Impact:** Sensitive information may be reconstructed or inferred from visually obscured pixels.
- **Likelihood:** Medium for screenshot workflows.
- **Mitigation:** The Blur/Pixelate hint states that these tools are not secure and directs users to Redact. Redact exports an opaque alpha-1 fill after replacing the covered output pixels; renderer tests inspect the flattened covered region. Linked NFR: SEC-Data-Protection.
- **Residual risk:** Editing remains non-destructive until output, so the immutable source and undo history still contain the original pixels; copies of the original are unaffected, and users can still choose the weaker tools despite the warning.

### F009-T13: Full-resolution Vision analysis exhausts memory

- **Vector:** OCR or foreground removal first renders and then analyzes a very large source at full resolution.
- **Impact:** Memory pressure, slow analysis, or app termination.
- **Likelihood:** Low to medium.
- **Mitigation:** Export rendering and Vision requests run on serial background queues, lifecycle generation/revision checks reject stale results, and explicit Resize rejects requested edges above 16,384 pixels. Linked NFR: PERF-Responsiveness.
- **Residual risk:** The 16,384 cap limits explicit resize output, not pre-existing source dimensions. Full-resolution source decode, composite, Vision internals, and mask allocation can therefore exceed practical memory budgets before cancellation is observed.

### F009-T14: Background-removal alpha is lost on overwrite

- **Vector:** A transparent background-removal result is encoded back into JPEG/JPG, BMP, or GIF; GIF supports only 1-bit transparency.
- **Impact:** Removed or partially transparent areas become opaque or lose alpha fidelity.
- **Likelihood:** Medium without format gating.
- **Mitigation:** Once `.removeBackground` is present, Save is disabled for JPEG/JPG, BMP, and GIF with guidance to Export As PNG, HEIC, or TIFF; Export As remains available. Linked NFR: SEC-Data-Protection.
- **Residual risk:** A user may deliberately export to a format that does not preserve alpha and accept its warning/flattening behavior.

### F009-T15: Stale analysis or composite crosses document state

- **Vector:** A same-file reload installs a replacement session with the same revision number, or an asynchronous composite completes while an item is being dragged.
- **Impact:** OCR boxes, a foreground mask, or baked overlay pixels could appear on the wrong image or ghost an active item.
- **Likelihood:** Low after identity checks; medium without them.
- **Mitigation:** `AnalysisToken` requires editor generation, session identity, and revision; every load/reload cancels analysis and clears OCR. Analyzer cancellation calls `VNRequest.cancel()` and cancelled work never completes. Live composites require matching session/revision, are suppressed during drag, and failed renders clear stale output. Shutdown cancels all analysis. Linked NFR: SEC-Data-Protection, A11Y.
- **Residual risk:** Framework work may retain already-allocated image buffers briefly after cancellation, but its completion cannot mutate editor state.


## Residual Risks

- HTML files with project-root read access can read any file in the project. This is by design for asset resolution but creates a disclosure risk for sensitive project files.
- System image/PDF decoder vulnerabilities are outside the app's control; mitigation depends on macOS updates.
- T05 replacement detection uses file-resource identity both before render and immediately before write, but a final check-to-write TOCTOU window remains.
- Export As detects direct, symlink, and hard-link aliases, but its identity check is not atomic with the destination write.
- Remote version checking is check-then-write without provider CAS; SFTP size+mtime tokens have one-second resolution, and tokenless providers are trusted.
- Display decode, full-resolution output, and Vision run off-main. Explicit Resize caps requested edges at 16,384 pixels, but Vision first receives a full-resolution composited image and decoding an already-huge source remains a memory-pressure risk.
- Raster file operations are not logged.
- Canvas keyboard handling includes crop commands, markup traversal/delete/nudge/deselect, and standard Undo/Redo. VoiceOver can press markup buttons and invoke selected-item Delete/Move or crop Shrink/Expand/Move/Apply/Cancel actions without a pointer. Status changes are announced. App-level ⌘S routes to raster Save.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Scoped file access; dedicated SVG host; system decoders. |
| SEC-Data-Protection | Partial | Full-resolution output, revisions/generations, atomic writes, local identity checks, fail-closed remote tokens, alias-aware Export As refusal, overwrite policy, and conflict UI reduce loss; local/export/remote final TOCTOU and coarse SFTP-token risks remain. |
| PERF-Responsiveness | Partial | Decode, export, live composites, Vision, and disk writes are off-main; proxies are bounded and Resize caps requested edges at 16,384 pixels, but full-resolution output/analysis buffers can still be large and loading is not progressive. |
| A11Y | Compliant | Stable identifiers, keyboard commands, pressable markup buttons, selected-item and crop custom actions, tool traits, slider values, and VoiceOver status announcements are implemented. |
| OBS | Unsupported | Raster file operations are not logged. |
