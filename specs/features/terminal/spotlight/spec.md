# Terminal Spotlight — Spec

Status: draft

## Overview

Terminal Spotlight provides a centered overlay mode for focusing on a single terminal session. It supports temporary and persistent spotlight surfaces, carousel navigation via swipe, nested restore chains, and compose input. Spotlight can be triggered from board tiles, rail cards, shortcut commands, and session previews.

## Dependencies

- F001 (Sessions & Tabs) — spotlight surfaces host terminal sessions
- F002 (Terminal Board) — double-click tile opens spotlight; minimized tiles open in spotlight
- F004 (Terminal Rail) — double-click rail card opens spotlight

## Requirements

### F003-R01: Board Temporary Spotlight Focus

When user double-clicks a board tile, a centered `Terminal Spotlight` overlay MUST open for that tile terminal. Board layout columns/rows and tile positions MUST remain unchanged. Spotlight MUST be dismissible by double-click, `Esc`, or clicking outside overlay. Dismissal MUST return attention to the original board layout state.

### F003-R02: Swipe to Switch Terminals in Spotlight

When user performs a two-finger horizontal trackpad swipe on the spotlight card, spotlight MUST transition to the next (swipe left) or previous (swipe right) item in vibespace order. The transition MUST use a horizontal slide animation. The swipe sequence MUST wrap around at boundaries. The target terminal MUST receive keyboard focus automatically. VibeCast spotlight MUST hide the terminal compose bar and auto-focus its own compose input. Transient/temporary spotlight terminals MUST NOT support swipe-to-switch.

### F003-R03: Stacked Rail Temporary Spotlight Focus

When user double-clicks a stacked rail terminal card, a centered `Terminal Spotlight` overlay MUST open for that card terminal. Focused project/editor/file preview state MUST remain unchanged. Stacked rail layout MUST remain unchanged. Spotlight MUST be dismissible by double-click, `Esc`, or clicking outside overlay.

### F003-R04: Double-Click Toggles Expanded Terminal Overlay

When user double-clicks a terminal session view, the session MUST open in a centered expanded overlay. Double-clicking the expanded session MUST return it to the original layout.

### F003-R05: Temporary Spotlight Restore Chain

When a temporary spotlight is dismissed, the previous spotlight item MUST be restored. Spotlight state MUST be cleared only when no restore target remains.

### F003-R06: Temporary Spotlight Excludes Carousel Navigation

When spotlight shows a temporary terminal, file preview, or browser preview, carousel navigation controls MUST be hidden and swipe-based switching MUST be disabled.

### F003-R07: Temporary Spotlight Dismissal Consistency

When user dismisses a temporary spotlight with the close button, `Escape`, or backdrop click, the previous spotlight item MUST be restored if a restore target exists. The spotlight MUST be fully dismissed only when no restore target exists.

### F003-R08: Temporary Terminal Process Exit Restores Previous Spotlight

When a temporary terminal process exits on its own, the previous spotlight item MUST be restored if a restore target exists. Spotlight state MUST be cleared only when no restore target remains.

### F003-R09: Compose Bar Terminal Input

When the compose bar is visible in spotlight, TerminalComposeInputView MUST provide a text input field. Submitted input MUST be dispatched to the active terminal session.

### F003-R10: Compose Input Focus Retention

When the spotlight compose input is focused, terminal-output interactions that do not explicitly switch keyboard focus to another input MUST leave keyboard focus on the compose input. Opening or using terminal link and file actions MUST NOT pull focus away from the compose input unless the user directly focuses the terminal session.

### F003-R11: Spotlight Compose Input Supports Inline Insert Triggers

Spotlight compose input MUST support the inline insert trigger behavior defined in F038 (Terminal Inline Triggers). The spotlight terminal context MUST be used as the originating context for path resolution and shortcut filtering. When the spotlight is hosted in a board layout, the picker MUST use the board-scoped popup presentation per F038-R07.

### F003-R12: Spotlight Tab Strip Overflow Controls

When the spotlight carousel has more tabs than fit in the tab strip window, the strip MUST expose left and right page controls whenever hidden tabs exist on that side. Activating either control MUST shift the visible strip window toward the hidden tabs without switching the active spotlight item. The active spotlight item MUST remain visible after carousel switches, direct tab clicks, and page-control use.

### F003-R13: Spotlight Tab Strip Reordering

When the user drags a persistent terminal tab chip in the spotlight tab strip, the strip MUST show browser-style reorder feedback: the dragged chip is visually lifted/dimmed, a narrow insertion marker appears before or after the hovered target based on pointer position, and terminal chips move by stable Spotlight identity as the drag crosses valid terminal targets. The final order MUST be committed in the same ordering model that produced the visible Spotlight carousel. Reordering MUST NOT terminate sessions, change the active terminal selection, or resize tab chips during drag/drop feedback. VibeSpace Spotlight MUST support cross-project terminal reordering. Non-terminal spotlight items MUST NOT be reordered by this interaction.

