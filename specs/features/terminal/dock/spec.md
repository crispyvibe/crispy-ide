# Terminal Board Dock — Spec

Status: draft

## Overview

Terminal Board Dock provides dockable content on the terminal board including file tiles, browser tiles, VibeCast tiles, and ACP tiles. Covers spotlight preview from terminal board, pin-to-board workflows, docked content persistence, spotlight integration for docked content, VibeCast/ACP board content, and board session/layout management.

## Dependencies

- F002 (Terminal Board) — dock tiles live on the terminal board
- F003 (Terminal Spotlight) — spotlight preview and pin workflows
- F012 (Browser) — browser tiles on board
- F006 (Content Viewer) and F008 (Markdown) — live editor groups and combined file/fragment navigation
- F007 (Editing) — file tiles use editor infrastructure
- F028 (VibeCast) — VibeCast tiles on board

## Requirements

### F037-R01: Spotlight Preview from Terminal Board

File explorer activation MUST open spotlight preview in terminal board mode; activating another file replaces the current preview.

### F037-R02: Pin Spotlight Content to Board

Pinning file or browser spotlight MUST create docked tiles on the board; pin MUST be rejected when board has no free capacity.

### F037-R03: Docked Content Persistence

Pinned file and browser tiles MUST persist across sessions; missing files MUST be pruned gracefully.

### F037-R04: Spotlight Integration for Docked Content

Double-click on docked tiles MUST open spotlight; pin routes to detailed content viewer when canvas mode is detailed.

### F037-R05: VibeCast and ACP Board Content

VibeCast and ACP sessions MUST be pinnable to board tiles with persistence and spotlight navigation.

### F037-R06: Board Session and Layout Management

Minimized tiles MUST persist; board MUST render drag/resize decorations; layout sync MUST update persisted state.

### F037-R07: Pinned Navigation Continuity and Atomic Promotion

A docked file tile MUST retain an immutable persisted root while preserving one live editor group whose mutable current linked file drives rendering, compact Back/Forward, title, directory, comments, provider, accessibility, Spotlight, and detailed promotion. Render lookup MUST NOT reopen the root. A browser tile, Spotlight, and linked detailed tab MUST share one canonical session or latest authoritative snapshot; closing detail MUST not revert the tile. Browser preview pinning MUST persist a complete snapshot before retiring the preview, and failed insertion MUST preserve the preview. Browser hydration MUST include primary and detached surfaces and both visible and minimized tiles; preview reuse MUST require matching project and snapshot identity.

## Scenarios

### Scenario F037-S01: File explorer activation opens spotlight preview in terminal board mode

**Given** user is on terminal board view
**When** user previews or opens a file from the file explorer
**Then** canvas mode remains terminalOnly
**And** the file is shown as a temporary spotlight preview over the board
**And** the file uses the existing editor/content-viewer infrastructure

### Scenario F037-S02: Activating another file replaces the current temporary preview

**Given** a temporary file spotlight preview is already visible over terminal board
**When** user activates a different file from the explorer
**Then** the spotlight preview content is replaced with the new file
**And** no second temporary preview stack entry is created from explorer activation alone

### Scenario F037-S03: Temporary board preview dismisses with standard spotlight gestures

**Given** a temporary file or browser preview is visible over terminal board
**When** user presses Escape or clicks outside the spotlight card
**Then** the temporary preview is dismissed using spotlight dismissal behavior

### Scenario F037-S04: Nested temporary board preview restores the previous spotlight item

**Given** user opened a temporary file, browser, or terminal preview from another spotlight item
**When** the nested preview is dismissed
**Then** the previous spotlight item is restored instead of clearing spotlight state

### Scenario F037-S05: Detailed-mode explorer activation continues to use the detailed editor surface

**Given** user is on the detailed vibespace canvas
**When** user previews or opens a file from the file explorer
**Then** the file opens in the detailed content viewer/editor surface
**And** no terminal-board spotlight preview is shown

### Scenario F037-S06: Pinning file spotlight in terminal-only mode creates a docked file tile

**Given** a file is open in spotlight preview
**And** canvas mode is terminal board
**When** user clicks the spotlight pin action
**Then** a docked file tile is created on the board
**And** the live editor group is assigned to that tile

### Scenario F037-S07: Pinning browser spotlight in terminal-only mode creates a docked browser tile

