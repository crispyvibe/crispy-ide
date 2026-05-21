# Terminal Context Summary — Technical Design

## Overview

This document describes the architecture, data flow, and implementation details for the Terminal Context Summary feature (F041). The feature extends the existing `TerminalInsightObserver` infrastructure with AI-powered summary generation via Apple's Foundation Models framework using a persistent per-terminal chat session.

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│          TerminalContextSummaryOverlayContainer (View)           │
│  @StateObject TerminalContextSummaryViewModel                    │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │         TerminalContextSummaryOverlay (View)                 ││
│  │  ┌──────────────────────┐  ┌───────────────────────────────┐││
│  │  │  Collapsed Pill       │  │  Expanded Timeline View       │││
│  │  │  • AI headline        │  │  • Recent terminal commands   │││
│  │  │  • Phase icon + color │  │  • Reverse chronological      │││
│  │  │  • Generating spinner │  │  • Chevron-right icons        │││
│  │  │  • Expand chevron     │  │                               │││
│  │  └──────────────────────┘  └───────────────────────────────┘││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              TerminalContextSummaryViewModel                     │
│  @MainActor final class, ObservableObject                       │
│                                                                  │
│  @Published headline: String?                                    │
│  @Published phase: String = "idle"                               │
│  @Published isExpanded: Bool                                     │
│  @Published timelineEntries: [TimelineEntry]                     │
│  @Published isGenerating: Bool                                   │
│                                                                  │
│  Private state:                                                  │
│  • recentCommands: [String] (max 10)                             │
│  • generationTask: Task<Void, Never>?                            │
│  • debounceWorkItem: DispatchWorkItem?                           │
│  • observerCancellable: AnyCancellable                           │
│                                                                  │
│  Dependencies (init-injected):                                   │
│  • insightObserver: TerminalInsightObserver                      │
│  • summaryGenerator: any ContextSummaryGenerating                │
└─────────────────────────────────────────────────────────────────┘
          │                              │
          ▼                              ▼
┌──────────────────┐        ┌────────────────────────────┐
│TerminalInsight   │        │ContextSummaryGenerator     │
│Observer (existing)│        │                            │
│• lastInput       │        │• Persistent LanguageModel  │
│• isTUIMode       │        │  Session (stored as Any?)  │
│• $lastInput pub  │        │• System instruction        │
│                  │        │• @Generable structured out │
│                  │        │• 2s timeout via TaskGroup  │
└──────────────────┘        └────────────────────────────┘
```

### Layer Mapping

```
SwiftUI View (TerminalContextSummaryOverlayContainer)
    → @StateObject ViewModel (TerminalContextSummaryViewModel)
        → Services:
            TerminalInsightObserver (existing, terminal command input)
            ContextSummaryGenerator (new, Foundation Models)
        → Protocols:
            ContextSummaryGenerating
```

## Data Flow

### Summary Generation Flow

```
TerminalInsightObserver.$lastInput publishes new command
    │
    ▼
ViewModel.recordCommand() — appends to recentCommands buffer (max 10)
ViewModel.scheduleRegeneration() — debounce 500ms via DispatchWorkItem
    │
    ▼ (after 500ms debounce)
ViewModel.regenerateSummary()
    │
    ├── Cancel previous generationTask
    ├── Set isGenerating = true
    ├── Build ContextSummaryInput(recentInput: recentCommands)
    │
    ├── Call summaryGenerator.generate(input:)
    │   │
    │   ├── Check SystemLanguageModel.default.availability
    │   │   └── Not .available → return nil
    │   │
    │   ├── Get or create persistent LanguageModelSession
    │   │   └── Session initialized with system instruction on first use
    │   │
    │   ├── Format message: "Recent input:\n  " + last 10 commands joined
    │   │
    │   ├── TaskGroup race:
    │   │   ├── Task 1: session.respond(to: message, generating: GeneratedContextSummary.self)
    │   │   │   └── Returns TerminalContextSummary(headline, phase)
    │   │   └── Task 2: Task.sleep(2 seconds) → return nil
    │   │
    │   ├── First result wins, cancel other
    │   │
    │   ├── Success → return TerminalContextSummary
    │   └── Error → nil session (_session = nil), return nil
    │
    ├── Result present → update headline + phase
    └── Result nil → fallback: headline = insightObserver.lastInput, phase = "idle"
