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

Detached board window frame coordinates and captured display identity must persist per vibespace. On reopen, the saved frame is reapplied directly as best-effort placement. The current restore path does not use the persisted display identity to choose a screen or explicitly clamp/fallback an unavailable display.

### F048-R07: Tile transfer via context menu

Visible tile headers and minimized tab context menus must support sending the selected tile to a new board window or an existing open board window.

### F048-R08: Surface-targeted creation

New-terminal and split/create-new-persistent-terminal actions initiated from a board surface must create a persistent tile on the initiating surface. A create action offered from temporary Spotlight creates a separate persistent terminal tile; it does not convert the temporary process.

### F048-R09: Independent local Spotlight coordinator

Each detached board window MUST own an independent `TerminalSpotlightCoordinator`, restore stack, browser-preview owner, scroll ownership, and host-scoped editor lease. Its catalog MUST enumerate all project-terminal and standalone-terminal tile members first in visible-then-minimized terminal order, then file, browser, ACP, VibeCast, and tile-backed Vibe Lanes members in a second visible-then-minimized pass. When no Vibe Lanes tile exists, the host MUST append a synthetic Vibe Lanes member. A persisted Spotlight snapshot MAY retain a user-arranged order different from this catalog seed. The local host MUST provide the F003 44 pt shelf, compact grid-count semantic overview, max-two combo layout, separate pane-local terminal compose bars/drafts, full-identity Up/Down history through the AppContainer-owned store, activation-before-send, orientation, and focus parity. Terminal link/file/browser previews, validated restore, temporary process-exit cleanup, and dismissal MUST remain local and MUST NOT jump to or release ownership held by the primary window.

### F048-R10: Single-tile transfer semantics

A single-tile transfer initiated through `Send to New Board Window` or `Send to Board Window` must move exactly the selected tile between board surfaces. That action must not clone the tile, move sibling tiles, or leave blank placeholders on the source surface. This restriction applies only to the single-tile transfer actions; the separate project-scoped bulk move defined by F048-R13 intentionally moves all matching tiles.

### F048-R11: Surface-local window toolbar

Detached board windows MUST have a surface-scoped toolbar in this order: Terminal, Agent, Browser, VibeCast, and Vibe Lanes. Terminal creation MUST distinguish persistent and temporary submission: persistent creates a tile directly on the detached surface, while temporary crosses a per-window toolbar bridge and opens in that window's local Spotlight without creating a tile. Choosing split/create new persistent terminal from the temporary Spotlight MUST create exactly one separate persistent tile on the same detached surface; it MUST NOT convert the temporary process. Toolbar availability MUST respect that surface's tile cap. VibeCast and Vibe Lanes singleton checks MUST include both visible `layout.tiles` and `layout.minimizedTiles`, so a minimized singleton suppresses its corresponding add action.

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

### F048-R14: Bulk-move and bulk-recall board-mode guard

The bulk-move and bulk-recall shortcuts MUST operate in terminal board mode only. A Detailed-mode invocation MUST be a silent no-op, including when a detached board window is focused.

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

### F048-R17: Per-surface Spotlight layout, restore, and privacy

Each detached surface MUST persist and restore its own `spotlightLayout` order, combos, member order, and orientation with tile layout and placement. Decode/reconciliation MUST validate persistent surface membership/tile identity plus terminal-tab, ACP-store, and file-owner availability where applicable; browser-preview descriptors MUST additionally contain a decodable URL. A persistent browser MAY recreate or resolve its canonical owner without requiring a pre-existing browser view model. Reconciliation MUST collapse missing combo members, append new members, preserve board geometry/session lifetime, and never merge state with another surface. Semantic overview metadata MUST follow F003 redaction rules and MUST NOT contain screenshots, terminal screen excerpts, commands, or live output.

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

### Scenario F048-S06: Full local Spotlight in detached window

**Given** a detached board contains project/standalone terminals and nonterminal persistent panes
**When** the user opens Spotlight, a terminal link/file preview, or a browser preview
**Then** the independent local coordinator presents within that detached window
**And** the primary coordinator, restore stack, and editor leases are unchanged
**And** the local 44 pt shelf, grid-count semantic overview, persisted-order combos, orientation, and pane-local compose behavior include every supported persistent kind
**When** the preview closes or its active temporary process exits
**Then** stale descriptors are skipped, the nearest valid local owner restores, and local temporary resources are cleaned up.

### Scenario F048-S07: Toolbar terminal creation targets the initiating surface

**Given** the user is focused on a detached board window
**When** the toolbar creates a persistent terminal
**Then** one tile appears on that detached surface, not the primary surface
**When** the toolbar creates a temporary terminal
**Then** the per-window bridge opens it in local Spotlight and no tile is added
**When** the user chooses split/create new persistent terminal from that temporary Spotlight
**Then** exactly one separate persistent tile is added to the same detached surface
**And** the temporary process is not converted or transferred into that tile.

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
**Then** every tile on the primary surface where `projectPath == projectA` is detached in one source-store mutation and added to a new detached surface in a second store mutation
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

### Scenario F048-S13: Detailed-mode shortcut behavior

