# Shelf — Technical Design

## Overview

Shelf is a lightweight persistence and navigation feature for standalone files. It stores a pinned list of file paths in `shelf-state.json`, renders that list as a section at the top of the Files sidebar, and opens Shelf files in the shared content viewer rather than owning a dedicated editor surface.

## Architecture

### Core Components

- `ShelfStore` — `ObservableObject` that owns pinned file paths, selected Shelf file, persistence, and one-time load behavior.
- `ShelfSidebarSectionView` — reusable SwiftUI section that renders the Shelf header and file rows.
- `VibeSpaceSidebarFilesPane` — hosts the Shelf section above project explorer sections.
- `ContentViewShelfActions` — routes welcome actions, external file opens, and Shelf row interaction into `ShelfStore`, the vibespace shell, and the content viewer.
- `ContentViewerStore` — opens Shelf files in the shared editor/preview surface.

### Entry Points

- Welcome surface: Shelf utility action reveals the Files sidebar and opens the selected Shelf file.
- External open / drag-and-drop: file URLs are added to Shelf, then opened in the content viewer when a vibespace is available.
- Files sidebar: Shelf rows can be opened, removed, or cleared in place.
- Shelf header: disclosure-based expand/collapse control, with destructive clear action in the section context menu.

### File List Behavior

- Files are prepended in most-recent-first order.
- Duplicates are deduplicated with newest position winning.
- Directory URLs are silently filtered out.
- Missing files render with a warning icon and reduced opacity.
- Shelf rows show only the file name in the list; the full standardized path is exposed through hover help and context-menu copy-path.

## Data Flow

### Adding Files

1. `ShelfStore.addFiles(_:)` receives one or more file URLs.
2. Directory URLs are filtered out.
3. Remaining URLs are normalized and prepended to the list.
4. Duplicates are removed.
5. The first added file becomes the selected Shelf file.
6. State is persisted to `shelf-state.json`.

### External File Open

1. The app receives file URLs from Finder, drag-and-drop, or external open forwarding.
2. `ContentView.openFilesInShelf` delegates to `ShelfStore.addFiles(_:)`.
3. If an active vibespace exists, or a fallback vibespace can be selected, the Files sidebar is revealed and the selected Shelf file is opened in the main content viewer.
4. If no vibespace exists yet, the files remain persisted in Shelf until a vibespace is available.

### Selection Sync

- `ShelfStore.selectFile(at:)` updates the stored selection when the user clicks a Shelf row.
- `ContentView.openShelfFile(at:)` opens the selected file in the shared content viewer and switches the vibespace canvas into detailed mode.
- `ShelfStore.syncSelection(from:)` updates Shelf selection when the active content viewer file changes to another Shelf file.
- `ShelfStore.ensureSelectionIfNeeded()` selects the first available Shelf file when Shelf is revealed without a valid selection.

## API / Command Contracts

### ShelfStore API

| Method | Behavior |
|---|---|
| `addFiles([URL]) -> URL?` | Normalize, deduplicate, prepend, select first, persist, and return selected file |
| `selectFile(at: String) -> URL?` | Update selection if the path belongs to Shelf and return the resolved URL |
| `removeFile(at: String) -> String?` | Remove file, update selection if needed, persist, and return the next selected path |
| `clear()` | Remove all Shelf entries, clear selection, and delete `shelf-state.json` |
| `ensureSelectionIfNeeded() -> String?` | Select the first Shelf file if selection is missing or invalid |
| `syncSelection(from: URL?)` | Persist selection changes when the active content viewer file belongs to Shelf |
| `loadIfNeeded()` | Load from `shelf-state.json` once per session |
| `resetForFreshStart()` | Clear paths, selection, and `didLoad` without writing persistence |

### ContentView Shelf Actions

| Method | Behavior |
|---|---|
| `openFilesInShelf(_:makeVisible:)` | Add files to Shelf, optionally reveal the Files sidebar, and open the selected file |
| `openShelfFile(at:makeVisible:)` | Select a Shelf file, optionally reveal the Files sidebar, switch to detailed canvas mode, and open the file |
| `openShelfFileInFinder(at:)` | Reveal a Shelf file in Finder, or open its parent directory when the file is missing |
| `openShelfDirectoryInTerminal(at:)` | Open the Shelf file's parent directory in the focused or fallback project terminal |
| `renameShelfFile(at:to:)` | Rename a Shelf file on disk, update persisted Shelf state, and retarget open editor tabs |
| `deleteShelfFile(at:)` | Delete a Shelf file on disk, close matching editor tabs, and remove it from Shelf |
| `removeShelfFile(at:)` | Remove a Shelf entry and reopen the next Shelf selection when needed |
| `clearShelf()` | Clear Shelf state |

## State Management

### Persistence

- File list and selected file path are serialized to `shelf-state.json` in the app persistence directory.
- Persistence writes happen on add, selection change, remove, and clear.
- On load, paths are normalized and deduplicated.
- If the persisted selected path is no longer present, the first file becomes selected.
- `loadIfNeeded()` is guarded by `didLoad` and runs only once per session.

### UI Visibility

- Shelf does not have its own shell-level visibility flag.
- The Shelf section is shown only when `ShelfStore.filePaths` is non-empty.
- Revealing Shelf means revealing the Files sidebar, not navigating to a separate surface.

## Dependencies

- `SwiftUI` — sidebar section and row rendering
- `AppKit` — file existence checks and app-level file-open integration
- `ContentViewerStore` — shared file preview and editing

## Platform Considerations

- macOS-only file URL handling is normalized through `URL.standardizedFileURL`.
- Missing files are tolerated and shown in the UI without crashing or auto-removing the entry.

## Performance Constraints

- Shelf section should render within 100ms for up to 50 entries.
- Persistence writes remain atomic to avoid partial-state corruption.

## Migration / Rollout Notes

- This design replaces the earlier standalone Shelf surface with a Files-sidebar section.
- External open and drag-and-drop plumbing remains routed through `ShelfStore` so "Open with CrispyVibes" continues to work.
