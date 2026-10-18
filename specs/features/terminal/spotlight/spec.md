# Terminal Spotlight — Spec

Status: implemented

## Overview

Terminal Spotlight provides a centered overlay mode for focusing on a single terminal session. It supports temporary and persistent spotlight surfaces, carousel navigation via swipe, nested restore chains, and compose input. Spotlight can be triggered from board tiles, rail cards, shortcut commands, and session previews.

## Dependencies

- F001 (Sessions & Tabs) — spotlight surfaces host terminal sessions
- F002 (Terminal Board) — double-clicking a visible tile opens Spotlight; minimized tabs restore tiles to the grid and remain represented in the persistent Spotlight shelf order
- F004 (Terminal Rail) — double-click rail card opens spotlight
- F006 (Content Viewer) and F008 (Markdown) — current-file compact navigation ownership
- F012 (Browser) — canonical browser history and mouse/toolbar navigation
- F037 (Terminal Board Dock) — pinned file/browser presentation continuity

## Requirements

### F003-R01: Board Temporary Spotlight Focus

When user double-clicks a board tile, a centered `Terminal Spotlight` overlay MUST open for that tile terminal. Board layout columns/rows and tile positions MUST remain unchanged. Spotlight MUST be dismissible by double-click, `Esc`, or clicking outside overlay. Dismissal MUST return attention to the original board layout state.

### F003-R02: Carousel Navigation by Persistent Position

A qualifying horizontal gesture on non-shelf Spotlight content MUST move by one persistent Spotlight position, wrapping at the boundaries. A single item is one position and a two-member combo is one position. The focused member of the target position MUST become the shared header, action, and default keyboard-focus owner. Compose ownership remains pane-local. Temporary previews MUST remain outside the carousel. While All Tabs is open, carousel navigation MUST be suppressed.

### F003-R03: Stacked Rail Temporary Spotlight Focus

When user double-clicks a stacked rail terminal card, a centered `Terminal Spotlight` overlay MUST open for that card terminal. Focused project/editor/file preview state MUST remain unchanged. Stacked rail layout MUST remain unchanged. Spotlight MUST be dismissible by double-click, `Esc`, or clicking outside overlay.

### F003-R04: Double-Click Toggles Expanded Terminal Overlay

When user double-clicks a terminal session view, the session MUST open in a centered expanded overlay. Double-clicking the expanded session MUST return it to the original layout.

### F003-R05: Validated Temporary Spotlight Restore Chain

When a temporary Spotlight is dismissed, the host MUST pop restore descriptors until it finds a target that is still valid for that host. Validation MUST confirm persistent membership and the source-specific live owner (terminal tab, ACP store, or active file owner). Browser-preview restore in both main and detached hosts MUST reject a snapshot whose URL cannot be decoded. Other invalid descriptors MUST be skipped. Spotlight state MUST be cleared only when no valid restore target remains, and restoring MUST preserve the exact focused member, position, combo orientation, callbacks, and surface affinity.

### F003-R06: Temporary Spotlight Excludes Carousel Navigation

When Spotlight shows a temporary terminal, file preview, or browser preview, carousel navigation controls and the persistent 44 pt shelf MUST be hidden and swipe-based switching MUST be disabled.

### F003-R07: Temporary Spotlight Dismissal Consistency

Close, `Escape`, backdrop click, and terminal double-click MUST use the same validated restore-first route. The Spotlight MUST fully dismiss only when no valid descriptor remains. Preview owners and host-scoped editor leases MUST be released when the temporary presentation is replaced or dismissed.

### F003-R08: Temporary Terminal Process Exit Restores Previous Spotlight

When a temporary terminal process exits on its own, the Spotlight-ID-guarded callback MUST run the same validated restore-first route. A stale exit callback MUST do nothing. If no valid target remains, Spotlight MUST dismiss and release the temporary process, callback, preview owner, and host lease without affecting persistent sessions.

### F003-R09: Compose Bar Terminal Input

When the compose bar is visible in spotlight, TerminalComposeInputView MUST provide a text input field. Submitted input MUST be dispatched to the active terminal session.

### F003-R10: Compose Input Focus Retention

When the spotlight compose input is focused, terminal-output interactions that do not explicitly switch keyboard focus to another input MUST leave keyboard focus on the compose input. Opening or using terminal link and file actions MUST NOT pull focus away from the compose input unless the user directly focuses the terminal session.

### F003-R11: Spotlight Compose Input Supports Inline Insert Triggers

Spotlight compose input MUST support the inline insert trigger behavior defined in F038 (Terminal Inline Triggers). The spotlight terminal context MUST be used as the originating context for path resolution and shortcut filtering. When the spotlight is hosted in a board layout, the picker MUST use the board-scoped popup presentation per F038-R07.

### F003-R12: Attached 44 pt Persistent Shelf