**Given** the vibespace primary window is in Detailed mode
**When** the user presses `⌘⌥M`
**Then** nothing happens (no error, no notification, no UI change)
**When** the user presses `⌘⌥B` from either the primary window or a focused detached board window
**Then** nothing happens because both bulk routes require Terminal Board mode.

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
- Spotlight opens in the board window where the user initiated it and uses an independent coordinator, restore stack, preview owner, scroll owner, and editor lease.
- Detached Spotlight includes all persistent kinds with per-surface 44 pt shelf/grid/combo/orientation and pane-local terminal compose parity.
- Detached terminal link, file, and browser previews stay local; restore validates surface/tile identity, terminal/ACP/file owners where applicable, and browser-preview URLs, while a valid persistent browser can resolve without a pre-existing view model. Temporary process exit cleans up local resources.
- The toolbar distinguishes direct persistent terminal creation from the bridged temporary Spotlight path; split/create-new-persistent-terminal adds a separate tile to the same surface without converting the temporary process.
- Settings continue to behave as primary-window shell flows.
- Persistent terminal creation from plus, split, and spotlight actions appears on the initiating board surface.
- Context-menu tile transfer moves one selected tile only, leaves no blank source placeholders, and closes emptied detached source windows.
- Transfer target menu shows current surface content labels.
- Bulk-move shortcut (`⌘⌥M`, F048-R13) relocates every tile on the source surface owned by the focused project to a new detached board window through a source-detach mutation followed by a destination-surface mutation; remaining tiles compact via the existing source-layout reflow (F048-R15). The same action is invokable from any tile's right-click menu via "Send All From This Project to New Window", which uses the right-clicked tile's project (not the focused project). A crash between the two mutations can leave removal persisted before destination creation.
- Bulk-recall shortcut (`⌘⌥B`, F048-R16) returns every tile on a focused detached surface to the primary surface and closes the detached window; tile-cap overflow rolls into the minimized strip.
- Bulk move and bulk recall are silent no-ops outside terminal board mode. Bulk move is also a no-op when no source tiles match; bulk recall is a no-op from the primary window.

## Test Coverage

> **Evidence status (2026-10-18 documentation review):** No tests, builds, apps, processes, or manual UI checks were run. The table is a static inventory only. Source and `SpotlightEnhancementTests` contain surface identity, detached snapshot, full-kind factory, local shortcut/permanent creation, restore, process-exit, redaction, and geometry assertions. Production inspection confirms detached compose-history environment injection, visible-plus-minimized VibeCast/Vibe Lanes singleton checks, and the bulk-recall Terminal Board mode guard. Mounted detached NSWindow coverage for toolbar bridge delivery, complete local preview UI, multi-host editor leases, placement restore, and cleanup was not found.

| Requirement | Static test/source inventory |
|------|------|
| F048-R09 / F048-S06 | `SpotlightStandaloneAndRestoreTests` statically covers detached identity/factory and restore guards; local window UI/parity remains unmounted. |
| F048-R11 / F048-S07 | Production source contains `DetachedToolbarTemporaryTerminalBridge` and surface-targeted `onCreateTerminal`; no dedicated toolbar bridge test was found. |
| F048-R17 | Detached snapshot Codable and unequal-geometry tests are present; end-to-end window restoration and lease cleanup remain gaps. |
| F048-R13 (bulk detach + new surface) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachTilesForProjectRemovesOnlyMatching`, `testCreateDetachedSurfaceWithTilesPopulatesAndSetsActive` |
| F048-R13 (visible + minimized) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testTileIDsForProjectIncludesMinimizedTiles`, `testBulkDetachTilesForProjectIncludesMinimized` |
| F048-R13 (source detach publication) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachIsSingleMutation` covers only the source-detach helper's publication; the complete detach-then-create move spans two mutations. |
| F048-R13 (no match no-op) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testBulkDetachTilesForProjectNoMatchIsNoOp` |
| F048-R16 (recall merges back) | `VibeSpaceTerminalBoardStoreBulkMoveTests.testRecallMergesAllDetachedTilesBackToPrimary` |

## Open Questions

None — feature is implemented.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: scoped F048-R10 to single-tile transfer while preserving F048-R13 bulk move; documented detached history injection, visible-plus-minimized VibeCast/Vibe Lanes singleton checks, and the Terminal Board recall guard; replaced obsolete conversion wording with separate split/create-new-persistent-tile behavior. Static sources only; no tests or manual runs. | — |
| 2026-10-18 | Review expanded F048-R09/R11/R17 and S06/S07 for independent local ownership, terminal-first two-pass ordering plus built-in Vibe Lanes fallback, per-surface shelf/grid/combo persistence, pane-local drafts/activation, canonical toolbar order, temporary versus persistent creation, local previews, restore validation, safe metadata, geometry-preserving reconciliation, placement limitations, immediate placement writes, and two-step non-atomic bulk move. Later production-fix status is recorded above. | — |
| 2026-05-23 | Added F048-R13 to R16 (multi-monitor bulk pane move) with scenarios S10 to S14 and Test Coverage table | Kiro |
| 2026-05-23 | Added "Send All From This Project to New Window" tile context menu entry alongside the keyboard shortcut (scenario S15) | Kiro |
| 2026-05-20 | Initial spec from implemented feature | Kiro |
