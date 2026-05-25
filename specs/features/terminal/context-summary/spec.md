# Terminal Context Summary — Spec

Status: implemented

## Overview

Terminal Context Summary evolves the existing Terminal Insight overlay (F001-R47/R48/R49) from a simple last-command pill into an AI-powered context summary. The overlay has two levels: a collapsed pill showing an AI-generated headline of what the developer is doing in the terminal, and an expanded view showing a recent command timeline.

Summary generation uses Apple's Foundation Models framework with `@Generable` structured output and a persistent `LanguageModelSession` per terminal. The session accumulates conversation history so summaries evolve naturally as activity progresses. The feature is availability-gated — when Apple Intelligence is unavailable, it falls back to displaying the raw last command.

Per-terminal summary state (the LLM session, the rolling buffer of submitted commands, and the timeline ledger) is owned by a service (`TerminalContextSummarySession`) attached to each `TerminalSession`, not by a SwiftUI view. The state therefore survives surface transitions (board ↔ spotlight ↔ rail) — a terminal moved between surfaces shows the same summary and timeline immediately on mount, without restarting the LLM session or losing prior commands.

## Dependencies

- F001 (Terminal Sessions & Tabs) — R47 auto-dismiss, R48 TUI suppression, R49 overlay animation; `TerminalInsightObserver` provides finalized command input and TUI mode detection
- Apple Foundation Models framework (macOS 26+) — `LanguageModelSession`, `@Generable`

### Future Enhancements

- F040 (Agent Conversation Persistence) — thread title, conversation history integration
- F011 (ACP) — agent session context, tool calls, messages for richer summaries
- Reactive experimental flag toggling — currently the summary session is created at terminal-construction time. A future enhancement may attach/detach the session reactively as the user toggles `experimental.terminalInsight`.

## Requirements

### F041-R01: AI-Generated Context Headline

The collapsed overlay MUST display an AI-generated one-line summary (under 12 words) describing what the developer is currently doing in the terminal (e.g., "Building the project after editing config" or "Running test suite"). The summary MUST be generated using Apple's Foundation Models framework via a persistent `LanguageModelSession` with a `@Generable` output struct (`GeneratedContextSummary`) containing `headline: String` and `phase: String`.

### F041-R02: Expandable Overlay

The overlay MUST support two states: collapsed (default on hover) and expanded (on tap). The collapsed state shows the AI headline pill with a phase icon and chevron indicator. The expanded state slides down to reveal the activity timeline. A chevron indicator MUST signal expandability and reflect current state (up when expanded, down when collapsed).

### F041-R03: Recent Command Timeline (All User Messages Persisted)

The expanded overlay MUST display a chronological timeline of every recorded user input for the current terminal session, in reverse chronological order (newest first). The timeline MUST persist all user messages submitted during the session lifetime — both visible commands and sensitive-information placeholders (see F041-R17) — capped only by a generous safety limit (currently 1000 entries, see `TerminalContextSummarySession.maxPersistedEntries`) to bound memory in extreme cases. The timeline projection MUST be identical regardless of which surface (board, spotlight, rail) is currently rendering the terminal.

### F041-R04: Persistent Chat Session

The `ContextSummaryGenerator` MUST maintain a long-lived `LanguageModelSession` per terminal instance. Each generation call adds to the conversation history so the model builds on its previous understanding. The session is initialized with a system instruction that tells the model to observe terminal activity, write concise status updates, build on previous understanding, reflect workflow progression, and exclude secrets/paths. If the session enters a bad state (error), it MUST be reset by nilling the stored session.

### F041-R05: Summary Regeneration Triggers

The AI summary MUST be regenerated when a new visible terminal command is detected via `TerminalInsightObserver.lastRecordedInput == .visible`. Regeneration is debounced with a 500ms interval — if multiple visible commands arrive within 500ms, only the last one triggers generation. The summary MUST be cached between triggers — hovering over the terminal MUST NOT trigger regeneration. Sensitive input events (F041-R17) MUST NOT trigger regeneration.

### F041-R06: Generation Timeout with Fallback

Summary generation MUST enforce a 20-second timeout using a `TaskGroup` race between the LLM response and a sleep timer. If the Foundation Models response does not complete within 20 seconds, the overlay MUST fall back to displaying the raw last command from `TerminalInsightObserver.lastRecordedInput` with phase set to `"idle"`. The 20s budget accommodates first-token latency on cold sessions and on devices where the model has just become available, while still bounding any single in-flight generation.

### F041-R07: Availability-Gated Generation

