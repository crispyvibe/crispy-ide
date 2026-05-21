# Terminal Board — Technical Design

## Overview

Terminal Board is a terminal-only canvas mode rendered by `VibeSpaceTerminalOnlyView`. It replaces the editor pane with a column-based grid of terminal tiles, each hosting an independent terminal session. The board is driven by `VibeSpaceTerminalBoardStore`, which owns tile lifecycle, layout mutations, project synchronization, and persistence.

The store models one vibespace board as multiple `VibeSpaceTerminalBoardSurface` values. The primary surface is embedded in the vibespace shell. Detached surfaces are rendered in auxiliary board windows and share the same vibespace runtime, terminal view models, board store, and persistence file.

## Architecture

### Component Hierarchy

```
VibeSpaceTerminalOnlyView
├── VibeSpaceTerminalBoardStore (ObservableObject, state owner)
│   ├── VibeSpaceTerminalBoardState (Codable multi-surface model, single source of truth)
│   ├── VibeSpaceTerminalBoardLayout (Codable per-surface model)
│   ├── BoardSnapshotProviders (captures external state at persist time)
│   ├── VibeSpaceTerminalBoardMetrics (frame computation)
│   └── VibeSpaceTerminalBoardStandaloneRegistry (standalone VMs)
├── DetachedTerminalBoardWindowContent (auxiliary board window surface)
│   └── TerminalSpotlightCoordinator (window-local spotlight owner)
├── BoardInlinePickerOverlayController (shared inline-trigger popup owner)
│   └── BoardInlinePickerOverlayView (shared two-pane popup renderer)
├── BoardInteractionController (state machine for pointer interactions)
│   ├── BoardHitTesting (pointer target resolution)
│   └── BoardCursorRectsView (NSViewRepresentable, AppKit cursor rects)
├── BoardSpatialNavigation (keyboard tile navigation)
├── Board Header (toolbar chrome)
├── Tile Cards (VibeSpaceTerminalBoardTileCard)
│   └── TerminalSessionHostView (terminal surface)
└── Minimized Tab Bar (horizontal scroll strip)
```

### State Ownership Invariants

`VibeSpaceTerminalBoardStore` is the single source of truth for board state. The state ownership model enforces:

- `boardState` is `@Published private(set)` — views observe; no external code writes directly.
- Every mutation flows through `mutate(_:)`, which applies a transform to a copy of the state, normalizes the result, publishes if changed, and persists. `mutateLive(_:)` is the live-drag variant that publishes without persisting; callers invoke `commit()` on interaction end.
- `updateVibeSpaceID(_:)` is a vibespace rebind, not a mutation — it swaps the store to point at a different vibespace's state loaded from persistence.
- Detached board windows share the same store instance and re-render via `@Published` propagation; no cross-window notification channel is used.
- `LayoutPersistenceService.setTerminalBoardState(_:for:)` is a pure sink: dedupe by equality, assign to in-memory cache, write to disk. It performs no normalization of board state and no external-state injection.
- External state (browser session snapshots, current browser URLs) is captured via `BoardSnapshotProviders` inside the store's `persist()` method immediately before the state is handed to the persistence layer. Providers are owned by the feature, not by the persistence layer.

### Surface And Layout Model

`VibeSpaceTerminalBoardState` owns:

- `primarySurfaceID`: stable identifier for the vibespace shell board.
- `surfaces`: primary and detached `VibeSpaceTerminalBoardSurface` entries.
- per-surface layout, title, kind, and optional window placement.

Each board window renders exactly one surface. Surface-targeted APIs must pass `surfaceID`; defaulting to the primary surface is only valid for legacy primary-window flows or non-board fallback paths.

The grid is a list of `VibeSpaceTerminalBoardColumn`, each containing an ordered list of tiles.

