# Terminal Board — Spec

Status: implemented

## Overview

Terminal Board is a terminal-only canvas mode that replaces the editor pane with a resizable grid of terminal tiles. Each tile hosts an independent terminal session scoped to a project or standalone. The board supports up to 16 tiles (4×4), drag-and-drop repositioning, column/row resizing, tile minimization, spatial keyboard navigation, and board-level chrome.

Terminal Board can be presented as the primary vibespace board surface or as one or more detached board window surfaces. Each surface owns its visible layout, active tile, local spotlight presentation, and persistent terminal creation target.

## Dependencies

- F001 (Sessions & Tabs) — each tile is backed by a terminal tab/session
- F003 (Spotlight) — minimized tabs restore their tiles to the grid when activated and remain persistent members of the surface-scoped Spotlight shelf; double-clicking a visible tile body opens Spotlight
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

When a user creates a persistent terminal from a board surface, the resulting tile MUST be added to that same surface. This applies to the board `New Terminal` button, tile split actions, terminal context-menu split actions, terminal Spotlight split actions, and create-new-persistent-tile actions offered from a temporary Spotlight. These actions create a new persistent terminal tile; they do not convert or transfer the temporary process. Non-board terminal panes MAY continue to create raw terminal tabs without adding board tiles.

### F002-R10: Board Tile Context Menus Support Window Transfer

Board tile context menus and minimized tile context menus MUST provide a `Send to New Board Window` action when detached board windows are supported. When other board windows are open for the same vibespace, those menus MUST also list existing board windows as transfer targets. Choosing a transfer action MUST move exactly the selected tile, preserve its backing content/session identity, remove it from the source surface, assign a destination-scoped board position on the target surface, and close an emptied detached source surface without merging stale shells. Source-surface column, row, minimized index, and linear Spotlight order positions MUST NOT be reused as authoritative positions on the destination surface.

### F002-R11: Detached Board Windows Own Local Spotlight

Each detached board window MUST own its own board-scoped spotlight presentation. Opening terminal, standalone terminal, file, browser, ACP, VibeCast, or temporary-terminal spotlight from a detached board window MUST present within that detached window and MUST NOT jump to the primary vibespace window. Persistent shelf order, max-two combos, orientation, overview, and focus behavior MUST follow F003 with surface-scoped persistence.

### F002-R12: Detached Board Windows Persist With VibeSpace State

Detached board surfaces MUST persist with the owning vibespace, including their per-surface tile layout, F003 Spotlight shelf/combo/orientation snapshot, and best-effort window placement metadata. Spotlight member order MAY mirror flattened tile order but MUST NOT mutate column/row geometry, tile count, or session lifetime. Reopening the vibespace MUST restore open detached board surfaces as detached board windows. Missing or changed displays MUST NOT automatically merge detached surfaces into the primary board.

### F002-R13: Minimized Tab Labels Prefer Terminal Tab Title

The minimized tab bar MUST label a terminal tile with its terminal tab title, falling back to the owning project title when the tab title is empty, then a generic `Terminal` label when neither is available. This matches the tab-title source defined in F001-R17 and the Spotlight carousel chip labeling.

### F002-R14: Detached-Local Shelf, Grid, and Combo Parity

Each detached board MUST enumerate all persistent project-terminal and standalone-terminal tile members first in visible-then-minimized terminal order. It MUST then enumerate file, browser, ACP, VibeCast, and tile-backed Vibe Lanes members in a second visible-then-minimized pass. When no tile-backed Vibe Lanes member exists, the host MUST append the synthetic Vibe Lanes member. A persisted Spotlight snapshot MAY retain a user-arranged order different from this catalog seed. The detached board provides the same F003 44 pt shelf, compact grid-count overview control, safe three-column semantic grid, max-two combo, independent combo-half focus, orientation, separate terminal compose bars/drafts, activation-before-send, and full-identity Up/Down compose history as the primary host.