Persistent Spotlight MUST render one compact, full-card-width shelf attached directly to the card and fixed at 44 pt high. Every persistent position/member MUST have a complete icon-and-title chip with project accent or secondary disambiguation. The shelf MUST scroll horizontally without partial pagination or passive replacement of members. Its trailing control MUST be a compact grid icon plus the total persistent-member count, with an accessible **All Tabs** label; it MUST NOT expand into a text button or separate pager. A single click on a member selects it after the system double-click interval. An exclusive double-click MUST cancel that pending selection and open All Tabs with search focused, without selecting or changing the double-clicked member.

### F003-R13: Shelf Reorder, Club, and Unclub

A shelf drop target MUST divide into before 25%, club center 50%, and after 25%. Before/after drops reorder a whole position or extract and reposition one combo member. A center drop creates exactly one two-member combo from distinct persistent members. Whole combos reorder as one position. A combo member can be dragged out to become a single position. Hover MUST provide preview decoration only; persistence occurs exactly once after an accepted drop. Stale generations, cross-host payloads, temporary items, self-drops, duplicate members, and attempts to exceed two members MUST be rejected without persistence.

### F003-R14: Spotlight Activity Animation Visibility

When a terminal represented in the spotlight tab strip is active, its tab chip MUST show a clearly visible animated bottom underline in addition to the narrow activity bar. The animation MUST be drawn inside the chip's existing bounds and MUST NOT change chip size, tab-strip height, or neighboring tab positions while animating.

### F003-R15: Native Terminal Double-Click Routes Exactly Once

Double-clicking a Ghostty terminal that has a Spotlight action MUST invoke that action through the AppKit terminal host exactly once, including while the terminal is magnified or panned. The handled second Ghostty press and matching release MUST be suppressed so word selection and Spotlight activation do not race. SwiftTerm MUST retain the SwiftUI double-click fallback. A terminal host without a Spotlight action MUST leave Ghostty's native double-click word selection unchanged.

### F003-R16: Shelf Start-Region Axis Ownership

A precise scroll sequence beginning anywhere in the 44 pt shelf start region, except the trailing grid-count control, MUST initially remain unclaimed. After more than 4 pt of accumulated intent, horizontal-dominant motion MUST latch to the shelf through changed/end/cancel and momentum phases, including with no overflow, at an edge, or after pointer leave; that sequence MUST never change carousel offset or selection. Vertical-dominant motion, and sequences beginning over the excluded trailing control, MUST pass through without shelf or carousel ownership. Non-shelf content retains horizontal carousel arbitration and strict `>1×` terminal viewport precedence. Ownership MUST clear on dismissal, direct replacement, layout commit, overview presentation, monitor removal, or shelf/window loss.

### F003-R17: Compact Content Navigation and Spotlight Return Semantics

When Spotlight presents Markdown or browser content, presentation-appropriate Back and Forward controls MUST be visible and MUST dispatch to that content's canonical navigation owner. Markdown MUST also support ⌘[ and ⌘] through that same owner; browser mouse Back/Forward MUST match its toolbar owner. For Markdown, the Spotlight title, directory, comments context, provider, accessibility context, and detailed promotion MUST follow the current linked file rather than the immutable root. Content Back/Forward MUST be distinct from closing Spotlight and restoring its prior terminal or Spotlight origin. The current implementation MUST NOT be documented as providing a separate visible Return control; Escape, close, backdrop dismissal, and the existing restore chain remain the return mechanism.

### F003-R18: Single-Input Position and Focus Convergence

Each arrow, qualifying non-shelf swipe, or shelf/overview activation MUST resolve one stable member and position. Selecting the other member of the shown combo changes focus without moving the carousel; selecting a member elsewhere selects its position. Only the current generation may animate, attach live content, or request focus, and no keyed root replacement may recreate the shared split host.

### F003-R19: Value-Only Stable Persistent Identity

Persistent IDs and snapshots MUST be Codable values separate from live UI references. Project terminals use normalized project path plus tab UUID; detached standalone terminals additionally use surface and tile identity. File, browser, ACP, VibeCast, and Vibe Lanes IDs use their stable owning values. Accessibility and diagnostics MUST use safe tokens and MUST NOT expose raw project paths.

### F003-R20: Live Reconciliation

The host MUST normalize duplicate or invalid persisted positions, remove missing members, and append newly live persistent items. If one combo member disappears, the remaining member becomes a single position. If the focused member disappears, the surviving partner becomes focused; if both disappear, the nearest surviving position is selected or Spotlight dismisses when none remains. Reconciliation MUST be generation-safe and MUST NOT change session lifetime or board geometry.

### F003-R21: Searchable Semantic All Tabs Grid

