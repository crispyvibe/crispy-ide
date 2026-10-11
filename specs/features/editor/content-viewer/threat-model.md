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
- **Mitigation:** Session restore checks `fileExists` before opening file tabs (missing files are skipped). Vibespace config uses HMAC-signed JSON persistence, making tampering detectable. Files are opened read-only unless they match an editable document type. Linked NFR: SEC-2.

### F006-T02: Autosave symlink race condition

- **Vector:** Between the user opening a file and autosave triggering, an attacker replaces the file with a symlink pointing to a sensitive location. The autosave writes editor content to the symlink target.
- **Impact:** Overwrite of arbitrary file contents.
- **Likelihood:** Very low — requires concurrent local file system manipulation as the same user, within a 450ms window.
- **Mitigation:** Autosave writes atomically (write to temp, then rename). The file URL is the `standardizedFileURL` resolved at open time. Consider adding a check that the file's device/inode hasn't changed since open. Linked NFR: SEC-2.

### F006-T03: Malicious file URL via drag-and-drop

- **Vector:** A crafted drag payload from an external app provides a file URL pointing to a sensitive system file. The content viewer opens it as a tab.
- **Impact:** Disclosure of sensitive file contents.
- **Likelihood:** Low — the user must accept the drop; the file must be readable by the user.
- **Mitigation:** Dropped file URLs are processed through `standardizedFileURL`, which normalizes path syntax but does not resolve symbolic links. The content viewer only opens files the user already has read permission for; symlink targets remain subject to the user's filesystem permissions, and resolving/restricting them to an approved root remains a residual hardening opportunity. Files are opened in the appropriate mode (read-only for non-editable types). Linked NFRs: SEC-3a, SEC-7.

### F006-T04: Resource exhaustion via excessive split panes or tabs

- **Vector:** Repeated split operations or mass tab opening exhausts memory.
- **Impact:** App performance degradation.
- **Likelihood:** Low — split panes are capped at 4 (`SplitPaneNode.maxPanes == 4`).
- **Mitigation:** Maximum pane count is enforced at 4. Tab count is bounded by available memory but each tab is lightweight (metadata only until content is loaded). Session restore skips missing files, preventing unbounded tab creation from stale state. Linked NFR: PERF-3.

### F006-T05: Browser tab loading arbitrary web content

- **Vector:** A `webPage` tab type can load any URL in WKWebView. If session state is tampered to include a malicious URL, the user could be exposed to phishing or exploit content.
- **Impact:** Phishing, drive-by download, or WKWebView exploit.
- **Likelihood:** Very low — requires tampered session state; WKWebView is sandboxed.
- **Mitigation:** Browser tabs use WKWebView which runs in a separate process with macOS sandbox restrictions. Session state is HMAC-signed. Browser tab restore uses a dedicated `browserTabRestoreHandler` that can validate URLs. Linked NFR: SEC-2.

### F006-T06: Tab retargeting prefix collision

- **Vector:** `retargetFileSystemLocation` remaps all tabs whose URL starts with the old path prefix. If two projects share a common prefix (e.g., `/Users/dev/project` and `/Users/dev/project-backup`), a rename of the shorter path could incorrectly remap tabs from the longer path.
- **Impact:** Tabs point to wrong files; potential data loss on save.
- **Likelihood:** Low — path matching uses exact prefix with path separator boundary.
- **Mitigation:** Retargeting uses `URL.standardizedFileURL` for comparison. The implementation iterates tabs and checks if the tab URL matches or is a descendant of the old URL (using path separator boundaries). Linked NFR: SEC-3a.

### F006-T07: Active file and provider context diverge

- **Vector:** Cross-document Markdown navigation changes the active tab, but comments, provider, metadata, accessibility, or promotion continue using a dock root or prior tab reference. A same-path file in another project amplifies the ambiguity.
- **Impact:** Wrong-file comments, unintended cross-project reads/writes, misleading title/accessibility output, or promotion of a different document than the one displayed.
- **Likelihood:** Medium without tab-scoped providers and one current-reference owner.
- **Mitigation:** Project-qualified `FileDocumentReference` defines tab identity; providers are keyed per tab and restored on activation; `activeFileDocumentReference` drives every current-context consumer; dock root references remain fallback-only; closed history entries are pruned. Linked NFRs: SEC-2, SEC-7.

### F006-T08: Stale routed host remains attached after selection changes

- **Vector:** A pane observes a parent snapshot rather than its group, filter reconciliation recursively reactivates a tab, or a same-kind A→B route retains A-scoped state/`WKWebView`.
- **Impact:** The UI can display or interact with content from a different tab/project than the selected identity, including wrong-provider reads or browser input sent to the prior page.
- **Likelihood:** Medium without direct observation and target-keyed boundaries.
- **Mitigation:** Pane scopes directly observe `EditorGroupStore`; reconciliation and user activation use distinct idempotence semantics; routed content is keyed by tab ID; browser containers detach A before attaching B; mounted tests verify one-turn selected/routed/attached convergence. Linked NFRs: SEC-2, REL-1, TEST-2.

## Residual Risks

- The content viewer opens any file the user has read access to. This is by design — it's an editor.
- WKWebView vulnerabilities are mitigated by Apple's process isolation but remain a residual risk for browser tabs.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-3a | Compliant | URL normalization; path validation; pane cap enforced. |
| SEC-2 | Compliant | HMAC-signed session state; atomic writes; fileExists checks; active references remain coupled to tab-scoped providers/comments. |
| PERF-3 | Compliant | Split panes capped at 4; autosave debounced. |
| A11Y-2 | Compliant | Active pane indicator; keyboard navigation for splits; one activation converges selected and routed identity. |
| OBS-1 | Partial | Tab selection and routed-content appearance emit tokenized diagnostics; general file open, save, and drag/drop operations do not yet have complete dedicated structured event coverage. |

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-09 | Added T08 for selected/routed/attached host divergence and direct-observation/keyed-route mitigations; canonicalized A11Y-2 and OBS-1 references. | — |
| 2026-10-06 | Added T07 for active-file/provider/comments divergence during cross-document navigation and compact-surface promotion. | — |