- Max columns: 4, max rows per column: 4, max total tiles: 16.
- Each column has a `widthWeight`; all column weights normalize to 1.0.
- Each tile has a `heightWeight`; all tile weights within a column normalize to 1.0.
- Minimum weight floor: 0.01 (prevents zero-size tiles).
- Normalization runs on every mutation and before persistence: deduplicates tile IDs, enforces max limits, re-normalizes weights.

### Tile Types

| Type | `projectPath` | `terminalTabID` | `isVibeCast` | Notes |
|------|--------------|-----------------|-------------|-------|
| Project | set | set | false | Bound to project's `TerminalViewModel` |
| Standalone | nil | set | false | Uses vibespace-scoped standalone `TerminalViewModel`; header shows "VibeSpace" |
| VibeCast | — | — | true | Non-terminal; max one per board |
| Unresolved | — | — | false | Placeholder when backing session is missing |

### Metrics Computation

`VibeSpaceTerminalBoardMetrics` distributes available space:
- Width across columns proportionally by `widthWeight`.
- Height within each column proportionally by tile `heightWeight`.
- Configurable spacing (default 8pt) between tiles; padding (default 6pt) at board edges.

## Data Flow

### Tile Creation Flow

1. User opens create sheet → selects project (or "VibeSpace") + working directory.
2. The caller supplies the initiating `surfaceID`; `addTile` checks that surface's 16-tile max → resolves terminal scope → creates tab in appropriate `TerminalViewModel`.
3. Deduplication: if tile already exists for same identity (scope + tab ID), activates existing tile.
4. `insertNewTile` placement strategy:
   - Empty board → single column with new tile.
   - One tile → add second column.
   - One column with ≥2 tiles → add second column.
   - Otherwise → insert below active tile in same column (if room).
   - Active column full → new column right of active.
   - Last resort → append to first column with room.
5. Activate tile → focus terminal → persist layout.

All board-originated persistent terminal creation flows must call `VibeSpaceTerminalBoardStore.addTile(..., surfaceID:)` rather than creating a raw `TerminalViewModel` tab. This includes:

- board header `New Terminal`
- tile header/context-menu `Split Terminal`
- terminal surface context-menu split
- terminal spotlight split
- temporary spotlight split-to-persistent

Raw `TerminalViewModel.createTab` remains valid for detailed-mode/non-board terminal panes where no board surface owns the action.

### Detached Window Spotlight Flow

The primary vibespace window and each detached board window own separate `TerminalSpotlightCoordinator` instances:

1. Primary board actions route through the vibespace shell's spotlight coordinator.
2. Detached board actions route through `DetachedTerminalBoardWindowContent` and its local coordinator.
3. Terminal, file, browser, ACP, VibeCast, and temporary-terminal spotlight presentations stay in the originating board window.
4. Split-to-persistent actions launched from detached spotlight call `VibeSpaceTerminalBoardStore.addTile(..., surfaceID:)` for the detached surface.

This keeps focus, temporary previews, and persistent terminal creation aligned with the window where the user initiated the action.

### Window Title Bar Toolbars

The primary vibespace window title bar groups toolbar controls into two pills, separated by macOS's native toolbar item gap:

- **Group 1 (content creation):** VibeCast, Agent (ACP), Browser.
- **Group 2 (vibespace view + management):** detail/terminal canvas toggle, project rail-position menu (detailed mode only), remote connection status (when the vibespace has remote projects), Add Project, Close VibeSpace.

Each group is rendered as a single `ToolbarItem` whose content is an `HStack` of buttons so the group renders as one visual pill capsule. Buttons that should be hidden for the current state (non-applicable rail position, no remote projects) are omitted rather than rendered disabled, so the pill never contains empty slots.

Detached board windows attach their own `NSToolbar` (style `.unifiedCompact`, `showsBaselineSeparator = false`) and expose a surface-scoped Agent and Browser action as `.primaryAction` toolbar items. Both target the detached window's `surfaceID` and respect the 16-tile cap. The Agent button is only shown when the detached window has an ACP factory wired (it is wired when constructed from `ContentViewProjectCanvas` with the vibespace's `contentViewerStore` + `acpVibeSpaceSessionService`).