Before generating, the generator MUST check `SystemLanguageModel.default.availability`. If the model is not `.available`, generation MUST return `nil` and the view model MUST fall back to the raw last command. The `LanguageModelSession` is created lazily and is OS-version-gated by `import FoundationModels`; the feature compiles and runs on earlier OS versions as a no-op.

### F041-R08: TUI Mode Suppression

The context summary overlay MUST be suppressed when the terminal is in TUI mode, as detected by `TerminalInsightObserver.isTUIMode`. This inherits the behavior defined in F001-R48.

### F041-R09: Auto-Dismiss Behavior

The collapsed pill MUST auto-dismiss after 4 seconds of inactivity (inheriting F001-R47). The expanded view MUST remain visible until the user explicitly dismisses it by clicking the pill to collapse. The `dismiss()` method MUST only collapse the expanded state — the headline MUST persist for subsequent hovers.

### F041-R10: Phase Classification

The `@Generable` output MUST include a `phase` field as a `String` with a `@Guide` description listing valid values: `idle`, `building`, `testing`, `debugging`, `deploying`, `reviewing`, `editing`, `searching`. The view MUST map known phase strings to SF Symbol icons and colors. Unknown phase values MUST fall back to a generic circle icon with secondary color.

### F041-R11: Service-Owned Per-Terminal State

Per-terminal context-summary state — including the `recentCommands` buffer, the persistent `LanguageModelSession`, the timeline ledger, and the current headline/phase — MUST live in a `TerminalContextSummarySession` service stored on `TerminalSession`. The service is constructed via the `terminalServices.contextSummarySessionFactory` closure, which is wired from `AppContainer.makeDefault()` and consults a single shared `ExperimentalFeaturesService` instance to gate creation. View models (`TerminalContextSummaryViewModel`) MUST be thin per-mount projections that hold a reference to the service, own only ephemeral UI state (e.g., `isExpanded`), and forward observation via Combine. SwiftUI views MUST NOT own the durable state as `@StateObject`. The service MUST expose an explicit `shutdown()` method called from `TerminalSession.terminate()`.

### F041-R12: Glass Style

The context summary overlay MUST use the `scrollAssistGlassBackground` helper for its background, rendering with Liquid Glass on macOS 26+ and falling back to `.ultraThinMaterial` on earlier versions.

### F041-R13: Summary/Original Toggle in Timeline

The expanded timeline view MUST provide a Summary/Original toggle that filters which entries are visible:

- **Summary mode** (default) MUST show only `.message` entries — the AI-generated summary rows. Each row displays the summary text (`generatedText`).
- **Original mode** MUST show only `.command` entries — the raw user-input rows. Each row displays the raw command text (`originalText`).

Both modes MUST also display sensitive-information placeholder entries (`isSensitivePlaceholder == true`), because those entries represent activity that has no AI-summary version and whose actual content cannot be recovered. The displayed text for a placeholder is the localized "sensitive information" string in both modes.

The two streams MUST NOT be displayed simultaneously — the user sees one mode at a time. Toggling between the two preserves scroll position where SwiftUI permits.

### F041-R14: Copy Respects Toggle Mode

The copy button MUST copy only the text that is currently visible based on the Summary/Original toggle state. If Summary mode is active, copy copies the summary text; if Original mode is active, copy copies the raw command text. For sensitive-information placeholder entries, copy MUST yield only the placeholder text — never the underlying input.

### F041-R15: Copy Button Feedback

The copy button MUST show a hover highlight state and MUST display a checkmark icon as confirmation feedback after a successful copy action.

### F041-R16: Auto-Collapse on Hover Out

The expanded panel MUST auto-collapse after 0.4 seconds when the mouse leaves the panel area. The collapse timer MUST be cancelled if the mouse re-enters the panel before the timer fires.

### F041-R17: Sensitive Input Handling

The `TerminalInsightObserver` exposes two input methods with different trust treatments:

1. **Keystroke path** (`recordTypedKeystroke`) — used by `GhosttyTerminalViewInput` for direct typing into the terminal surface and for clipboard paste through the surface. Characters are accumulated in an internal buffer and classified on Enter. Classification is deferred so the keystroke→PTY→shell-echo→render round-trip has time to complete:
    - The first check runs synchronously. If the surface already shows the trimmed input, the observer publishes `.visible(text)` with no further work.
    - If not, the observer schedules up to six retries at 150 ms intervals on the main queue, capped at a 1 s total budget.
    - If the surface never shows the input within the budget, the observer publishes `.sensitive`. The typed bytes are never exposed to any downstream consumer.
    - The retry policy is configurable on the observer (`classificationPolicy`) for unit tests; production uses immediate + 6 × 150 ms with a 1 s budget.
    - Only one classification is in flight per terminal at a time. A new Enter cancels any pending work; `TerminalSession.terminate()` calls `observer.shutdown()`; streaming-output detection in `processFrame` also cancels pending work.

