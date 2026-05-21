# Terminal Scroll Assist — Technical Design

## Overview

Scroll Assist is a SwiftUI overlay rendered above each `TerminalSessionHostView` in the bottom-right corner. It owns a small view model with three actions: jump-up, jump-down, and toggle-search. Behavior fans out to a backend-agnostic service (`TerminalScrollbackReader`) that adapts to either the Ghostty surface API or tmux's CLI commands depending on whether the session is tmux-backed.

The feature has no persistence, no protocol changes, and no shell integration requirements. It reads existing in-memory state (`ComposeHistoryStore`) and the live terminal buffer.

## Architecture

```
ContentView (SwiftUI)
    └── TerminalSessionHostView
          ├── TerminalSessionHostRepresentable (NSViewRepresentable wrapping the terminal)
          └── overlay(alignment: .bottomTrailing)
                └── TerminalScrollAssistOverlay (this feature)
                      ├── @StateObject ScrollAssistViewModel
                      ├── States: collapsed ball (24px, 45% opacity) ↔ expanded D-pad cross
                      ├── D-pad layout: ⬆ top, ⬇ bottom, 🔍 center, temp-terminal left, split-terminal right
                      ├── Each button: individual glass circle (scrollAssistGlassBackground helper)
                      ├── Drag gesture: @State dragOffset persists position within terminal bounds
                      ├── Collapse timer: 0.8s after mouse exit (cancelled if search is open)
                      └── reads: ComposeHistoryStore, calls: TerminalScrollbackReader

TerminalScrollbackReader (service, @MainActor)
    ├── readScrollback(for: session) -> String         // dispatches by engine
    ├── search(in: session, query:) -> [Match]         // string search
    └── scrollToMatch(in:match:allMatches:query:)      // dispatches by engine
          ├── Ghostty path: ghostty_surface_binding_action("scroll_to_row:N")
          └── Tmux path: tmux copy-mode + search-forward
```

### Ball / Expanded State Machine

- **Collapsed**: Default. 24px translucent circle at `dragOffset` position. Renders with `scrollAssistGlassBackground` (Liquid Glass on macOS 26+, ultraThinMaterial fallback).
- **Expanded**: On hover/tap. Spring animation expands into 5-button D-pad cross. Each button is a separate glass circle — no shared container rectangle.
- **Collapse trigger**: Mouse leaves the D-pad area → 0.8s timer starts → collapses to ball. Timer is cancelled if `isSearchVisible == true`.
- **Drag**: `DragGesture` on the ball/pad updates `@State dragOffset: CGSize`. Position persists per session lifetime.

## Data Flow

### Up / Down navigation

```
User clicks ⬆ on overlay
    → ScrollAssistViewModel.navigatePrevious()
    → Read entries: composeHistoryStore.entries(for: session.id)
    → Decrement internal cursor (or initialize to last entry)
    → Get target text: entries[cursor]
    → Call TerminalScrollbackReader.scrollToText(in: session, text: target)
        → Ghostty: read scrollback, find LAST occurrence of text, scroll_to_row
        → Tmux:    copy-mode + history-top + search-backward(text) (lands on most recent)
```

Cursor state lives in `ScrollAssistViewModel` and resets when:
- The user types in the terminal (observed via existing `TerminalInsightObserver.recordKeystroke()` or by listening to `composeHistoryStore` for new entries).
- The user closes the overlay panel.

### Search

```
User types in search field
    → ScrollAssistViewModel.runSearch(query)
    → TerminalScrollbackReader.readScrollback(for: session)
    → Linear scan, collect matches with line indices
    → Render matches in overlay results list

User clicks a result row
    → ScrollAssistViewModel.scrollToMatch(match)
    → TerminalScrollbackReader.scrollToMatch(in:match:allMatches:query:)
        → Ghostty: scroll_to_row:N where N = match.lineIndex - viewportRows/2
        → Tmux: copy-mode + history-top + search-forward(query) × (matchIndex+1)
```

## API / Command Contracts

### Internal API

