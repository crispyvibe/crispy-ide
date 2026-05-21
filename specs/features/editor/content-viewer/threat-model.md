# Content Viewer — Threat Model

## Overview

The Content Viewer manages editor panes, tab lifecycle, split layouts, drag-and-drop tab reorganization, and session snapshot/restore. It opens files by type detection, manages autosave, and supports non-file tab types (terminal, ACP, VibeCast, web). The threat surface centers on file path handling, session restore from persisted state, and drag-and-drop URL processing. No network I/O is performed.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Content Viewer | Files are opened by URL from explorer selection or session restore. Paths are resolved via `URL.standardizedFileURL`. |
| Persisted session state ↔ Restore logic | `EditorSessionState` is deserialized from disk (JSON). Tab references, split ratios, and active tab IDs are restored. |
| Drag sources ↔ Drop delegate | File URLs and tab references arrive via `NSItemProvider` or `NSPasteboard` from Finder or internal drag. |
| Content Viewer ↔ WKWebView (browser tabs) | Web page tabs render arbitrary URLs in a `WKWebView`. |
| Autosave ↔ Disk | Edited content is written atomically to the original file path after a 450ms debounce. |

## Attack Surfaces

1. **Session restore file paths** — persisted `FileDocumentReference` paths are reopened on restore. A tampered state file could reference paths outside the workspace.
2. **Drag-and-drop file URLs** — external file URLs dropped onto panes are opened as tabs. Symlinks or crafted paths could reference sensitive files.
3. **Split ratio persistence** — ratios stored as `[String: Double]` are restored without bounds checking; extreme values could cause layout issues.
4. **Autosave to original path** — content is written back to the file's original URL. If the path was manipulated (e.g., via symlink race), writes could target unintended locations.
5. **Browser tab URLs** — `webPage` tabs can load arbitrary URLs in WKWebView.
6. **Tab retargeting on rename** — `retargetFileSystemLocation` remaps tab URLs based on path prefix matching.

## Threats

### F006-T01: Path traversal via tampered session state

- **Vector:** An attacker modifies the persisted `EditorSessionState` JSON to include file paths outside the workspace (e.g., `/etc/passwd`, `~/.ssh/id_rsa`). On restore, these files are opened in the editor.
- **Impact:** Disclosure of sensitive file contents in the editor UI.
- **Likelihood:** Very low — requires write access to the vibespace config directory (same user).
- **Mitigation:** Session restore checks `fileExists` before opening file tabs (missing files are skipped). Vibespace config uses HMAC-signed JSON persistence, making tampering detectable. Files are opened read-only unless they match an editable document type. Linked NFR: SEC-Data-Protection.

### F006-T02: Autosave symlink race condition

- **Vector:** Between the user opening a file and autosave triggering, an attacker replaces the file with a symlink pointing to a sensitive location. The autosave writes editor content to the symlink target.
- **Impact:** Overwrite of arbitrary file contents.
- **Likelihood:** Very low — requires concurrent local file system manipulation as the same user, within a 450ms window.
- **Mitigation:** Autosave writes atomically (write to temp, then rename). The file URL is the `standardizedFileURL` resolved at open time. Consider adding a check that the file's device/inode hasn't changed since open. Linked NFR: SEC-Data-Protection.

### F006-T03: Malicious file URL via drag-and-drop

- **Vector:** A crafted drag payload from an external app provides a file URL pointing to a sensitive system file. The content viewer opens it as a tab.
- **Impact:** Disclosure of sensitive file contents.
- **Likelihood:** Low — the user must accept the drop; the file must be readable by the user.
- **Mitigation:** Dropped file URLs are processed through `standardizedFileURL` (resolves symlinks). The content viewer only opens files the user already has read permission for — no privilege escalation occurs. Files are opened in the appropriate mode (read-only for non-editable types). Linked NFR: SEC-Input-Sanitization.

### F006-T04: Resource exhaustion via excessive split panes or tabs

- **Vector:** Repeated split operations or mass tab opening exhausts memory.
- **Impact:** App performance degradation.
- **Likelihood:** Low — split panes are capped at 4 (`SplitPaneNode.maxPanes == 4`).
- **Mitigation:** Maximum pane count is enforced at 4. Tab count is bounded by available memory but each tab is lightweight (metadata only until content is loaded). Session restore skips missing files, preventing unbounded tab creation from stale state. Linked NFR: PERF-Responsiveness.

### F006-T05: Browser tab loading arbitrary web content

- **Vector:** A `webPage` tab type can load any URL in WKWebView. If session state is tampered to include a malicious URL, the user could be exposed to phishing or exploit content.
- **Impact:** Phishing, drive-by download, or WKWebView exploit.
- **Likelihood:** Very low — requires tampered session state; WKWebView is sandboxed.
- **Mitigation:** Browser tabs use WKWebView which runs in a separate process with macOS sandbox restrictions. Session state is HMAC-signed. Browser tab restore uses a dedicated `browserTabRestoreHandler` that can validate URLs. Linked NFR: SEC-Data-Protection.

### F006-T06: Tab retargeting prefix collision

- **Vector:** `retargetFileSystemLocation` remaps all tabs whose URL starts with the old path prefix. If two projects share a common prefix (e.g., `/Users/dev/project` and `/Users/dev/project-backup`), a rename of the shorter path could incorrectly remap tabs from the longer path.
- **Impact:** Tabs point to wrong files; potential data loss on save.
- **Likelihood:** Low — path matching uses exact prefix with path separator boundary.
- **Mitigation:** Retargeting uses `URL.standardizedFileURL` for comparison. The implementation iterates tabs and checks if the tab URL matches or is a descendant of the old URL (using path separator boundaries). Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- The content viewer opens any file the user has read access to. This is by design — it's an editor.
- WKWebView vulnerabilities are mitigated by Apple's process isolation but remain a residual risk for browser tabs.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | URL normalization; path validation; pane cap enforced. |
| SEC-Data-Protection | Compliant | HMAC-signed session state; atomic writes; fileExists checks. |
| PERF-Responsiveness | Compliant | Split panes capped at 4; autosave debounced. |
| A11Y | Compliant | Active pane indicator; keyboard navigation for splits. |
| OBS | Compliant | File operations logged. |
