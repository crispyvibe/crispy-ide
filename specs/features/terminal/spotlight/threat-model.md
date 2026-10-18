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

### F003-T01: Unintended or cross-pane command dispatch

- Vector: A combo's unfocused compose bar, a stale shared header shortcut, or an identity change dispatches a draft to the previously focused terminal.
- Impact: A command can be sent to the wrong terminal session.
- Likelihood: Medium.
- Mitigation: Each terminal half owns its compose view and pane-local text/image drafts. Draft identity uses the full stable Spotlight identity (project path+tab, surface+tile+tab, or transient session). Send captures that identity, activates the pane, revalidates identity, then resolves the live session. An AppContainer-owned, environment-injected `ComposeHistoryStore` gives each pane its own navigator/history bucket in main and detached hosts; no shared or global navigator fallback is used. Nonterminal members have no terminal compose bar.

### F003-T02: Reorder payload targets the wrong tab

- Vector: A drag payload carries a terminal identity that no longer exists, has stale project scope, belongs to a different vibespace, or is dropped on a non-terminal item.
- Impact: Tab order or board layout order could be corrupted.
- Likelihood: Medium.
- Mitigation: Drop handling accepts only value-only persistent subjects in the same host and current generation. Before/club/after reduction validates live source/target positions, distinct members, and max-two combos. Unknown, temporary, stale, duplicate, self, and cross-host drops are ignored.

### F003-T03: Reorder writes to the wrong persistence field

- Vector: A host updates the project tab-order field when the visible carousel was built from vibespace Spotlight order or `VibeSpaceTerminalBoardLayout.tiles`, or updates board layout when the visible carousel was vibespace-scoped.
- Impact: The visible reorder appears to work during drag animation but does not persist or snaps back after rebuild.
- Likelihood: Medium.
- Mitigation: The overlay delegates one accepted snapshot to its host. Main writes the VibeSpace Spotlight snapshot and mirrors legacy terminal order; a board host writes only its surface snapshot and mirrors flattened tile order with unchanged geometry.

### F003-T04: Invalid restore target or transient owner outlives Spotlight

- Vector: A persisted member leaves its host catalog, a terminal/ACP/file owner becomes invalid, a browser preview contains an invalid URL, or dismissal/process-exit callbacks race with replacement.
- Impact: Blank or wrong content can mount, callbacks can mutate newer state, or a temporary process/editor/browser owner can leak.
- Likelihood: Medium without validation.
- Mitigation: Restore validates host membership plus terminal, ACP, and file owners where applicable; a valid persistent browser can resolve through its canonical coordinator. Browser previews require a decodable URL in both main and detached hosts. Stale process exits are Spotlight-ID guarded. Full dismissal clears termination callbacks, synchronously terminates coordinator-owned temporary sessions, tears down preview owners, clears only that host's editor lease, and leaves persistent sessions untouched.

### F003-T05: Inline insert exposes unintended local paths or auto-runs generated text

- Vector: Inline search roots are broader than the active vibespace context, or generated command text is executed immediately.
- Impact: Local path disclosure inside the UI or accidental command execution.
- Likelihood: Low.
- Mitigation: Search roots are limited to local vibespace project roots and the active local working directory fallback. Inline insert actions replace text only and never auto-execute.

### F003-T06: Ambiguous gesture triggers duplicate or unintended Spotlight navigation

- Vector: A transformed native terminal and its SwiftUI wrapper both handle one double-click, or the application-level carousel monitor consumes a pan intended for a magnified terminal.
- Impact: Spotlight can open and immediately close, switch to the wrong item, disturb terminal selection, or leave stale carousel offset.
- Likelihood: Medium without explicit arbitration.
- Mitigation: Ghostty uses one explicit AppKit double-click callback and suppresses the matching second press/up; its SwiftUI handler is gated off while SwiftTerm retains the fallback. The exact terminal scale boundary `>1×` reserves precise scrolling before carousel classification (`1.0001×` qualifies) and resets partial carousel state. At exactly/below normal, viewport pan is neutralized, horizontal gestures remain eligible for carousel navigation, and other scrolling over displayed terminal content follows terminal scrollback; blank optical margins consume scroll rather than forwarding it to Ghostty. Static policy/tracker and mounted optical test sources cover those boundaries; physical trackpad delivery, shelf axis intent, and excluded grid-count routing remain unexecuted UI/manual gaps in this documentation review. Linked NFRs: A11Y-4, PERF-3, TEST-2.

### F003-T07: Cross-project identity collision or stale generation redirects focus

- Vector: Two projects reuse a terminal tab UUID, or queued completion/focus work from an older carousel generation runs after a rapid/direct replacement.
- Impact: Spotlight can render or focus a terminal from the wrong project, expose misleading context, or mutate the current transition.
- Likelihood: Medium without scoped identity and cancellation guards.
- Mitigation: Persistent identity combines normalized owning-project path and tab UUID; missing scope receives a unique non-carousel identity. Generation, target identity, Spotlight instance, and surface/project state are validated before animation completion or focus. Direct presentation cancels queued generation/focus work. Diagnostics hash project scope through `AppDiagnostics.pathToken`. Linked NFRs: SEC-2, REL-1, OBS-1, TEST-2.

