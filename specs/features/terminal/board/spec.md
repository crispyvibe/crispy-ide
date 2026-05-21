# Terminal Board — Spec

Status: implemented

## Overview

Terminal Board is a terminal-only canvas mode that replaces the editor pane with a resizable grid of terminal tiles. Each tile hosts an independent terminal session scoped to a project or standalone. The board supports up to 16 tiles (4×4), drag-and-drop repositioning, column/row resizing, tile minimization, spatial keyboard navigation, and board-level chrome.

Terminal Board can be presented as the primary vibespace board surface or as one or more detached board window surfaces. Each surface owns its visible layout, active tile, local spotlight presentation, and persistent terminal creation target.

## Dependencies

- F001 (Sessions & Tabs) — each tile is backed by a terminal tab/session
- F003 (Spotlight) — minimized tiles open in spotlight on tap; double-click tile body opens spotlight
- F011 (ACP) — ACP panes can appear as board tiles and participate in board-window transfer
- F012 (Browser) — browser panes can appear as board tiles and participate in board-window transfer
- F028 (VibeCast) — VibeCast can appear as a board tile and participate in board-window transfer
- F037 (Terminal Board Dock) — file and browser docked panes share board tile movement semantics
- VibeSpace lifecycle — board layout is persisted per vibespace

## Requirements

### F002-R01: Board Renders Independent Terminal Tiles

The terminal board MUST render each tile as an independent terminal session surface. Tile selection MUST be tracked by persisted active tile id.

### F002-R02: New Terminal Flow Supports Project and Directory Selection

The `New Terminal` create sheet MUST allow the user to choose a project root or `No Project (VibeSpace)` and discovered subfolders or an arbitrary folder. Standalone default directory MUST resolve to vibespace base path with home-directory fallback. Created tile MUST start in the chosen working directory.

### F002-R03: Tile Interactions Move Active Focus

When user clicks a tile or interacts with controls inside that tile, that tile MUST become active for keyboard routing. Active tile id MUST be persisted with board layout. Project-mapped tiles MUST reuse the same terminal tabs as detailed project view. Standalone vibespace tiles MUST remain available after switching between modes.

### F002-R04: Tiles Drag and Resize Inside Bounded 4×4 Grid

Tile placement MUST snap to grid cells. Placement MUST be clamped to a maximum 4×4 grid boundary. Invalid collisions MUST be rejected or relocated to the next valid position.

### F002-R05: Directional Navigation Between Board Tiles

When user presses an arrow key while a tile is focused, BoardSpatialNavigation MUST resolve the nearest tile in that direction. Focus MUST move to the resolved tile.

### F002-R06: Board-Level Toolbar UI

When terminal board vibespace mode is active, VibeSpaceTerminalOnlyViewBoardChrome MUST display board-level toolbar controls.

### F002-R07: Board Tile Command Menus Expose Terminal Shortcuts

Terminal board tile command menus MUST expose the saved terminal shortcut actions for that tile's current vibespace and owning project context. Running a `currentTerminal` or `newPermanentTerminal` shortcut from a board tile MUST target that tile's terminal session context. Running a `newTemporaryTerminal` shortcut from a board tile MUST open a temporary terminal spotlight from that tile context and MUST NOT add a persistent board tile. `Manage Shortcuts…` from a board tile command menu MUST open vibespace settings for the active vibespace with the `Shortcuts` category selected.

### F002-R08: Board Inline Trigger Popup Uses Shared Two-Pane Overlay

When an inline terminal trigger is opened from a board tile surface, Terminal Board MUST render the picker as one shared board-scoped popup instead of clipping or resizing inside the tile. The shared popup MUST preserve the originating tile layout, show file and folder results in a left pane, show prompt and shortcut actions in a right pane, expose `Manage Shortcuts…` when that source supports it, and provide an explicit close button. Cancelling the popup MUST leave input unchanged and return focus to the originating tile input.

### F002-R09: Board Surface Affinity for Terminal Creation

When a user creates a persistent terminal from a board surface, the resulting tile MUST be added to that same surface. This applies to the board `New Terminal` button, tile split actions, terminal context-menu split actions, terminal spotlight split actions, and temporary-terminal-to-persistent split actions. Non-board terminal panes MAY continue to create raw terminal tabs without adding board tiles.