```

### Timeline Assembly Flow

```
ViewModel.assembleTimeline() — called on expand()
    │
    ├── Take last 10 from recentCommands
    ├── Map each to TimelineEntry(kind: .command, text: command)
    ├── Take suffix(15), reverse for newest-first
    └── Publish to @Published timelineEntries
```

### Hover / Expand Flow

```
Mouse enters terminal tile → isHovering = true
    │
    ├── headline != nil? → Show collapsed pill
    ├── Start 4s auto-dismiss timer (DispatchWorkItem)
    │
    ├── User taps pill
    │   ├── viewModel.toggle()
    │   ├── If expanding: assembleTimeline()
    │   └── If collapsing: isExpanded = false
    │
    ├── 4s elapsed (collapsed, not expanded) → collapse()
    │
    └── Mouse leaves (not expanded) → cancel auto-dismiss
```

## API / Command Contracts

### ContextSummaryGenerating Protocol

```swift
@MainActor
protocol ContextSummaryGenerating {
    func generate(input: ContextSummaryInput) async -> TerminalContextSummary?
}
```

### ContextSummaryInput

```swift
struct ContextSummaryInput {
    let recentInput: [String]  // last terminal commands (up to 10)
}
```

### GeneratedContextSummary (@Generable, macOS 26+)

```swift
@available(macOS 26.0, *)
@Generable
struct GeneratedContextSummary {
    @Guide(description: "A concise one-line summary of what the developer is currently doing in the terminal")
    var headline: String

    @Guide(description: "The current activity phase. Must be one of: idle, building, testing, debugging, deploying, reviewing, editing, searching")
    var phase: String
}
```

### TerminalContextSummary (all OS versions)

```swift
struct TerminalContextSummary {
    var headline: String
    var phase: String
}
```

### TimelineEntry

```swift
struct TimelineEntry: Identifiable {
    let id: UUID
    let kind: Kind
    let text: String
    let timestamp: Date

    enum Kind {
        case command
        case toolCall   // reserved for future agent integration
        case message    // reserved for future agent integration
        case status     // reserved for future agent integration
    }
}
```

### System Instruction (LanguageModelSession)

```
You are observing a developer's terminal session in an IDE.
Each message contains what the user recently typed. Based on the
evolving activity, write a short status update (under 12 words)
describing what they are actively doing right now.
Build on your previous understanding — if the activity progresses
(e.g., editing → building → testing), reflect the current stage.
Do not include file paths, secrets, tokens, or passwords.
Use plain language a teammate would understand at a glance.
```

## State Management

### ViewModel State

`TerminalContextSummaryViewModel` is `@MainActor final class` conforming to `ObservableObject`.

| Property | Type | Mutation |
|----------|------|---------|
| `headline` | `String?` | `@Published private(set)` — set by `regenerateSummary()` |
| `phase` | `String` | `@Published private(set)` — set by `regenerateSummary()`, default `"idle"` |
| `isExpanded` | `Bool` | `@Published` — toggled by user interaction |
| `timelineEntries` | `[TimelineEntry]` | `@Published private(set)` — assembled on expand |
| `isGenerating` | `Bool` | `@Published private(set)` — true during LLM inference |

### Private State

| Property | Type | Purpose |
|----------|------|---------|
| `recentCommands` | `[String]` | Rolling buffer of last 10 commands |
| `generationTask` | `Task<Void, Never>?` | Active generation, cancelled on new trigger |
| `debounceWorkItem` | `DispatchWorkItem?` | 500ms debounce for regeneration |
| `observerCancellable` | `AnyCancellable` | Subscription to `insightObserver.$lastInput` |

### Persistent Session State (Generator)

| Property | Type | Purpose |
|----------|------|---------|
| `_session` | `Any?` | Stored `LanguageModelSession`, type-erased for availability |
| `timeoutSeconds` | `TimeInterval` | Configurable timeout, default 2.0 |

The session is lazily created on first access via a computed property gated by `@available(macOS 26.0, *)`. It persists across generation calls, accumulating conversation history. On error, the session is nilled and recreated on the next call.

### View Ownership

`TerminalContextSummaryOverlayContainer` owns the view model as `@StateObject`. Its `nonisolated init` uses `MainActor.assumeIsolated` to create the `StateObject` wrappedValue:

```swift
nonisolated init(observer: TerminalInsightObserver, isHovering: Bool) {
    self.observer = observer
    self.isHovering = isHovering
    _viewModel = StateObject(wrappedValue: MainActor.assumeIsolated {
        TerminalContextSummaryViewModel(
            insightObserver: observer,
            summaryGenerator: ContextSummaryGenerator()
        )
    })
}
```

### Phase-to-Icon/Color Mapping (View)

The overlay view maps known phase strings to SF Symbols and colors:

| Phase | Icon | Color |
|-------|------|-------|
| `"building"` | `hammer` | `.orange` |
| `"testing"` | `checkmark.circle` | `.green` |
| `"debugging"` | `ant` | `.red` |
| `"deploying"` | `arrow.up.circle` | `.orange` |
| `"reviewing"` | `eye` | `.blue` |
| `"editing"` | `pencil` | `.purple` |
| `"searching"` | `magnifyingglass` | `.blue` |
| default/`"idle"` | `circle` | `.secondary` |

## Dependencies (frameworks, libraries)

| Dependency | Purpose | Version |
|------------|---------|---------|
| Foundation Models | On-device LLM for summary generation | macOS 26+ |
| SwiftUI | Overlay view rendering | macOS 26+ |
| Combine | `@Published` observation, `$lastInput` subscription | macOS 26+ |

No new third-party dependencies. All functionality uses Apple frameworks.

## Platform Considerations

- **Availability-gated, not baseline**: Foundation Models is gated behind `#if canImport(FoundationModels)` and `@available(macOS 26.0, *)`. The app compiles and runs on earlier macOS versions — the feature gracefully degrades to raw command display.
- **Session stored as `Any?`**: The `LanguageModelSession` is stored as `Any?` and cast in an `@available` computed property. This avoids availability errors at the storage level.
- **Model availability check**: Before each generation, `SystemLanguageModel.default.availability` is checked. If not `.available` (model downloading, unsupported hardware), generation returns `nil`.
- **Apple Silicon**: Foundation Models runs on the Neural Engine. Intel Macs running macOS 26 (if supported) may have degraded performance.

