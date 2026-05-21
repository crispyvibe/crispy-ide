# Compose History — Feature Spec

Status: draft
Feature ID: F043
Domain: D1 App Shell

> **Doc layout:** This feature intentionally uses a single-file layout rather
> than the four-doc convention in [`CONVENTION.md`](../../CONVENTION.md). The
> feature is a small, well-scoped shared service with a stable surface, and
> the combined spec + technical design is short enough to read in one pass.
> Security and usage notes are folded into the sections below. If the feature
> grows (persistence, search, cross-bucket modes), promote to the full
> four-doc layout at that point.

## Overview

Arrow-key history recall for text compose inputs across the app. When the
user submits a message through a participating compose surface (terminal
spotlight, ACP chat, VibeCast), the text is appended to a per-input history
bucket. Pressing Up on the first visual line of the same input recalls the
previous entry; Down advances forward; stepping past the newest entry
restores the in-progress draft. Multiline cursor navigation is preserved —
up/down on interior lines move the caret normally.

History is in-memory only, scoped per backend resource identity (terminal
session id, ACP store id, VibeCast session id), and cleared when the owning
resource is disposed.

## Dependencies

- F003 Terminal Spotlight — consumer
- F011 ACP — consumer
- F028 VibeCast — consumer
- F016 Keyboard Shortcuts — arrow-key binding context

## Requirements

### F043-R01: Up recalls previous entry when caret is on first visual line

Pressing Up in a participating compose input with no modifier keys and no
overlay active MUST, when the caret is on the first visual line, replace
the compose text with the previous history entry for the input's bucket.

### F043-R02: Down advances or restores draft when caret is on last visual line

Pressing Down with no modifier keys and no overlay active MUST, when the
caret is on the last visual line:
- If in history, advance to the newer entry.
- If at the newest entry, exit history and restore the pending draft (the
  text the user had before entering history).

The pending draft is recorded only at the moment the user first enters
history from idle. It MUST be cleared whenever the navigator returns to
idle (via send, user edit of recalled text, identity change, or exit past
newest). A send always clears it so an in-progress draft that was
abandoned in favor of sending something else is NOT resurfaced later.

### F043-R03: Interior-line arrows move caret normally

Up on any visual line except the first, and Down on any visual line except
the last, MUST preserve default NSTextView caret movement. History MUST NOT
be triggered.

### F043-R04: Modifier-combined arrows fall through

Option, Command, Shift, or Control combined with Up/Down MUST never trigger
history navigation. Default text-view behaviour applies.

### F043-R05: Deduplicate consecutive duplicates

Submitting a string identical to the most recent history entry MUST NOT
append a new entry. Other duplicates (separated by at least one distinct
entry) are retained.

### F043-R06: In-memory only

History MUST NOT be persisted to disk. The store is recreated empty on app
launch.

### F043-R07: Editing a recalled entry exits history

Any text change originated by the user (not by history navigation) MUST
exit history-navigation mode for that input: cursor reset, pending draft
discarded.

### F043-R08: Per-bucket isolation

History buckets are keyed by a stable resource identity (UUID). Entries
MUST NOT be visible across buckets. The compose view MUST re-bind the
navigator when the underlying identity changes (e.g., switching tabs in
terminal spotlight, switching threads in ACP).

### F043-R09: Per-bucket cap

Each bucket MUST retain at most N most-recent entries (default 500). On
overflow, oldest entries are dropped.

### F043-R11: Suppressed by overlays

When an overlay captures Up/Down (e.g., inline-trigger picker), history
navigation MUST NOT run; the overlay's handler takes priority.

### F043-R12: Selection invariant

History navigation MUST only fire when the current selection is a
zero-width caret. With an active selection, Up/Down collapses the
selection normally (NSTextView default); history is not triggered on that
keystroke.

## Scenarios

### F043-S01: Empty history, Up pressed

**Given** the compose input's history bucket is empty,
**When** the user presses Up on the first line,
**Then** nothing happens (no text change, no beep, draft preserved).

### F043-S02: Single-line recall and restore

**Given** history contains `["ls", "pwd"]` and the user is typing `echo 1`,
**When** the user presses Up,
**Then** the input shows `pwd` with caret at end.
**When** the user presses Up again,
**Then** the input shows `ls`.
**When** the user presses Down,
**Then** the input shows `pwd`.
**When** the user presses Down again,
**Then** the input shows `echo 1` (draft restored), history navigation
exited.

### F043-S03: Multiline draft, caret in middle, Up moves caret

**Given** the user has typed a 5-line draft with the caret on line 3,
**When** the user presses Up,
**Then** the caret moves to line 2. History is not triggered.

### F043-S04: Multiline draft, caret on first line, Up enters history

**Given** the user has typed a 5-line draft with the caret on line 1,
**And** history is non-empty,
**When** the user presses Up,
**Then** the pending draft is saved, the input is replaced with the newest
history entry, caret is at the end of the recalled entry.

