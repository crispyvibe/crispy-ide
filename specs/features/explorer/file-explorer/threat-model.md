# File Explorer — Threat Model

## Overview

The File Explorer provides a tree-based file browser for all projects in the active vibespace. It supports lazy-loaded directory expansion, search, inline create/rename/delete, context menu actions (reveal in Finder, copy path, open in terminal), and both local and remote project roots. The threat surface includes file system operations (create, rename, delete), path handling, and the "Open in Terminal" action which spawns shell sessions. No direct network I/O for local projects; remote projects use SSH (covered by F034 threat model).

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| File system ↔ Explorer tree | Directory contents are read via `PaneWorkerExecutor`. File operations (create, rename, delete) are executed through the worker. |
| Explorer ↔ Terminal sessions | "Open in Terminal" spawns a terminal session at the selected path. |
| Explorer ↔ System pasteboard | "Copy Path" and "Copy Relative Path" write to the system clipboard. |
| Explorer ↔ Finder / macOS workspace | Local Reveal in Finder and Open in System invoke macOS with original local URLs. SSH rows are never passed to Finder as local paths. |
| Explorer ↔ Remote transfer coordinator | Remote Open in System and Download… pass project identity and remote path to the app-wide coordinator shared by explorer file/folder rows and active project roots. It permits one such transfer at a time and retains that slot through cancellation cleanup. Editor-triggered remote HTML uses a separate service and is not serialized by this boundary. |
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

- **Vector:** A context-menu action resolves the wrong target because mutable current selection differs from the right-clicked item, an unresolved name or path placeholder obscures the target, or same-named items cannot be distinguished before the user confirms permanent deletion of a file or directory tree (no Trash).
- **Impact:** Irreversible deletion of the wrong local or remote file/folder, or irreversible loss of an intended directory tree.
- **Likelihood:** Low after mitigation — every supported explorer surface requires explicit confirmation for an immutable retained target and displays its exact full path, though users may still click through dialogs habitually.
- **Mitigation:** Every filesystem deletion initiated from the AppKit unified explorer, SwiftUI explorer, or Shelf Files sidebar MUST retain the exact right-clicked item or path and create the shared `ExplorerDeleteConfirmation` from that target, never from mutable current selection. Its title MUST be `Delete “name”?` with the exact item name. Its message MUST use a permanent warning paragraph that repeats the exact name and states deletion cannot be undone, followed by a separate paragraph containing a localized `Path:` block with the exact full local or remote path from the retained target. All three surfaces MUST provide the same content and behavior, the destructive button MUST be `Delete`, and the UI MUST NOT show an unresolved raw placeholder. This full-path disclosure is intentional in a locally presented confirmation dialog because it reduces wrong-target risk for ambiguous names. Cancellation MUST invoke no deletion. Only acceptance may dispatch deletion for the retained target; dependent selections under the successfully deleted subtree are then cleared (F024-R06, F024-R19, F024-S53). Moving to Trash remains a possible future recoverability improvement. Linked NFR: SEC-Data-Protection.
- **Residual risk:** A user can still knowingly confirm permanent deletion, and deletion is not recoverable through Trash. The displayed path can expose local or remote directory structure to someone already able to view the user's local screen.

### F024-T04: Terminal session at attacker-influenced path

- **Vector:** "Open in Terminal" spawns a shell at the selected directory path. If a symlink in the explorer points to a directory containing a malicious `.bashrc`, `.zshrc`, or shell initialization file, the terminal session could execute attacker-controlled code on startup.
- **Impact:** Arbitrary command execution in the spawned terminal session.
- **Likelihood:** Low — requires a malicious symlink in the project and the user choosing "Open in Terminal" on it. Shell initialization files are user-controlled.
- **Mitigation:** The terminal opens at the literal path selected by the user. Shell initialization is controlled by the user's shell configuration, not by Crispy. The path is passed as the working directory to the terminal session, not as a shell command. Linked NFR: SEC-Input-Sanitization.

### F024-T05: Resource exhaustion via deep/wide directory expansion

- **Vector:** A project contains a directory with millions of files (e.g., `node_modules` without `.gitignore`). Expanding this directory loads all immediate children, consuming memory and causing UI stalls.
- **Impact:** UI freeze; memory exhaustion.
- **Likelihood:** Medium — large `node_modules` directories are common.
- **Mitigation:** Directory loading is lazy (only expanded directories are fetched). The tree uses targeted refresh, serializes requests per directory, coalesces event bursts, and does not recursively rebuild unchanged expanded subtrees. Deleted nodes are pruned from the AppKit cache. Git-ignored items are visually de-emphasized but still loaded. Consider adding a child count limit per directory expansion with a "show more" affordance. Tree load target is 200ms for up to 10,000 files. Linked NFR: PERF-Responsiveness.

### F024-T06: Information disclosure via Copy Path

- **Vector:** "Copy Path" writes the absolute file path to the system clipboard. If the user pastes this in a shared context (chat, issue tracker), it may reveal the local directory structure, username, or project organization.
- **Impact:** Minor information disclosure of local file system structure.
- **Likelihood:** Medium — users frequently paste paths in collaborative contexts.
- **Mitigation:** "Copy Relative Path" is offered as an alternative that reveals only project-relative structure. The absolute path copy is a deliberate user action. No mitigation needed beyond offering the relative alternative. Linked NFR: SEC-Data-Protection.

### F024-T07: Remote content persists in a local system-open snapshot

