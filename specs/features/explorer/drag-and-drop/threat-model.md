# Drag & Drop — Threat Model

## Overview

Drag & Drop enables file and folder reorganization within the explorer sidebar. Intra-project drags execute move operations; cross-project drags execute copy operations. The feature validates against self-moves, descendant-into-ancestor moves, and destination collisions. Operations are delegated to the `PaneWorkerExecutor` which performs actual file system operations. No network I/O is performed.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| NSPasteboard / NSItemProvider ↔ Drop planner | Drag payloads arrive via macOS drag-and-drop APIs. Source URLs are decoded from the pasteboard. |
| Drop planner ↔ PaneWorkerExecutor | Validated transfer plans are executed by the worker, which performs `moveItem` or `copyItem` on the file system. |
| File system ↔ Explorer tree | After move/copy, the tree is refreshed to reflect the new state. Selections are remapped. |

## Attack Surfaces

1. **Source URLs from pasteboard** — drag payloads from external apps (Finder, other apps) provide file URLs that may reference paths outside the workspace or contain symlinks.
2. **Destination directory resolution** — the drop target directory is determined by the row the user drops onto. The target must be a valid existing directory.
3. **Move/copy operation execution** — the worker performs file system operations using the source and destination paths from the transfer plan.
4. **Cross-project boundary detection** — the operation type (move vs. copy) depends on whether source and target share a project root. Incorrect detection could cause unintended moves (data loss) instead of copies.

## Threats

### F025-T01: Path traversal via crafted drag payload

- **Vector:** An external application provides a drag payload with a source URL containing path traversal components (e.g., `../../sensitive-file`) or a symlink pointing outside the workspace. The drop planner resolves this to a move/copy operation targeting an unintended file.
- **Impact:** Moving or copying sensitive files into the workspace (disclosure) or moving workspace files to unexpected locations.
- **Likelihood:** Low — source URLs are normalized via `standardizedFileURL` which resolves symlinks and `..` components. `fileExists` is checked before planning.
- **Mitigation:** `ExplorerItemDropPlanner` normalizes all URLs via `standardizedFileURL`. Source files must pass `FileManager.fileExists`. Destination collision check prevents overwriting existing files. Self-move and descendant-into-ancestor checks prevent circular operations. Linked NFR: SEC-Input-Sanitization.

### F025-T02: Unintended move instead of copy due to project root miscalculation

- **Vector:** The operation resolver determines move vs. copy by checking if source and target share a project root (longest matching prefix). If project roots are misconfigured or overlap, a cross-project drag could be incorrectly classified as intra-project, resulting in a move (source deleted) instead of a copy.
- **Impact:** Unintended deletion of the source file (data loss).
- **Likelihood:** Low — project roots are distinct paths managed by the vibespace. The resolver uses `longestMatchingProjectRoot` with exact path prefix matching.
- **Mitigation:** Operation resolution uses `standardizedFileURL` for all comparisons. The `longestMatchingProjectRoot` function ensures the most specific project root wins. If neither source nor target matches a project root, the operation defaults to copy (safe default). Linked NFR: SEC-Data-Protection.

### F025-T03: Destination collision bypass via race condition

- **Vector:** Between the collision check (`fileExists` at destination) and the actual move/copy execution, another process creates a file at the destination path. The worker overwrites the newly created file.
- **Impact:** Data loss — the file created by the other process is overwritten.
- **Likelihood:** Very low — requires precise timing by a concurrent process.
- **Mitigation:** The collision check in `ExplorerItemDropPlanner` rejects plans where the destination already exists. The actual file operation in `PaneWorkerExecutor` uses file system APIs that may fail on collision (depending on implementation). Consider using `FileManager.moveItem` which throws on existing destination. Linked NFR: SEC-Data-Protection.

### F025-T04: Resource exhaustion via large directory move

- **Vector:** User drags a very large directory (thousands of files) to a new location. The move operation blocks the worker and UI shows a busy state for an extended period.
- **Impact:** UI unresponsiveness during the operation.
- **Likelihood:** Low — move operations on the same volume are typically fast (metadata-only). Cross-volume moves (which become copy+delete) could be slow.
- **Mitigation:** Transfer operations run asynchronously via `Task` with `[weak self]`. The worker status shows a progress indicator ("Moving" / "Copying"). The operation has a 20-second timeout per plan item. Linked NFR: PERF-Responsiveness.

## Residual Risks

- File system operations are performed with the user's permissions. The app cannot move/copy files the user doesn't have access to, and cannot prevent the user from moving files they do have access to.
- Symlinks in the workspace are resolved by `standardizedFileURL`, which means the actual target is moved/copied rather than the symlink itself. This is correct behavior but may surprise users.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | URL normalization; fileExists validation; self-move prevention. |
| SEC-Data-Protection | Compliant | Collision detection; safe default to copy for ambiguous cases. |
| PERF-Responsiveness | Compliant | Async execution; timeout per operation; progress indicator. |
| A11Y | Compliant | Invalid drop targets provide visual feedback. |
| OBS | Compliant | All drag-drop operations logged. |
