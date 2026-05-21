# Terminal Context Summary — Spec

Status: implemented

## Overview

Terminal Context Summary evolves the existing Terminal Insight overlay (F001-R47/R48/R49) from a simple last-command pill into an AI-powered context summary. The overlay has two levels: a collapsed pill showing an AI-generated headline of what the developer is doing in the terminal, and an expanded view showing a recent command timeline.

Summary generation uses Apple's Foundation Models framework with `@Generable` structured output and a persistent `LanguageModelSession` per terminal. The session accumulates conversation history so summaries evolve naturally as activity progresses. The feature is availability-gated — when Apple Intelligence is unavailable, it falls back to displaying the raw last command.

## Dependencies

- F001 (Terminal Sessions & Tabs) — R47 auto-dismiss, R48 TUI suppression, R49 overlay animation; `TerminalInsightObserver` provides last command input and TUI mode detection
- Apple Foundation Models framework (macOS 26+) — `LanguageModelSession`, `@Generable`

### Future Enhancements

- F040 (Agent Conversation Persistence) — thread title, conversation history integration
- F011 (ACP) — agent session context, tool calls, messages for richer summaries

## Requirements

### F041-R01: AI-Generated Context Headline

The collapsed overlay MUST display an AI-generated one-line summary (under 12 words) describing what the developer is currently doing in the terminal (e.g., "Building the project after editing config" or "Running test suite"). The summary MUST be generated using Apple's Foundation Models framework via a persistent `LanguageModelSession` with a `@Generable` output struct (`GeneratedContextSummary`) containing `headline: String` and `phase: String`.

### F041-R02: Expandable Overlay

The overlay MUST support two states: collapsed (default on hover) and expanded (on tap). The collapsed state shows the AI headline pill with a phase icon and chevron indicator. The expanded state slides down to reveal the activity timeline. A chevron indicator MUST signal expandability and reflect current state (up when expanded, down when collapsed).

### F041-R03: Recent Command Timeline

The expanded overlay MUST display a chronological timeline of recent terminal commands sourced from the view model's `recentCommands` buffer (populated via `TerminalInsightObserver.lastInput`). The timeline shows the most recent 10 commands in reverse chronological order, capped at 15 entries total.

### F041-R04: Persistent Chat Session

The `ContextSummaryGenerator` MUST maintain a long-lived `LanguageModelSession` per terminal instance. Each generation call adds to the conversation history so the model builds on its previous understanding. The session is initialized with a system instruction that tells the model to observe terminal activity, write concise status updates, build on previous understanding, reflect workflow progression, and exclude secrets/paths. If the session enters a bad state (error), it MUST be reset by nilling the stored session.

### F041-R05: Summary Regeneration Triggers

The AI summary MUST be regenerated when a new terminal command is detected via `TerminalInsightObserver.lastInput`. Regeneration is debounced with a 500ms interval — if multiple commands arrive within 500ms, only the last one triggers generation. The summary MUST be cached between triggers — hovering over the terminal MUST NOT trigger regeneration.

### F041-R06: Generation Timeout with Fallback

Summary generation MUST enforce a 2-second timeout using a `TaskGroup` race between the LLM response and a sleep timer. If the Foundation Models response does not complete within 2 seconds, the overlay MUST fall back to displaying the raw last command from `TerminalInsightObserver.lastInput` with phase set to `"idle"`.

### F041-R07: Availability-Gated Generation

Before generating, the generator MUST check `SystemLanguageModel.default.availability`. If the model is not `.available`, generation MUST return `nil` and the view model MUST fall back to the raw last command. The `LanguageModelSession` is stored as `Any?` and cast with `@available` checks to support compilation on earlier OS versions.

### F041-R08: TUI Mode Suppression

The context summary overlay MUST be suppressed when the terminal is in TUI mode, as detected by `TerminalInsightObserver.isTUIMode`. This inherits the behavior defined in F001-R48.

### F041-R09: Auto-Dismiss Behavior

