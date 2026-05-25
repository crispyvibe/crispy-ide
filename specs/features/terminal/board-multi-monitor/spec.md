# Terminal Board Multi-Monitor — Spec

Status: implemented

## Overview

Terminal Board Multi-Monitor allows a single vibespace's terminal board to span multiple displays by opening detached board windows. Detached windows render terminal-board tiles only and remain tied to the owning vibespace runtime. Tiles can be transferred between board surfaces via context menu or drag.

## Dependencies

- F002 (Terminal Board) — extends the board with multi-surface support
- F003 (Terminal Spotlight) — each board window owns an independent local spotlight

## Requirements

### F048-R01: Open detached board windows

A vibespace in terminal board mode must be able to open additional detached board windows on other displays.

### F048-R02: Board content only

Detached board windows must render terminal-board content only (tiles, minimized tabs, VibeCast, ACP, browser tiles). They must not become independent vibespace shells.

### F048-R03: Mode independence

Switching the primary vibespace window from terminal board to detailed mode must not close detached board windows.

### F048-R04: Settings ownership

App settings and vibespace settings must remain owned by the primary vibespace window even when detached board windows are visible.

### F048-R05: Lifecycle coupling

Detached board windows must close when the owning vibespace closes.

### F048-R06: Placement persistence

Detached board window geometry (frame, display assignment) must persist per vibespace and restore on next open using best-effort placement.

### F048-R07: Tile transfer via context menu

Visible tile headers and minimized tab context menus must support sending the selected tile to a new board window or an existing open board window.

### F048-R08: Surface-targeted creation

New-terminal, split-terminal, and temporary-terminal-to-persistent actions initiated from a board surface must target the initiating surface.

### F048-R09: Independent spotlight

Each detached board window must own an independent local spotlight coordinator so spotlight does not jump to the primary vibespace window.

### F048-R10: Tile transfer semantics

Tile transfer must move exactly one tile between board surfaces. No cloning, no bulk-move, no blank placeholders left on the source surface.

### F048-R11: Window toolbar

Detached board windows must have a toolbar with actions to add VibeCast, Agent, and Browser tiles to that surface.

### F048-R12: Window rename

Detached board windows must support renaming via titlebar context menu.

### F048-R13: Bulk move shortcut

A keyboard shortcut MUST move every tile on the current board surface that
belongs to the focused project to a new detached board window in a single
operation. This is the bulk equivalent of single-tile transfer (F048-R07).
Default binding: `⌘⌥M`. Source surface is resolved from the key window:
the active detached board window if one is focused, otherwise the primary
surface.

The same operation MUST also be available as a per-tile context menu
entry "Send All From This Project to New Window", appearing alongside the
existing "Send to New Board Window" item. The context-menu variant uses
the right-clicked tile's `projectPath` to determine which project's tiles
to bulk-move (the right-clicked tile may not be from the focused project)
and is hidden when the tile has no resolved project ownership.

### F048-R14: Board mode only

The bulk-move and bulk-recall shortcuts MUST operate in terminal board mode
only. Detailed mode invocations are a no-op (silent, no error).

### F048-R15: Source surface reorganization

After bulk move, remaining tiles on the source board surface MUST be
reorganized to fill empty space. This is automatic via the existing layout
reflow that runs on every store mutation; no additional logic is required.

### F048-R16: Reverse bulk move

