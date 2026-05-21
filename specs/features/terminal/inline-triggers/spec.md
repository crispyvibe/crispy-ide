# Terminal Inline Triggers — Spec

Status: draft

## Overview

Terminal Inline Triggers provide a settings-backed typed trigger that opens a contextual insert picker from terminal-adjacent input surfaces. The picker lets users insert file or directory paths, insert saved terminal shortcuts, or route the current request into the built-in command generation action without leaving the current typing flow.

The feature is shared across direct terminal input, terminal spotlight compose, ACP compose, and VibeCast compose. Dense board layouts use one board-scoped popup so the picker does not resize or disturb the owning tile.

## Dependencies

- F001 (Terminal Sessions & Tabs) — inline triggers resolve against a terminal session context
- F002 (Terminal Board) — board layouts host the shared board popup
- F003 (Terminal Spotlight) — spotlight compose uses the same trigger model
- F011 (ACP) — ACP compose integrates the shared trigger behavior
- F016 (Keyboard Shortcuts) — trigger symbol and shortcut management depend on settings-backed shortcut infrastructure
- F028 (VibeCast) — VibeCast compose integrates the same picker behavior
- F034 (SSH Remote Development) — remote terminals provide the execution context for future remote path resolution

## Requirements

### F038-R01: Configurable Typed Trigger

Inline triggers MUST be activated by a settings-backed typed trigger token rather than a hardcoded character. The default trigger MAY be provided by product defaults, but users MUST be able to change it through settings.

### F038-R02: Token-Scoped Activation

The picker MUST open only for the active trigger token in the current draft or terminal input stream. Normal typing outside that token MUST remain unchanged.

### F038-R03: Literal-Safe Editing and Dismissal

Dismissing the picker MUST preserve the current draft text. After dismissal, the same trigger token MUST remain suppressed until the user edits past that token boundary or starts a new trigger token. Inline trigger behavior MUST never make it impossible to continue normal typing.

### F038-R04: Unified Result Model

The picker MUST support one unified trigger flow that can surface:

- matching files and directories for the originating terminal context when path results are available
- matching saved terminal shortcuts for the originating terminal context
- one built-in `Generate Command` action
- one `Manage Shortcuts…` action when shortcut management is available from the originating surface

### F038-R05: Review-First Insertion

Selecting a file, directory, shortcut, or generated command MUST replace only the active trigger token and MUST NOT auto-execute the resulting text. Confirmation MUST return the user to the same originating input surface for further editing or manual submission.

### F038-R06: Surface-Consistent Behavior

The same trigger model MUST be available in:

- direct terminal session input
- terminal spotlight compose input
- ACP compose input
- VibeCast compose input

Each surface MAY render the picker differently, but keyboard behavior, insertion behavior, and dismissal behavior MUST remain consistent.

### F038-R07: Centered Overlay Presentation

The inline picker MUST render as a centered overlay popup above the current vibespace canvas. The popup MUST be shared across all surfaces — board tiles, spotlight compose, ACP compose, and VibeCast compose — using a single `BoardInlinePickerOverlayController` injected via SwiftUI environment. Only one picker popup may be active at a time per overlay controller. Opening, updating, and dismissing the popup MUST NOT resize or reflow the underlying vibespace layout. When the overlay controller is unavailable (environment not set), the picker MAY fall back to an inline panel rendered within the owning surface.

### F038-R08: Keyboard Navigation and Dismissal

While the picker is open, users MUST be able to navigate results by keyboard. `Up` and `Down` MUST move selection within the active list, `Tab` and `Enter` MUST confirm the selected item, `Right Arrow` MUST be able to move focus into the action pane when that pane is present. The picker MUST be dismissible by: `Escape` key, the close button in the picker header, or clicking outside the picker area. All dismissal methods MUST preserve the current draft text.

### F038-R09: Popup Layout and Affordances

The popup MUST use the following layout:

1. **Header**: title label on the left, close button (×) on the right.
2. **Query display**: shows the active query text when non-empty, or a "Type to search" placeholder when the query is empty.
3. **Two-pane body**: file and directory results in the left pane (scrollable), actions in the right pane (fixed width). A vertical divider separates the panes.
4. **Right pane contents**: the `Generate Command` featured action (when available), matching saved terminal shortcuts, and a `Manage Shortcuts…` action (when shortcut management is available).
5. **Footer**: result count and status text on the left, keyboard hint text on the right.

The popup MUST have a maximum width, constrained height range, rounded corners, drop shadow, and semi-transparent background. Selection highlighting MUST be visible for the currently focused result row or featured action.

