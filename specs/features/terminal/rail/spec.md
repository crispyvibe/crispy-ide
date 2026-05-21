# Terminal Rail — Spec

Status: draft

## Overview

Terminal Rail manages terminal presentation inside the stacked project rail in Detailed canvas mode. Visible rail terminals MUST be grouped by Project rather than flattened across the whole VibeSpace. Each non-focused Project contributes a compact terminal stack with one representative terminal on top, activity-aware ordering inside that stack, hover/focus expansion for the remaining visible terminals, and manual hide/unhide controls.

## Dependencies

- F001 (Sessions & Tabs) — rail cards reflect terminal tab state
- F003 (Terminal Spotlight) — double-click rail card opens spotlight
- F021 (VibeSpace Projects) — rail stacks render inside stacked project cards

## Requirements

### F004-R01: Active Terminal Data Marks Tab as Active

When a terminal session receives meaningful incoming data past the activity threshold, tab `isActive` MUST be set true. The tab header MUST show an animated activity sweep indicator. The terminal pane header MUST show a matching inline activity indicator while any tab is active. The terminal board tile header MUST show a matching inline activity indicator for the active tile tab. Startup/resize suppression windows MUST NOT mark activity on their own.

### F004-R02: Activity Indicator Clears After Idle Threshold

When no significant terminal data arrives for the idle period (~1 second), tab `isActive` MUST be set false and the activity sweep indicator MUST be removed.

### F004-R03: Rail Groups Visible Terminals by Project

Visible rail terminals MUST be grouped by Project. A non-focused Project MUST render as at most one collapsed rail stack regardless of how many visible terminals it owns. The order of Project stacks in the rail MUST follow vibespace Project order and MUST NOT be reshuffled by terminal activity. Manually hidden terminals MUST NOT appear in the collapsed stack or the hover-expanded stack.

### F004-R04: Representative Terminal Stays on Top of the Project Stack

Within a Project stack, terminals with live output activity (`isActive == true`) MUST rank ahead of idle terminals. Among active terminals, the most recently active terminal MUST be shown on top. When no terminal is currently active, the most recently focused or selected visible terminal for that Project MUST remain on top. If no recency metadata exists, the Project's active tab MUST be used; otherwise the first visible terminal is the fallback.

### F004-R05: Project Stack Expands on Hover or Keyboard Focus

When the pointer hovers a collapsed Project stack, or keyboard focus enters it, the remaining visible terminals for that Project MUST slide out into view in ranked order. When hover and keyboard focus both leave the stack, the additional terminals MUST collapse back behind the representative terminal after a short grace period that prevents flicker during pointer movement.

### F004-R06: Project Rail Card Reflects Aggregate Tab Activity

When any visible terminal in a Project stack has `isActive` true, that Project's stacked rail card MUST keep the Project color on the existing stack icon and surface the same inline activity treatment used elsewhere for terminal activity.

### F004-R07: Content Viewer Tab Reflects Terminal Activity

When any terminal tab in a project has `isActive` true, the content viewer tab for that project MUST show the same inline activity indicator. The indicator MUST clear when all terminal tabs become idle. The header MUST show the same inline activity indicator style used in terminal tabs. Icon and inline indicator MUST return to normal when all tabs become inactive.

### F004-R08: Hide Terminal from Rail

When the user hides a terminal via rail context menu, the terminal MUST be removed from the visible Project stack and the board. The terminal process MUST remain alive. The hidden terminal MUST appear in a "hidden terminals" section in the rail.

### F004-R09: Unhide Terminal from Rail

When the user unhides a terminal, the terminal MUST be restored to its Project stack and the board. The terminal session MUST resume display without restarting.

### F004-R10: Rail Card Maintains Minimal Project-Stack Presentation

When a collapsed Project stack renders, it MUST show the Project identity, the representative terminal title, activity state, and a visible-terminal count affordance when more than one terminal is available. Secondary actions (hide, rename, restart) MUST be available via context menu only.

### F004-R11: No Split Terminal Icon on Rail Card

No split terminal icon MUST be displayed on the rail card. Terminal splitting MUST be managed from the board or terminal tab bar only.

### F004-R12: No Temporary Terminal Icon on Rail Card

No temporary terminal creation icon MUST be displayed on the rail card. Temporary terminal creation MUST be accessible from the board toolbar only.

## Scenarios

### Scenario F004-S01: Active terminal data marks tab as active

