# Terminal Scroll Assist — Spec

Status: draft

## Overview

Terminal Scroll Assist provides quick navigation through a terminal's scrollback buffer without leaving the keyboard or scrolling manually. It lives as an iOS AssistiveTouch-style collapsed ball in the terminal that expands into a D-pad cross on hover. The D-pad contains five controls: jump to previous user message (⬆ top), jump to next user message (⬇ bottom), search scrollback (🔍 center), temporary terminal (left), and split terminal (right).

The ball is draggable to reposition anywhere in the terminal. The feature works for both terminal engines Crispy supports (Ghostty primary, SwiftTerm fallback) and behaves correctly when a tmux session — fresh or resumed — is running inside the engine.

## Dependencies

- F001 (Terminal Sessions & Tabs) — provides the `TerminalSession` and engine abstractions.
- F010 (tmux Integration) — provides tmux session detection, capture-pane, and copy-mode commands used for tmux-backed scroll behavior.
- F043 (Compose History) — provides the centralized `ComposeHistoryStore` keyed by session UUID. Scroll Assist reads previous user messages from this store.

## Requirements

### F046-R01: AssistiveTouch-style control ball

The control pad MUST render as a small translucent ball (24px circle, 45% opacity) in the bottom-right corner of every active terminal. On hover or tap, the ball MUST expand with a spring animation into a 5-button D-pad cross layout: ⬆ (top), ⬇ (bottom), 🔍 (center), temporary-terminal (left), split-terminal (right). Each button MUST be an individual glass circle — no container rectangle. The ball/pad MUST be draggable to reposition anywhere within the terminal bounds. The pad MUST collapse back to the ball after 0.8 seconds when the mouse leaves (but MUST stay expanded while the search bar is open). It MUST NOT obscure terminal content under normal use.

### F046-R09: Drag-to-reposition

The ball (and expanded D-pad) MUST be draggable to any position within the terminal tile. The drag offset MUST persist for the lifetime of the terminal session. The default position is bottom-right.

### F046-R10: Split and temporary terminal actions in D-pad

The D-pad MUST include a split-terminal button (right position) and a temporary-terminal button (left position). These actions were previously in the tile header and are now exclusively in the D-pad.

### F046-R02: Up/Down navigation through prior user messages

⬆ MUST jump the terminal viewport to the most recent user-submitted message (command). Subsequent presses MUST step further back through the history. ⬇ MUST step forward toward the present. The history source is `ComposeHistoryStore.entries(for: session.id)`.

### F046-R03: Scrollback text search

🔍 MUST open a search bar that filters the terminal's scrollback by substring (case-insensitive). Matching lines MUST appear as clickable rows. Clicking a row MUST scroll the terminal viewport to that line.

### F046-R04: Engine-agnostic scrolling

Scrolling MUST work for both Ghostty and tmux-backed sessions. For Ghostty, scroll uses the `scroll_to_row:N` keybind action. For tmux, scroll uses `copy-mode` plus `search-forward` to land on the chosen match. The user MUST NOT need to know which backend is in use.

### F046-R05: Cursor reset on user typing

The up/down history cursor MUST reset to the live (newest) position whenever the user types into the terminal, so a subsequent ⬆ press starts from the most recent message again.

### F046-R06: Search bar expansion animation

When the user activates 🔍, the search bar MUST animate into view from the left of the control pad. The pad icons MUST remain in place. Closing the search MUST animate it out symmetrically.

### F046-R07: Empty-state behavior

When `ComposeHistoryStore` has no entries for the session, ⬆ and ⬇ MUST be visually dimmed and become no-ops. 🔍 MUST remain functional.

### F046-R08: tmux copy-mode exit

When the user dismisses Scroll Assist after a tmux scroll, Scroll Assist MAY leave the tmux pane in copy-mode (the user can press `q` to return to live input). Auto-exit is a non-goal for the initial implementation.

## Scenarios

### Scenario F046-S01: Jump to previous command in Ghostty

Given a terminal where the user has run `ls`, `git status`, `echo hi` in order  
When the user clicks ⬆ on the control pad  
Then the terminal viewport scrolls to the line containing `echo hi`  
And clicking ⬆ again scrolls to `git status`  
And clicking ⬆ again scrolls to `ls`

### Scenario F046-S02: Jump forward after going back

Given the user has pressed ⬆ twice (currently viewing `git status`)  
When the user clicks ⬇ once  
Then the terminal viewport scrolls forward to `echo hi`  
And clicking ⬇ again returns the viewport to live (bottom)

### Scenario F046-S03: Search and click result

Given the terminal scrollback contains the text "ERROR" on line 42 and line 87  
When the user clicks 🔍, types "ERROR", and clicks the row showing line 87  
Then the terminal viewport scrolls so line 87 is centered in view

### Scenario F046-S04: Cursor reset on typing

Given the user has pressed ⬆ twice (history cursor is mid-stack)  
When the user types any character into the terminal  
Then the history cursor resets to live  
And the next ⬆ press jumps to the most recent command

### Scenario F046-S05: Resumed tmux session

Given the user has reattached to a tmux session that was created in a prior Crispy run  
And the tmux pane contains scrollback from the previous session  
When the user clicks 🔍, types text from the previous session, and clicks a result  
Then the tmux pane enters copy-mode and scrolls to the match  
And the match is visible regardless of whether Ghostty rendered the historical content

### Scenario F046-S06: Ball expansion on hover

Given the control ball is in its collapsed state (24px circle, 45% opacity)  
When the user moves the cursor over the ball  
Then the ball expands with a spring animation into the 5-button D-pad cross  
And the D-pad collapses back to the ball after 0.8s when the cursor leaves (unless search is open)

### Scenario F046-S07: Empty history disables nav

Given a fresh terminal with no submitted commands  
Then ⬆ and ⬇ are visually dimmed  
And clicking them does nothing  
And 🔍 remains fully functional

## Acceptance Criteria

- All scenarios above pass on Ghostty and on Ghostty+tmux configurations.
- Build succeeds and unit tests pass.
- The control pad does not interfere with click events on the underlying terminal area.
- No new keyboard shortcuts are required for the initial scope (interaction is mouse-only). Keyboard shortcuts can be layered on later.

## Open Questions

- Should the up/down history include only finalized commands (Enter-submitted) or also pasted multi-line input?  
  *Initial decision:* finalized commands only, matching what `ComposeHistoryStore` already records.

- Should the search bar support regex / case-sensitive toggle?  
  *Initial decision:* substring case-insensitive only for the first version.

## Change History

- 2026-05-19 — Initial draft.
- 2026-05-20 — UX redesign: capsule replaced with AssistiveTouch-style ball that expands into D-pad cross. Added F046-R09 (drag-to-reposition), F046-R10 (split/temp buttons in D-pad). Updated F046-S06 for ball expansion.
