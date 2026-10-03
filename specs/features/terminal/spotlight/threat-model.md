# Terminal Spotlight — Threat Model

## Overview

Terminal Spotlight presents existing terminal sessions and related vibespace surfaces inside a high-priority overlay. The main risks are accidental command dispatch, stale or spoofed tab identities during drag/drop, incorrect persistence targets for reorder operations, and transient terminal lifecycle leaks.

## Trust Boundaries

- User input crosses from SwiftUI/AppKit controls into terminal sessions when the compose bar sends text.
- Spotlight drag/drop payloads cross from view-layer event handling into vibespace Spotlight order persistence or board layout persistence.
- Persistent terminal tabs are owned by project terminal view models; vibespace Spotlight ordering is a vibespace-scoped field in centralized persistence; terminal-board ordering is owned by board layout state in that same persistence boundary.
- Transient Spotlight terminals are owned by the Spotlight coordinator and must not outlive the overlay.
- Inline path search crosses from the compose UI into the bundled helper process and local filesystem roots.

## Attack Surfaces

- Compose input submission, including keyboard shortcuts and visible send controls.
- Drag/drop reordering in the Spotlight tab strip.
- Carousel switching and focus restoration between terminal sessions, VibeCast, and temporary previews.
- Temporary terminal process creation and termination callbacks.
- Inline insert trigger lookup and generated command insertion.
- Native/SwiftUI double-click arbitration and trackpad ownership between terminal panning and carousel switching.

## Threats

### F003-T01: Unintended command dispatch

- Vector: Keyboard focus moves from the compose field to Spotlight chrome, but a shortcut still submits a stale or unexpected draft.
- Impact: A command can be sent to the wrong terminal session.
- Likelihood: Medium.
- Mitigation: Submission must resolve the current Spotlight terminal at send time, compose drafts are keyed by terminal/session ID, and non-terminal Spotlight sources hide the terminal compose bar.

### F003-T02: Reorder payload targets the wrong tab

- Vector: A drag payload carries a terminal identity that no longer exists, has stale project scope, belongs to a different vibespace, or is dropped on a non-terminal item.
- Impact: Tab order or board layout order could be corrupted.
- Likelihood: Medium.
- Mitigation: Drop handling validates source and target as persistent terminal tabs in the same vibespace and current Spotlight host before invoking host persistence. VibeSpace Spotlight accepts cross-project terminal identities within that vibespace; terminal-board Spotlight accepts terminal tiles only on the active board surface. Unknown identities, cross-vibespace identities, stale board-surface identities, and non-terminal drops are ignored.

### F003-T03: Reorder writes to the wrong persistence field

- Vector: A host updates the project tab-order field when the visible carousel was built from vibespace Spotlight order or `VibeSpaceTerminalBoardLayout.tiles`, or updates board layout when the visible carousel was vibespace-scoped.
- Impact: The visible reorder appears to work during drag animation but does not persist or snaps back after rebuild.
- Likelihood: Medium.
- Mitigation: The overlay delegates reorder persistence to its host, and the host writes only the centralized persistence field that backs the visible carousel. VibeSpace Spotlight writes the vibespace-level Spotlight order field; terminal-board Spotlight writes active board surface tile order.

### F003-T04: Transient Spotlight session outlives the overlay

- Vector: Dismissal or process-exit callbacks race with Spotlight replacement.
- Impact: Orphaned terminal processes or callbacks acting on stale Spotlight state.
- Likelihood: Low.
- Mitigation: Transient dismissal is guarded by Spotlight ID, clears termination callbacks, and terminates owned sessions synchronously on dismiss.

### F003-T05: Inline insert exposes unintended local paths or auto-runs generated text

- Vector: Inline search roots are broader than the active vibespace context, or generated command text is executed immediately.
- Impact: Local path disclosure inside the UI or accidental command execution.
- Likelihood: Low.
- Mitigation: Search roots are limited to local vibespace project roots and the active local working directory fallback. Inline insert actions replace text only and never auto-execute.

### F003-T06: Ambiguous gesture triggers duplicate or unintended Spotlight navigation

- Vector: A transformed native terminal and its SwiftUI wrapper both handle one double-click, or the application-level carousel monitor consumes a pan intended for a magnified terminal.
- Impact: Spotlight can open and immediately close, switch to the wrong item, disturb terminal selection, or leave stale carousel offset.
- Likelihood: Medium without explicit arbitration.
- Mitigation: Ghostty uses one explicit AppKit double-click callback and suppresses the matching second press/up; its SwiftUI handler is gated off while SwiftTerm retains the fallback. Magnified terminal sources reserve precise scrolling before carousel classification, and all ineligible/takeover/momentum-end paths clear cumulative gesture state and visual offset. Linked NFRs: A11Y-4, PERF-3, TEST-2.

## Residual Risks

- Reorder persistence is intentionally host-specific, so regression tests must cover both vibespace Spotlight and terminal-board Spotlight.
- A stale tab UUID from legacy state can only be resolved if restored state has enough project scope and legacy identity fields to match a tab before the next stable-ID snapshot.
- While a terminal remains magnified, horizontal trackpad gestures are intentionally unavailable for carousel switching; users can use the tab strip or chevrons, or return to `1×`.

## NFR Compliance

- SEC-1, SEC-3a — see `nfr/security.md`
- A11Y-2 — keyboard focus and shortcut routing must remain predictable.
- A11Y-4 — Spotlight terminal interaction remains functional at supported magnification.
- REL-1 — restore chains and persisted reorder state must survive view rebuilds and vibespace restore.
- PERF-3 — double-click and scroll arbitration remain immediate UI interactions.
- TEST-2 — native double-click and magnified scroll arbitration have scenario-mapped regression coverage.
- OBS-1 — Spotlight operations should remain observable for diagnosis.