### F002-R15: Detached Toolbar Temporary Terminal Bridge

A detached titlebar New Terminal action MUST publish a surface-local request through a temporary toolbar bridge into that detached window's local Spotlight coordinator. It MUST create a temporary terminal Spotlight and no tile. Choosing split/create-new-persistent-terminal from that temporary Spotlight MUST call `addTile(..., surfaceID:)` and create one new persistent tile on the originating detached surface. The temporary process remains a separate temporary Spotlight resource and is not converted into the persistent tile. Persistent toolbar/split creation MUST bypass the temporary route and create the tile directly.

### F002-R16: Detached-Local Link, Browser, File, and Editor Ownership

Terminal links and filesystem targets activated in a detached board or its Spotlight MUST open browser/file previews in that same detached window and restore to its local chain. Persistent browser/file members MUST reuse or resolve their canonical presentation owners. File display MUST use host-scoped leases so a main and detached Spotlight cannot release or duplicate each other's editor surface.

### F002-R17: Validated Restore and Process-Exit Cleanup

Detached restore MUST validate surface membership and tile identity for every persistent member, plus terminal-tab existence, ACP-store availability, and active file ownership where applicable. A persistent browser MAY be recreated or resolved through its canonical coordinator without requiring a pre-existing browser view model; a browser-preview descriptor MUST additionally contain a decodable URL. Invalid descriptors MUST be skipped. Active temporary process exit MUST restore the nearest valid descriptor or dismiss locally; stale exits MUST do nothing. Dismissal MUST release temporary sessions, preview owners, callbacks, scroll monitors, and only the detached host's editor lease.

### F002-R18: Surface Persistence, Privacy, Reconciliation, and Geometry

Every surface MUST persist its own `spotlightLayout`, tile layout, active/minimized state, and best-effort window placement. Reconciliation MUST normalize missing/duplicate members, collapse partial combos, and append new live members without crossing surfaces. Overview metadata MUST follow F003 safe metadata/redaction rules and MUST NOT persist or render screenshots, terminal screen excerpts, commands, or live output. Shelf reorder MUST preserve destination column/row IDs and counts, width/height weights, tile/session identity and lifetime, active/minimized state, and all other surfaces.

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

### Scenario F002-S13: Minimized terminal tab shows the terminal name

**Given** a terminal tile is minimized into the minimized tab bar
**When** the minimized chip renders
**Then** the chip label shows the terminal tab title
**And** when the tab title is empty the chip falls back to the owning project title

### Scenario F002-S14: Detached Spotlight matches shelf, grid, combo, and compose behavior

**Given** a detached surface contains persistent terminals and nonterminal panes
**When** local Spotlight opens
**Then** its 44 pt shelf and semantic three-column overview enumerate all supported persistent kinds in that surface's persisted order
**And** combo halves are independently clickable, terminal halves retain separate full-identity compose drafts, and activation occurs before send
**And** focused shared header/actions and orientation match the primary host
**And** both hosts provide Up/Down history per full terminal identity through the AppContainer-owned `ComposeHistoryStore`.

### Scenario F002-S15: Detached New Terminal separates temporary and persistent creation

**Given** a detached board window is active
**When** its toolbar requests a temporary New Terminal
**Then** the local bridge opens a temporary terminal in that window and does not add a tile
**When** the user chooses split/create new persistent terminal from it
**Then** exactly one new persistent tile is added to the same detached surface
**And** the temporary process is not converted or transferred into that tile
**And** a direct persistent creation path adds a tile without first creating a temporary Spotlight.

### Scenario F002-S16: Detached link and file actions remain local

**Given** a detached terminal exposes a link or filesystem target
**When** the user activates it
**Then** the browser or file preview opens in that detached window's Spotlight restore chain
**And** persistent browser/editor owners are reused
**And** file rendering is leased by that host without releasing another host's lease.

### Scenario F002-S17: Detached restore validates owners and cleans up process exit