- **Vector:** Open in System copies an SSH file or directory content to local temporary storage where another application can read it.
- **Impact:** Sensitive remote content crosses onto the local disk and may remain after the external application exits.
- **Likelihood:** Medium for users working with confidential remote projects.
- **Mitigation:** Explorer delegates to the F034 transfer service, which creates owner-only app temporary snapshots and performs 24-hour stale cleanup. A failed operation cannot reuse or open an older snapshot. Linked NFR: SEC-Data-Protection.
- **Residual risk:** Same-user local processes and the chosen external application can read the snapshot during its retained lifetime.

### F024-T08: Failed remote download exposes a partial destination

- **Vector:** A transfer fails or is cancelled after writing some bytes directly to the user-selected destination.
- **Impact:** Other tools or users mistake incomplete content for a successful download; replacing an existing destination may destroy its prior contents.
- **Likelihood:** Medium without staging.
- **Mitigation:** Download writes to a hidden sibling staging item and publishes/replaces the chosen destination only after complete verified success. Before publication, the service synchronously awaits a MainActor publication-state acknowledgment and checks `Task` cancellation again immediately before replace/move. Cancel is unavailable while publishing. Failure or cancellation before that final boundary removes staging and reports through the global transfer overlay. Save-panel and destination replacement behavior governs user-confirmed replacement. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Final destination replacement follows filesystem/save-panel semantics and can still fail at publish time. Cancellation arriving after the final check can race with the atomic replace/move and may not prevent publication; the UI therefore does not advertise cancellation in publishing.

### F024-T09: Editor autosave recreates a successfully deleted item

- **Vector:** A local or remote file/directory is deleted while a matching dirty tab remains open. Normal close flushing or a pending autosave writes the buffer back after deletion, recreating the file or a descendant.
- **Impact:** The destructive action appears to fail, deleted content unexpectedly returns, or remote data is written after the user intentionally removed it.
- **Likelihood:** Low after typed event propagation; high if any detailed/docked surface misses the event.
- **Mitigation:** Local and legacy/enhanced remote explorers emit `ExplorerDeletionEvent` only after filesystem success. Local/remote project sessions forward the exact URL and directory flag. Detailed editor groups plus docked/floating groups close exact-path tabs and path-component descendants for directory deletion through `closeTab(..., discardUnsavedChanges: true)`, which omits the writer and discards the buffer so close flush/autosave cannot recreate the target. Failed/cancelled deletion emits no event. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** External applications or unrelated processes may independently recreate a deleted path; the mitigation covers Crispy-owned open buffers reached by the event pipeline.

## Residual Risks

- The explorer operates with the user's file system permissions. It cannot prevent the user from deleting their own files.
- Symlinks are followed by design. Restricting symlink traversal would break common development workflows.
- Remote explorer threats are covered in depth by the SSH Remote (F034) threat model.
- Remote system-open copies do not synchronize external edits back to the SSH source. Remote drag/drop remains unsupported.
- One coordinator-backed remote transfer from an explorer file/folder row or active project root runs at a time. Structured cancellation retains that slot through transport and staging cleanup; Cancel is unavailable while cancelling or publishing; failures remain in the overlay; transfers are not resumable. Publication uses a synchronous MainActor state acknowledgment and a final cancellation check immediately before replace/move, but cancellation after that check may not prevent the atomic publication. Editor-triggered remote HTML open is independent and uses editor busy/alert state.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Name validation; path construction via URL APIs; no shell interpolation. |
| SEC-Data-Protection | Compliant | Exact-target confirmation plus post-success typed deletion propagation and discard closure prevent Crispy autosave from recreating deleted local/remote items. |
| PERF-Responsiveness | Partial | Lazy loading and targeted refresh are implemented. The F024-R20/S54 user UI test source checks that ⌘T can still reach Terminal Board, but no case executed and it does not assert row completeness or scroll offset. |
| A11Y | Compliant | Keyboard navigation; disclosure toggles; error alerts dismissible. |
| OBS | Partial | Remote transfer lifecycle and newly relevant diagnostics are recorded. Diagnostics export sanitizes path-like strings in event metadata. Comprehensive logging of every local file operation is not implemented. |

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. `FolderExplorerViewModelTests` checks only confirmation-model formatting. Test-source search found no direct use of `ExplorerDeletionEvent`, `closeFileTabs`, `DockedFileViewerCoordinator.handleDeletion`, or `discardUnsavedChanges`; F024-T09's local/remote emission, session forwarding, exact/descendant detailed+docked+floating discard closure, and no-recreation mitigation are supported by production-source inspection only. `VibeSpaceAndNavigationUITests.testFilesSidebarRemainsResponsiveAfterRepeatedProjectScrolling` checks post-scroll liveness only by sending ⌘T and waiting for Terminal Board.

## Change History

- 2026-10-23: Final reconciliation confirms typed post-success local/remote deletion propagation, exact/descendant detailed+docked+floating discard closure, no-recreation behavior, and the absence of direct test invocation; validation is build/test-build only.
- 2026-10-23: Added F024-T09 for autosave resurrection after successful deletion, documented typed local/remote event propagation and discard-close mitigation, named the F024-R20/S54 user UI test exactly, and narrowed evidence to static/build-only source.
- 2026-10-23: Narrowed delete-confirmation evidence to shared-model formatting and recorded F024-S54's exact liveness-only UI assertion; final validation is build/test-build only with no executed pass.
- 2026-10-20: Strengthened F024-T03 requirements for mutable-selection and ambiguous-name risks; static evidence is limited to shared-model text/path formatting, not per-surface target, Cancel, or deletion routing.
- 2026-10-20: Reconciled publication-state acknowledgment, final cancellation checking, and residual atomic replace/move risk; corrected OBS to partial and documented sanitization of path-like exported event metadata.
