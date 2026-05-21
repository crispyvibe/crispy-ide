# File Explorer — Threat Model

## Overview

The File Explorer provides a tree-based file browser for all projects in the active vibespace. It supports lazy-loaded directory expansion, search, inline create/rename/delete, context menu actions (reveal in Finder, copy path, open in terminal), and both local and remote project roots. The threat surface includes file system operations (create, rename, delete), path handling, and the "Open in Terminal" action which spawns shell sessions. No direct network I/O for local projects; remote projects use SSH (covered by F034 threat model).

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Explorer tree | Directory contents are read via `PaneWorkerExecutor`. File operations (create, rename, delete) are executed through the worker. |
| Explorer ↔ Terminal sessions | "Open in Terminal" spawns a terminal session at the selected path. |
| Explorer ↔ System pasteboard | "Copy Path" and "Copy Relative Path" write to the system clipboard. |
| Explorer ↔ Finder | "Reveal in Finder" invokes `NSWorkspace.shared.activateFileViewerSelecting`. |
| File system watcher ↔ Explorer | `FSEvents` or polling triggers targeted directory refreshes. |

## Attack Surfaces

1. **Inline file/folder creation** — user-provided names are used to create files/folders on disk. Names could contain path separators or special characters.
2. **Inline rename** — user-provided names replace existing file/folder names. Validation must prevent path traversal.
3. **Delete with confirmation** — removes files/folders from disk permanently.
4. **Open in Terminal** — spawns a shell session at the selected directory path. The path becomes the working directory.
5. **Copy Path to clipboard** — absolute or relative paths are written to the system pasteboard.
6. **Search/filter** — user-provided search queries filter the tree. Queries are used for substring matching.
7. **Lazy directory loading** — expanding a directory fetches its contents. Symlinks in the tree could point outside the project.

## Threats

### F024-T01: Path traversal via crafted file/folder name

- **Vector:** User enters a name containing path separators (`../`, `/`) or null bytes during inline create or rename. If not validated, this could create files outside the intended directory.
- **Impact:** File creation or rename at unintended locations within the user's permission scope.
- **Likelihood:** Low — the worker constructs the destination path by appending the name to the parent directory URL. Path separators in names would create nested paths.
- **Mitigation:** Rename validation MUST reject empty names and names containing path separator characters (`/`). The worker uses `URL.appendingPathComponent` which handles path construction safely. Duplicate destination names produce an error (F024-R06). File system permissions prevent operations outside the user's access scope. Linked NFR: SEC-Input-Sanitization.

### F024-T02: Symlink escape in directory tree

- **Vector:** A project directory contains a symlink pointing outside the project root (e.g., `link -> /etc/`). Expanding this symlink in the explorer exposes files outside the project. Operations (delete, rename) on symlink targets affect the actual files.
- **Impact:** Disclosure of files outside the project; potential modification or deletion of external files.
- **Likelihood:** Medium — symlinks to external directories are common in development projects (e.g., `node_modules` links, build output links).
- **Mitigation:** The explorer displays symlinks as regular items (they are visible and selectable). File operations act on the symlink target (standard macOS behavior). The explorer does not restrict navigation through symlinks — this is by design for developer workflows. Users should be aware that symlinks may reference external locations. Linked NFR: SEC-Data-Protection.

### F024-T03: Destructive delete without adequate confirmation

- **Vector:** User accidentally confirms deletion of a large directory tree. The delete operation removes all contents permanently (no Trash).
- **Impact:** Irreversible data loss.
- **Likelihood:** Medium — delete requires confirmation (F024-R06), but users may click through dialogs habitually.
- **Mitigation:** Delete MUST require explicit confirmation before execution. The confirmation dialog SHOULD display the item name and indicate the operation is permanent. Dependent selections under the deleted subtree are cleared. Consider moving to Trash instead of permanent deletion for recoverable operations. Linked NFR: SEC-Data-Protection.

### F024-T04: Terminal session at attacker-influenced path

- **Vector:** "Open in Terminal" spawns a shell at the selected directory path. If a symlink in the explorer points to a directory containing a malicious `.bashrc`, `.zshrc`, or shell initialization file, the terminal session could execute attacker-controlled code on startup.
- **Impact:** Arbitrary command execution in the spawned terminal session.
- **Likelihood:** Low — requires a malicious symlink in the project and the user choosing "Open in Terminal" on it. Shell initialization files are user-controlled.
- **Mitigation:** The terminal opens at the literal path selected by the user. Shell initialization is controlled by the user's shell configuration, not by Crispy. The path is passed as the working directory to the terminal session, not as a shell command. Linked NFR: SEC-Input-Sanitization.

### F024-T05: Resource exhaustion via deep/wide directory expansion

- **Vector:** A project contains a directory with millions of files (e.g., `node_modules` without `.gitignore`). Expanding this directory loads all immediate children, consuming memory and causing UI stalls.
- **Impact:** UI freeze; memory exhaustion.
- **Likelihood:** Medium — large `node_modules` directories are common.
- **Mitigation:** Directory loading is lazy (only expanded directories are fetched). The tree uses targeted refresh (only affected directories reload on file system events). Git-ignored items are visually de-emphasized but still loaded. Consider adding a child count limit per directory expansion with a "show more" affordance. Tree load target is 200ms for up to 10,000 files. Linked NFR: PERF-Responsiveness.

### F024-T06: Information disclosure via Copy Path

- **Vector:** "Copy Path" writes the absolute file path to the system clipboard. If the user pastes this in a shared context (chat, issue tracker), it may reveal the local directory structure, username, or project organization.
- **Impact:** Minor information disclosure of local file system structure.
- **Likelihood:** Medium — users frequently paste paths in collaborative contexts.
- **Mitigation:** "Copy Relative Path" is offered as an alternative that reveals only project-relative structure. The absolute path copy is a deliberate user action. No mitigation needed beyond offering the relative alternative. Linked NFR: SEC-Data-Protection.

## Residual Risks

- The explorer operates with the user's file system permissions. It cannot prevent the user from deleting their own files.
- Symlinks are followed by design. Restricting symlink traversal would break common development workflows.
- Remote explorer threats are covered by the SSH Remote (F034) threat model.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Name validation; path construction via URL APIs; no shell interpolation. |
| SEC-Data-Protection | Compliant | Delete confirmation; relative path alternative; lazy loading. |
| PERF-Responsiveness | Compliant | Lazy loading; targeted refresh; 200ms tree load target. |
| A11Y | Compliant | Keyboard navigation; disclosure toggles; error alerts dismissible. |
| OBS | Compliant | All file operations logged. |