**Given** a detached temporary Spotlight has valid and stale restore descriptors
**When** it closes or its active temporary process exits
**Then** stale entries are skipped and the nearest valid local owner is restored
**And** a stale process callback changes nothing
**And** no temporary process, preview owner, callback, scroll monitor, or host lease survives final dismissal.

### Scenario F002-S18: Surface restore and shelf reconciliation preserve geometry and privacy

**Given** primary and detached surfaces have different tile and `spotlightLayout` snapshots
**When** state reloads or live members reconcile
**Then** each surface retains its own order, combo orientation, active/minimized state, and best-effort placement
**And** grid IDs/counts/weights and session lifetime are unchanged
**And** semantic metadata is redacted and contains no screenshot, terminal screen excerpt, command, or live output.

## Static Coverage Status

No build, test, app, process, or manual UI verification was run for this documentation update. Static inspection found source/test coverage for surface-local `spotlightLayout`, visible/minimized standalone identity, detached factory attachment, AppContainer compose-history injection, shortcut launch routing, exact restore/process-exit guards, browser URL redaction, and unequal geometry persistence. Mounted detached toolbar delivery, local link/file preview UI, independent pane-history behavior, multi-host editor-lease release, and complete window restoration remain UI/manual or missing dedicated regression gaps.

## Acceptance Criteria

- Tile add/remove/move operations complete within 100ms (PERF-3).
- Layout persistence writes complete within 200ms (PERF-4).
- No orphaned processes after tile removal (REL-6).
- Spatial navigation works via keyboard only (A11Y-2).
- Tile-operation logging remains an unmet OBS-1/OBS-2 acceptance target; no Terminal Board production logger call was found in the static review.
- Detached board windows render board content only and never become separate vibespace shells.
- Detached Spotlight has persistent-kind shelf/grid/combo parity, pane-local terminal compose drafts, full-identity Up/Down history, activation-before-send, and safe metadata.
- The local toolbar bridge distinguishes temporary Spotlight terminal creation from direct persistent tile creation; split/create-new-persistent-terminal adds a separate persistent tile without converting the temporary process.
- Terminal link/browser/file previews stay in the originating detached window and reuse canonical owners.
- Host-scoped editor leases prevent duplicate file surfaces across simultaneous main/detached Spotlights.
- Restore validation and active process-exit cleanup skip stale owners and release temporary resources without terminating persistent sessions.
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
| 2026-10-18 | Final audit fixes: documented AppContainer-backed detached terminal/ACP/VibeCast history parity and replaced obsolete temporary-terminal conversion wording with the implemented split/create-new-persistent-tile flow, which creates a separate persistent terminal. Static sources only; no tests or manual runs. | — |
| 2026-10-18 | Review added detached-local shelf/grid/combo parity, terminal-first two-pass catalog ordering plus built-in Vibe Lanes fallback, pane-local drafts/activation, temporary versus persistent creation routes, the Terminal/Agent/Browser/VibeCast/Vibe Lanes toolbar, local browser/file previews, host-scoped editor leases, restore validation, safe metadata, geometry-preserving surface persistence/reconciliation, and the unmet tile-logging target; later production-fix status is recorded above. | — |
| 2026-10-16 | Documented Spotlight shelf mirroring as a geometry-preserving operation: destination column/row slots retain their weights and primary/detached surfaces retain independent canonical member identities. | — |
| 2026-05-31 | Added R13/S13: minimized tab labels prefer the terminal tab title (project-title fallback), aligning with F001-R17 and Spotlight chip labeling. | — |
| 2026-04-27 | Clarified that board-window transfer preserves tile identity but recalculates destination-surface position. | — |
| 2026-04-26 | Marked implemented; added multi-window board support, local spotlight, surface-targeted terminal creation, context-menu transfer, and non-terminal tile transfer requirements. | Codex |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-034–036, TRM-039, TRM-069, TRM-070) | — |