### F038-R10: Context-Correct Resolution

Inline triggers MUST resolve results against the originating surface context. Local terminals MUST use local vibespace context. Spotlight, ACP, and VibeCast compose MUST inherit the terminal or project context they are attached to. The feature MUST NOT silently insert a path from the wrong context into the draft.

### F038-R11: Remote Compatibility Direction

The feature MUST support terminal surfaces that point at remote SSH sessions. Remote support MUST preserve the same interaction model and review-first insertion behavior, while using a remote-appropriate path enumeration backend rather than assuming a local filesystem crawl. Remote support MUST NOT require a separate user-installed CrispyVibes dependency on the remote host.

### F038-R12: Resource Cleanup

When the picker closes, the originating surface disappears, or the trigger token is cleared, any picker-scoped observers, asynchronous tasks, and path-search processes MUST be released promptly. Dismissing the picker MUST NOT leave background scans or orphan helper processes running.

## Scenarios

### Scenario F038-S01: Direct terminal opens the inline picker

**Given** a direct terminal input surface is focused
**When** the user types the configured trigger at the start of a token
**Then** one inline picker opens for that terminal context
**And** the terminal remains the owning input surface for confirmation and dismissal

### Scenario F038-S02: Spotlight compose inserts a selected path for review

**Given** terminal spotlight compose is focused
**When** the user opens the inline picker and selects a file or directory result
**Then** only the active trigger token is replaced with the selected path
**And** the command is not executed automatically
**And** focus remains on the spotlight compose input

### Scenario F038-S03: ACP compose inserts a shortcut without sending

**Given** ACP compose is focused
**When** the user opens the inline picker and selects a saved terminal shortcut
**Then** only the active trigger token is replaced with the shortcut text
**And** ACP does not auto-send the message
**And** focus remains on ACP compose

### Scenario F038-S04: VibeCast compose routes the query into Generate Command

**Given** VibeCast compose is focused
**When** the user opens the inline picker and confirms `Generate Command`
**Then** Crispy uses the active trigger query as the generation request
**And** replaces only the active trigger token with the generated text
**And** leaves the result in the compose box for review

### Scenario F038-S05: Board popup does not disturb tile layout

**Given** a board-hosted compose surface opens the inline picker
**When** the picker renders
**Then** a centered board-scoped popup appears above the board
**And** the owning tile keeps its existing size and position
**And** closing the popup leaves the board layout unchanged

### Scenario F038-S06: Dismissing the picker suppresses the same token

**Given** the inline picker is open for a trigger token
**When** the user presses `Escape`
**Then** the picker closes without changing the current draft
**And** continuing to type inside that same trigger token does not immediately reopen the picker
**And** starting a new trigger token can open the picker again

### Scenario F038-S07: Keyboard user moves from files to actions

**Given** the two-pane popup is open with both file results and actions
**When** the user presses `Right Arrow`
**Then** selection moves into the action pane
**And** the user can confirm `Generate Command` or a shortcut with `Enter`

### Scenario F038-S08: Closing the popup releases picker resources

**Given** the inline picker opened path-search resources for a local query
**When** the user clears the trigger token, dismisses the popup, or closes the owning surface
**Then** picker-scoped search work is stopped
**And** no inline-trigger helper process or observer remains active for that closed picker session

### Scenario F038-S09: Double-trigger exits the picker and inserts a literal token

**Given** the inline picker is open with an empty query
**When** the user types the trigger token a second time
**Then** the picker closes
**And** a single literal trigger token is inserted into the draft at the cursor position
**And** this behavior MUST be consistent across direct terminal input, spotlight compose, ACP compose, and VibeCast compose

### Scenario F038-S10: Dismissal clears picker query state

**Given** the inline picker is open with a non-empty query
**When** the picker is dismissed by any means (Escape, double-trigger, backdrop click, or surface teardown)
**Then** the picker query text is cleared
**And** the picker result list is cleared
**And** reopening the picker starts with an empty query

### Scenario F038-S11: Clicking outside the picker dismisses it

**Given** the inline picker is open (board popup or inline panel)
**When** the user clicks outside the picker area
**Then** the picker closes without changing the current draft
**And** the dismissed trigger token is suppressed per F038-S06

### Scenario F038-S12: Compose surface cursor moves to end of inserted text

**Given** a non-terminal compose surface (spotlight compose, ACP compose, or VibeCast compose) has the inline picker open
**When** the user selects a result and the trigger token is replaced with the inserted text
**Then** the text cursor MUST be positioned immediately after the last character of the inserted text
**And** the user can continue typing without manually repositioning the cursor