The compact shelf grid-count control, or an exclusive shelf-member double-click, MUST present a searchable, flat, borderless, no-gradient, YouTube-style three-column grid. Each position card MUST retain a 16:9 safe aspect ratio, and positions/members MUST appear in persisted order rather than list order or project groups. Cards MUST be metadata-only: they MUST NOT capture screenshots, terminal screen excerpts, live terminal output, command history, or WebView/editor pixels. Terminal artwork MAY show only semantic active/idle status and a working-directory basename; file artwork MUST use the current owning editor group's filename and parent display name; browser artwork MUST use the current owning browser title and a location with userinfo, query, and fragment redacted. Search and accessibility MUST consume the same safe metadata. Search MUST autofocus. Deterministic Left/Right/Up/Down/Return and pointer activation MUST select directly; Escape MUST close only the overview. Current-position, combo, and focused-member status MUST use localized labels and safe identifiers.

### F003-R22: Live Independently Selectable Two-Member Combo

A combo MUST render both existing live members in persisted member order through one stable `NativeSplitView`, side-by-side by default with a persisted stacked toggle. Each half MUST be independently clickable and expose its own accessibility target. Exactly one member is focused; that member owns the shared header metadata, header actions, and keyboard focus. Every terminal half MUST retain a separate pane-local compose bar. Compose interaction and send MUST activate that half before resolving and dispatching to its live terminal. Draft text and pasted-image draft MUST remain scoped to the full stable Spotlight identity: normalized project path plus tab UUID for a project terminal, surface plus tile plus tab identity for a standalone terminal, and transient session UUID for a temporary terminal. Main and detached hosts MUST inject the AppContainer-owned `ComposeHistoryStore`; navigator/history MUST use that same full identity. The implementation MUST reuse terminal, browser, editor-group, and ACP owners and MUST NOT clone sessions, stores, or live surfaces.

### F003-R23: Main and Detached Host Parity and Editor Leases

All persistent Spotlight kinds—project terminal, standalone terminal, file, browser, ACP, VibeCast, and Vibe Lanes—MUST support the same attached shelf, semantic overview, host-scoped persisted arrangement, combo, orientation, and focused-member behavior in main and detached board hosts; host-specific catalog seed order is defined by F003-R24. Detached actions and previews MUST stay in the originating window. File members MUST acquire ownership through a host-scoped editor lease keyed by host and tile set; the union of active leases suppresses duplicate board rendering, and one host releasing its lease MUST NOT release another host's file member. Drag payload scope MUST prevent mutation of another VibeSpace or board surface.

### F003-R24: Host-Scoped Persistence, Reconciliation, and Geometry

Main order, combos, focusable member order, and `spotlightLayout` orientations MUST persist in the VibeSpace layout snapshot; each board surface MUST persist its own `spotlightLayout`. Decode MUST migrate absent legacy snapshots, reject unsupported future versions, normalize duplicate/invalid positions, and reconcile only against current live IDs. The main live catalog MUST seed project terminals in legacy VibeSpace order, then primary-board standalone terminals, ACP/file/browser members, and finally virtual VibeCast/Vibe Lanes members. A detached catalog MUST seed all terminal tile members first in visible-then-minimized terminal order, then nonterminal tile members in a second visible-then-minimized pass, appending a synthetic Vibe Lanes member when no Vibe Lanes tile exists. A persisted Spotlight snapshot MAY retain a user-arranged order different from those catalog seeds. Flattened board mirroring/reorder MUST include visible tile-backed members only; minimized board placement MUST remain unchanged, with minimized member order retained in the Spotlight snapshot. Synthetic host-level members MUST remain outside the flattened tile mirror. Surface IDs, tile/session identity and lifetime, active/minimized state, column/row counts and IDs, width weights, and row height weights MUST remain preserved. Browser snapshot capture MUST use the board snapshot-provider boundary rather than stale in-memory metadata.

## Scenarios

### Scenario F003-S01: Terminal board supports temporary spotlight focus

**Given** terminal board has at least one tile terminal
**When** user double-clicks a tile
**Then** a centered `Terminal Spotlight` overlay opens for that tile terminal
**And** board layout columns/rows and tile positions are unchanged
**And** user can dismiss spotlight by double-click, `Esc`, or clicking outside overlay
**And** dismissed spotlight returns attention to the original board layout state

### Scenario F003-S02: Swipe to switch terminals and VibeCast in spotlight

**Given** `Terminal Spotlight` is open for a persistent terminal or VibeCast
**And** the vibespace has more than one swipeable item (terminal tabs across all projects plus VibeCast)
**When** user performs a two-finger horizontal trackpad swipe on the spotlight card
**Then** spotlight transitions to the next (swipe left) or previous (swipe right) item in vibespace order
**And** the transition uses a horizontal slide animation matching swipe direction
**And** the swipe sequence wraps around at boundaries
**And** the target terminal receives keyboard focus automatically after transition
**And** VibeCast spotlight hides the terminal compose bar and auto-focuses its own compose input
**And** transient/temporary spotlight terminals do not support swipe-to-switch

### Scenario F003-S03: Stacked rail supports temporary spotlight focus

**Given** detailed view shows stacked project rail cards
**When** user double-clicks a stacked rail terminal card
**Then** a centered `Terminal Spotlight` overlay opens for that card terminal
**And** focused project/editor/file preview state remains unchanged
**And** stacked rail layout remains unchanged
**And** user can dismiss spotlight by double-click, `Esc`, or clicking outside overlay