VibeSpace Spotlight MUST persist terminal-tab reordering through a vibespace-level Spotlight order field in centralized vibespace persistence, keyed by stable terminal identity, not through any single project's terminal tab order. Terminal-board Spotlight MUST persist terminal-tab reordering through the board layout tile order for the active board surface. The reordered sequence MUST define subsequent Spotlight carousel order for that host.

Persisted terminal session entries MUST carry stable terminal tab IDs. VibeSpace Spotlight order entries MUST include enough scope to disambiguate cross-project tabs, such as project identity plus terminal tab ID. Spotlight tab reordering MUST persist the reordered terminal identity sequence so the order survives Spotlight close/reopen and vibespace restore, including projects with multiple tabs that share the same working directory, name, origin, or tmux state.

### F003-R14: Spotlight Activity Animation Visibility

When a terminal represented in the spotlight tab strip is active, its tab chip MUST show a clearly visible animated bottom underline in addition to the narrow activity bar. The animation MUST be drawn inside the chip's existing bounds and MUST NOT change chip size, tab-strip height, or neighboring tab positions while animating.

## Scenarios

### Scenario F003-S01: Terminal board supports temporary spotlight focus

**Given** terminal board has at least one tile terminal
**When** user double-clicks a tile
**Then** a centered `Terminal Spotlight` overlay opens for that tile terminal
**And** board layout columns/rows and tile positions are unchanged
**And** user can dismiss spotlight by double-click, `Esc`, or clicking outside overlay
**And** dismissed spotlight returns attention to the original board layout state

### Scenario F003-S02: Swipe to switch terminals and VibeCast in spotlight

**Given** `Terminal Spotlight` is open for a persistent terminal or VibeCast
**And** the vibespace has more than one swipeable item (terminal tabs across all projects plus VibeCast)
**When** user performs a two-finger horizontal trackpad swipe on the spotlight card
**Then** spotlight transitions to the next (swipe left) or previous (swipe right) item in vibespace order
**And** the transition uses a horizontal slide animation matching swipe direction
**And** the swipe sequence wraps around at boundaries
**And** the target terminal receives keyboard focus automatically after transition
**And** VibeCast spotlight hides the terminal compose bar and auto-focuses its own compose input
**And** transient/temporary spotlight terminals do not support swipe-to-switch

### Scenario F003-S03: Stacked rail supports temporary spotlight focus

**Given** detailed view shows stacked project rail cards
**When** user double-clicks a stacked rail terminal card
**Then** a centered `Terminal Spotlight` overlay opens for that card terminal
**And** focused project/editor/file preview state remains unchanged
**And** stacked rail layout remains unchanged
**And** user can dismiss spotlight by double-click, `Esc`, or clicking outside overlay

### Scenario F003-S04: Double-click toggles centered expanded terminal overlay

**Given** a terminal session view is visible
**When** user double-clicks the session
**Then** the session opens in a centered expanded overlay
**And** double-clicking the expanded session returns it to the original layout

### Scenario F003-S05: Dismissing a nested temporary spotlight restores the previous spotlight item

**Given** a temporary terminal, file preview, or browser preview was opened from another spotlight item
**When** user dismisses the temporary spotlight
**Then** the previous spotlight item is restored
**And** spotlight state is cleared only when no restore target remains

### Scenario F003-S06: Temporary spotlight previews do not participate in carousel navigation

**Given** spotlight is showing a temporary terminal, file preview, or browser preview
**When** spotlight chrome renders
**Then** carousel navigation controls are hidden
**And** swipe-based spotlight switching is disabled for that temporary preview

### Scenario F003-S07: Temporary spotlight dismissal rules apply consistently across close affordances

**Given** spotlight is showing a temporary terminal, file preview, or browser preview
**When** user dismisses it with the close button, `Escape`, or backdrop click
**Then** the previous spotlight item is restored if a restore target exists
**And** the spotlight is fully dismissed only when no restore target exists

### Scenario F003-S08: Temporary terminal process exit restores the previous spotlight when possible

**Given** a temporary terminal spotlight was opened from another spotlight item
**When** that temporary terminal process exits on its own
**Then** the previous spotlight item is restored if a restore target exists
**And** spotlight state is cleared only when no restore target remains

### Scenario F003-S09: Compose bar provides terminal input

**Given** a terminal session is active
**When** the compose bar is visible
**Then** TerminalComposeInputView provides a text input field for composing terminal commands
**And** submitted input is dispatched to the active terminal session
**And** `Command` + `Return` dispatches the compose draft to the active terminal session when the compose field is focused
**And** `Command` + `Return` remains available from the visible compose send action after tab-strip or header interactions move keyboard focus away from the compose field

### Scenario F003-S10: Spotlight compose input keeps focus during non-terminal actions

**Given** spotlight compose input is focused
**When** the user triggers a terminal output action that does not explicitly focus the terminal session
**Then** the spotlight compose input remains the keyboard focus target
**And** subsequent typing continues in the compose input

### Scenario F003-S11: Spotlight compose input supports inline insert triggers