2. **Compose-UI path** (`recordSubmittedFromComposeUI`) — used by `TerminalSession.recordSentInput` for VibeCast, Spotlight compose, inline triggers, and other SwiftUI compose paths. The submitted command is classified `.visible` immediately by trust boundary — the user authored the text in a visible SwiftUI field before pressing Send, so a separate surface check is not required. A compose-UI submission cancels any in-flight keystroke classification.

On `.sensitive` (keystroke path only):

- The summary session MUST append a timeline entry whose `text`, `originalText`, and (effectively) `generatedText` all resolve to the localized "sensitive information" placeholder, with `isSensitivePlaceholder = true`. The actual typed bytes MUST NOT be stored anywhere in the timeline.
- The collapsed headline MUST be updated to the same placeholder so the UI reflects that recent activity occurred — replacing the previous "show nothing" behavior.
- The summary session MUST NOT include the input in the LLM prompt window and MUST NOT trigger a regeneration on its account. The persistent `LanguageModelSession` conversation history MUST remain free of any reference to the sensitive content.
- Compose history MUST also reject the sensitive input. Compose history is fed by a single Combine subscription on `TerminalInsightObserver.$lastRecordedInput` held by `TerminalSession`; the subscription only appends on `.visible` events. The previous synchronous raw-text fallback in `recordSentInput` and `forwardRecordSentInput` has been removed entirely.

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
**When** the Foundation Models generation exceeds 20 seconds
**Then** the overlay displays the raw last command as the headline
**And** the phase is set to "idle"

### Scenario F041-S06: Apple Intelligence unavailable falls back to raw command

**Given** Apple Intelligence is not available on the system
**When** the user hovers over a terminal with recent commands
**Then** the overlay displays the raw last command from `TerminalInsightObserver`
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

**Given** the user has submitted several visible commands and the AI summary has produced a summary for each
**When** the user expands the overlay in Summary mode
**Then** the timeline shows only the AI-summary rows (one per command), not the raw command rows
**When** the user switches to Original mode
**Then** the timeline shows only the raw command rows, not the AI summaries
**And** sensitive-information placeholder rows appear in both modes

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

### Scenario F041-S16: Summary state persists across surface transitions

**Given** the user has run several commands in a board-view terminal tile and an AI headline is visible on hover
**When** the user spotlights the same terminal (or moves it to a rail / detached window)
**Then** the spotlight overlay displays the same headline and phase immediately on first hover, without restarting the LLM session
**And** expanding the overlay shows the same timeline of commands and summaries that was visible in the board view

### Scenario F041-S17: Sensitive input shows placeholder, never echoes content

**Given** a terminal command (e.g., `sudo` or `git pull` over SSH) prompts for a password and disables echo
**When** the user types the password and presses Enter
**Then** the observer's deferred classification runs (immediate + retries) and the surface never shows the typed text within 1 s
**And** the observer publishes `.sensitive`
**And** the collapsed pill shows "sensitive information" with phase "idle"
**And** the expanded timeline shows a "sensitive information" entry that yields only the placeholder text in both Summary and Original modes
**And** the entry's copy button copies only the placeholder text
**And** no LLM regeneration is triggered by the sensitive event
**And** subsequent visible commands trigger regenerations whose prompt window contains the surrounding visible commands but not the sensitive content
**And** the compose history does not contain the sensitive content

### Scenario F041-S19: Render-lag on visible command resolves via retry

**Given** the user types a command at a normal shell prompt and presses Enter
**When** Ghostty's render of the typed echo lags behind the Enter event
**Then** the observer's first synchronous visibility check fails
**And** within at most 1 s the deferred retries find the typed text on the surface
**And** the observer publishes `.visible(text)` and the command is treated as a normal visible command (compose history append, LLM ingestion)

### Scenario F041-S20: Compose-UI submission bypasses surface check

**Given** the user authors a command in the VibeCast or Spotlight compose field
**When** the user presses Send
**Then** `TerminalSession.recordSentInput` calls `TerminalInsightObserver.recordSubmittedFromComposeUI`
**And** the observer publishes `.visible(text)` immediately, regardless of what is currently rendered on the terminal surface
**And** the command appears in compose history and is fed to the AI summary like any other visible command