### Scenario F003-S04: Double-click toggles centered expanded terminal overlay

**Given** a terminal session view is visible
**When** user double-clicks the session
**Then** the session opens in a centered expanded overlay
**And** double-clicking the expanded session returns it to the original layout

### Scenario F003-S05: Dismissing a nested temporary spotlight restores the previous spotlight item

**Given** a temporary terminal, file preview, or browser preview was opened from another spotlight item
**When** user dismisses the temporary spotlight
**Then** the previous spotlight item is restored
**And** spotlight state is cleared only when no restore target remains

### Scenario F003-S06: Temporary spotlight previews do not participate in carousel navigation

**Given** spotlight is showing a temporary terminal, file preview, or browser preview
**When** spotlight chrome renders
**Then** carousel navigation controls are hidden
**And** swipe-based spotlight switching is disabled for that temporary preview

### Scenario F003-S07: Temporary spotlight dismissal rules apply consistently across close affordances

**Given** spotlight is showing a temporary terminal, file preview, or browser preview
**When** user dismisses it with the close button, `Escape`, or backdrop click
**Then** the previous spotlight item is restored if a restore target exists
**And** the spotlight is fully dismissed only when no restore target exists

### Scenario F003-S08: Temporary terminal process exit restores the previous spotlight when possible

**Given** a temporary terminal spotlight was opened from another spotlight item
**When** that temporary terminal process exits on its own
**Then** the previous spotlight item is restored if a restore target exists
**And** spotlight state is cleared only when no restore target remains

### Scenario F003-S09: Compose bar provides terminal input

**Given** a terminal session is active
**When** the compose bar is visible
**Then** TerminalComposeInputView provides a text input field for composing terminal commands
**And** submitted input is dispatched to the active terminal session
**And** `Command` + `Return` dispatches the compose draft to the active terminal session when the compose field is focused
**And** `Command` + `Return` remains available from the visible compose send action after tab-strip or header interactions move keyboard focus away from the compose field

### Scenario F003-S10: Spotlight compose input keeps focus during non-terminal actions

**Given** spotlight compose input is focused
**When** the user triggers a terminal output action that does not explicitly focus the terminal session
**Then** the spotlight compose input remains the keyboard focus target
**And** subsequent typing continues in the compose input

### Scenario F003-S11: Spotlight compose input supports inline insert triggers

**Given** spotlight compose input is focused
**When** the user types the configured inline insert trigger
**Then** the inline insert picker opens per F038 behavior
**And** the picker resolves against the spotlight terminal context
**And** path insertion, shortcut insertion, command generation, and dismissal follow F038 scenarios F038-S02, F038-S03, F038-S04, and F038-S06

### Scenario F003-S12: Attached shelf exposes complete positions and compact overview control

**Given** Spotlight has more persistent positions than fit across the card
**When** the 44 pt attached shelf renders and the user scrolls horizontally
**Then** every complete single or combo chip remains reachable
**And** the trailing control remains a compact grid icon plus total member count
**And** no passive page count or separate paging controls replace members
**When** the user exclusively double-clicks a shelf member
**Then** the delayed single-click selection is cancelled
**And** All Tabs opens with search focused without changing the selected member

### Scenario F003-S13: VibeSpace Spotlight arranges persistent members

**Given** persistent items from one or more projects **When** the user drops a member or whole combo in a before, club, or after zone **Then** the preview reflects that exact zone **And** one accepted VibeSpace snapshot persists order/combo/orientation **And** the legacy terminal-order mirror follows terminal members without changing any live owner.

### Scenario F003-S14: Board Spotlight arrangement is surface-scoped

**Given** a main primary-board or detached-board Spotlight **When** a valid arrangement drop succeeds **Then** one canonical commit updates that host snapshot **And** the main commit atomically updates the VibeSpace snapshot, legacy terminal order, matching primary-surface snapshot, and flattened visible tile-backed primary order **And** captures current externally owned browser URL/session payloads through the board snapshot-provider boundary **And** detached commits update only their surface snapshot/order **And** destination column/row slots retain their IDs, counts, width weights, and row weights **And** sessions, tile count, active tile, minimized tiles, and every other surface remain unchanged.

### Scenario F003-S15: Spotlight terminal activity presentation is stable

**Given** an active terminal member appears in the shelf **When** activity feedback renders **Then** it remains within the complete member chip and does not resize neighboring positions or the attached shelf.

### Scenario F003-S16: Double-clicking a transformed terminal opens or closes Spotlight exactly once

**Given** a Ghostty terminal session has a Spotlight double-click action
**And** the terminal may be magnified or panned
**When** the user double-clicks inside the visible transformed terminal
**Then** the AppKit host invokes the Spotlight action exactly once
**And** the second Ghostty press and matching release are not forwarded
**And** the same terminal can be double-clicked in Spotlight to return to its original layout
**And** a callback-free Ghostty terminal retains native word selection
**And** SwiftTerm retains its SwiftUI double-click fallback