### Scenario F038-S13: Dismissed picker does not reopen without a new trigger gesture

**Given** the inline picker was dismissed (by Escape, double-trigger, backdrop click, or result selection)
**When** the user continues typing without clearing and retyping the trigger token
**Then** the picker MUST NOT reopen
**And** the picker MUST only reopen when the user types a new trigger token at a valid token boundary
**And** no SwiftUI state cycle or observer feedback loop may cause the picker to flicker or reopen autonomously

### Scenario F038-S14: Picker lifecycle does not leak resources across sessions

**Given** the inline picker has been opened and dismissed one or more times
**When** the owning surface is torn down (spotlight dismissed, tab closed, board tile removed)
**Then** all picker-scoped Combine subscriptions, Task handles, and path-search helper processes MUST be cancelled and released
**And** no strong reference cycle between the picker controller, its closures, and the owning view may prevent deallocation

### Scenario F038-S15: Spotlight swipe while picker is open closes picker cleanly

**Given** the inline picker is open in a terminal spotlight compose surface
**When** the user swipes to a different terminal in the spotlight carousel
**Then** the picker MUST close before the spotlight transition begins
**And** the path-search helper process MUST terminate without crashing
**And** no file-handle read exception may propagate as an uncaught ObjC exception

### Scenario F038-S16: Trigger token mid-word does not activate picker

**Given** a compose or terminal input surface is focused
**When** the user types text that contains the trigger token mid-word (e.g., `hello`world`)
**Then** the picker MUST NOT open
**And** the trigger token is treated as literal text

### Scenario F038-S17: Rapid open/close does not leak helper processes

**Given** a compose or terminal input surface is focused
**When** the user rapidly types and deletes the trigger token multiple times
**Then** each dismissal MUST fully terminate the previous path-search helper process before a new one starts
**And** no orphan helper processes accumulate

### Scenario F038-S18: Empty vibespace shows graceful empty state

**Given** the vibespace has no projects or the terminal has no resolvable local context
**When** the user opens the inline picker
**Then** the picker MUST show an empty state in the paths pane
**And** the picker MUST NOT crash, hang, or attempt to launch a path-search helper with no search roots

### Scenario F038-S19: Long path insertion preserves full text

**Given** the inline picker shows a deeply nested file path result
**When** the user selects that result
**Then** the full shell-safe path MUST be inserted without truncation
**And** the compose input MUST accommodate the inserted text without layout breakage

### Scenario F038-S20: Only one picker is active at a time per overlay controller

**Given** a board tile has an active inline picker open via the board overlay controller
**When** the user opens a spotlight or switches focus to a different surface that also uses the same overlay controller
**Then** the previous picker MUST be dismissed
**And** only the newly activated picker is shown

## Acceptance Criteria

- The inline picker never auto-executes inserted text (A11Y-2, REL-1).
- Popup presentation does not cause vibespace layout shifts (PERF-3).
- Confirmation and dismissal always return focus to the originating input surface (A11Y-2).
- Active-query rendering shows the current typed query and remains editable without duplicate text insertion (REL-1).
- Picker-scoped search resources are released on dismiss and surface teardown (REL-1, PERF-3).
- Double-trigger inserts a literal token and closes the picker on all surfaces (REL-1).
- Dismissed picker never reopens without an explicit new trigger gesture (REL-1).
- Compose surface cursor is positioned at end of inserted text after selection (A11Y-2).
- No strong reference cycle between picker controller, closures, and owning view survives surface teardown (PERF-3).
- Spotlight swipe while picker is open closes picker without crash (REL-1).
- Only one picker popup is active at a time per overlay controller (REL-1).
- Trigger token mid-word does not activate picker (REL-1).
- Rapid open/close cycling does not leak helper processes (PERF-3).

## Open Questions

- When remote SSH path search ships, should remote hosts stream results continuously or return bounded snapshots per query revision?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-20 | Promoted inline trigger behavior from planning into dedicated feature spec F038 | Codex |
| 2026-04-21 | Added edge-case scenarios F038-S09 through F038-S14 (double-trigger exit, dismissal clears state, backdrop click, cursor positioning, no-reopen-without-gesture, resource leak prevention) | Engineering |
| 2026-04-21 | Added edge-case scenarios F038-S15 through F038-S20 (swipe crash, mid-word trigger, rapid cycling, empty vibespace, long paths, single-picker-at-a-time) | Engineering |
| 2026-04-21 | Updated R07, R08, R09 to match current UI: centered overlay for all surfaces (not just board), close button, backdrop dismiss, full popup layout description with header/query/two-pane/footer | Engineering |
