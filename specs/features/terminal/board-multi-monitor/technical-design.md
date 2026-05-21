# Terminal Board Multi-Monitor — Technical Design

## Overview

Multi-monitor support is modeled as "one logical vibespace board → many board surfaces." The `VibeSpaceTerminalBoardState` owns multiple `VibeSpaceTerminalBoardSurface` instances (one primary, zero or more detached). A `VibeSpaceTerminalBoardDetachedWindowManager` manages NSWindow lifecycle for detached surfaces.

## Architecture

```
VibeSpaceTerminalBoardStore (single instance per vibespace)
    |
    +-- boardState: VibeSpaceTerminalBoardState
    |       +-- primarySurfaceID: UUID
    |       +-- surfaces: [VibeSpaceTerminalBoardSurface]
    |               +-- id, kind (.primary | .detached), layout, title, placement, isOpen
    |
    +-- VibeSpaceTerminalBoardDetachedWindowManager
            +-- windowsByID: [UUID: WindowRecord]
            +-- openWindow(...) -> UUID
            +-- closeWindows(for vibespaceID:)
            +-- surfaceID(vibespaceID:atScreenPoint:)
            +-- orderedSurfaceIDs(for:)
```

Each detached window hosts a `VibeSpaceTerminalOnlyView` bound to a specific `surfaceID`. All views share the same `VibeSpaceTerminalBoardStore` instance, so mutations propagate via `@Published boardState`.

## Data Flow

### Opening a detached window

1. User triggers "Send to New Board Window" on a tile.
2. `VibeSpaceTerminalBoardStore` creates a new `VibeSpaceTerminalBoardSurface` with `.detached` kind.
3. The tile is moved from the source surface layout to the new surface layout.
4. `VibeSpaceTerminalBoardDetachedWindowManager.openWindow(...)` creates an `NSWindow` with `NSHostingController` wrapping `VibeSpaceTerminalOnlyView(surfaceID: newSurface.id)`.
5. Window observers track move/resize for placement persistence.

### Tile transfer

1. Context menu action calls `onTileSendToBoardWindowRequested(tileID, targetSurfaceID, store, sourceSurfaceID)`.
2. Store removes the tile from source surface layout and inserts it into target surface layout via `mutate(_:)`.
3. If source surface is now empty and detached, `closeAfterTransfer(id:)` closes the window.

### Vibespace close

1. `WorkspaceCatalogStore` calls `shutdownProjects()`.
2. `VibeSpaceTerminalBoardDetachedWindowManager.closeWindows(for: vibespaceID)` tears down all detached windows.
3. Window observers are removed, `onUserClose` callbacks fire.

### Placement restoration

1. On vibespace open, `boardState.surfaces` is loaded from persistence.
2. For each detached surface with `isOpen == true`, a window is opened with the stored `placement`.
3. macOS positions the window at the stored frame; if the display is unavailable, the window appears on the primary display.

## API / Command Contracts

### VibeSpaceTerminalBoardDetachedWindowManager

| Method | Purpose |
|--------|---------|
| `openWindow(vibespaceID:surfaceID:title:placement:toolbarConfiguration:onUserClose:onPlacementChanged:content:)` | Creates and shows a detached NSWindow |
| `closeWindows(for:)` | Closes all detached windows for a vibespace |
| `closeAfterTransfer(id:)` | Closes a specific window after tile transfer empties it |
| `surfaceID(vibespaceID:atScreenPoint:excluding:)` | Hit-tests screen point to find target surface for drag |
| `orderedSurfaceIDs(for:)` | Returns surface IDs in front-to-back window order |
| `focusSurface(_:vibespaceID:)` | Brings a surface's window to front |
| `setTitle(_:forSurfaceID:vibespaceID:)` | Updates window title |
| `containsManagedWindow(_:)` | Checks if an NSWindow is managed by this registry |

### BoardWindowTransferContextMenuItems

SwiftUI view that renders "Send to New Board Window" and "Send to Board Window > [targets]" menu items.

### VibeSpaceTerminalBoardSurfaceTransferTarget

```swift
struct VibeSpaceTerminalBoardSurfaceTransferTarget: Identifiable, Equatable {
    let id: UUID      // surface ID
    let title: String // display label for the target window
}
```

## State Management

- `VibeSpaceTerminalBoardState` is the single source of truth, persisted via `LayoutPersistenceService`.
- All mutations go through `VibeSpaceTerminalBoardStore.mutate(_:)` which normalizes, publishes, and persists atomically.
- Detached windows share the store instance — SwiftUI re-renders via `@ObservedObject`.
- `BoardInteractionDelegateAdapter` accepts a `surfaceID` parameter so drag/drop operations target the correct surface.
- Window placement is captured on move/resize notifications and stored in the surface's `placement` field.

## Dependencies (frameworks, libraries)

- **AppKit**: `NSWindow`, `NSHostingController`, `NSToolbar`, `NSEvent` monitors for titlebar context menu.
- **SwiftUI**: `VibeSpaceTerminalOnlyView` as the hosted content.
- **Combine**: `AnyPublisher<Void, Never>` for toolbar state invalidation.
- **NotificationCenter**: `willCloseNotification`, `didMoveNotification`, `didResizeNotification` for window lifecycle.

## Platform Considerations

- macOS only. Uses `NSWindow` APIs for multi-window management.
- `NSScreen.deviceDescription` is used to capture display identity for placement restoration.
- Titlebar context menu uses `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)` with hit-testing against the titlebar region.
- `NSApp.orderedWindows` is used for front-to-back surface ordering and drag hit-testing.

## Performance Constraints

- Detached windows share the same `VibeSpaceTerminalBoardStore` — no state duplication.
- Terminal sessions are not duplicated; tiles reference the same `TerminalTab` instances.
- Window creation is lightweight (single `NSHostingController`).
- Placement persistence is debounced via move/resize notification coalescing on `RunLoop.main`.

## Migration / Rollout Notes

- `VibeSpaceTerminalBoardState` was extended from a single layout to a `surfaces` array. Existing persisted state with no surfaces array is migrated to a single primary surface on load.
- No breaking changes to the board store API — `surfaceID` parameters default to `primarySurfaceID` for backward compatibility.