### Scenario F003-S17: Only an above-normal Spotlight terminal reserves scrolling for pan

**Given** Spotlight shows a persistent terminal at magnification above `1×`
**When** the user performs a precise trackpad scroll gesture over Spotlight
**Then** the terminal viewport receives the gesture for panning
**And** the Spotlight carousel does not switch
**And** any partial carousel offset is cleared
**When** terminal scale is exactly `1×` or optically shrunk to `0.5×...0.9×`
**Then** the terminal does not reserve scrolling for viewport pan
**And** a qualifying horizontal trackpad swipe switches to the previous or next carousel item
**And** ordinary non-carousel scrolling follows terminal scrollback behavior

### Scenario F003-S18: Compact content surfaces expose Back and Forward

**Given** Spotlight presents Markdown or browser content with content history
When Spotlight chrome renders and the user activates a visible Back or Forward button
Then controls report the canonical content history availability and invoke the same owner
And Markdown ⌘[/⌘] and browser mouse Back/Forward match their respective toolbar actions
And Markdown metadata and comments follow the current linked file
And browser metadata and comments follow the current URL

### Scenario F003-S19: Content Back does not close or return Spotlight

**Given** content was opened from a terminal or prior Spotlight item
When the user activates content Back
Then only Markdown or browser content history changes
And Spotlight remains open
When the user presses Escape, uses close, or clicks the backdrop
Then the existing Spotlight restore chain returns to the prior origin when available
And no separate visible Return control is required in the current scope

### Scenario F003-S20: One navigation input converges selection, card, attachment, and focus

**Given** Spotlight has multiple persistent carousel items
**When** the user presses one arrow, completes one qualifying swipe, or activates one non-current chip
**Then** exactly one target stable identity is selected
**And** direction and the signed entry offset are published before the target
**And** after one normal main/layout turn the selected identity, rendered card sentinel, attached surface, project context, and focus owner all identify that target
**And** no second navigation input is required
**And** tab-strip centering uses the target identity without a competing animation

### Scenario F003-S21: Rapid and direct presentations suppress stale generations

**Given** a Spotlight switch from A to B has queued animation completion or focus work
**When** the user rapidly switches to C or a direct/non-carousel presentation replaces B
**Then** prior generation work is cancelled or ignored
**And** B cannot later receive focus, reset C's offset, complete C's generation, or replace C's surface/project context
**And** dismissal clears generation, direction, offset, and queued focus work

### Scenario F003-S22: Duplicate terminal tab IDs remain project-scoped

**Given** two projects contain persistent terminal tabs with the same tab UUID
**When** Spotlight resolves, renders, reorders, or diagnoses those terminals
**Then** normalized project path plus tab UUID keeps the identities distinct
**And** state identity derived from `owningProjectRootURL` matches the corresponding item identity
**And** an unscoped persistent terminal aliases neither project terminal nor another unscoped terminal
**And** diagnostics contain only a hashed/tokenized project scope

### Scenario F003-S23: Missing or unscoped current identity hides dead carousel controls

**Given** persistent Spotlight state has no navigation identity in the live item sequence
**When** Spotlight chrome renders or receives carousel input
**Then** previous/next controls and the tab strip are hidden
**And** the scroll monitor is not installed for carousel navigation
**And** an unscoped terminal is not matched to a project terminal by tab UUID alone

### Scenario F003-S24: Shelf shows every persistent member

**Given** persistent Spotlight items exist **When** Spotlight opens **Then** the attached 44 pt shelf shows every item/member with type and project disambiguation and a compact trailing grid icon plus persistent-member count.

### Scenario F003-S25: All Tabs uses safe semantic cards and deterministic selection

**Given** All Tabs opens from the grid-count control or an exclusive member double-click
**When** the overview renders
**Then** search is focused and a flat three-column sequence follows persisted position/member order
**And** each borderless, no-gradient card remains 16:9
**And** terminal cards show only active/idle and directory-basename status, file cards follow the current editor owner, and browser cards follow the current browser owner with sensitive URL components redacted
**And** no screenshot, terminal screen excerpt, live output, command history, or project grouping is used
**When** the user uses pointer, Left/Right/Up/Down, and Return
**Then** the chosen member opens directly with current/combo/focused semantic status
**And** Escape closes the overview without dismissing Spotlight.

### Scenario F003-S26: Shelf start-region ownership is axis-gated and sequence-latched

**Given** a precise sequence begins in the shelf start region outside the grid-count control
**When** horizontal intent exceeds the axis threshold
**Then** shelf ownership remains latched through pointer leave, edge/no-overflow conditions, end/cancel, and momentum
**And** carousel offset and selection never change
**When** vertical intent wins, or the sequence begins over the grid-count control
**Then** the sequence passes through without shelf or carousel ownership.

### Scenario F003-S27: Club and unclub persistent members