**Given** a terminal session receives meaningful incoming data
**When** data chunk passes activity threshold
**Then** tab `isActive` is set true
**And** tab header shows animated activity sweep indicator
**And** terminal pane header shows a matching inline activity indicator while any tab is active
**And** terminal board tile header shows a matching inline activity indicator for the active tile tab
**And** startup/resize suppression windows do not mark activity on their own

### Scenario F004-S02: Activity indicator clears after idle threshold

**Given** no significant terminal data arrives for idle period
**When** idle timer exceeds ~1 second
**Then** tab `isActive` is set false
**And** activity sweep indicator is removed

### Scenario F004-S03: Rail groups visible terminals by project

**Given** multiple non-focused projects each have one or more visible terminals
**When** the terminal rail renders
**Then** each project appears as at most one collapsed project stack
**And** manually hidden terminals do not appear in that stack

### Scenario F004-S04: Representative terminal stays on top of the project stack

**Given** a project has multiple visible rail terminals
**When** one terminal emits live output or becomes the most recently selected terminal
**Then** that terminal is promoted to the top of the project's collapsed stack
**And** the remaining visible terminals keep their ranked order beneath it

### Scenario F004-S05: Hover or keyboard focus expands the project stack

**Given** a collapsed project stack has more than one visible terminal
**When** the user hovers the stack or moves keyboard focus into it
**Then** the remaining visible terminals slide out and become individually visible
**And** they remain ordered by activity and recency
**When** hover and keyboard focus both leave the stack
**Then** the stack collapses back to one representative terminal after a short grace period

### Scenario F004-S06: Project rail card reflects aggregate tab activity

**Given** a project's terminal tabs emit activity
**When** any visible tab `isActive` is true
**Then** that project's stacked rail card keeps the Project color on the existing stack icon
**And** the stack surfaces the inline activity treatment until all visible tabs go idle

### Scenario F004-S07: Content viewer tab reflects terminal activity

**Given** a content viewer tab is open for a file belonging to a project
**And** that project has at least one terminal tab with active output
**When** any terminal tab in that project has `isActive` true
**Then** the content viewer tab for that project shows the same inline activity indicator
**And** the indicator clears when all terminal tabs in that project become idle
**And** the header shows the same inline activity indicator style used in terminal tabs
**And** icon and inline indicator return to normal when all tabs become inactive

### Scenario F004-S08: Hide a terminal from the rail

**Given** a project has multiple terminal tabs visible in the rail
**When** the user hides a terminal via rail context menu
**Then** the terminal is removed from the visible project stack and the board
**And** the terminal process remains alive (not terminated)
**And** the hidden terminal appears in a "hidden terminals" section in the rail

### Scenario F004-S09: Unhide a terminal from the rail

**Given** one or more terminals are hidden
**When** the user unhides a terminal from the hidden terminals section or rail context menu
**Then** the terminal is restored to the visible project stack and the board
**And** the terminal session resumes display without restarting

### Scenario F004-S10: Rail card shows minimal collapsed project-stack presentation

**Given** a project stack is visible in the rail
**When** the collapsed rail card renders
**Then** it shows project identity, representative terminal title, activity state, and a visible-terminal count affordance when needed
**And** secondary actions (hide, rename, restart) are available via context menu only

### Scenario F004-S11: Split terminal icon is not shown on rail card

**Given** a project stack is visible in the rail
**When** the rail card renders
**Then** no split terminal icon is displayed on the card
**And** terminal splitting is managed from the board or terminal tab bar only

### Scenario F004-S12: Temporary terminal icon is not shown on rail card

**Given** a project stack is visible in the rail
**When** the rail card renders
**Then** no temporary terminal creation icon is displayed on the card
**And** temporary terminal creation is accessible from the board toolbar only

## Acceptance Criteria

- Activity indicator appears within 100ms of data threshold (PERF-3).
- Activity indicator clears within 100ms of idle threshold (PERF-3).
- Representative-terminal promotion follows activity/selection changes without restarting sessions.
- Hover/focus expansion reveals the rest of a project's visible terminals and collapses automatically on exit.
- Hide/unhide operations complete within 100ms (PERF-3).
- Hidden terminals do not leak processes (REL-6).
- Hover-only behavior has a keyboard-reachable equivalent (A11Y-2).
- Activity state changes logged (OBS-1).

## Open Questions

- None currently.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-23 | Resolved rail stack ordering to preserve vibespace project order | Codex |
| 2026-04-23 | Refined rail behavior to group terminals by project, rank representative terminals by activity/recency, and expand stacks on hover/focus | Codex |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-017–019A, TRM-072–076) | — |