### Tile Transfer Flow

Visible tile headers and minimized tile headers expose board-window transfer commands through their context menus:

1. `VibeSpaceTerminalOnlyView` asks the shell for transfer targets for the current `surfaceID`.
2. The shell lists the primary board window when the source is detached, then open detached board windows for the same vibespace in AppKit window order, excluding the source surface.
3. `Send to New Board Window` detaches the selected tile with `includeMinimized` semantics, creates a new detached surface containing only that tile, opens the detached window, then closes the source detached window if it became empty.
4. `Send to Board Window` calls `VibeSpaceTerminalBoardStore.moveTile(tileID, fromSurface:, toSurface:)`, focuses the target detached window when applicable, and closes an emptied detached source surface.

Detached target labels and NSWindow titles are derived from current surface content. Empty or generic persisted titles must not be shown as identical placeholders; when a surface contains multiple panes, the label includes the active/first tile title and pane count.

The transfer path moves one `VibeSpaceTerminalBoardTile` value. It must not copy tiles, bulk-move sibling tiles, or leave blank shells on the source surface. Because `VibeSpaceTerminalBoardLayout.removeTile(withID:)` checks minimized tiles before visible grid tiles, the same transfer path supports visible tiles and minimized tabs.

Transfer preserves the tile's backing content/session identity but not its source-surface placement. The source surface's column, row, minimized index, and flattened Spotlight order position are discarded as placement hints when attaching to the destination. The destination surface inserts the tile using destination-owned placement rules:

- New detached surface: create a one-tile layout containing the moved tile.
- Existing surface with visible capacity: insert via the same placement strategy used for new tiles, preferably near the destination active tile when available.
- Existing surface from minimized transfer: restore into visible layout when capacity allows, otherwise keep it in the destination minimized strip at the end.
- Existing surface at visible capacity: reject visible insertion with user feedback or place the tile in the destination minimized strip, according to the command's explicit affordance.

After transfer, the active board surface's Spotlight carousel order is derived from the destination layout's updated tile order. The source surface order is normalized without the moved tile.

### Project Synchronization (Three-Phase Reconciler)

Triggered by subscribing to each project's `TerminalViewModel.tabsPublisher` and the standalone tabs publisher. `reconcileTerminalTiles()` runs all three phases inside a single `mutate { ... }` block so the result is normalized and persisted atomically. Non-terminal tiles (browser, ACP, file, VibeCast) are invariant across reconciliation — the pure helpers in `TerminalTileReconciler` only read and update terminal tiles.

**Phase 1 — Reconcile tile project assignments (`reconcileProjectAssignments`):**
- Tile with valid `projectPath` → bind to project VM (match by tab ID, fall back to working directory match).
- Tile with stale `projectPath` (project removed) → clear path and terminalTabID, fall through to standalone matching.
- Tile with no `projectPath` → bind against standalone view model.

**Phase 2 — Sync tiles with current tabs (`VibeSpaceTerminalBoardLayoutSync.syncTiles`):**
- Build desired set of terminal identities (excluding hidden tabs).
- Remove stale minimized terminal tiles whose identity no longer exists.
- Remove stale grid terminal tiles whose identity no longer exists.
- Update terminal tiles whose working directory changed.
- Insert new tabs that have no tile into the primary surface only (up to 16-tile limit) without activating. Detached surfaces do not auto-adopt arbitrary new tabs; detached-window actions must create tiles through the explicit surface-targeted `addTile` flow.

**Phase 3 — Restore persisted terminal tiles (`restorePersistedTerminalTiles`):**
- For each terminal tile whose `terminalTabID` is not yet a known live tab, instruct the owning view model to create a tab and reassign the tile to the created tab's id.

Reentrancy guard: `isReconciling` prevents recursive reconciler calls. After each reconcile, `objectWillChange.send()` is invoked so views that depend on store lookup tables (`projectsByPath`, `tabsByProjectPathAndID`, etc.) for tile context resolution re-render even when `boardState` itself is unchanged.