**Given** a browser is open in spotlight preview
**And** canvas mode is terminal board
**When** user clicks the spotlight pin action
**Then** a docked browser tile is created on the board
**And** the live browser session is assigned to that tile

### Scenario F037-S08: Pin action is rejected when the board has no free tile capacity

**Given** the terminal board has no remaining free tile capacity
**When** user attempts to pin file or browser spotlight content
**Then** no new docked tile is created
**And** the spotlight preview remains visible

### Scenario F037-S09: Pinned file and browser tiles support standard board interactions

**Given** a docked file tile or docked browser tile exists on the board
**When** user drags, resizes, swaps, minimizes, restores, or focuses that tile
**Then** the tile follows the same board interaction rules as terminal tiles

### Scenario F037-S10: Pinned content tiles can be minimized and restored

**Given** a docked file tile or docked browser tile exists on the board
**When** user minimizes the tile
**Then** the tile moves into the minimized tab bar
**And** user can restore it back onto the board

### Scenario F037-S11: Pinned file tiles persist across sessions

**Given** a docked file tile exists on the terminal board
**When** the vibespace is closed and reopened
**Then** the file tile is restored in the same board position
**And** the file content reopens from the persisted path

### Scenario F037-S12: Pinned browser tiles persist across sessions

**Given** a docked browser tile exists on the terminal board
**When** the vibespace is closed and reopened
**Then** the browser tile is restored in the same board position
**And** the persisted browser session snapshot is restored

### Scenario F037-S13: Missing persisted file tile is pruned gracefully

**Given** a persisted file tile references a file that no longer exists
**When** the vibespace is reopened
**Then** the missing tile is removed from board layout restoration without crashing

### Scenario F037-S14: Double-click docked file tile opens file spotlight

**Given** a docked file tile exists on the terminal board
**When** user double-clicks the tile content
**Then** the file opens in spotlight mode using the same file viewer state

### Scenario F037-S15: Double-click docked browser tile opens browser spotlight

**Given** a docked browser tile exists on the terminal board
**When** user double-clicks the tile content
**Then** the browser opens in spotlight mode using the same browser session state

### Scenario F037-S16: Spotlight pin routes to detailed content viewer when canvas mode is detailed

**Given** spotlight is showing file or browser content
**And** canvas mode is detailed
**When** user clicks the spotlight pin action
**Then** the content is promoted into the detailed content viewer
**And** no board tile is created

### Scenario F037-S17: Detailed-mode file spotlight keeps pin available for both preview and docked spotlight content

**Given** canvas mode is detailed
**And** spotlight is showing file content from either a temporary preview or a docked file tile
**When** spotlight chrome renders
**Then** the pin action remains available
**And** using that pin action promotes the file into the detailed content viewer instead of the terminal board

### Scenario F037-S18: Detailed-mode pin remains available even when terminal board capacity is exhausted

**Given** canvas mode is detailed
**And** spotlight is showing file or browser content
**And** the terminal board has no remaining free tile capacity
**When** user clicks the spotlight pin action
**Then** the content is still promoted into the detailed content viewer
**And** board capacity does not block the detailed-mode pin action

### Scenario F037-S19: Temporary previews are excluded from spotlight carousel navigation

**Given** spotlight is showing a temporary file or browser preview
**When** spotlight chrome renders
**Then** carousel navigation controls are hidden
**And** swipe-based spotlight navigation is disabled for that preview

### Scenario F037-S20: Docked file and browser tiles appear in persistent spotlight navigation

**Given** docked file tiles, docked browser tiles, or persistent terminal spotlight items exist
**When** user navigates spotlight carousel for persistent content
**Then** docked file and browser items participate in that navigation sequence

### Scenario F037-S21: Terminal-only board pin is available only for transient file and browser previews

**Given** canvas mode is terminal board
**When** spotlight is showing a temporary file preview or temporary browser preview
**Then** spotlight chrome shows a board pin action
**When** spotlight is showing a docked file tile or docked browser tile in spotlight
**Then** spotlight chrome does not show a second board pin action

### Scenario F037-S22: VibeCast tile content kind on board

**Given** canvas mode is terminal board
**When** a VibeCast session is pinned to the board
**Then** a docked VibeCast tile is created
**And** the tile renders live VibeCast content and follows standard board interaction rules

### Scenario F037-S23: ACP tile content kind on board with persistence

**Given** canvas mode is terminal board
**When** an ACP session is pinned to the board
**Then** a docked ACP tile is created
**And** the tile renders live ACP content
**And** the ACPStandalonePaneSnapshot is persisted for session restoration