### Scenario F041-S18: All user messages persisted within a session

**Given** the user has submitted 30 visible commands in a single terminal session
**When** the user expands the overlay
**Then** the timeline contains all 30 commands in reverse chronological order
**And** the LLM prompt window for the most recent regeneration includes only the last 20 commands (token-budget bound), without dropping older entries from the persisted timeline

## Acceptance Criteria

- All scenarios (F041-S01 through F041-S20) have passing test coverage.
- AI summary generation uses `@Generable` structured output with a persistent `LanguageModelSession`.
- Collapsed pill shows AI headline when Apple Intelligence is available, raw last command otherwise, and the localized "sensitive information" placeholder when the most recent input was sensitive.
- Expanded view shows every user message recorded during the session — visible commands and sensitive placeholders — capped only by a generous safety limit.
- Generation timeout of 20 seconds is enforced via `TaskGroup` race with graceful fallback.
- TUI suppression and auto-dismiss behaviors are preserved from F001-R47/R48.
- Dismiss preserves headline for re-hover.
- `TerminalContextSummarySession` is the single owner of per-terminal AI state, attached to `TerminalSession`, surviving SwiftUI surface transitions; `TerminalContextSummaryViewModel` is a thin per-mount projection.
- The summary session factory in `AppContainer.makeDefault()` consults a single shared `ExperimentalFeaturesService` rather than instantiating its own.
- Glass style applied via `scrollAssistGlassBackground` helper (Liquid Glass on macOS 26+, ultraThinMaterial fallback).
- Timeline Summary/Original toggle switches visible text per entry; copy respects active mode.
- Panel auto-collapses after 0.4s on hover out with cancellable timer.
- Copy button shows hover highlight and checkmark feedback on click.
- The observer exposes two input methods (`recordTypedKeystroke`, `recordSubmittedFromComposeUI`) with distinct trust treatments. The keystroke path defers classification with immediate + 6 × 150 ms retries (1 s budget) and publishes `.sensitive` only when the surface never shows the typed text. The compose-UI path classifies `.visible` immediately by trust boundary.
- Compose history is the responsibility of a single Combine subscription on `TerminalInsightObserver.$lastRecordedInput` held by `TerminalSession`; sensitive input never reaches it.
- Sensitive input never appears in the LLM prompt window, the persistent LLM session conversation history, the compose history store, or the displayed timeline text — only the localized placeholder is shown.

## Open Questions

1. Should the keyboard shortcut for expand/collapse be added alongside tap?
2. Should the `TimelineEntry.Kind` cases beyond `.command` (`.toolCall`, `.message`, `.status`) be removed until agent integration is implemented?
3. Should the experimental flag toggling re-attach/detach the summary session at runtime instead of only on session construction?

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial draft |
| 2026-04-25 | Updated to match implementation: removed agent integration (F040/F011 runtime dependency), simplified input to terminal commands only, added persistent chat session, String-based phase, overlay container pattern, dismiss-preserves-headline, availability-gated fallback |
| 2026-05-20 | Added F041-R12 (glass style), F041-R13 (Summary/Original toggle), F041-R14 (copy respects mode), F041-R15 (copy button feedback), F041-R16 (auto-collapse on hover out). Updated F041-S09 for auto-collapse. Added scenarios S13–S15. |
| 2026-05-24 | Refactored F041-R11 to require service-owned per-terminal state (`TerminalContextSummarySession`) attached to `TerminalSession`; view model becomes a thin per-mount projection. Updated F041-R03 to require persisting all user messages within the session and to extend the timeline to include sensitive placeholders. Updated F041-R06 timeout from 2s to 20s. Added F041-R17 (sensitive input handling) and scenarios S16–S18. Removed prior cap-of-15 timeline limit. |
| 2026-05-25 | Refactored F041-R17 to split the observer API into a keystroke path (deferred screen-visibility classification: immediate + 6 × 150 ms retries, 1 s budget) and a compose-UI path (`.visible` by trust boundary). Compose history flows through a single Combine subscription on `$lastRecordedInput`; the previous synchronous raw-text fallback was removed. Added scenarios S19 (render-lag retry resolves visible) and S20 (compose-UI bypass). Refined F041-R13 and F041-S13: the Summary/Original toggle now filters by entry kind (AI-summary rows vs raw-input rows) rather than per-row text, with sensitive placeholders shown in both modes. |
