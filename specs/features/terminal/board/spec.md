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

### Scenario F002-S19: Project cleanup removes owned members across every surface

**Given** a project owns visible, minimized, and Spotlight members on primary and detached board surfaces
**When** project park or remove supplies frozen ownership evidence to the board store
**Then** one normalized and persisted mutation removes every proven owned tile from all visible and minimized collections
**And** every matching Spotlight member is removed
**And** unrelated or ambiguous tiles remain

### Scenario F002-S20: Tile ownership decodes and migrates safely

**Given** persisted board tiles were written before `projectIdentifier` existed
**When** board state decodes and `syncProjects` reconciles current projects
**Then** the missing optional field decodes without invalidating the layout
**And** a host-qualified owner is stamped only when one project is uniquely provable
**And** ambiguous legacy remote raw-root-only tiles remain unstamped and retained

### Scenario F002-S21: Same remote root on different hosts remains isolated

**Given** two SSH projects use the same raw root on different hosts
**And** their board runtime contexts use distinct host-qualified project identifiers
**When** either project is synchronized, parked, removed, restored, or opened in Spotlight
**Then** subscriptions, terminal context, reconciliation, tile ownership, and Spotlight identity remain scoped to the correct host
**And** the other host's panes are not removed or adopted

### Scenario F002-S22: Cleanup recognizes all supported project-owned tile kinds

**Given** project-owned terminal, browser, file, and ACP tiles exist
**When** automatic project cleanup evaluates ownership
**Then** terminal and browser `projectIdentifier` evidence is accepted
**And** terminal tab membership may prove a legacy remote terminal owner
**And** a stamped file `projectIdentifier` is accepted
**And** an unstamped local file is matched only by root containment with a path-component boundary
**And** ACP ownership uses `selectedProjectIdentifier`

### Scenario F002-S23: Empty detached surfaces close after project cleanup

**Given** cleanup removes the final visible, minimized, and Spotlight members from a detached surface
**When** the board mutation normalizes
**Then** the empty detached surface is removed from persisted state
**And** its managed window closes
**And** no stale blank surface is restored

### Scenario F002-S24: Restored project content retains unique ownership

**Given** an unparked project has pinned browser snapshots and terminal session entries
**When** restoration runs
**Then** each pinned browser tile and view model is recreated on the primary surface with its original tile ID, snapshot, and unique project owner
**And** terminal reconciliation recreates restored project terminals
**And** user-initiated remote tile drag behavior remains unchanged

### Scenario F002-S25: Remote file and web routes retain their host-qualified owner

**Given** two SSH projects share a raw root path
**When** a terminal target, dock preview, main or detached Spotlight file/browser/link route, or restored persistent Spotlight identity is created
**Then** the originating host-qualified `projectIdentifier` reaches provider lookup, document/tile ownership, and navigation identity
**And** `ssh://` survives Spotlight Codable round-trip verbatim
**And** a legacy remote file tile migrates before local stale-file pruning when uniquely owned
**And** an ambiguous legacy remote tile is retained rather than guessed or deleted

### Scenario F002-S26: Send All moves only the initiating unique owner

**Given** two SSH projects use the same raw root on different hosts
**When** Send All From This Project is invoked from one owned tile
**Then** the operation uses that tile's unique `projectIdentifier`
**And** only tiles with that owner move to the new board window
**And** the other host's tiles remain on the source surface

### Scenario F002-S27: Every Spotlight route retains the exact project owner

**Given** two SSH projects share a raw root but have different host-qualified identifiers
**When** Spotlight is entered from any main or detached direct, temporary, project-shortcut, split, permanent-terminal, ACP, link, file, browser, editor-pane, restore, or detached-attachment route
**Then** `owningProjectIdentifier` remains the originating project's exact identifier
**And** project/provider lookup does not fall back to the other same-root host
**And** detached attachment copies the identifier unchanged
**And** any nested split, permanent creation, preview, or shortcut action continues with that same owner

## Automatic Project Cleanup Requirements