```swift
@MainActor
enum TerminalScrollbackReader {
    struct Match: Identifiable, Sendable {
        let id: UUID
        let lineIndex: Int
        let lineText: String
    }

    static func readScrollback(for session: TerminalSession) async -> String
    static func search(in session: TerminalSession, query: String, limit: Int) async -> [Match]
    static func scrollToMatch(in session: TerminalSession, match: Match, allMatches: [Match], query: String) async
    static func scrollToText(in session: TerminalSession, text: String) async
}
```

### External commands invoked

- **Ghostty**: `ghostty_surface_read_text` (with `GHOSTTY_POINT_SCREEN`), `ghostty_surface_binding_action("scroll_to_row:N")`.
- **Tmux**: `tmux capture-pane -pS -`, `tmux copy-mode`, `tmux send-keys -X history-top`, `tmux send-keys -X search-forward <query>`, `tmux send-keys -X search-backward <text>`.

## State Management

`ScrollAssistViewModel` (per terminal host view, owned by the SwiftUI overlay):

```swift
@Published var isSearchVisible: Bool
@Published var searchQuery: String
@Published var matches: [TerminalScrollbackReader.Match]
@Published var historyCursor: Int?     // nil = at live
@Published var isPanelHovered: Bool
@Published var isExpanded: Bool        // false = collapsed ball, true = D-pad cross
var dragOffset: CGSize                 // persisted position within terminal bounds
var collapseTimer: DispatchWorkItem?   // 0.8s collapse delay
```

Lifecycle:
- Created with `@StateObject` in `TerminalSessionHostView`.
- Bound to the `TerminalSession` via initializer.
- Observes `ComposeHistoryStore` indirectly by reading entries on demand (no need for reactive binding for the initial scope).

## Dependencies (frameworks, libraries)

- **SwiftUI** — overlay rendering and animation.
- **GhosttyKit** — for `ghostty_surface_*` calls.
- **Foundation.Process** — for invoking tmux CLI commands.
- **No new third-party dependencies.**

## Platform Considerations

- macOS 26+ — Liquid Glass via `scrollAssistGlassBackground` helper. SwiftUI animations and `.ultraThinMaterial` are also available.
- Each D-pad button is rendered as an individual glass circle using the same helper.
- The overlay must coexist with existing overlays on `TerminalSessionHostView` (`TerminalContextSummaryOverlayContainer` at top alignment). Bottom-right alignment avoids collision.
- Click events on overlay buttons must not pass through to the terminal NSView. Use `.contentShape(Rectangle())` and `.onTapGesture` (the `Button` style was unreliable over NSViewRepresentable in earlier testing).

## Performance Constraints

- Reading scrollback on every keystroke in the search field is acceptable for terminals up to ~50,000 lines (current default). For larger buffers, consider caching the snapshot per search session.
- tmux `capture-pane` shells out — performed off the main actor via `Task.detached`.
- Hover-driven opacity transitions use 0.2s ease-out animations; no per-frame work.

## Migration / Rollout Notes

- No feature flag required. Lands directly on all terminals once merged.
- Removes the prior orange "Search" button POC. The new control pad supersedes it.
- No data migration. `ComposeHistoryStore` is already in use and centralized via `TerminalSession.recordSentInput`.

## Failure Modes

| Condition | Behavior |
|-----------|----------|
| `ComposeHistoryStore` missing | Up/Down dimmed, log warning, search still works |
| Ghostty surface not yet created | All actions become no-ops |
| Tmux binary missing | Tmux path falls back to no-op |
| Search query produces no matches | Empty-state message in results panel |
| User clicks ⬆ at oldest entry | No-op; button remains visually dim if at boundary |

## Test Plan

- Unit: cover `TerminalScrollbackReader.search` regex behavior, line indexing, and match limit.
- Integration: simulate `ComposeHistoryStore` populated with 3 entries, verify up/down cursor advancement.
- Manual: validate scroll accuracy in Ghostty, in tmux fresh, and in a resumed tmux session per F046-S05.