### Hidden Terminals

`hiddenTerminalIDsByProjectPath: [String: Set<UUID>]` specifies tabs visible in the editor pane. Hidden tabs are excluded from the desired set during sync, so they don't generate board tiles.

### Tile Shortcut Context

Board tile shortcut menus resolve shortcuts per tile, not from the globally focused project. The tile command menu combines:

- vibespace-scoped shortcut rows for the active vibespace
- project-scoped shortcut rows for the tile's owning project when `projectPath` is set

This prevents one board tile from showing shortcut rows for a different focused project.

### Board Inline Trigger Overlay

Board tiles do not render large inline-trigger pickers inside the tile body. Instead:

- `VibeSpaceTerminalOnlyView` owns one `BoardInlinePickerOverlayController`
- board tile surfaces inject picker state into that controller
- the board root renders one centered `BoardInlinePickerOverlayView`

This prevents small or dense board tiles from clipping the picker, avoids tile relayout while the popup is open, and keeps keyboard ownership with the originating input surface.

The shared popup is intentionally two-pane:

- left pane: file and folder results
- right pane: generate action, matching shortcuts, and `Manage Shortcuts…` when available

Dismissal behavior is source-aware: the close button and keyboard cancel both route back through the originating tile surface so that focus and input state are restored correctly.

## API / Command Contracts

### Tile Operations

| Operation | Trigger | Behavior |
|-----------|---------|----------|
| Add | "New Terminal" button / create sheet | Insert tile via placement strategy; alert if at 16-tile max |
| Remove | Close button / context menu | Close underlying terminal tab; remove column if empty; fallback active tile |
| Split | Split button, terminal context menu, or spotlight split | `addTile` on the initiating surface with same project path + working directory |
| Run Shortcut | Tile command menu | Load vibespace + owning-project shortcut rows for that tile, then dispatch via the same launch behavior rules as other terminal surfaces |
| Manage Shortcuts | Tile command menu | Open vibespace settings to `Shortcuts` |
| Minimize | Minimize button | Move to minimized tray; session stays alive; doesn't count against grid limit |
| Restore | Double-tap / drag from minimized bar | Blocked if grid at 16; insert via standard strategy |
| Move | Drag tile header | Drop intents: Insert Left/Right/Above/Below, Swap |
| Send to New Board Window | Visible/minimized tile context menu | Detach exactly the selected tile, create a new detached surface, open it in a board window |
| Send to Board Window | Visible/minimized tile context menu | Move exactly the selected tile to an existing board surface for the same vibespace |
| Inline Trigger Popup | Typed trigger from terminal/ACP/VibeCast board input | Publish one shared board popup, route confirm/cancel back to originating surface |

### Drop Intent Resolution

- Insert Left/Right: new column adjacent to target. If at 4-column max, insert into target's column instead.
- Insert Above/Below: insert in same column. If at 4-row max, create new column if possible, else first column with space.
- Swap: exchange positions of dragged and target tiles.

### Resize Operations

- Column resize: drag vertical divider. Redistributes weight pair of two adjacent columns. Min weight: 0.12. Live updates; committed on drag end.
- Row resize: drag horizontal divider within column. Same weight-pair redistribution and 0.12 min clamping.

### Notifications Consumed

| Notification | Action |
|-------------|--------|
| `.focusNextProjectTerminal` | Navigate down |
| `.focusPreviousProjectTerminal` | Navigate up |
| `.boardNavigateRight` | Navigate right |
| `.boardNavigateLeft` | Navigate left |
| `.copyInTerminal` | Copy from active tile's terminal |
| `.pasteInTerminal` | Paste to focused tile (or active tile fallback) |
| `.terminalFocusedSessionDidChange` | Update active tile to match focused terminal |

## State Management

### Interaction State Machine (`BoardInteractionController`)

