# Terminal Board Dock — Threat Model

## Overview

Terminal Board Dock manages dockable content tiles (files, browsers, VibeCast, ACP) on the terminal board. It handles file path persistence for pinned tiles, spotlight preview via `DockPreviewBridge`, drag/resize interactions, and session restore from persisted board layout. The threat surface centers on file path injection during tile restore, stale file reference handling, and UI spoofing via tile content.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Persistence JSON ↔ Dock tile restore | Pinned file tile paths are persisted in vibespace JSON (HMAC-signed). On restore, paths are used to reopen files via the editor infrastructure. |
| `DockPreviewBridge` ↔ File system | `requestPreview(for:)` accepts a `URL` and standardizes it via `.standardizedFileURL`. The URL is passed to the editor/content-viewer infrastructure. |
| `DockPinnedFileView` ↔ `EditorGroupStore` | The pinned file tile embeds a `MarkdownEditorView` backed by `WKWebView`. The editor renders file content which could contain scripts. |
| Board interaction controller ↔ Tile layout | Drag/resize gestures update tile positions. Layout changes are persisted to vibespace state. |
| File system ↔ Tile content | File tiles read content from disk. A file modified externally between sessions could contain different (potentially malicious) content on restore. |

## Attack Surfaces

1. **Persisted file paths for tile restore** — File URLs stored in vibespace JSON are used to reopen files on session restore. Path traversal or symlink manipulation could redirect to unintended files.
2. **`DockPreviewBridge.requestPreview(for:)`** — Accepts a URL from the file explorer and standardizes it. The preview panel renders file content.
3. **`MarkdownEditorView` / `WKWebView` content rendering** — Pinned file tiles render markdown/HTML content. Malicious content could attempt XSS or local file access via WebView.
4. **Missing file handling during restore** — Persisted paths that no longer exist must be pruned. Failure to handle this gracefully could crash or expose error information.
5. **Board layout persistence** — Tile positions, sizes, and minimized state are persisted. Tampered layout data could produce overlapping tiles or extreme dimensions.

## Threats

### F037-T01: Path traversal via tampered persisted file tile path

- **Vector:** An attacker modifies the vibespace JSON to change a pinned file tile's path to a sensitive file (e.g., `~/.ssh/id_rsa`, `/etc/shadow`). On restore, the editor opens and renders that file's content.
- **Impact:** Disclosure of sensitive file contents in the editor tile, visible on screen.
- **Likelihood:** Very low — vibespace JSON is HMAC-signed; tampering invalidates the signature. The file must also be readable by the user.
- **Mitigation:** Persistence uses HMAC integrity signing. `DockPreviewBridge.requestPreview(for:)` standardizes URLs via `.standardizedFileURL` (resolves `..` components). The editor infrastructure respects macOS file permissions — files not readable by the user cannot be opened. Missing files are pruned gracefully per F037-R03. Linked NFR: SEC-Data-Protection.

### F037-T02: XSS or local file access via WebView in pinned file tile

- **Vector:** A pinned markdown or HTML file contains malicious JavaScript. When rendered in `MarkdownEditorView` (backed by `WKWebView`), the script could attempt to access local files, exfiltrate data, or manipulate the UI.
- **Impact:** Potential local file read via `file://` URLs in WebView; JavaScript execution in the renderer context.
- **Likelihood:** Low — requires the user to pin a file containing malicious content, or an attacker to modify a pinned file on disk.
- **Mitigation:** `WKWebView` configuration should disable `allowsFileAccessFromFileURLs` and restrict navigation to the rendered content. The markdown runtime uses a bundled renderer that sanitizes HTML output. WebView is sandboxed by WebKit's process isolation. Content is rendered read-only (no form submission or navigation to external URLs from tile context). Linked NFR: SEC-Input-Sanitization.

### F037-T03: UI spoofing via crafted file tile content