### F002-R19: Migration-Safe Project Ownership

`VibeSpaceTerminalBoardTile` MUST support an optional Codable `projectIdentifier`. Missing ownership MUST decode as legacy state. `syncProjects` MUST stamp or migrate a host-qualified owner only when ownership is uniquely provable.

### F002-R20: Atomic Multi-Surface Project Cleanup

Given frozen project ownership evidence, the board store MUST perform one normalized and persisted mutation that removes every proven project-owned tile from visible and minimized collections across primary and detached surfaces and removes every corresponding Spotlight member.

### F002-R21: Evidence-Based, Fail-Closed Matching

Cleanup MUST recognize terminal/browser tile `projectIdentifier`, terminal tab membership for legacy remote terminal tiles, component-boundary local file-root containment, stamped file `projectIdentifier`, and ACP `selectedProjectIdentifier`. Same raw remote roots on different SSH hosts MUST remain isolated; ambiguous legacy remote raw-root-only tiles MUST be retained.

### F002-R22: Empty Detached Surface Lifecycle

Normalization after cleanup MUST remove empty detached surfaces, persist their absence, and cause the managed detached windows to close.

### F002-R23: Host-Qualified Remote Runtime Identity

Remote board runtime terminal subscriptions, project context, reconciliation, tile ownership, and Spotlight member identities MUST use the host-qualified project owner rather than raw remote root text. Existing remote drag/transfer behavior MUST remain unchanged.

### F002-R24: Ownership-Preserving Project Restoration

Unpark restoration MUST recreate pinned browser tiles and browser view models on the primary surface with the original tile ID, browser snapshot, and unique owner. Terminal reconciliation MUST recreate restored project terminals.

### F002-R25: Host-Qualified File, Web, and Spotlight Routing
`TerminalFileSystemTarget`, `DockPreviewBridge`, and main/detached Spotlight file, browser, and link routes MUST preserve the host-qualified `projectIdentifier` through provider resolution, document identity, pinning, and navigation. `SpotlightPersistentItemID` Codable MUST preserve `ssh://` identifiers verbatim rather than normalize them as local paths. Legacy remote file tiles MUST be migrated before local missing-file pruning; uniquely owned tiles are stamped, while ambiguous remote tiles remain fail-closed.

### F002-R26: Unique Send-All Ownership
Send All From This Project MUST select tiles by the unique `projectIdentifier` carried by the initiating tile/context. It MUST NOT bulk-move another SSH project's tiles merely because both projects expose the same raw remote root.

### F002-R27: Complete Project-Qualified Spotlight Routing
`TerminalSpotlightState.owningProjectIdentifier` MUST retain the exact `projectIdentifier` through main-window and detached-window direct presentation, temporary terminal creation, project-scoped shortcut dispatch, split and permanent-terminal creation, ACP presentation, link activation, file and browser preview/persistent presentation, editor-pane routes, restoration, and detached attachment. Provider/project lookup MUST prefer that identifier over raw-root inference, and `DetachedSpotlightStateFactory.attach` MUST copy it unchanged. Same-root SSH projects MUST therefore remain distinct throughout every route.

## Static Coverage Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static source includes board same-root isolation, dock-preview identity, legacy remote-file migration-before-prune, fail-closed removal, and verbatim SSH Spotlight Codable cases. `SpotlightEnhancementTests.testDetachedFactoryAttachesEveryDirectKindAndRetainsCanonicalCallbacksAndIdentity` directly checks that every direct persistent kind copied by detached attachment retains `owningProjectIdentifier` and callbacks. `testDetachedTemporaryShortcutRouterDispatchesCurrentNestedAndPermanentExactlyOnce` directly checks the detached temporary shortcut router, and `testDetachedPermanentStandaloneShortcutCreatesTileOnlyOnOriginatingSurface` checks surface-local permanent creation. These tests still do not mount both hosts or exercise the complete direct/temporary/split/permanent/ACP/link/file/browser/editor route matrix. Remaining nested routes, unique-owner Send All, managed-window closure, and unpinned cleanup were verified by static production-source inspection only.