**Given** spotlight compose input is focused
**When** the user types the configured inline insert trigger
**Then** the inline insert picker opens per F038 behavior
**And** the picker resolves against the spotlight terminal context
**And** path insertion, shortcut insertion, command generation, and dismissal follow F038 scenarios F038-S02, F038-S03, F038-S04, and F038-S06

### Scenario F003-S12: Spotlight tab strip pages left and right

**Given** `Terminal Spotlight` is open for a persistent carousel item
**And** the spotlight tab strip has hidden items to the left or right of the visible window
**When** the user clicks the corresponding strip page control
**Then** the visible tab window shifts toward those hidden items
**And** the spotlight content does not switch because of paging alone
**And** the active spotlight item remains visible after subsequent carousel switches

### Scenario F003-S13: VibeSpace Spotlight terminal tabs can be reordered across projects

**Given** vibespace `Terminal Spotlight` is open with two or more persistent terminal tabs from one or more projects
**When** the user drags one terminal tab chip and drops it on another terminal tab chip from the vibespace
**Then** the hovered tab shows a before/after insertion marker based on pointer position
**And** the dragged chip is visually lifted or dimmed without changing tab-strip layout
**And** terminal chips move by stable Spotlight identity while the drag crosses valid targets
**And** the vibespace-level Spotlight order updates to match the insertion marker
**And** later spotlight carousel navigation follows the updated order
**And** closing and reopening Spotlight preserves the reordered tab sequence
**And** vibespace restore preserves the reordered tab sequence by project identity and terminal tab ID
**And** terminal sessions keep running and the active terminal selection is unchanged
**And** non-terminal items are not reordered

### Scenario F003-S14: Terminal-board Spotlight terminal tabs can be reordered within the active surface

**Given** terminal-board `Terminal Spotlight` is open with two or more persistent terminal tab tiles on the active board surface
**When** the user drags one terminal tab chip and drops it on another terminal tab chip from that surface
**Then** the hovered tab shows a before/after insertion marker based on pointer position
**And** the dragged chip is visually lifted or dimmed without changing tab-strip layout
**And** terminal chips move by stable board tile identity while the drag crosses valid targets
**And** the active board surface's linear tile order updates to match the insertion marker
**And** the board grid shape, tile count, running sessions, and active terminal selection are unchanged
**And** later terminal-board Spotlight carousel navigation follows the updated board tile order
**And** closing and reopening terminal-board Spotlight preserves the reordered board sequence
**And** vibespace restore preserves the reordered terminal-board sequence by board tile identity and terminal tab identity
**And** non-terminal items are not reordered

### Scenario F003-S15: Spotlight active tab activity animation is prominent and stable

**Given** a terminal represented in the spotlight tab strip is active
**When** its tab chip renders activity feedback
**Then** the chip shows both the narrow activity bar and an animated bottom underline inside the chip
**And** the chip and tab strip keep stable dimensions throughout the animation

## Test Coverage

| Scenario | Coverage |
|----------|----------|
| F003-S09 | Unit or UI regression MUST verify `Command` + `Return` sends from the Spotlight compose box while the compose field is focused and after focus moves to Spotlight chrome. |
| F003-S12 | View regression MUST verify left/right strip controls appear only when hidden items exist and page the strip without switching the active Spotlight item. |
| F003-S13 | VibeSpace Spotlight order tests MUST verify cross-project reorder persistence by project identity plus terminal tab ID, including close/reopen and vibespace restore. |
| F003-S14 | `VibeSpaceTerminalBoardStoreAddTileTests.testMoveTerminalTabTileReordersBoardLinearOrder` covers terminal-board tile reorder state; persistence coverage MUST verify board layout restore preserves the reordered tile sequence. |
| F003-S15 | View regression MUST verify the active-tab underline animates inside fixed chip bounds without changing tab-strip height or neighboring chip positions. |

## Acceptance Criteria

- Spotlight open/close transitions complete within 200ms (PERF-3).
- Swipe transitions complete within 300ms (PERF-3).
- Restore chain correctly unwinds for up to 3 nested spotlights (REL-1).
- Keyboard focus is correctly routed after spotlight transitions (A11Y-2).
- Spotlight compose input retains focus during non-focus-changing terminal output actions (A11Y-2).
- Spotlight compose inline trigger actions never auto-execute commands (A11Y-2).
- Spotlight tab strip overflow controls expose hidden items in both directions without switching content.
- Spotlight terminal tab reordering persists through the carousel host's source of truth: vibespace-level Spotlight order for vibespace Spotlight and board layout tile order for terminal-board Spotlight.
- Spotlight terminal tab reordering preserves running sessions, active selection, and board grid shape.
- Spotlight active-tab animation remains contained within existing tab-chip bounds.
- Spotlight operations logged (OBS-1).

## Open Questions

- Should spotlight support pinch-to-resize?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-27 | Clarified cross-project vibespace Spotlight ordering and separate terminal-board Spotlight reorder persistence requirements. | — |
| 2026-04-26 | Added tab-strip overflow, reorder, and prominent activity animation requirements. | — |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-036A–C, TRM-040, TRM-047–048, TRM-052–053, TRM-067) | — |