### F043-S05: Multiline recalled entry, Up traverses within before history

**Given** the user recalled a 5-line entry (caret at end, on line 5),
**When** the user presses Up,
**Then** the caret moves to line 4 within the recalled entry.
**When** the user repeats Up until reaching line 1 and presses Up again,
**Then** the previous history entry replaces the input with caret at end.

### F043-S06: Edit while recalled → reset

**Given** the user has recalled entry "X" and has not yet edited it,
**When** the user types any character,
**Then** history navigation exits; pending draft is discarded; the next
Up starts a fresh traversal from the newest entry.

### F043-S07: Dedupe consecutive duplicates

**Given** history ends with `["ls"]`,
**When** the user submits `ls` again,
**Then** history remains `["ls"]` (one entry).

### F043-S08: Identity switch resets navigation state

**Given** the user is navigating history in spotlight for session A,
**When** they switch the spotlight to session B,
**Then** the navigator rebinds to B's bucket; cursor and pending draft
are cleared; entering history from the newly-bound input starts fresh.

### F043-S10: Overlay suppression

**Given** the inline-trigger picker is presented over the compose input,
**When** the user presses Up or Down,
**Then** the picker handles the keystroke. History is not touched.

### F043-S11: Modifier arrows ignored

**Given** history is non-empty, caret on first line,
**When** the user presses Option+Up (word-jump), Cmd+Up (doc start),
or Shift+Up (extend selection),
**Then** default NSTextView behaviour runs. History is not triggered.

### F043-S12: Pending draft is cleared on send

**Given** the user has typed `draft A` but not sent,
**And** pressed Up to navigate history (so `pendingDraft == "draft A"`),
**When** the user sends a message (either an edited recalled entry or new
text),
**Then** the sent text is appended to history (deduped if identical to
newest),
**And** the navigator resets to idle,
**And** `pendingDraft` is cleared.
**When** the user presses Up again,
**Then** the newly sent message is recalled and the saved pending draft
at that moment is `""` (the input was empty after send), not `draft A`.
**When** the user presses Down past the newest entry,
**Then** the input is empty — `draft A` is NOT restored.

## Architecture

### Components

```
AppContainer
└── ComposeHistoryStore (singleton, in-memory, [UUID: [String]])

Per compose view (terminal spotlight / ACP / VibeCast):
├── ComposeHistoryNavigator (ObservableObject)
│   ├── references ComposeHistoryStore
│   ├── holds cursor: Int? and pendingDraft: String?
│   └── exposes attach(to:), append(_:), navigateBack(_:), navigateForward(_:),
│       resetOnUnrelatedEdit()
└── NSTextView subclass key handler
    ├── detects caret on first/last visual line via NSLayoutManager
    └── routes Up/Down (plain, no selection, no overlay active) to navigator
```

### Store API

```swift
@MainActor
final class ComposeHistoryStore {
    func entries(for key: UUID) -> [String]
    func append(_ text: String, for key: UUID)  // dedupes consecutive, enforces cap
}
```

### Navigator API

```swift
@MainActor
final class ComposeHistoryNavigator: ObservableObject {
    init(store: ComposeHistoryStore)

    func attach(to key: UUID?)                       // resets cursor + draft on key change
    func append(_ text: String)                      // after successful send
    func navigateBack(currentText: String) -> Nav    // up on first line
    func navigateForward(currentText: String) -> Nav // down on last line
    func resetOnUnrelatedEdit()                      // any user edit not from navigation

    enum Nav {
        case noChange
        case replace(text: String, caret: CaretTarget)   // .end or .start
    }

    private(set) var isApplyingNavigation: Bool
}
```

### State machine (inside the navigator)

Two states:

- **idle** — `cursor == nil`, `pendingDraft == nil`.
- **browsing(index)** — `cursor == index`, `pendingDraft` holds the text
  the user had before entering history.

Transitions:

| From | Event | To | Output |
|------|-------|----|--------|
| idle | navigateBack, history empty | idle | `.noChange` |
| idle | navigateBack, history non-empty | browsing(last) | save draft; `.replace(entries.last, .end)` |
| idle | navigateForward | idle | `.noChange` |
| browsing(i) | navigateBack, i > 0 | browsing(i-1) | `.replace(entries[i-1], .end)` |
| browsing(0) | navigateBack | browsing(0) | `.noChange` |
| browsing(i) | navigateForward, i < last | browsing(i+1) | `.replace(entries[i+1], .end)` |
| browsing(last) | navigateForward | idle | `.replace(pendingDraft ?? "", .end)` (pendingDraft cleared) |
| any | attach(to: newKey ≠ currentKey) | idle | — |
| any | resetOnUnrelatedEdit | idle | — |
| any | append(text) | idle | append to store (dedupe); pendingDraft cleared |