## Performance Constraints

| Metric | Target | Rationale |
|--------|--------|-----------|
| Summary generation latency | ≤ 2s (hard timeout) | Must not block hover UX; fallback to raw command |
| Timeline assembly | ≤ 5ms | Synchronous collection from in-memory buffer |
| Hover-to-pill render | ≤ 50ms | Must feel instant; no async work in the collapsed path |
| Memory overhead | ≤ 5MB per terminal | Cached summary + session history + observer state |
| Generation frequency | At most 1 concurrent per terminal | Cancel-and-replace prevents accumulation |

### Throttling

If multiple commands arrive within 500ms, only the last one triggers generation. The `DispatchWorkItem` debounce cancels earlier pending items.

## File Structure

```
Features/Terminal/ContextSummary/
├── Views/
│   ├── TerminalContextSummaryOverlay.swift      ← container + collapsed pill + expanded overlay
│   └── ContextSummaryTimelineView.swift         ← expanded timeline list
├── ViewModels/
│   └── TerminalContextSummaryViewModel.swift    ← state, triggers, generation coordination
├── Services/
│   ├── ContextSummaryGenerator.swift            ← persistent LanguageModelSession, generation + timeout
│   └── ContextSummaryGenerating.swift           ← protocol
└── Models/
    ├── TerminalContextSummary.swift             ← @Generable output struct + OS-agnostic result struct
    └── TimelineEntry.swift                      ← timeline data model
```

Note: No `ContextPhase.swift` — phase is a `String`, not an enum. The `@Generable` struct uses `@Guide` description to list valid values. The view maps strings to icons/colors.

### Modified files

- Terminal tile view (swap `TerminalInsightOverlay` → `TerminalContextSummaryOverlayContainer`)

### Rollback

If the feature needs to be reverted, restore the `TerminalInsightOverlay` reference at the call site. The existing insight infrastructure is untouched and remains functional.

## Future Enhancements

- **Agent integration (F040/F011)**: When agent-terminal linking is implemented, `ContextSummaryInput` can be extended with agent messages, tool calls, and thread titles. The `TimelineEntry.Kind` cases `.toolCall`, `.message`, and `.status` are already defined for this purpose.
- **AppContainer factory**: Currently the generator is created directly in the overlay container. A future refactor could add a `makeContextSummaryViewModel` factory to `AppContainer` for testability.

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial draft |
| 2026-04-25 | Updated to match implementation: removed agent integration dependencies, simplified to terminal-only input, persistent chat session, String phase, overlay container with MainActor.assumeIsolated, availability-gated generation |