The collapsed pill MUST auto-dismiss after 4 seconds of inactivity (inheriting F001-R47). The expanded view MUST remain visible until the user explicitly dismisses it by clicking the pill to collapse. The `dismiss()` method MUST only collapse the expanded state — the headline MUST persist for subsequent hovers.

### F041-R10: Phase Classification

The `@Generable` output MUST include a `phase` field as a `String` with a `@Guide` description listing valid values: `idle`, `building`, `testing`, `debugging`, `deploying`, `reviewing`, `editing`, `searching`. The view MUST map known phase strings to SF Symbol icons and colors. Unknown phase values MUST fall back to a generic circle icon with secondary color.

### F041-R11: Overlay Container Ownership

`TerminalContextSummaryOverlayContainer` MUST own the `@StateObject` view model. The container uses a `nonisolated init` with `MainActor.assumeIsolated` to create the `StateObject` wrappedValue, ensuring proper SwiftUI lifecycle management. The container passes the view model to `TerminalContextSummaryOverlay` as an `@ObservedObject`.

### F041-R12: Glass Style

The context summary overlay MUST use the `scrollAssistGlassBackground` helper for its background, rendering with Liquid Glass on macOS 26+ and falling back to `.ultraThinMaterial` on earlier versions.

### F041-R13: Summary/Original Toggle in Timeline

The expanded timeline view MUST provide a Summary/Original toggle that switches between showing AI-generated summaries and the raw original command text for each entry. Only one mode is visible at a time — not both texts per entry.

### F041-R14: Copy Respects Toggle Mode

The copy button MUST copy only the text that is currently visible based on the Summary/Original toggle state. If Summary mode is active, copy copies the summary text; if Original mode is active, copy copies the raw command text.

### F041-R15: Copy Button Feedback

The copy button MUST show a hover highlight state and MUST display a checkmark icon as confirmation feedback after a successful copy action.

### F041-R16: Auto-Collapse on Hover Out

The expanded panel MUST auto-collapse after 0.4 seconds when the mouse leaves the panel area. The collapse timer MUST be cancelled if the mouse re-enters the panel before the timer fires.

## Scenarios

### Scenario F041-S01: Hover shows AI summary headline

**Given** a terminal session has at least one command submitted and Apple Intelligence is available
**When** the user hovers over the terminal tile
**Then** the collapsed pill displays an AI-generated headline summarizing current activity
**And** a phase icon and chevron indicator are visible

### Scenario F041-S02: Expand shows command timeline

**Given** the collapsed pill is visible on hover
**When** the user taps the pill
**Then** the overlay expands to show the recent command timeline
**And** the timeline includes recent terminal commands with chevron-right icons

### Scenario F041-S03: Summary evolves with session history

**Given** the user has run `swift build` and the summary shows "Building the Swift project"
**When** the user runs `swift test`
**Then** the persistent session generates a new summary reflecting the progression
**And** the headline updates to reflect testing activity (e.g., "Running tests after build")

### Scenario F041-S04: Summary regenerates after new command

**Given** the AI summary is cached from a previous generation
**When** the user submits a new terminal command
**Then** a debounced summary regeneration is triggered after 500ms
**And** the cached summary is replaced with the new result once generation completes

### Scenario F041-S05: Generation timeout falls back to raw command

**Given** the user hovers over a terminal with recent commands
**When** the Foundation Models generation exceeds 2 seconds
**Then** the overlay displays the raw last command as the headline
**And** the phase is set to "idle"

### Scenario F041-S06: Apple Intelligence unavailable falls back to raw command

**Given** Apple Intelligence is not available on the system
**When** the user hovers over a terminal with recent commands
**Then** the overlay displays the raw last command from `TerminalInsightObserver.lastInput`
**And** the phase is set to "idle"

### Scenario F041-S07: TUI mode suppresses overlay

**Given** the terminal is running a TUI application (e.g., vim, htop)
**When** the user hovers over the terminal tile
**Then** no overlay is displayed
**And** the overlay reappears when the terminal exits TUI mode

