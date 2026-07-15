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

Directories respond only to select and toggle-expansion.

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
- **Delete** — via worker. Selections pointing to deleted item or descendants cleared. Tree refreshed.

### Expand and Collapse

Toggling expansion adds/removes from expanded set. Collapsing a directory also collapses all expanded descendants. Expansion disabled during search.

## State Management

### Directory Watching

`DirectoryWatcher` backed by **FSEvents** for local file systems; polling watcher for remote.

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
- Create refreshes and expands the affected parent before setting selection and inline rename state. Rename, delete, move, and copy refresh only their affected parent directories.
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

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| Tree load (list directory) | 45 s | Load project directory structure |
| Rename | — | Rename file/folder via worker |
| Delete | — | Delete file/folder via worker |
| Move/Copy (drag-and-drop) | 20 s per item | Transfer files between directories |

## Dependencies (frameworks, libraries)

- `FolderExplorerViewModel` — per-project file tree and git state
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