### Scenario F037-S24: ACP and VibeCast spotlight navigation

**Given** docked ACP tiles or docked VibeCast tiles exist on the board
**When** user navigates spotlight carousel for persistent content
**Then** ACP and VibeCast items participate in the navigation sequence alongside other docked content

### Scenario F037-S25: Minimized tiles persistence across sessions

**Given** one or more tiles are minimized in the tab bar
**When** the vibespace is closed and reopened
**Then** minimized tiles are restored in the minimized tab bar in their previous order

### Scenario F037-S26: Board interaction decorations during drag and resize

**Given** a tile on the terminal board is being dragged or resized
**When** the interaction is in progress
**Then** the board renders visual decorations indicating drop targets or resize constraints

### Scenario F037-S27: Board metrics calculation

**Given** the terminal board layout has changed
**When** board metrics are recalculated
**Then** tile positions, sizes, and capacity reflect the current board dimensions and tile count

### Scenario F037-S28: Board layout sync

**Given** a board layout change occurs from drag, resize, pin, minimize, or restore
**When** the change is committed
**Then** the persisted board layout state is updated to match the current arrangement

### Scenario F037-S29: Board chrome toolbar UI

**Given** the terminal board is visible
**When** board chrome toolbar renders
**Then** it displays controls for board-level actions including layout management and tile operations

### Scenario F037-S30: Pinned Markdown tile keeps current linked file through rerender

**Given** a file preview rooted at `A.md` follows `B.md#fragment`
When the preview is pinned and its dock tile rerenders
Then the tile keeps the same live editor group current on `B.md`
And the persisted root remains `A.md`
And visible Back/Forward and ⌘[/⌘] traverse fragment and cross-file history
And title, directory, comments, provider, accessibility, Spotlight, and detailed promotion use `B.md`

### Scenario F037-S31: Linked browser detail close preserves board history

**Given** a board browser navigates `A → B → C` and opens a linked detailed presentation
When the detailed presentation closes
Then the board remains at the latest canonical URL and history
And Back/Forward continue from C rather than reverting to the seed or a stale board snapshot

### Scenario F037-S32: Browser pin commits immediately and failed pin is non-destructive

**Given** a temporary browser preview has current URL and history
When board insertion succeeds
Then its complete snapshot and tile identity are persisted in one promotion flow before preview retirement
When board insertion fails because the target surface cannot accept the tile
Then no partial tile is persisted and the live preview remains visible and retryable

### Scenario F037-S33: Browser restore covers detached and minimized surfaces

**Given** persisted browser tiles exist on primary or detached board surfaces in visible or minimized state
When board hydration runs
Then every matching tile snapshot is restored by stable tile identity
And no stale preview from another project or snapshot is reused

## Test Coverage

| Scenario | Coverage |
|----------|----------|
| F037-S30 | Unit: editor-group and Markdown state regressions cover linked navigation, stable root lookup, command consumption, per-document history, and provider identity. Required UI/manual: pin/rerender continuity plus compact metadata, comments, accessibility, and controls. |
| F037-S31 | Unit: browser coordinator regressions cover shared ownership and decoded legacy stale-clone close without board reversion. Required UI/manual: board/detail chrome remains synchronized. |
| F037-S32 | Unit: board pin tests verify immediate persisted snapshots and non-mutating full-board rejection; coordinator tests verify promotion state. Required UI/manual: rejected pin leaves the preview visibly retryable. |
| F037-S33 | Unit: board/coordinator regressions cover detached/minimized snapshot enrichment and cross-project preview isolation. Required UI/manual: launch-time hydration renders each WebView surface. |

## Acceptance Criteria

- File and browser tiles pin to board within 100ms.
- Docked tiles persist and restore across sessions.
- Missing file tiles prune without crash.
- Spotlight carousel includes docked content.
- Board layout sync persists on every change.
- File root identity remains stable while the live current linked file drives compact UI and promotion.
- Browser promotion, linked detail close, and all-surface hydration preserve the latest canonical snapshot without stale preview reuse.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-06 | Added pinned Markdown current-file continuity, canonical browser session/detail-close behavior, atomic preview persistence, all-surface hydration, stale-preview isolation, and S30–S33 test mappings (R07). | — |
| 2026-04-15 | Migrated from docs/features/terminal-board-dock/feature.md (DCK-001–026) | — |
