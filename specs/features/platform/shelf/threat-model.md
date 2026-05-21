# Shelf — Threat Model

## Overview

Shelf is a persistent pinned-files section that stores file paths in `shelf-state.json` and opens files in the content viewer. It accepts file URLs from Finder, external open requests, and user interaction. The threat surface is limited to path handling (symlink traversal, path normalization), persistence integrity, and resource consumption from large directory trees.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| External open requests ↔ ShelfStore | Files opened from Finder or other apps via `openFilesInShelf` are added to Shelf. The source URLs are untrusted. |
| ShelfStore ↔ `shelf-state.json` | Shelf state is persisted via `AppPersistenceDataStore` as JSON. The file is readable/writable by same-user processes. |
| ShelfStore ↔ Content viewer | Selected shelf files are opened in the editor/content viewer pipeline. |
| NSOpenPanel ↔ ShelfStore | User-selected files from the "Add to Shelf" panel are added. These are user-confirmed and trusted. |

## Attack Surfaces

1. **External file URLs** — URLs received from Finder or other apps via `openFilesInShelf`. Could contain symlinks, paths outside the user's home, or paths to sensitive system files.
2. **`shelf-state.json` persistence** — plaintext JSON containing absolute file paths. Readable by same-user processes.
3. **Path normalization** — `URL(fileURLWithPath:).standardizedFileURL.path` is used for deduplication. Symlinks are not resolved, only `.` and `..` components.
4. **Folder expansion** — Shelf supports expandable folders with recursive inline browsing, which could traverse into large directory trees.
5. **File existence checks** — Shelf renders missing-file indicators; rapid existence checks on network-mounted paths could stall.

## Threats

### F033-T01: Symlink traversal via external open request

- **Vector:** A malicious app sends an open request with a symlink path that points to a sensitive file (e.g., `~/.ssh/id_rsa`). Shelf adds the path and the user opens it in the content viewer, potentially exposing the file content.
- **Impact:** User unknowingly views sensitive file content. No data leaves the app, but the content is rendered in the editor.
- **Likelihood:** Low — the user must actively click the shelf entry to open it; the file name is visible.
- **Mitigation:** Shelf normalizes paths via `standardizedFileURL` (resolves `.` and `..` but not symlinks). The content viewer displays the file path in the tab. Users can see what file they are opening. Shelf does not automatically open files without user interaction (except the first added file becomes selected). Linked NFR: SEC-Input-Sanitization.

### F033-T02: Path disclosure via `shelf-state.json`

- **Vector:** `shelf-state.json` contains absolute file paths in plaintext. A same-user process or backup system could read this file, revealing the user's project structure and file locations.
- **Impact:** Information disclosure of file paths the user has pinned.
- **Likelihood:** Medium — file is in the app's data directory, accessible to same-user processes.
- **Mitigation:** Shelf state is stored in the app's standard data directory (via `AppPersistenceDataStore`). The file contains only paths, not file contents. `clear()` removes the file entirely. `resetForFreshStart()` clears in-memory state. This is acceptable residual risk — same-user processes already have filesystem access. Linked NFR: SEC-Data-Protection.

### F033-T03: Resource exhaustion via deep folder expansion

- **Vector:** A user adds a folder with deeply nested structure (e.g., `node_modules`, `/usr`) to Shelf and expands it recursively, causing the app to enumerate thousands of entries.
- **Impact:** UI stall; memory pressure from large tree rendering.
- **Likelihood:** Low — requires user to manually expand deep folders.
- **Mitigation:** Folder expansion is lazy (user-triggered per level). The file tree uses the same `listTree` worker method as the explorer, which returns only immediate children per expansion. No recursive pre-loading occurs. Linked NFR: PERF-Responsiveness.

### F033-T04: Persistence corruption causing crash loop

- **Vector:** `shelf-state.json` is corrupted (e.g., by disk error or concurrent write from another process), causing JSON decode failure on every launch.
- **Impact:** Shelf fails to load; potential crash if error is not handled gracefully.
- **Likelihood:** Very low — `AppPersistenceDataStore.load()` returns nil on decode failure.
- **Mitigation:** `loadIfNeeded()` handles nil return from persistence gracefully (sets empty state). The `didLoad` guard prevents repeated load attempts. `resetForFreshStart()` clears state without writing. JSON persistence uses `AppPersistenceDataStore` which handles encode/decode errors. Linked NFR: PERF-Responsiveness.

### F033-T05: Unbounded shelf growth

- **Vector:** Repeated external open requests or automated tooling adds thousands of files to Shelf without user intervention, growing `shelf-state.json` and degrading UI performance.
- **Impact:** Slow shelf rendering; large persistence file.
- **Likelihood:** Very low — each add triggers deduplication and persistence.
- **Mitigation:** Shelf deduplicates entries by normalized path. The `addFiles` method removes existing entries before re-inserting (no duplicates). A reasonable cap (e.g., 500 entries) SHOULD be considered for future hardening. Current implementation has no explicit cap. Linked NFR: PERF-Responsiveness.

## Residual Risks

- Shelf stores absolute file paths. If the user's home directory is renamed or the volume is remounted at a different path, shelf entries become stale (shown as missing-file state).
- External open requests (`openFilesInShelf`) accept any file URL without prompting. This is by design for Finder integration but means any app can add entries to Shelf.
- Shelf does not validate that added paths are within the user's home directory or any specific scope. System files can be pinned if the user (or an external app) provides the path.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Path normalization via standardizedFileURL; deduplication. |
| SEC-Data-Protection | Compliant | No secrets stored; paths only; clear/reset available. |
| PERF-Responsiveness | Compliant | Lazy folder expansion; deduplication prevents unbounded growth. |
| A11Y | Compliant | Shelf rows accessible; missing-file state indicated visually. |