### F002-R10: Board Tile Context Menus Support Window Transfer

Board tile context menus and minimized tile context menus MUST provide a `Send to New Board Window` action when detached board windows are supported. When other board windows are open for the same vibespace, those menus MUST also list existing board windows as transfer targets. Choosing a transfer action MUST move exactly the selected tile, preserve its backing content/session identity, remove it from the source surface, assign a destination-scoped board position on the target surface, and close an emptied detached source surface without merging stale shells. Source-surface column, row, minimized index, and linear Spotlight order positions MUST NOT be reused as authoritative positions on the destination surface.

### F002-R11: Detached Board Windows Own Local Spotlight

Each detached board window MUST own its own board-scoped spotlight presentation. Opening terminal, file, browser, ACP, VibeCast, or temporary-terminal spotlight from a detached board window MUST present within that detached window and MUST NOT jump to the primary vibespace window.

### F002-R12: Detached Board Windows Persist With VibeSpace State

Detached board surfaces MUST persist with the owning vibespace, including their per-surface tile layout and best-effort window placement metadata. Reopening the vibespace MUST restore open detached board surfaces as detached board windows. Missing or changed displays MUST NOT automatically merge detached surfaces into the primary board.

## Scenarios

### Scenario F002-S01: Terminal board renders independent terminal tiles

**Given** terminal board vibespace mode is active
**When** board view renders from persisted layout
**Then** each tile hosts one independent terminal session surface
**And** tile selection is tracked by persisted active tile id

### Scenario F002-S02: New terminal flow supports project + directory selection

**Given** user taps `New Terminal` in terminal board vibespace mode
**When** the create sheet opens
**Then** user can choose a project root or `No Project (VibeSpace)`
**And** user can choose discovered subfolders or browse an arbitrary folder
**And** selecting `No Project (VibeSpace)` creates a standalone vibespace terminal tile (not mapped to a project tab set)
**And** standalone default directory resolves to vibespace base path (common parent of vibespace project roots) with home-directory fallback
**And** created tile starts in the chosen working directory

### Scenario F002-S03: Tile interactions move active focus to selected terminal

**Given** terminal board has multiple tiles
**When** user clicks a tile or interacts with controls inside that tile
**Then** that tile becomes active for keyboard routing
**And** active tile id is persisted with board layout
**And** project-mapped tiles reuse the same terminal tabs as detailed project view
**And** standalone vibespace tiles remain available after switching between detailed and terminal-only modes

### Scenario F002-S04: Tiles drag and resize inside a bounded 4×4 grid

**Given** terminal board vibespace mode is active
**When** user drags a tile or resizes using the tile handle
**Then** tile placement snaps to grid cells
**And** placement is clamped to a maximum 4×4 grid boundary
**And** invalid collisions are rejected or relocated to the next valid position

### Scenario F002-S05: Directional navigation between board tiles

**Given** terminal board has multiple tiles
**When** user presses an arrow key while a tile is focused
**Then** BoardSpatialNavigation resolves the nearest tile in that direction
**And** focus moves to the resolved tile

### Scenario F002-S06: Board-level toolbar UI

**Given** terminal board vibespace mode is active
**When** the board view renders
**Then** VibeSpaceTerminalOnlyViewBoardChrome displays board-level toolbar controls

### Scenario F002-S07: Board tile command menus include saved shortcuts and shortcut management

**Given** terminal board vibespace mode is active
**And** a terminal tile is visible
**And** shortcut commands exist for the active vibespace and, when applicable, that tile's owning project
**When** user opens the tile command menu
**Then** saved terminal shortcuts appear for that tile context
**And** `Manage Shortcuts…` appears in that menu
**When** user runs a `currentTerminal` or `newPermanentTerminal` shortcut from that menu
**Then** the shortcut executes against that tile's terminal session context
**When** user runs a `newTemporaryTerminal` shortcut from that menu
**Then** a temporary terminal spotlight opens from that tile context
**And** no persistent board tile is added
**When** user selects `Manage Shortcuts…`
**Then** vibespace settings open with the `Shortcuts` category selected