A keyboard shortcut MUST move every tile on a focused detached board
window back to the primary surface, then close the detached window.
Default binding: `⌘⌥B`. Invocation from the primary window is a no-op.
Tile overflow (when the primary surface's 16-tile cap is reached) is
handled by the existing reattach pathway, which folds excess tiles into
`minimizedTiles`.

## Scenarios

### Scenario F048-S01: Open a detached board window

**Given** the user is in terminal board mode  
**When** the user sends a tile to a new board window via context menu  
**Then** a new detached board window opens containing that tile  
**And** the tile is removed from the source surface

### Scenario F048-S02: Transfer tile to existing window

**Given** two board windows are open for the same vibespace  
**When** the user right-clicks a tile and selects "Send to Board Window > [target title]"  
**Then** the tile moves to the target surface  
**And** the tile is removed from the source surface

### Scenario F048-S03: Primary window mode change

**Given** the primary window is in terminal board mode with one detached board window  
**When** the user switches the primary window to detailed view  
**Then** the detached board window remains open and functional

### Scenario F048-S04: Vibespace close

**Given** a vibespace has two detached board windows  
**When** the user closes the vibespace  
**Then** both detached board windows close automatically

### Scenario F048-S05: Placement restoration

**Given** a vibespace previously had a detached board window on an external monitor  
**When** the vibespace is reopened with the same display topology  
**Then** the detached board window is restored at its previous frame position

### Scenario F048-S06: Spotlight in detached window

**Given** a detached board window is focused  
**When** the user triggers spotlight  
**Then** spotlight opens within the detached board window, not the primary window

### Scenario F048-S07: New terminal targets initiating surface

**Given** the user is focused on a detached board window  
**When** the user creates a new terminal tile  
**Then** the tile appears on the detached board surface, not the primary surface

### Scenario F048-S08: Empty window closes after transfer

**Given** a detached board window contains a single tile  
**When** the user transfers that tile to another board window  
**Then** the now-empty detached board window closes automatically

### Scenario F048-S09: Rename detached window

**Given** a detached board window is open  
**When** the user right-clicks the titlebar and selects "Rename Window"  
**Then** a rename prompt appears  
**And** the window title updates after confirmation

### Scenario F048-S10: Bulk move project tiles to a new monitor

**Given** the user is in terminal board mode with multiple projects' tiles on the primary surface  
**And** project A is the focused project  
**When** the user invokes the bulk-move shortcut (`⌘⌥M`)  
**Then** every tile on the primary surface where `projectPath == projectA` moves to a new detached board window in a single mutation  
**And** other projects' tiles remain on the primary surface  
**And** the layout on the primary surface compacts to fill the freed space (F048-R15)  
**And** the new detached window opens at the system-default placement, ready to be dragged to another monitor

### Scenario F048-S11: Bulk move from a detached window to another new window

**Given** a detached board window is the key window and contains tiles from project A and project B  
**And** project A is the focused project  
**When** the user invokes the bulk-move shortcut from that detached window  
**Then** project A's tiles move to a NEW detached window  
**And** project B's tiles remain on the original detached surface

### Scenario F048-S12: Bulk recall to primary

**Given** a detached board window is the key window  
**When** the user invokes the bulk-recall shortcut (`⌘⌥B`)  
**Then** every tile on that detached surface moves back to the primary surface  
**And** the detached window closes automatically  
**And** if the primary surface's 16-tile cap is exceeded, overflow tiles roll into the minimized tab strip

### Scenario F048-S13: Bulk shortcuts in detailed mode are no-ops

**Given** the vibespace primary window is in detailed mode  
**When** the user presses `⌘⌥M` or `⌘⌥B`  
**Then** nothing happens (no error, no notification, no UI change)  
**Because** F048-R14 restricts these shortcuts to terminal board mode

### Scenario F048-S14: Bulk move with no matching tiles is a no-op

**Given** the user is in terminal board mode  
**And** the focused project has no tiles on the source surface  
**When** the user invokes `⌘⌥M`  
**Then** no detached window is created  
**And** the source surface is unchanged

### Scenario F048-S15: Bulk move via tile context menu

**Given** the user is in terminal board mode with multiple projects' tiles on the same surface  
**And** project B is the focused project  
**When** the user right-clicks a tile owned by project A and selects "Send All From This Project to New Window"  
**Then** every tile on the current surface where `projectPath == projectA` (the right-clicked tile's project — NOT the focused project) moves to a new detached window  
**And** the menu item is hidden when the right-clicked tile has no resolved `projectPath` (e.g., a standalone-terminal tile)

## Acceptance Criteria

- User can place terminal-board windows on multiple monitors without creating a second vibespace shell.
- Primary vibespace window can switch modes without disrupting detached board windows.
- Detached board windows close automatically with the owning vibespace.
- Detached board windows are restored using persisted surface state and best-effort window placement.
- Spotlight opens in the board window where the user initiated it.
- Settings continue to behave as primary-window shell flows.
- Persistent terminal creation from plus, split, and spotlight actions appears on the initiating board surface.
- Context-menu tile transfer moves one selected tile only, leaves no blank source placeholders, and closes emptied detached source windows.
- Transfer target menu shows current surface content labels.
- Bulk-move shortcut (`⌘⌥M`, F048-R13) relocates every tile on the source surface owned by the focused project to a new detached board window in a single store mutation; remaining tiles compact via the existing layout reflow (F048-R15). The same action is invokable from any tile's right-click menu via "Send All From This Project to New Window", which uses the right-clicked tile's project (not the focused project).
- Bulk-recall shortcut (`⌘⌥B`, F048-R16) returns every tile on a focused detached surface to the primary surface and closes the detached window; tile-cap overflow rolls into the minimized strip.
- Bulk shortcuts are no-ops outside terminal board mode (F048-R14) and when no tiles match the focused project on the source surface.

## Test Coverage

| Requirement | Test |
|------|------|
| F048-R13 (bulk detach + new surface) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachTilesForProjectRemovesOnlyMatching`, `testCreateDetachedSurfaceWithTilesPopulatesAndSetsActive` |
| F048-R13 (visible + minimized) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testTileIDsForProjectIncludesMinimizedTiles`, `testBulkDetachTilesForProjectIncludesMinimized` |
| F048-R13 (single mutation) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachIsSingleMutation` |
| F048-R13 (no match no-op) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachTilesForProjectNoMatchIsNoOp` |
| F048-R16 (recall merges back) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testRecallMergesAllDetachedTilesBackToPrimary` |

## Open Questions

None — feature is implemented.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-20 | Initial spec from implemented feature | Kiro |
| 2026-05-23 | Added F048-R13 to R16 (multi-monitor bulk pane move) with scenarios S10 to S14 and Test Coverage table | Kiro |
| 2026-05-23 | Added "Send All From This Project to New Window" tile context menu entry alongside the keyboard shortcut (scenario S15) | Kiro |