**Given** distinct persistent members **When** one is dropped in another tab's center 50% **Then** one max-two combo is persisted once **And** dragging a member to a before/after zone extracts and repositions it **And** invalid host, generation, temporary, duplicate, self, or max-two drops are rejected.

### Scenario F003-S28: Combo halves own live interaction and pane-local compose state

**Given** a combo is selected
**When** either half or its pane-local terminal compose bar is clicked
**Then** that half activates without replacing the stable split roots
**And** it becomes the shared header/action/keyboard owner
**And** sending activates the same half before resolving its live terminal
**And** the other terminal half retains an independent draft, pasted images, history navigator, and history bucket keyed by its full stable Spotlight identity
**And** orientation persists as side-by-side or stacked.

### Scenario F003-S29: Missing combo members reconcile safely

**Given** an open combo loses members **When** live items reconcile **Then** one survivor becomes a single focused position, both missing select the nearest survivor, and no survivor dismisses Spotlight without cloning or terminating unrelated owners.

### Scenario F003-S30: Host-scoped layout and validated restore preserve ownership

**Given** main and detached hosts have different Spotlight layouts and nested temporary previews
**When** they reopen, reconcile, dismiss a preview, or receive the active temporary process exit
**Then** each host restores its own persisted order, combos, orientations, surface affinity, and valid live owner
**And** invalid restore descriptors are skipped, stale process exits do nothing, editor leases remain host-scoped, new live items append, legacy terminal/tile order mirrors, and board geometry is unchanged.

## Test Coverage

> **Evidence status (2026-10-18 documentation review):** The mappings below are a static inventory of source and test files. No tests, builds, apps, or manual UI checks were run for this documentation update. “Covers” means the named test source contains the stated assertions, not that it passed in this session. Production inspection confirms pane-local compose views/drafts, activation-before-send, AppContainer history injection in main and detached roots, and malformed browser-preview URL rejection in both restore paths. Physical gesture delivery, real accessibility vending, exclusive shelf double-click timing, visual 44 pt/grid-count styling, pane-local draft/history behavior in a mounted two-terminal combo, detached toolbar presentation, and end-to-end editor-lease release remain manual/UI or missing mounted-regression gaps.

