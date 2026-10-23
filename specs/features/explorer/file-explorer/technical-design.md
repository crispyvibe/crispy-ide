# File Explorer — Technical Design

## Overview

The file explorer provides a tree-based file browser in the sidebar, managed by `FolderExplorerViewModel` per project. It supports lazy-loaded directory expansion, debounced search, inline CRUD, directory watching via FSEvents, and multi-project vibespace layout.

## Architecture

### Tree View

Each project in the vibespace is a collapsible section in the Files tab. The tree is loaded via a worker process that lists directory structure from the project root. Tree loading has a **45-second timeout**.

Directories are lazily loaded: children fetched only on first expansion. Already-loaded children preserved across refreshes via a merge strategy that retains loaded subtrees.

### Multi-Project Sidebar

- Each project appears as a collapsible section in Files and Git tabs.
- Expansion state tracked by project root path; pruned when project list changes.
- Focused project auto-expanded; terminal-only canvas mode starts all collapsed.
- Header actions (refresh, create file, create folder) target the focused project (or first project if none focused).

### Selection Model

- Selecting a file sets `selectedFileURL` and `selectedFolderURL` (parent directory), issues a preview open request.
- Selecting a directory updates `selectedFolderURL`, clears `selectedFileURL`.
- Selected folder defaults to project root when no folder is selected.

### Open Actions

| Action | Behavior |
|--------|----------|
| Single click | Preview (transient open) |
| Open in tab | Persistent editor tab |
| Open in new window | Detached editor window |
| Open in horizontal split | Split pane |
| Open in vertical split | Split pane |
| Open in System (local) | Pass the original file or directory URL to the macOS workspace |
| Open in System (remote) | Delegate a protected temporary-copy transfer and system launch to the app-wide remote-transfer coordinator |
| Download… (remote) | Select a local destination and delegate transactional download to the app-wide remote-transfer coordinator |
| Reveal in Finder | Local files/directories only; omitted for SSH rows |

Directories support selection/expansion plus the applicable context actions above.

## Data Flow

### Search

- Case-insensitive substring match on file/folder name.
- Debounced at **180 milliseconds**.
- Filtering runs on a background thread.
- Directories appear if they match or contain matching descendants; children pruned to matching items only.
- Expansion disabled during active search.

### Create, Rename, Delete

- **Create** — default names: "untitled" (file), "New Folder" (folder). Targets the selected folder or project root; a stale selected folder falls back to its nearest existing project ancestor. Enters inline rename mode immediately.
- **Rename** — inline editing state. Committed via worker. On success: selections updated, rename event published (consumed by open editors), tree refreshed. Empty/whitespace names rejected silently.
- **Delete** — the AppKit unified explorer, SwiftUI explorer, and Shelf Files sidebar each retain the exact item or path whose context menu initiated deletion and construct the shared `ExplorerDeleteConfirmation` from that immutable target, never by re-reading mutable current selection. The model resolves the exact local or remote item name and full path once, then supplies the title `Delete “name”?`, a permanent-deletion warning paragraph that repeats the exact name and states deletion cannot be undone, a following separate paragraph containing the localized `Path:` block and exact full local or remote path, and the destructive button label `Delete`. All three surfaces use the same confirmation content and behavior. Full-path disclosure is intentional because the confirmation is presented locally to help the user disambiguate same-named destructive targets. Confirmation invokes the appropriate worker-backed filesystem deletion only for the retained target; cancellation only dismisses the dialog and invokes no deletion. After confirmed filesystem success, both local `FolderExplorerViewModel` and legacy/enhanced `RemoteFolderExplorer` emit `ExplorerDeletionEvent(url:isDirectory:)`; they emit nothing on cancellation or failure. `ProjectSession` and `RemoteProjectSession` forward that typed event. `VibeSpaceCanvasFileOpenUseCase` closes matching tabs in every detailed editor group and delegates docked/floating cleanup to `DockedFileViewerCoordinator`. Matching is exact for files and exact-plus-path-component descendants for directories. `EditorGroupStore.closeFileTabs` calls `closeTab(..., discardUnsavedChanges: true)`, supplying no writer and discarding the buffer so close flushing or autosave cannot recreate the deleted path. Selections are cleared and the affected parent is refreshed after success.

### Expand and Collapse

Toggling expansion adds/removes from expanded set. Collapsing a directory also collapses all expanded descendants. Expansion disabled during search.

## State Management

### Directory Watching

`DirectoryWatcher` backed by **FSEvents** for local file systems; polling watcher for remote.

Remote projects default to the legacy root-only names snapshot. When **Enhanced remote file explorer (Beta)** is enabled before session construction, the poller takes immediate metadata snapshots for the root and expanded directories on a two-second cadence. Remote mutations and watcher callbacks then use the same targeted parent-directory refresh policy; manual refresh reconciles every expanded directory. The setting is per-device, defaults off, and requires reopening remote projects.