### Scenario F002-S08: Board inline trigger opens shared popup without disturbing tile layout

**Given** terminal board vibespace mode is active
**And** a terminal, ACP, or VibeCast tile input invokes the configured inline trigger
**When** the picker opens
**Then** a shared board-scoped popup is presented instead of rendering inside the tile body
**And** the tile layout remains unchanged
**And** the popup shows files and folders in the left pane
**And** the popup shows generate and shortcut actions in the right pane
**And** an explicit close button is available
**When** the user cancels the popup
**Then** the originating tile input regains focus
**And** its text remains unchanged

### Scenario F002-S09: Persistent terminal creation follows the initiating board surface

**Given** terminal board mode has a primary board surface and a detached board window surface
**And** a terminal tile is active in the detached board window
**When** the user creates a terminal from `New Terminal`, `Split Terminal`, terminal context menu split, or terminal spotlight split in that detached window
**Then** the new persistent terminal tile is inserted into the detached board window surface
**And** the primary board surface is not changed except for shared session state updates
**When** the same actions are initiated from the primary board surface
**Then** the new persistent terminal tile is inserted into the primary board surface

### Scenario F002-S10: Context menu transfers a tile to another board window

**Given** terminal board mode has a primary board surface and one or more detached board window surfaces
**And** a visible or minimized terminal, file, browser, ACP, or VibeCast tile exists on a source surface
**When** the user opens that tile's context menu
**Then** `Send to New Board Window` is available
**And** existing open board windows for the same vibespace are listed as transfer targets, excluding the source surface
**When** the user selects a transfer target
**Then** exactly that tile moves to the target surface
**And** the tile receives a target-surface board position from the destination insertion rules
**And** the source surface's column, row, minimized index, and linear Spotlight order position are not carried as authoritative destination positions
**And** the source surface no longer contains that tile or a blank placeholder
**And** if the source was a detached surface that became empty, its window closes after the transfer

### Scenario F002-S11: Detached board windows present local spotlight

**Given** terminal board mode has a detached board window
**And** a terminal, file, browser, ACP, or VibeCast tile is visible in that detached window
**When** the user opens spotlight from that tile
**Then** spotlight appears in the detached board window
**And** the primary vibespace window does not steal the spotlight presentation
**When** the user creates a persistent terminal from that local spotlight
**Then** the persistent terminal tile is added to the detached board window surface

### Scenario F002-S12: Detached board windows restore with vibespace state

**Given** a vibespace has one or more detached board windows
**And** each detached window has board tiles and saved placement metadata
**When** the vibespace closes and later reopens
**Then** the detached board surfaces reopen as detached board windows
**And** each detached board window restores its persisted tile layout
**And** window placement is restored on a best-effort basis
**And** detached surfaces are not merged into the primary board solely because display topology changed

## Acceptance Criteria

- Tile add/remove/move operations complete within 100ms (PERF-3).
- Layout persistence writes complete within 200ms (PERF-4).
- No orphaned processes after tile removal (REL-6).
- Spatial navigation works via keyboard only (A11Y-2).
- All tile operations logged (OBS-1, OBS-2).
- Detached board windows render board content only and never become separate vibespace shells.
- Persistent terminal creation from a detached board window targets that detached board surface.
- Spotlight opened from a detached board window stays local to that detached board window.
- Detached board surfaces restore with the vibespace using persisted layout and best-effort placement.
- Tile drag transfer and context-menu transfer move exactly one visible or minimized tile across board surfaces.
- Tile transfer preserves backing content/session identity while recalculating board position in the destination surface.
- File, browser, ACP, and VibeCast board tiles participate in transfer flows using the same one-tile move semantics as terminal tiles.
- Detached board window titles and transfer target labels are derived from current surface content instead of duplicate generic placeholders.

## Open Questions

- None.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-27 | Clarified that board-window transfer preserves tile identity but recalculates destination-surface position. | — |
| 2026-04-26 | Marked implemented; added multi-window board support, local spotlight, surface-targeted terminal creation, context-menu transfer, and non-terminal tile transfer requirements. | Codex |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-034–036, TRM-039, TRM-069, TRM-070) | — |