| Scenario | Coverage |
|----------|----------|
| F003-S09 | Unit or UI regression MUST verify `Command` + `Return` sends from the Spotlight compose box while the compose field is focused and after focus moves to Spotlight chrome. |
| F003-S12 | Mounted `SpotlightPresentationTests.testShelfAndOverviewMountCompletePersistentMembersAndSearch` verifies the attached shelf/overview host and complete combo model; `SpotlightComboNavigationAndScrollTests` verifies shelf-owned precise scrolling without carousel switching. Visual trailing placement of All Tabs remains UI coverage. |
| F003-S13 | `LayoutPersistenceServiceTests.testMoveVibeSpaceSpotlightTerminalPersistsCrossProjectOrder` verifies project-scoped cross-project reorder; `SpotlightHostPersistenceAndPolicyTests.testMainHostSnapshotRoundTripsAndMirrorsLegacyTerminalOrder` verifies snapshot reload and the legacy terminal-order mirror. |
| F003-S14 | `SpotlightHostPersistenceAndPolicyTests.testMainOverlayCommitPathMirrorsPrimaryTileOrderAndPreservesEnrichedBrowserState` invokes the production main commit path with unequal two-column/row weights, a clubbed reorder, stale in-memory browser data, and a non-noop snapshot provider. It verifies the VibeSpace snapshot, legacy terminal order, primary surface snapshot/order, destination-slot geometry, current browser URL/history/zoom after reload, unchanged in-memory ownership, minimized state, active tile, tile identity/count, detached isolation, and disk reload. `testBoardSurfaceReorderPreservesUnequalDestinationGeometryAndOtherSurfaceThroughReload` retains detached-surface reorder/reload coverage. |
| F003-S15 | Mounted `SpotlightPresentationTests.testShelfActivityAnimationUsesLiveStateWithoutChangingMountedGeometry` changes the actual observable activity state and verifies the shelf scroll view, document root, document frame, and fitting size remain stable. |
| F003-S16 | Automated core coverage: `GhosttyTerminalViewInputTests.testHostDoubleClickInvokesCallbackWithoutForwardingSecondGhosttyClick` and `testDoubleClickWithoutCallbackRetainsGhosttyMouseSequence` verify exact native routing, suppression, and callback-free Ghostty behavior under the host path. UI smoke coverage remains responsible for visible Spotlight open/close and SwiftTerm fallback. |
| F003-S17 | Pure policy/unit: `TerminalViewModelTests.testSpotlightScrollRoutingReservesGesturesOnlyAboveNormal` verifies `0.5×`, `0.9×`, and exactly `1×` do not reserve scroll while `1.0001×` and higher do; `testSpotlightScrollGestureTrackerSwitchesAtNormalSizeAndResetsForZoomedPan` verifies accumulation, switch direction, takeover, and reset. Mounted AppKit: `GhosttyTerminalViewInputTests.testViewportPanUsesStrictAboveNormalBoundaryAndOptionPassesThrough` proves `1.0001×` pan interception plus exactly/below-normal and Option pass-through, while `testCenteredShrinkConsumesVerticalAndHorizontalScrollInBlankMarginsOnly` proves blank-margin scroll consumption and displayed-content forwarding. Physical NSEvent monitor delivery, horizontal-vs-scrollback feel, and real trackpad arbitration remain UI/manual coverage. |
| F003-S18 | Unit: Markdown/editor-group and browser regressions cover canonical history ownership, command/mouse dispatch, and current file/URL state. Required UI/manual: visible Spotlight controls, enabled-state changes, ⌘[/⌘], mouse-button parity, and metadata/comments rendering. |
| F003-S19 | Unit: content-history owner tests verify Back mutates content state rather than the restore chain. Required UI/manual: Spotlight remains open after content Back and Escape/close/backdrop restores the prior origin. |
| F003-S20 | Pure resolver/coordinator tests verify stable selection and generation ordering. Mounted synthetic and real-browser tests verify target sentinel/accessibility convergence and live `WKWebView` attachment in both directions. `testMountedShelfKeepsStableRootWhileSelectionChangesByIdentity` verifies identity selection without replacing the shelf root. Physical trackpad delivery, full-ContentView hit testing, terminal first-responder focus, and final animation paint remain UI/manual coverage. |
| F003-S21 | Pure coordinator: `TerminalSpotlightCoordinatorSynchronizationTests` verifies rapid A→B→C, direct replacement, stale focus/completion suppression, target surface/project retention, and dismiss reset. Mounted synthetic and real-browser suites verify no-second-input and forward/reverse host convergence; rapid A→B→C is not mounted. Remaining production-input/UI gaps: callback hit-testing and focus behavior across a live Ghostty/browser responder chain. |
| F003-S22 | Pure resolver/policy: `SpotlightNavigationResolverTests` verifies duplicate tab UUIDs across normalized project scopes, exact state/item identity agreement, unique nil-scope behavior, no invented project match, and tokenized diagnostics. Board-store regression verifies project-scoped reorder with duplicate tab UUIDs. Mounted/UI: no additional identity algorithm; UI smoke remains responsible only for distinguishable labels. |
| F003-S23 | Pure policy and mounted chrome coverage retains missing-identity suppression. |
| F003-S24–S25 | Static inventory: `SpotlightPresentationTests.testShelfAndOverviewMountCompletePersistentMembersAndSearch` mounts shelf membership and overview search. `SpotlightHostPersistenceAndPolicyTests.testBrowserMetadataStripsUserInfoQueryAndFragment` and safe-token assertions cover URL redaction and path-safe IDs. The source statically confirms three flexible columns, 16:9 cards, semantic status lines, current file/browser owner lookup, and no live-content capture. Exact visual styling, full keyboard event delivery, accessibility vending, exclusive double-click cancellation, and count-control presentation remain UI/manual gaps. |
| F003-S26 | Static inventory: `SpotlightComboNavigationAndScrollTests.testShelfScrollSequenceRemainsLatchedThroughLeaveEndAndMomentumWithoutCarouselOffset`, `testShelfOwnershipDoesNotRequireOverflowOrCarouselAvailability`, and registration-generation assertions cover horizontal latching. Vertical shelf intent and excluded grid-count pass-through are present in production policy but lack an explicit named assertion in the inspected test source. |
| F003-S27 | Static inventory: `SpotlightLayoutSnapshotTests` contains 25/50/25 move, club, unclub, max-two, self, stale-generation, and cross-host reducer assertions. |
| F003-S28 | Static inventory: mounted `SpotlightPresentationTests.testTerminalComboCompanionSelectionHasOneOwnerAndKeepsNativeRootsStable` and `testComboFocusAndOrientationUpdateWithoutReplacingSplitOrHostingRoots` cover one-owner focus and stable roots. Production source shows one `SpotlightTerminalInputBar` per terminal member, activation-before-send, full `SpotlightComposeIdentity`, and main/detached root history injection. Mounted independent draft/history coverage was not found. |
| F003-S29–S30 | Static inventory: reconciliation, snapshot Codable, standalone identity, exact nested restore, stale process-exit, main production router, detached factory, detached shortcut, and surface-local permanent-creation assertions are present in `SpotlightEnhancementTests`. Host-scoped editor lease union logic is present in `DockedFileViewerCoordinator`; a dedicated multi-host lease regression and complete detached window UI restore run were not found. |

## Acceptance Criteria