Watched paths: project root + all currently expanded directories. Synchronized on expand/collapse and after tree load. Cap: **256 simultaneously watched paths** (shallower directories prioritized by depth, then alphabetically).

`DirectoryWatcher` produces structured `Event` objects containing:
- `kind`: enum — `modified`, `created`, `removed`, `renamed`, `rootChanged`, `unknown`
- `isDirectory`: Bool flag
- `rawFlags`: raw FSEvent flags for debugging

Callbacks: `onEvent` (structured events for targeted refresh), `onChange` (legacy path-based callback).

Change detection debounced by **150 milliseconds**. Multiple changes batched. Refresh strategy:

- Root directory changed → full tree refresh.
- Expanded subdirectory changed → only that directory's children reloaded.
- Neither → full tree refresh as fallback.

File system change events also published for other consumers (e.g., open editors).

If a refresh is in flight when another is requested, the new request queued and executed after current completes. Manual triggers take priority over watcher triggers.

### Targeted Subtree Refresh

`watcherRefreshTargetDirectoryPaths()` resolves changed paths from watcher events to the minimal set of visible directories to refresh:

- Directory modified → refresh that directory if currently expanded/visible.
- File created/removed/renamed → refresh the parent directory.
- Root changed → refresh root.

Watcher-triggered refreshes use `showLoadingState: false` to avoid loading spinners.

### Tree Mutation Tracking

- `treeMutationRevision` (Int) — incremented on each tree-modifying operation.
- `changedDirectoryIDs` (Set\<String\>) — accumulates directory IDs with pending changes.
- `consumePendingTreeMutationRevision()` — returns and clears pending revision, preventing redundant reloads when revision hasn't changed.
- `reloadChangedDirectoryNodes()` replaces `reloadExpandedNodes()` — only reloads NSOutlineView items whose directory IDs appear in `changedDirectoryIDs`.

### Refresh Coordination

- Root loads, watcher updates, lazy child loads, and mutation refreshes use the same per-directory refresh coordinator.
- Only one `listTree` request per directory can be in flight. Additional requests coalesce into one follow-up pass, and their callers wait for that pass.
- A tree-session identifier prevents responses from a previous project/root session from applying after the root changes.
- Watcher paths received while Files is inactive or the initial root load is incomplete are retained. Returning to Files, or completing the initial load, replays those paths.
- Create refreshes and expands the affected parent before setting selection and inline rename state. Rename and delete refresh only their affected parent directories. Existing local move and copy operations continue to refresh their source and destination parents.
- Successful directory snapshots reconcile selection and rename paths inside that directory. Missing items are cleared, and a removed selected folder falls back to its nearest surviving ancestor.

### Outline Reconciliation

- Selection and rename-only SwiftUI updates do not recursively walk the node cache.
- Root insertions/removals use `NSOutlineView` incremental operations. Surviving root rows reload only when their metadata changed and never recursively reload unchanged children.
- Targeted directory mutations reload only the changed parent node with children.
- Node-cache entries absent from the current model are pruned during tree reconciliation.
- If the selected model ID has no cached node or visible row, native outline selection is cleared so keyboard actions cannot target an adjacent row selected implicitly by AppKit.

### Disclosure vs Expansion Toggle

- `requestDisclosureToggle` — triggered by clicking the disclosure arrow; expands/collapses without changing selection.
- `requestExpansionToggle` — triggered by clicking the row; selects the item and toggles expansion.

### Source Control Watcher Filtering

The vibespace-level source control watcher filters observed paths before queueing refresh:

- Configured generated directories skipped.
- Internal `.git` churn (`.git/index`, object storage, logs) skipped.
- User-visible ref changes allowed: `.git/HEAD`, `FETCH_HEAD`, `ORIG_HEAD`, `packed-refs`, `refs/...`.

### External System Open and Download

The shared row action model dispatches by project capability. Local Open in System passes the selected file or folder's original URL to `VibeSpaceInteractionService`, which propagates the `NSWorkspace.open` Boolean; a false result uses the explorer's existing alert. Local rows retain Reveal in Finder. SSH-backed rows never invoke Finder. They expose Open in System and Download… and forward an immutable project identifier plus remote path to the app-wide `RemoteTransferCoordinator`.

That coordinator owns one user-facing slot shared by explorer file/folder rows and active project roots. It publishes preparing, transferring, cancelling, publishing, completed, and failed states to the remote overlay. Cancellation changes state immediately but deliberately keeps `operationTask` and the slot until structured cancellation terminates SFTP and removes staging. Before destination publication, the transfer service synchronously awaits a MainActor acknowledgment that `.publishing` has been installed, then performs a second `Task` cancellation check immediately before replace/move. Cancel is shown only while preparing or transferring, never while cancelling or publishing. A cancellation that arrives after the final check can coincide with the atomic replace/move boundary and may not prevent publication; this is the residual atomic-boundary semantics. Remote failures remain in the overlay until the user dismisses them; they do not route through the local/editor alert.