### Multiline routing rules (inside the NSTextView subclass)

On keyDown with `keyCode == UpArrow` or `DownArrow`:

1. If modifier keys are present (Option/Cmd/Shift/Control) → super.keyDown. Do nothing else.
2. If the current selection has non-zero length → super.keyDown. (Selection collapses per default behaviour; history not fired.)
3. If an overlay owner is active (e.g., inline trigger picker present) → forward to the overlay's handler (as today). Do not call navigator.
4. For Up: if caret glyph is on the same line fragment as glyph 0 → call `navigator.navigateBack(currentText:)`; apply `Nav`. Consume the event.
5. For Down: if caret glyph is on the same line fragment as the last glyph → call `navigator.navigateForward(currentText:)`; apply `Nav`. Consume the event.
6. Otherwise → super.keyDown.

Line-fragment comparison uses `NSLayoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)`. Visual lines, not logical lines — a soft-wrapped single logical line counts correctly as multiple visual lines.

### Applying `Nav.replace`

Navigator sets `isApplyingNavigation = true`, replaces the text view's
string, sets the caret position (start or end), sets `isApplyingNavigation = false`.

The text-change observer in the compose view checks `navigator.isApplyingNavigation`:
- `true` → ignore this change event.
- `false` → call `navigator.resetOnUnrelatedEdit()`.

### Consumer wiring checklist (per feature)

Each of the three feature surfaces does:

1. Create `@StateObject var navigator = ComposeHistoryNavigator(store: appContainer.composeHistoryStore)` in the compose view.
2. On view appearance and on identity change, call `navigator.attach(to: currentKey)`:
   - Terminal spotlight: `session.id`
   - ACP compose: ACP store id (shared across thread switches within the same pane)
   - VibeCast compose: VibeCast session id
3. In the send action, after the submit succeeds, call `navigator.append(sentText)`.
4. In the NSTextView subclass, implement the Up/Down routing from the "Multiline routing rules" section above. Expose an `onHistoryBack`/`onHistoryForward` closure that the SwiftUI representable passes in; the closures call the navigator and apply the result.
5. In the SwiftUI compose view, observe text changes: when text changes and `navigator.isApplyingNavigation == false`, call `navigator.resetOnUnrelatedEdit()`.

## Security Notes

(Would live in `threat-model.md` under the four-doc layout. Folded in here.)

- **Secret recall** — a user who types a password, API key, or other
  sensitive string into a compose input and submits it can later recall it
  with Up. **Mitigation:** in-memory only, per-bucket cap, dies with app
  restart. Document the behaviour in release notes and the usage-facing
  copy so users understand history is kept for the session. Future:
  consider a redaction hook for callers to mark sends as sensitive.
- **Cross-bucket leakage** — a bug in key resolution could expose one
  bucket's entries in another. **Mitigation:** buckets keyed by UUID of
  the backing resource; navigator's `attach(to:)` rebinds and clears
  state; unit tests assert isolation.
- **Memory exhaustion** — a runaway automation submitting continuously
  could fill a bucket. **Mitigation:** per-bucket cap (500 default),
  drop-oldest eviction.
- **PII / telemetry** — history entries are never logged, never
  telemetered, never written to `AppDiagnostics`.

## Usage (Brief)

(Would live in `usage-guide.md` under the four-doc layout. Folded in here.)

- Press **Up** in a compose input on its first line to recall the
  previous message. Repeat to go further back.
- Press **Down** on the last line to go forward, or exit history and
  restore your in-progress draft.
- While editing a multi-line message, Up and Down move the caret
  normally. History only kicks in when the caret is on the top (for Up)
  or bottom (for Down) visual line.
- History is in-memory and per compose input. Terminal spotlight, ACP
  chat, and VibeCast each have independent history per session /
  conversation.
- History does not persist across app restarts.
- History holds up to 500 most-recent messages per input.

## Acceptance Criteria

- Arrow-key response < 16 ms (PERF).
- Keyboard-only operable (A11Y-2).
- All state-machine transitions unit-tested (TEST).
- No persisted data, no telemetry on recalled content (SEC).
- Verified manually in all three consumer surfaces with single-line,
  multi-line, soft-wrapped, and empty-history cases.

## Open Questions

- **Esc to exit history**: nice-to-have exit-and-restore gesture via Esc.
  Deferred; may conflict with existing Esc bindings on specific surfaces.
- **Redaction hook for sensitive sends**: would allow callers to submit
  without appending to history. Deferred until a concrete use case
  surfaces.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-06 | Initial draft. Single-file layout per deliberate choice. ACP bucket key resolved to ACP store id (history shared across thread switches in the same pane). Clarified pending-draft lifecycle: cleared on send so an abandoned in-progress draft is never resurfaced (added F043-S12, tightened F043-R02). | — |
