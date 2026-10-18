# Compose History — Feature Spec

Status: draft
Feature ID: F043
Domain: D1 App Shell

> **Doc layout:** This feature uses the combined-document waiver recorded in
> [`CONVENTION.md`](../../CONVENTION.md#document-layout-waivers). The feature
> is a small, draft shared service with a stable surface, and the combined
> requirements, design, security, usage, and acceptance material remains
> readable in one pass. Promote it to the full four-document layout before
> shipping, or earlier if persistence, search, cross-bucket modes, or document
> size triggers the waiver review.

## Overview

Arrow-key history recall for terminal Spotlight, ACP chat, and VibeCast compose inputs. The main SwiftUI root and detached board roots inject the same AppContainer-owned history store, so Up/Down recall follows the same rules in both window types. Submitted text is appended to a per-input history bucket. Pressing Up on the first visual line recalls the previous entry; Down advances forward; stepping past the newest entry restores the in-progress draft. Multiline cursor navigation is preserved—Up/Down on interior lines move the caret normally.

History is in-memory only and scoped per stable compose-owner key. ACP and
VibeCast use store/session identities; Spotlight terminal panes use full
project+tab, surface+tile+tab, or temporary-session identity. No production
owner-disposal path currently calls `ComposeHistoryStore.clear(for:)`, so
buckets survive owner disposal for the lifetime of the AppContainer and clear
only when that container is released (normally app restart). No history is
persisted.

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

### F043-R04: Modifier-combined arrows do not navigate history

Option, Command, Shift, or Control combined with Up/Down MUST NOT trigger
history navigation. Option+Up/Down is reserved by the shared compose editor
and MAY cycle the selected VibeCast terminal target when that consumer supplies
target-cycling actions. Other modifier-arrow behavior is delegated to the
compose surface or text view; it is not universally equivalent to NSTextView's
default behavior.

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

### F043-R08: Stable per-resource and per-Spotlight-pane isolation

History buckets MUST be keyed by a stable string identity and MUST NOT be visible across buckets. `ComposeHistoryStore` is created and retained by `AppContainer`, then passed to main and detached compose surfaces through explicit SwiftUI environment injection; it is not a singleton or globally discovered service. Terminal, ACP, and VibeCast compose views create independent history navigators from that injected store.

Each visible terminal member in a Spotlight combo MUST own a separate compose view, navigator, history bucket, and draft/image-draft state. Its bucket and draft identity MUST include the complete stable terminal scope rather than tab UUID alone:

- project terminal: normalized project path plus terminal tab UUID;
- standalone board terminal: board surface UUID plus tile UUID plus terminal tab UUID;
- temporary terminal: temporary session UUID.

ACP and VibeCast retain their own stable store/session keys. A navigator MUST rebind and clear cursor/pending draft when its complete identity changes. Terminal send MUST capture the pane identity, activate that pane first, revalidate the identity, resolve the live session after activation, and append only to that pane's bucket.

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
keystroke. When history replaces the text, the existing zero-width selection
location MUST be preserved and clamped to the replacement's UTF-16 length;
the caret MUST NOT be forced to the end unless clamping requires it.

## Scenarios

### F043-S01: Empty history, Up pressed

**Given** the compose input's history bucket is empty,
**When** the user presses Up on the first line,
**Then** nothing happens (no text change, no beep, draft preserved).

### F043-S02: Single-line recall and restore

**Given** history contains `["ls", "pwd"]` and the user is typing `echo 1`,
**When** the user presses Up,
**Then** the input shows `pwd` and the prior zero-width selection location is preserved, clamped to the replacement length.
**When** the user presses Up again,
**Then** the input shows `ls` and the selection is clamped again if needed.
**When** the user presses Down,
**Then** the input shows `pwd`.
**When** the user presses Down again,
**Then** the input shows `echo 1` (draft restored), history navigation
exited, and the selection remains at its prior location when valid or at the restored text boundary when clamping is required.

### F043-S03: Multiline draft, caret in middle, Up moves caret

**Given** the user has typed a 5-line draft with the caret on line 3,
**When** the user presses Up,
**Then** the caret moves to line 2. History is not triggered.

### F043-S04: Multiline draft, caret on first line, Up enters history

**Given** the user has typed a 5-line draft with the caret on line 1,
**And** history is non-empty,
**When** the user presses Up,
**Then** the pending draft is saved, the input is replaced with the newest
history entry, and the prior caret location is preserved when valid or clamped
to the recalled entry's UTF-16 length.

### F043-S05: Multiline recalled entry, Up traverses within before history

**Given** the user recalled a 5-line entry and the preserved/clamped caret is on line 5,
**When** the user presses Up,
**Then** the caret moves to line 4 within the recalled entry.
**When** the user repeats Up until reaching line 1 and presses Up again,
**Then** the previous history entry replaces the input and the prior caret location is preserved or clamped to the new length.

### F043-S06: Edit while recalled → reset

**Given** the user has recalled entry "X" and has not yet edited it,
**When** the user types any character,
**Then** history navigation exits; pending draft is discarded; the next
Up starts a fresh traversal from the newest entry.

### F043-S07: Dedupe consecutive duplicates

**Given** history ends with `["ls"]`,
**When** the user submits `ls` again,
**Then** history remains `["ls"]` (one entry).

### F043-S08: Full Spotlight identity switch resets only that pane's navigator

**Given** a host with injected compose history shows a project terminal and a standalone terminal that reuse the same tab UUID, or two standalone tiles point at related sessions,
**When** Spotlight switches panes or restores a member,
**Then** normalized project+tab or surface+tile+tab keeps their buckets and drafts distinct,
**And** only the navigator whose complete identity changed rebinds and clears cursor/pending draft,
**And** the other visible combo pane retains its own draft and traversal state.

The main and detached hosts satisfy the injection precondition, so both preserve pane-local drafts and independent navigator/traversal state.

### F043-S10: Overlay suppression

**Given** the inline-trigger picker is presented over the compose input,
**When** the user presses Up or Down,
**Then** the picker handles the keystroke. History is not touched.

### F043-S11: Modifier arrows do not recall history

**Given** history is non-empty and the caret is on the first line,
**When** the user presses Option+Up or Option+Down in VibeCast,
**Then** the selected terminal target may cycle and history is not triggered.
**When** the user presses Command-, Shift-, or Control-modified Up/Down,
**Then** the compose surface or text view handles the command and history is not triggered.

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

### F043-S13: Nonfocused Spotlight compose activates before send

**Given** a two-terminal Spotlight combo shows separate compose bars for panes A and B,
**And** A currently owns the shared header and keyboard focus,
**And** B has its own draft keyed by B's complete stable identity,
**When** the user sends from B,
**Then** B activates before terminal lookup,
**And** identity is revalidated after activation,
**And** the text is dispatched only to B's terminal,
**And** A's draft remains unchanged.

**Then** B also appends only to B's history bucket and A's history cursor/pending draft remain unchanged in both main and detached hosts.

## Architecture

### Components

```
AppContainer (composition root)
└── ComposeHistoryStore (one in-memory service, [String: [String]])
    ├── main SwiftUI root injects EnvironmentValues.composeHistoryStore
    └── DetachedTerminalBoardWindowRoot injects the same dependency
        └── each compose view creates an independent navigator

Per compose view with an injected store:
├── independent compose draft state
├── independent ComposeHistoryNavigator (ObservableObject)
│   ├── receives the injected ComposeHistoryStore
│   ├── binds to one full stable key
│   ├── holds cursor: Int? and pendingDraft: String?
│   └── exposes attach(toStableKey:), append(_:), navigateBack(_:),
│       navigateForward(_:), resetOnUnrelatedEdit()
└── NSTextView subclass key handler
    ├── detects caret on first/last visual line via NSLayoutManager
    └── routes plain Up/Down with no selection/overlay to that navigator

Spotlight terminal pane send:
capture full identity → activate pane → revalidate identity → resolve live session → send
    → append to that pane only when a navigator/store is available
```

### Store API

```swift
@MainActor
final class ComposeHistoryStore {
    func entries(for key: String) -> [String]
    func append(_ text: String, for key: String)
    func clear(for key: String) // Available API; no production owner-disposal caller currently uses it.

    // UUID convenience overloads remain for UUID-keyed consumers.
}
```

### Navigator API

```swift
@MainActor
final class ComposeHistoryNavigator: ObservableObject {
    init(store: ComposeHistoryStore)

    func attach(toStableKey key: String?)             // resets cursor + draft on key change
    func attach(to key: UUID?)                        // convenience for UUID consumers
    func append(_ text: String)                      // after successful send
    func navigateBack(currentText: String) -> Nav    // up on first line
    func navigateForward(currentText: String) -> Nav // down on last line
    func resetOnUnrelatedEdit()                      // any user edit not from navigation

    enum Nav {
        case noChange
        case replace(text: String)
    }

    var isApplyingNavigation: Bool
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
| idle | navigateBack, history non-empty | browsing(last) | save draft; `.replace(entries.last)` |
| idle | navigateForward | idle | `.noChange` |
| browsing(i) | navigateBack, i > 0 | browsing(i-1) | `.replace(entries[i-1])` |
| browsing(0) | navigateBack | browsing(0) | `.noChange` |
| browsing(i) | navigateForward, i < last | browsing(i+1) | `.replace(entries[i+1])` |
| browsing(last) | navigateForward | idle | `.replace(pendingDraft ?? "")` (pendingDraft cleared) |
| any | attach(to: newKey ≠ currentKey) | idle | — |
| any | resetOnUnrelatedEdit | idle | — |
| any | append(text) | idle | append to store (dedupe); pendingDraft cleared |

### Multiline routing rules (inside the NSTextView subclass)

On keyDown with `keyCode == UpArrow` or `DownArrow`:

1. If an inline overlay owns a plain arrow → forward to the overlay. Do not call the navigator.
2. If Option+Up/Down is pressed → invoke the consumer's target-cycle action when supplied (VibeCast supplies it), consume the event, and do not call the navigator.
3. If any other modifier is present → delegate to the compose text view's normal command handling. Do not call the navigator.
4. If the current selection has non-zero length → delegate to `NSTextView`; history is not fired.
5. For plain Up: if the caret glyph is on the same line fragment as glyph 0 → call `navigator.navigateBack(currentText:)`; apply `Nav`; consume the event.
6. For plain Down: if the caret glyph is on the same line fragment as the last glyph → call `navigator.navigateForward(currentText:)`; apply `Nav`; consume the event.
7. Otherwise → `super.keyDown`.

Line-fragment comparison uses `NSLayoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)`. Visual lines, not logical lines—a soft-wrapped single logical line counts correctly as multiple visual lines.

### Applying `Nav.replace`

The compose view records the text view's current selection, assigns the replacement text from `Nav.replace(text:)`, and restores the previous location and length after clamping both to the replacement's UTF-16 length. A zero-width caret therefore remains at the same valid location rather than being forced to the end; if the recalled text is shorter, the caret clamps to its end. The caller sets mutable `navigator.isApplyingNavigation = true` before changing the bound text. The text-change observer resets it to `false` after that programmatic change; unrelated user edits instead call `navigator.resetOnUnrelatedEdit()`.

### Consumer wiring checklist

1. `AppContainer.makeDefault()` creates one `ComposeHistoryStore`; the main root and `DetachedTerminalBoardWindowRoot` inject that instance with `.environment(\.composeHistoryStore, appContainer.composeHistoryStore)`. No consumer calls a singleton.
2. Each compose view creates its own `ComposeHistoryNavigator`. A two-terminal Spotlight combo in either host therefore has two views, navigators, history buckets, and draft owners.
3. On appearance and complete identity change, attach the navigator:
   - project Spotlight terminal: `spotlight:<safe token(projectPath, tabID)>`;
   - standalone Spotlight terminal: `spotlight:<safe token(surfaceID, tileID, tabID)>`;
   - temporary Spotlight terminal: `spotlight:transient:<sessionID>`;
   - ACP: ACP store ID;
   - VibeCast: VibeCast session ID.
4. Spotlight send captures expected identity, invokes pane activation, verifies identity did not change, resolves the session, sends, then appends. ACP/VibeCast append after their successful submit.
5. The `NSTextView` routes Up/Down to only its own navigator. Text changes reset only that navigator unless `isApplyingNavigation` is set.

### Spotlight identity and focused chrome

The Spotlight card's focused member remains the shared header/action/keyboard owner, but compose ownership is pane-local. Shared chrome changes MUST NOT move drafts, pasted images, history cursors, or pending drafts between terminal halves. A full stable identity prevents duplicate tab UUIDs in different projects/surfaces from sharing history.

## Security Notes

(Would live in `threat-model.md` under the four-doc layout. Folded in here.)

### F043-T01: Submitted secrets can be recalled

- **Vector:** A user submits a password, API key, or other sensitive string through a compose input and later recalls it with Up.
- **Impact:** Sensitive text remains available during the current AppContainer lifetime.
- **Likelihood:** Medium when users submit credentials through compose UI.
- **Mitigation:** History is in-memory only, capped per bucket, and clears when the AppContainer is released (normally app restart). Usage-facing copy tells users that sent text remains recallable for the session. A future caller-controlled redaction hook remains an option. Linked NFR: SEC-2.

### F043-T02: Stable-key collision leaks another compose bucket

- **Vector:** Incorrect key resolution maps two compose owners to the same bucket.
- **Impact:** One terminal, ACP, or VibeCast input can recall text submitted from another.
- **Likelihood:** Low with complete stable identities.
- **Mitigation:** UUID consumers use stable UUID strings; Spotlight terminal keys encode full project+tab, surface+tile+tab, or transient-session identity. Every main and detached compose view owns a navigator whose `attach(toStableKey:)` rebinds and clears traversal state. Dedicated mounted combo identity regressions remain a documented verification gap. Linked NFRs: SEC-3a, REL-3.

### F043-T03: Unbounded history exhausts memory

- **Vector:** Runaway automation submits continuously to one or more compose buckets.
- **Impact:** Process memory grows without bound.
- **Likelihood:** Low.
- **Mitigation:** Each bucket is capped at 500 entries by default and evicts its oldest entries. Linked NFRs: PERF-2, REL-4.

### F043-T04: History reaches logs or telemetry

- **Vector:** Diagnostics or analytics accidentally record recalled or submitted history entries.
- **Impact:** Private compose text persists outside its intended in-memory bucket.
- **Likelihood:** Low under the current data flow.
- **Mitigation:** History entries are never logged, telemetered, or written to `AppDiagnostics`. Linked NFR: SEC-2.

## Usage (Brief)

(Would live in `usage-guide.md` under the four-doc layout. Folded in here.)

- Press **Up** in a compose input on its first line to recall the
  previous message. Repeat to go further back.
- Press **Down** on the last line to go forward, or exit history and
  restore your in-progress draft.
- While editing a multi-line message, Up and Down move the caret
  normally. History only kicks in when the caret is on the top (for Up)
  or bottom (for Down) visual line.
- History stays separate for each terminal, ACP conversation, and VibeCast session. Each terminal in a two-pane Spotlight keeps its own draft, pasted images, and Up/Down recall in both the main window and detached board windows.
- Sending from a terminal pane that is not focused activates that pane first, so the draft goes only to the terminal beside it.
- Recalled text keeps the caret at its previous valid position. If the recalled text is shorter, the caret moves only as far as the new end.
- Option+Up/Down may change the selected VibeCast terminal instead of moving the caret; modifier-arrow keys never recall history.
- History does not persist across app restarts. Closing a compose pane does not currently clear its session history early; it remains available until the app session ends.
- History holds up to 500 most-recent messages per input.

## Acceptance Criteria

- Arrow-key response target < 16 ms (PERF).
- Keyboard-only operable (A11Y-2).
- History remains in-memory, capped, deduplicated, and absent from telemetry (SEC).
- Buckets survive compose-owner disposal because no production path calls `clear(for:)`; they clear when the AppContainer is released, normally at app restart.
- AppContainer/environment injection is the only production dependency path; no singleton access. Main and detached terminal, ACP, and VibeCast consumers receive the same store.
- Spotlight project, standalone, and temporary terminal keys include the complete stable identity.
- Every visible terminal combo half owns a separate draft, navigator, and history bucket and activates before session resolution/send; focused shared header/actions do not merge pane state.
- `Nav.replace(text:)` preserves the text view's current selection and clamps it to the replacement's UTF-16 length; mutable `isApplyingNavigation` prevents that programmatic replacement from resetting traversal.
- Static unit-test inventory covers store append/dedupe/cap/isolation and navigator traversal/reset/pending-draft behavior. Static production inspection covers string-key support, full Spotlight compose identity, main/detached injection, selection clamping, and activation-before-send.
- **Known verification gaps for this documentation update:** No tests, builds, apps, or manual checks were run. Dedicated regressions for full Spotlight identity collisions, mounted two-pane draft/history isolation, activation-before-send dispatch, and owner-disposal cleanup were not found. Single-line, multiline, soft-wrap, selection, overlay priority, modifier-arrow consumer behavior, and all-consumer end-to-end UI behavior remain existing-test inventory or manual/UI gaps, not claimed verification.

## Open Questions

- **Esc to exit history**: nice-to-have exit-and-restore gesture via Esc.
  Deferred; may conflict with existing Esc bindings on specific surfaces.
- **Redaction hook for sensitive sends**: would allow callers to submit
  without appending to history. Deferred until a concrete use case
  surfaces.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: aligned `Nav.replace(text:)`, mutable `isApplyingNavigation`, and selection-preserving/clamped caret behavior with production; documented Option+Up/Down VibeCast target cycling without claiming universal NSTextView defaults; added canonical F043-T01–T04 headings; and recorded detached terminal/ACP/VibeCast history parity through AppContainer injection. No tests or manual UI runs were performed. | — |
| 2026-10-18 | Spotlight alignment established pane-local compose views/drafts keyed by full stable project+tab, surface+tile+tab, or transient identity; AppContainer/environment history injection; activation-before-send with focused shared chrome; AppContainer-lifetime buckets without owner-disposal cleanup; S08/S13; honest static/manual gaps; and the canonical combined-document waiver. Host injection status was finalized by the audit entry above. | — |
| 2026-05-06 | Initial draft under the combined-document waiver. ACP bucket key resolved to ACP store id (history shared across thread switches in the same pane). Clarified pending-draft lifecycle: cleared on send so an abandoned in-progress draft is never resurfaced (added F043-S12, tightened F043-R02). | — |