## Acceptance Criteria

- Project lifecycle cleanup removes every proven owned visible/minimized tile and Spotlight member from primary and detached surfaces in one normalized/persisted mutation.
- Optional tile `projectIdentifier` decoding preserves legacy layouts, while `syncProjects` stamps only uniquely proven host-qualified owners.
- Terminal/browser owner stamps, legacy terminal-tab evidence, component-boundary local file containment, stamped file ownership, and ACP selected-project ownership are recognized; ambiguous remote raw-root-only tiles remain.
- Same raw roots on different SSH hosts remain isolated through runtime subscriptions, context, reconciliation, cleanup, and Spotlight identity.
- Empty detached surfaces normalize away and their managed windows close.
- Unpark restores pinned browsers on primary with original tile ID/snapshot/owner, and terminal reconciliation recreates restored terminals.
- Remote drag and transfer semantics remain unchanged.
- Terminal targets, dock previews, main/detached file/web/link Spotlight routes, and Spotlight Codable preserve host-qualified project identity; legacy remote file migration precedes local stale pruning and ambiguous tiles fail closed (F002-R25).
- Send All selects the initiating tile's unique owner and cannot merge same-root projects across hosts (F002-R26).
- Every main/detached direct, temporary, shortcut, split, permanent, ACP, link, file, browser, editor-pane, restore, and detached-attachment Spotlight route retains the exact owner, including nested actions (F002-R27).

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
| 2026-10-23 | Final production reconciliation corrected static route coverage for detached direct kinds, temporary shortcut dispatch, and originating-surface permanent creation; validation is build/test-build only with no executed test pass. | — |
| 2026-10-23 | Added F002-R27/S27 for exact project identity across the complete main/detached Spotlight route matrix and detached attachment; narrowed full-route verification to production-source inspection and retained static/build-only status. | — |
| 2026-10-23 | Added F002-R25–R26/S25–S26 for host-qualified file/web/Spotlight routing, remote-file migration-before-prune, verbatim ssh Codable, fail-closed legacy retention, and unique-owner Send All; refreshed compile/static-only coverage. | — |
| 2026-10-20 | Added implemented automatic project-cleanup requirements F002-R19–R24 and scenarios F002-S19–S24: migration-safe ownership, one cross-surface mutation, evidence-based fail-closed matching, detached-window cleanup, host-qualified remote identity, and restoration. Static evidence reached build/test-build only; no executed pass is claimed. | — |
| 2026-10-18 | Final audit fixes: documented AppContainer-backed detached terminal/ACP/VibeCast history parity and replaced obsolete temporary-terminal conversion wording with the implemented split/create-new-persistent-tile flow, which creates a separate persistent terminal. Static sources only; no tests or manual runs. | — |
| 2026-10-18 | Review added detached-local shelf/grid/combo parity, terminal-first two-pass catalog ordering plus built-in Vibe Lanes fallback, pane-local drafts/activation, temporary versus persistent creation routes, the Terminal/Agent/Browser/VibeCast/Vibe Lanes toolbar, local browser/file previews, host-scoped editor leases, restore validation, safe metadata, geometry-preserving surface persistence/reconciliation, and the unmet tile-logging target; later production-fix status is recorded above. | — |
| 2026-10-16 | Documented Spotlight shelf mirroring as a geometry-preserving operation: destination column/row slots retain their weights and primary/detached surfaces retain independent canonical member identities. | — |
| 2026-05-31 | Added R13/S13: minimized tab labels prefer the terminal tab title (project-title fallback), aligning with F001-R17 and Spotlight chip labeling. | — |
| 2026-04-27 | Clarified that board-window transfer preserves tile identity but recalculates destination-surface position. | — |
| 2026-04-26 | Marked implemented; added multi-window board support, local spotlight, surface-targeted terminal creation, context-menu transfer, and non-terminal tile transfer requirements. | Codex |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-034–036, TRM-039, TRM-069, TRM-070) | — |