- **Vector:** A file pinned to the board contains content designed to mimic Crispy's UI chrome (fake buttons, fake terminal output, phishing prompts). The tile renders this content in a `MarkdownEditorView` that fills most of the tile area.
- **Impact:** User confusion — may interact with fake UI elements thinking they are real Crispy controls.
- **Likelihood:** Low — the tile has a distinct header with file name, close/minimize buttons, and border styling that distinguishes it from terminal tiles.
- **Mitigation:** `DockPinnedFileView` renders a fixed header overlay (`CrispyVibesHeaderChrome`) above the content area showing the real filename and controls. The tile has a distinct border and clip shape. Content is padded below the header (`.padding(.top, 30)`). The header is not part of the rendered file content. Linked NFR: SEC-Input-Sanitization.

### F037-T04: Crash or hang from malformed board layout data

- **Vector:** Tampered persistence data specifies extreme tile dimensions (e.g., width: 999999, negative positions) or an excessive number of tiles. On restore, SwiftUI attempts to render these, causing layout thrashing or memory exhaustion.
- **Impact:** UI freeze or crash during vibespace restore.
- **Likelihood:** Very low — HMAC signing prevents casual tampering.
- **Mitigation:** Board metrics calculation (F037-S27) recalculates positions based on current board dimensions and tile count. Layout sync validates against board capacity (F037-R02 rejects pins when no free capacity exists). SwiftUI's layout system clamps views to available space. Persistence integrity is HMAC-protected. Linked NFR: PERF-Responsiveness.

### F037-T05: Stale symlink exploitation during file tile restore

- **Vector:** A persisted file tile path points to a symlink. Between sessions, an attacker replaces the symlink target with a sensitive file. On restore, the tile opens the new target.
- **Impact:** Disclosure of the symlink target's content.
- **Likelihood:** Very low — requires write access to the symlink location and knowledge of the persisted path.
- **Mitigation:** `URL.standardizedFileURL` resolves symlinks to their canonical path. The editor opens whatever the resolved path points to, subject to standard macOS file permissions. This is equivalent to the user opening the file manually in any editor. Missing files are pruned (F037-R03) rather than retried. Linked NFR: SEC-Data-Protection.

### F037-T06: Resource exhaustion from excessive pinned tiles

- **Vector:** A user (or tampered persistence) creates many pinned file/browser tiles, each holding an `EditorGroupStore` and potentially a `WKWebView` instance. Memory consumption grows with each tile.
- **Impact:** Memory exhaustion, especially with large files or complex markdown rendering.
- **Likelihood:** Low — board capacity limits (F037-R02) prevent unbounded tile creation through the UI.
- **Mitigation:** Pin action is rejected when board has no free capacity (F037-S08). Minimized tiles move to a tab bar and may release their WebView. Board metrics enforce tile count limits based on board dimensions. Linked NFR: PERF-Responsiveness.

## Residual Risks

- File content rendered in `WKWebView` is subject to WebKit's security model. A WebKit vulnerability could be exploited via crafted file content, but this is a platform-level concern.
- Pinned files are read from disk on restore. If the file has been modified externally to contain malicious content, the tile renders it. This is equivalent to opening any file in an editor.
- The board layout is persisted as part of vibespace state. If HMAC signing is bypassed, arbitrary layout data could be injected. The impact is limited to UI rendering issues.
- Browser tiles (not yet fully implemented in the reviewed code) will introduce additional WebView attack surface when they render arbitrary web content.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | URLs standardized; WebView content sandboxed; header overlay prevents content spoofing tile chrome. |
| SEC-Data-Protection | Compliant | HMAC-signed persistence; missing files pruned gracefully; no secrets in tile metadata. |
| PERF-Responsiveness | Compliant | Board capacity limits prevent unbounded tiles; layout sync is incremental. |
| A11Y | Compliant | Tiles have accessibility identifiers and value labels; context menus for secondary actions. |
| OBS | Compliant | Board layout changes trigger persistence sync; no additional logging needed for dock-specific events. |