The explorer does not construct temporary paths or publish destinations itself. Remote Open in System receives a retained owner-only temporary snapshot URL only after verified transfer success; a false workspace-open result removes that newly created snapshot and becomes a failed overlay state. Download… presents destination selection and leaves hidden-sibling publication to F034's streaming service. It reports manifest/item/byte progress but does not present a size-confirmation prompt. `AppDiagnostics` records remote transfer lifecycle and newly relevant diagnostics, and diagnostics export sanitizes path-like strings found in event metadata. Comprehensive observability for every local file operation is not implemented.

This coordinator does not serialize editor-triggered remote HTML Open in System. F009 captures the editor buffer/provider and uses the separate app-level `ExternalFileOpenService`, editor busy state, and existing editor alert without the global overlay or dedicated bulk-transfer SFTP channel. Thus only one coordinator-backed explorer/root transfer runs at a time; the editor open path is independent.

Native drag recognition and drag/drop transfer remain local-only. SSH rows do not create drag payloads or accept remote drag/drop; Download… is the explicit supported copy-out path.

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| Tree load (list directory) | 45 s | Load project directory structure |
| Rename | — | Rename file/folder via worker |
| Delete | — | Delete file/folder via worker |
| Move/Copy (local drag-and-drop only) | 20 s per item | Transfer local files between directories; remote drag/drop is unsupported |

## Dependencies (frameworks, libraries)

- `FolderExplorerViewModel` / `RemoteFolderExplorer` — emit `ExplorerDeletionEvent` only after successful local/remote removal
- `ProjectSession` / `RemoteProjectSession` — forward typed deletion events
- `EditorGroupStore` / `ContentViewerStore` — close exact/descendant detailed tabs with `discardUnsavedChanges`
- `DockedFileViewerCoordinator` — closes matching floating previews and docked groups
- `ExplorerDeleteConfirmation` — immutable exact-target confirmation content shared by AppKit unified explorer, SwiftUI explorer, and Shelf Files sidebar
- `AppShellStore` — sidebar visibility state
- `DirectoryWatcher` — FSEvents-backed file system monitoring
- `PaneWorkerClient` — file operations

## Platform Considerations

- FSEvents for local file system watching (macOS kernel-level).
- Polling watcher for remote (SSH-backed) file systems.
- `AppKitTreeView` for native tree rendering with drag-and-drop support.

## Performance Constraints

- Tree load timeout: 45 seconds.
- Search debounce: 180 milliseconds.
- Directory watcher debounce: 300 milliseconds.
- Watcher path cap: 256 simultaneous paths.
- At most one active directory listing per directory, plus one coalesced follow-up pass.
- Drag-and-drop transfer timeout: 20 seconds per item.
- The multi-project sidebar uses lazy project sections without requiring the UI test to enumerate every row. Its repeated-scroll regression measures liveness by issuing ⌘T after six bidirectional scroll pairs and waiting for Terminal Board, not by reading scroll offset.

## Static Regression Source

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. The typed deletion path is statically present in `FolderExplorerTypes.swift`, local `FolderExplorerViewModelActions.swift`, remote `RemoteFolderExplorer.swift`, both project-session forwarders, `VibeSpaceCanvasFileOpenUseCase.swift`, `ContentViewerStore.swift`, `EditorGroupStore.swift`, and `DockedFileViewerCoordinator.swift`. `FolderExplorerViewModelTests` directly exercises only shared confirmation formatting; test-source search found no direct invocation of `ExplorerDeletionEvent`, `closeFileTabs`, `handleDeletion`, or `discardUnsavedChanges`. Exact/descendant detailed+docked+floating closure and no-recreation therefore remain production-source inspection. `VibeSpaceAndNavigationUITests.testFilesSidebarRemainsResponsiveAfterRepeatedProjectScrolling` sends ⌘T after six down/up scroll pairs and waits for `vibespace.terminal-only`; it does not assert all-project enumeration or scroll offset.

## Change History

- 2026-10-23: Final reconciliation inventories every production source in the typed successful-deletion pipeline and confirms no direct deletion-event/discard-close test source; validation is build/test-build only.
- 2026-10-23: Added the typed post-success deletion pipeline and discard-close/autosave-resurrection prevention; named the F024-R20/S54 user UI test exactly and narrowed new behavior to production-source-only verification.
- 2026-10-23: Added the F024-R20/S54 liveness contract and narrowed delete evidence to direct shared-model formatting; validation reached build/test-build only and no test pass is claimed.
- 2026-10-20: Expanded exact-target confirmation requirements across AppKit, SwiftUI, and Shelf; static evidence remains limited to direct shared-model formatting and does not prove per-surface target retention, Cancel, or delete dispatch.
- 2026-10-20: Reconciled synchronous publication acknowledgment/final cancellation checking and its atomic boundary; marked diagnostics scope partial, documented path-like event-metadata sanitization, and recorded manifest progress without a size-confirmation prompt.