```
┌──────┐  drag header   ┌─────────────┐
│ Idle │───────────────→│ Moving Tile  │
│      │  drag min tab  ├─────────────┤
│      │───────────────→│ Moving Min.  │
│      │  drag col div  ├─────────────┤
│      │───────────────→│ Resizing Col │
│      │  drag row div  ├─────────────┤
│      │───────────────→│ Resizing Row │
└──────┘                └─────────────┘
         (all return to Idle on drag end/cancel)
```

Navigation is suppressed while interaction controller is in a non-idle state.

The board inline-trigger overlay is intentionally outside this drag/resize state machine. It is view-state driven by `BoardInlinePickerOverlayController` and should not change board geometry or interaction metrics when shown or dismissed.

### Hit Testing Priority (`BoardHitTesting`)

1. Column dividers (16pt thickness)
2. Row dividers (16pt thickness within column bounds)
3. Tile headers (top ~32pt of tile frame)
4. Tile bodies
5. Empty space

### Standalone Terminal Registry

`VibeSpaceTerminalBoardStandaloneRegistry` maintains `[VibeSpaceID: TerminalViewModel]`:
- Lazily created per vibespace on first access.
- Shell resolution from app's stored terminal shell preference.
- Reconfigured on vibespace ID change.
- Released on vibespace deallocation; `shutdownAll()` for full cleanup.

### Initial Seeding

On view appear, if board is empty, `seedInitialTileIfNeeded` creates a single tile for the first project. Skipped if any project already has hidden terminal tabs.

## Dependencies

- `GhosttyKit` / `SwiftTerm` — terminal rendering engines (via `TerminalSessionHostView`)
- `TerminalViewModel` — tab/session lifecycle per project scope
- `LayoutPersistenceService` — vibespace-scoped JSON persistence
- `AppPersistenceDataStore` — per-vibespace file I/O
- `TerminalFocusCoordinator` — single-focus enforcement across surfaces

## Platform Considerations

- `BoardCursorRectsView` is an `NSViewRepresentable` wrapping AppKit cursor rect APIs. Column dividers → left-right resize cursor; row dividers → up-down resize cursor. Cursor rects invalidated on layout change.
- Named coordinate space `"terminalBoard"` used for all gesture tracking.
- Drag proxy follows pointer as a floating card showing project title and working directory.

## Performance Constraints

- Tile add/remove/move operations: < 100ms.
- Layout persistence writes: < 200ms.
- Layout normalization runs on every mutation — must remain O(n) where n = tile count (max 16).
- No orphaned processes after tile removal.

## Migration / Rollout Notes

### Legacy Layout Format

The layout decoder supports a legacy format where tiles were stored as a flat array with explicit `column` and `row` integer indices. On decode, legacy tiles are grouped by column index, sorted by row, and converted to the current column-based structure.

### Layout Orientation

`VibeSpaceTerminalOnlyLayoutOrientation` supports Vertical (columns side-by-side, default) and Horizontal. Persisted per-vibespace alongside board layout, rail position, and canvas mode.

### Detached Surface Restoration

Detached board surfaces are persisted as part of `VibeSpaceTerminalBoardState`. On vibespace hydration, open detached surfaces are reopened as auxiliary board windows with their saved `VibeSpaceTerminalBoardWindowPlacement` when present. Placement restoration is best-effort and does not merge surfaces into the primary board when the display topology changes.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-04 | Centralized board state in `VibeSpaceTerminalBoardStore` with a single `mutate` boundary; persistence layer now a pure sink. External state captured via `BoardSnapshotProviders` at persist time. Removed the `boardLayoutDidChange` self-observing notification loop. Added two-pill toolbar grouping on primary window and title-bar toolbar (Agent + Browser) on detached board windows. | — |
| 2026-04-27 | Clarified destination-owned placement for tile transfer between board surfaces. | — |
| 2026-04-26 | Documented ready multi-window board architecture: detached surfaces, local spotlight, surface-targeted terminal creation, one-tile transfer, target labels, and best-effort placement restore. | Codex |