### F003-T08: Cross-host or stale combo mutation

- Vector: A drag payload is replayed after shelf replacement or on another VibeSpace/board surface, or attempts to add a third/duplicate member.
- Impact: The wrong host order or combo could be corrupted.
- Likelihood: Medium.
- Mitigation: Payloads carry host scope, generation, and value-only subject identity. The reducer revalidates both positions, distinct live members, and the max-two invariant. Hover never persists; one accepted drop performs one host-owned write.

### F003-T09: Semantic overview metadata leaks private content

- Vector: Search cards or accessibility fields expose raw paths, browser credentials/query tokens, terminal commands/output, or captured screen pixels.
- Impact: Local secrets or user activity can be disclosed through the overview or accessibility tree.
- Likelihood: Medium if live content is sampled.
- Mitigation: All Tabs is metadata-only and never uses screenshots, terminal screen excerpts, live output, command history, editor pixels, or WebView pixels. Terminal status is limited to active/idle and directory basename. File metadata follows the current owner but exposes only filename and parent display name. Browser metadata follows the current owner and strips userinfo, password, query, and fragment. Search uses the same safe fields; identifiers use path-free stable tokens.

### F003-T10: Combo duplicates live owners or one host releases another host's editor

- Vector: Two combo panes construct replacement stores/sessions, or main and detached Spotlights use one global file-ownership flag and release each other.
- Impact: Lost state, duplicate rendering, double command delivery, responder races, or leaked owners.
- Likelihood: Medium.
- Mitigation: Snapshot IDs resolve existing registries; one stable `NativeSplitView` hosts independently clickable references; one focused member supplies shared chrome while terminal compose remains pane-local. File ownership is leased by host ID and tile set, and board suppression uses the union across hosts. Reconciliation and dismissal change only the calling host's lease. Linked NFRs: REL-1, A11Y-2, SEC-2, TEST-2.

## Residual Risks

- Reorder persistence is intentionally host-specific, so regression tests must cover both vibespace Spotlight and terminal-board Spotlight.
- A stale tab UUID from legacy state can only be resolved if restored state has enough project scope and legacy identity fields to match a tab before the next stable-ID snapshot.
- While a terminal remains above `1×`, horizontal trackpad gestures are intentionally unavailable for carousel switching; users can use the tab strip or chevrons, or return to `1×`/below. At exactly/below normal, horizontal carousel classification can still win over terminal scrollback by design.

## NFR Compliance

- SEC-1, SEC-3a — see `nfr/security.md`
- A11Y-2 — keyboard focus and shortcut routing must remain predictable.
- A11Y-4 — Spotlight terminal interaction remains functional at supported magnification.
- REL-1 — restore chains and persisted reorder state must survive view rebuilds and vibespace restore.
- PERF-3 — double-click and scroll arbitration remain immediate UI interactions.
- TEST-2 — native double-click and scale-bounded scroll arbitration have scenario-mapped pure and mounted regression coverage; physical trackpad monitor delivery remains an explicit UI/manual gap.
- OBS-1 — Spotlight operations should remain observable for diagnosis.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: recorded AppContainer compose-history injection and independent buckets in both main and detached hosts, plus malformed browser-preview URL rejection on both restore paths. Static sources were reviewed; no tests or manual UI verification were run. | — |
| 2026-10-18 | Review bound command dispatch to pane-local full identity and activation-before-send; prohibited screenshots, terminal screen excerpts, live output, commands, and sensitive URL/path data; and documented host-scoped editor leases plus restore/process cleanup. Later production-fix status is recorded above; no tests or manual UI verification were run. | — |
| 2026-10-18 | Removed terminal content reads from semantic cards, redacted browser locations, reduced file metadata, and added canonical editor ownership leases plus stale transaction/restore validation. | — |
| 2026-10-16 | Added stale/cross-host combo mutation, metadata/accessibility disclosure, and live-owner duplication threats for the shelf/overview/combo enhancement. | — |
| 2026-10-09 | Clarified F003-T06 mitigation and residual behavior: the exact `>1×` boundary reserves terminal pan (`1.0001×` qualifies); exactly/below normal retains carousel/scrollback arbitration and consumes scroll over blank optical margins, with physical trackpad delivery stated as manual coverage. | — |
| 2026-10-09 | Added T07 for cross-project terminal identity collisions and stale generation focus, including path-token diagnostic protection. | — |
| 2026-10-06 | Reviewed compact Markdown/browser navigation and prior-origin close semantics. No new Spotlight-specific threat was added: content integrity/privacy risks are owned by F008-T09, F012-T12, F006-T07, and F037-T07; existing F003-T04 continues to cover restore-chain lifetime. | — |