- Spotlight's configured open/replacement animation is 0.22 seconds and its configured close animation is 0.18 seconds. The earlier sub-200 ms combined target is not met by the open configuration and was not measured end to end in this documentation pass (PERF-3).
- Carousel switch generation completion is scheduled at 0.4 seconds. The earlier sub-300 ms completion target is not met by the configured completion delay and was not measured end to end in this documentation pass (PERF-3).
- Restore chain correctly unwinds for up to 3 nested spotlights (REL-1).
- Keyboard focus is correctly routed after spotlight transitions (A11Y-2).
- Spotlight compose input retains focus during non-focus-changing terminal output actions (A11Y-2).
- Spotlight compose inline trigger actions never auto-execute commands (A11Y-2).
- Spotlight's attached shelf is 44 pt high, scrolls every complete position, and keeps a compact trailing grid-plus-count control without separate paging controls.
- An exclusive member double-click opens focused All Tabs search without committing the delayed single-click selection.
- Shelf-started horizontal intent remains shelf-owned through momentum; vertical intent and the grid-count region pass through.
- All Tabs is a flat, borderless, no-gradient three-column 16:9 semantic grid in persisted order, never project-grouped and never sourced from screenshots, terminal screen excerpts, commands, or live output.
- Current file/browser owners provide privacy-safe metadata; raw project/file paths and browser userinfo, query, and fragment are not exposed.
- Each combo half is independently selectable; every terminal pane retains full-identity draft/image state and history and activates before send while the focused member owns shared chrome.
- Main and detached hosts use independent host-scoped editor leases and process-exit cleanup without changing persistent session lifetime or board geometry. Restore validates persistent terminal/ACP/file ownership and malformed browser-preview URLs in both hosts.
- Spotlight arrangement persists through each host's Spotlight snapshot. Main project terminals also mirror the legacy VibeSpace terminal order; only visible tile-backed board members mirror into board layout order, while minimized member order remains in the Spotlight snapshot.
- Spotlight terminal tab reordering preserves running sessions, active selection, and board grid shape.
- Spotlight active-tab animation remains contained within existing tab-chip bounds.
- A transformed Ghostty terminal double-click opens or closes Spotlight exactly once without forwarding an unmatched mouse event.
- Only terminal magnification above `1×` can reserve precise scrolling from Spotlight; exactly/below normal leaves carousel and ordinary scrollback behavior available.
- Spotlight operations logged (OBS-1).
- Compact Markdown/browser controls use the canonical content-history owner, while Spotlight dismissal alone uses the prior-origin restore chain.
- One arrow, swipe, or chip action converges stable selection, rendered card, attached surface, project context, and focus on one target generation without a second input.
- Rapid/direct replacement cannot run stale animation completion or focus work, and diagnostic project scopes never expose raw paths.

## Open Questions

- None for optical terminal magnification and carousel arbitration.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: recorded detached compose-history parity and main/detached malformed browser-preview URL rejection; aligned acceptance with configured 0.22 s open, 0.18 s close, and 0.4 s switch-completion timing; marked the prior sub-200/sub-300 ms targets unmet by configuration and unverified end to end. No tests or manual runs were performed. | — |
| 2026-10-18 | Review alignment fixed the attached shelf at 44 pt and documented compact grid-count and exclusive double-click behavior, axis-gated shelf ownership, safe persisted-order semantic cards, pane-local full-identity drafts and activation-before-send, independent combo halves, host-scoped editor leases, restore/process-exit cleanup, host-specific terminal-first catalog seeds, geometry-safe persistence, and honest static/manual gaps. Later production-fix status is recorded above. | — |
| 2026-10-18 | Preserved the flat borderless 16:9 All Tabs grid and specified persisted member order, privacy-safe metadata, and deterministic three-column keyboard movement. | — |
| 2026-10-16 | Implemented the attached full-width shelf, searchable All Tabs overview, sequence-latched shelf scrolling, max-two combos, focused live split rendering, reconciliation, and host-scoped persistence (R02, R12–R13, R16, R18–R24; S24–S30). | — |
| 2026-10-09 | Clarified that only terminal scale above `1×` reserves precise scrolling; exactly `1×` and `0.5×...0.9×` leave carousel and ordinary scrollback arbitration available (R16, S17). | — |
| 2026-10-09 | Added missing-current navigation suppression, project-scoped detached-board reorder coverage, mounted real-browser forward/reverse attachment coverage, and explicit static-audit/UI-gap classification (R20, S23). | — |
| 2026-10-09 | Added one-input selection/render/attachment/focus generation convergence, rapid/direct stale-work cancellation, project-scoped terminal identity, path-safe diagnostics, and unit/mounted/UI mappings (R18–R19, S20–S22). | — |
| 2026-10-06 | Added compact Markdown/browser Back/Forward controls and explicitly separated content history from Spotlight close/return semantics without claiming a new Return control (R17, S18–S19). | — |
| 2026-10-02 | Added native transformed-terminal double-click routing and magnified-terminal pan precedence over carousel swipe. | — |
| 2026-04-27 | Clarified cross-project vibespace Spotlight ordering and separate terminal-board Spotlight reorder persistence requirements. | — |
| 2026-04-26 | Added tab-strip overflow, reorder, and prominent activity animation requirements. | — |
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-036A–C, TRM-040, TRM-047–048, TRM-052–053, TRM-067) | — |
