# VibeCast — Spec

Status: draft

## Overview

VibeCast provides a broadcast compose-and-send interface for dispatching text to terminal tabs. It supports targeted and broadcast messaging, message history, terminal target selection with keyboard cycling, toolbar and shortcut toggling, singleton tab behavior, board tile integration, spotlight navigation, and AI-powered rephrase.

## Dependencies

- F001 (Terminal Sessions & Tabs) — VibeCast sends text to terminal sessions
- F002 (Terminal Board) — VibeCast renders as a board tile
- F003 (Terminal Spotlight) — VibeCast participates in spotlight carousel
- F006 (Content Viewer) — VibeCast opens as a content viewer tab
- F029 (Text Services) — rephrase uses text-service CLI

## Requirements

### F028-R01: Broadcast Compose and Send

Users MUST be able to send messages to a targeted terminal tab or broadcast to all tabs. Message history MUST group consecutive messages by target and enforce a 500-message cap.

### F028-R02: Target Terminal Selection

Users MUST be able to select a target terminal from a popover grouped by project, cycle targets via keyboard, and have the target auto-sync when terminal tabs change.

### F028-R03: Toggle and Toolbar

VibeCast MUST toggle via Cmd+Shift+V and toolbar button, opening or focusing in the content viewer.

### F028-R04: Singleton Tab

Only one VibeCast tab MUST exist per editor group, backed by a shared VibeCastStore.

### F028-R05: Board Tile

VibeCast MUST render as a board tile with compose and message history, supporting select, close, spotlight actions, and codable persistence with backward compatibility.

### F028-R06: Spotlight

VibeCast MUST appear in the spotlight carousel, support restore, and open from board tile double-tap.

### F028-R07: Rephrase

Rephrase MUST invoke a configured text-service CLI and replace compose text on success, gracefully handling missing or failing CLI.

### F028-R08: Inline Insert Trigger

VibeCast compose inputs MUST support the inline insert trigger behavior defined in F038 (Terminal Inline Triggers). The resolved target terminal context MUST be used as the originating context. When VibeCast is hosted in a board tile, the picker MUST use the board-scoped popup presentation per F038-R07.

## Scenarios

### Scenario F028-S01: User sends a message to a targeted terminal tab

**Given** VibeCast is open and at least one terminal tab exists
**When** the user types a message in the compose area and sends it
**Then** the message is delivered to the resolved target terminal tab via `sendRawTextWithEnter`
**And** the message appears in the VibeCast message history with a timestamp
**And** the compose text is cleared

### Scenario F028-S02: User broadcasts a message to all terminal tabs

**Given** VibeCast is open and multiple terminal tabs exist across projects
**When** the user triggers the broadcast action
**Then** the compose text is sent to every available terminal tab
**And** a separate message history entry is recorded for each target tab
**And** the compose text is cleared

### Scenario F028-S03: Message history groups consecutive messages by target

**Given** VibeCast has sent messages to the same target terminal tab consecutively
**When** the message history renders
**Then** consecutive messages to the same target are grouped under a single target header
**And** a new group starts when the target changes

### Scenario F028-S04: Message history enforces a maximum of 500 messages

**Given** VibeCast message history contains 500 messages
**When** a new message is sent
**Then** the oldest message is removed to maintain the 500-message cap

### Scenario F028-S05: User selects a target terminal from the popover

**Given** VibeCast is open with multiple terminal sources
**When** the user opens the target selection popover
**Then** all terminal tabs are listed grouped by project with accent colors
**And** selecting a tab updates the active target
**And** the popover dismisses

### Scenario F028-S06: Target cycles through available terminals via keyboard

**Given** VibeCast compose area is focused
**When** the user triggers cycle-target-up or cycle-target-down
**Then** the target advances or retreats through the flat list of all tabs wrapping at boundaries

### Scenario F028-S07: Target auto-syncs when terminal tabs change

**Given** VibeCast has a selected target terminal tab
**When** that terminal tab is closed or the terminal source list changes
**Then** VibeCast falls back to the first available tab
**And** if no tabs remain the target is set to nil

### Scenario F028-S08: Cmd+number focuses a project and cycles its terminals