### Scenario F041-S08: Auto-dismiss collapsed after 4 seconds

**Given** the collapsed pill is visible
**When** 4 seconds elapse without user interaction
**Then** the pill auto-dismisses

### Scenario F041-S09: Expanded view auto-collapses on hover out

**Given** the expanded overlay is visible
**When** the mouse leaves the panel area
**Then** the panel auto-collapses after 0.4 seconds
**And** if the mouse re-enters before 0.4s, the collapse is cancelled

### Scenario F041-S10: Dismiss preserves headline

**Given** the expanded overlay is visible with a headline
**When** the user dismisses the overlay
**Then** the expanded state collapses
**And** the headline persists and is visible on the next hover

### Scenario F041-S11: Phase changes after test command

**Given** the AI summary shows phase "building" after a `swift build` command
**When** the user submits `swift test`
**Then** the summary regenerates
**And** the phase updates to "testing" with a checkmark.circle icon in green

### Scenario F041-S12: Session reset on error

**Given** the `LanguageModelSession` encounters an error during generation
**When** the error is caught
**Then** the stored session is reset to nil
**And** the next generation creates a fresh session

### Scenario F041-S13: Summary/Original toggle in timeline

**Given** the expanded timeline is visible with multiple entries
**When** the user toggles from Summary to Original mode
**Then** each timeline entry displays the raw command text instead of the AI summary
**And** toggling back to Summary restores the AI-generated text

### Scenario F041-S14: Copy respects toggle mode

**Given** the timeline is in Original mode showing raw commands
**When** the user clicks the copy button
**Then** the clipboard contains the raw command text currently visible
**And** switching to Summary mode and copying produces the summary text

### Scenario F041-S15: Copy button feedback

**Given** the copy button is visible in the expanded timeline
**When** the user hovers over the copy button
**Then** the button shows a highlight state
**And** after clicking, the button displays a checkmark icon as confirmation

## Acceptance Criteria

- All scenarios (F041-S01 through F041-S15) have passing test coverage.
- AI summary generation uses `@Generable` structured output with a persistent `LanguageModelSession`.
- Collapsed pill shows AI headline when Apple Intelligence is available, raw last command otherwise.
- Expanded view shows recent terminal commands from the `recentCommands` buffer.
- Generation timeout of 2 seconds is enforced via `TaskGroup` race with graceful fallback.
- TUI suppression and auto-dismiss behaviors are preserved from F001-R47/R48.
- Dismiss preserves headline for re-hover.
- `TerminalContextSummaryOverlayContainer` owns `@StateObject` view model with `MainActor.assumeIsolated` init pattern.
- Glass style applied via `scrollAssistGlassBackground` helper (Liquid Glass on macOS 26+, ultraThinMaterial fallback).
- Timeline Summary/Original toggle switches visible text per entry; copy respects active mode.
- Panel auto-collapses after 0.4s on hover out with cancellable timer.
- Copy button shows hover highlight and checkmark feedback on click.

## Open Questions

1. Should the expanded overlay show a configurable number of timeline entries, or is the fixed limit (last 10 commands, capped at 15 entries) sufficient?
2. Should the keyboard shortcut for expand/collapse be added alongside tap?
3. Should the `TimelineEntry.Kind` cases beyond `.command` (`.toolCall`, `.message`, `.status`) be removed until agent integration is implemented?

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial draft |
| 2026-04-25 | Updated to match implementation: removed agent integration (F040/F011 runtime dependency), simplified input to terminal commands only, added persistent chat session, String-based phase, overlay container pattern, dismiss-preserves-headline, availability-gated fallback |
| 2026-05-20 | Added F041-R12 (glass style), F041-R13 (Summary/Original toggle), F041-R14 (copy respects mode), F041-R15 (copy button feedback), F041-R16 (auto-collapse on hover out). Updated F041-S09 for auto-collapse. Added scenarios S13–S15. |