**Given** VibeCast is open and receives a `focusProjectByNumber` notification with an index
**When** the index maps to a valid terminal source
**Then** the first tab of that project becomes the target
**And** if the target is already in that project the next tab in the project is selected

### Scenario F028-S09: VibeCast toggles via keyboard shortcut Cmd+Shift+V

**Given** a vibespace is active
**When** the user presses Cmd+Shift+V
**Then** a `toggleVibeCast` notification is posted
**And** the vibespace canvas coordinator activates an existing VibeCast tab or opens a new one in the content viewer

### Scenario F028-S10: VibeCast toggles via toolbar button

**Given** a vibespace is active and the toolbar is visible
**When** the user clicks the VibeCast toolbar button (antenna icon)
**Then** the same `toggleVibeCast` notification is posted
**And** VibeCast opens or focuses in the content viewer

### Scenario F028-S11: Only one VibeCast tab exists per editor group

**Given** VibeCast is already open as a content viewer tab with id "vibeCast"
**When** `openVibeCast` is called again
**Then** the existing VibeCast tab is activated instead of creating a duplicate
**And** the single shared `VibeCastStore` instance on `ContentViewerStore` is used

### Scenario F028-S12: VibeCast renders as a board tile in terminal-only mode

**Given** the terminal board layout contains a tile with `contentKind == .vibeCast`
**When** the board renders tile cards
**Then** a `VibeCastBoardTileCard` is displayed with compose and message history
**And** the tile supports select, close, and spotlight actions

### Scenario F028-S13: VibeCast board tile is codable and persists across sessions

**Given** a board layout is saved with a VibeCast tile
**When** the layout is decoded on next launch
**Then** the tile restores with `contentKind == .vibeCast`
**And** legacy `isVibeCast` boolean encoding is supported for backward compatibility

### Scenario F028-S14: VibeCast appears in the spotlight carousel

**Given** at least one terminal tab exists or VibeCast already has a target
**When** the flat spotlight item list is built
**Then** a `.vibeCast` spotlight item is appended
**And** carousel swipe navigation can land on VibeCast

### Scenario F028-S15: VibeCast spotlight supports carousel and restore

**Given** VibeCast is presented as a spotlight
**When** the user swipes to another spotlight item and later returns
**Then** VibeCast spotlight is restored from a `.vibeCast` restore descriptor
**And** carousel navigation remains enabled (`supportsCarouselNavigation == true`)

### Scenario F028-S16: Double-tapping a VibeCast board tile opens spotlight

**Given** VibeCast is rendered as a board tile
**When** the user double-taps the tile header
**Then** VibeCast spotlight is presented via `onVibeCastSpotlightRequested`

### Scenario F028-S17: User rephrases compose text via external CLI tool

**Given** the compose area contains text and a text-service CLI is configured
**When** the user triggers rephrase
**Then** `isRephrasing` is set to true
**And** the configured CLI tool is invoked with the rephrase prompt template
**And** on success the compose text is replaced with the cleaned response
**And** `isRephrasing` is reset to false

### Scenario F028-S18: Rephrase gracefully handles missing or failing CLI

**Given** no text-service CLI command is configured or the command fails
**When** the user triggers rephrase
**Then** the compose text remains unchanged
**And** `isRephrasing` is reset to false

### Scenario F028-S19: VibeCast compose supports inline insert triggers

**Given** VibeCast is open with a resolved target terminal tab
**When** the user types the configured inline insert trigger in the compose input
**Then** the inline insert picker opens per F038 behavior using the resolved target terminal context
**And** path insertion, shortcut insertion, command generation, board popup presentation, and dismissal follow F038 scenarios

## Acceptance Criteria

- Message delivery to terminal completes within 100ms (PERF-3).
- Target selection popover renders within 200ms (PERF-3).
- Spotlight transitions complete within 300ms (PERF-3).
- Keyboard cycling is accessible (A11Y-2).
- All message sends are logged (OBS-1).

## Open Questions

- Should VibeCast support message templates or saved snippets?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/vibecast/feature.md (VBC-001 through VBC-018) | — |
| 2026-04-19 | Added VibeCast inline trigger behavior for content-viewer and spotlight compose inputs | Codex |
| 2026-04-20 | Added board-tile shared popup behavior for VibeCast inline triggers | Codex |
