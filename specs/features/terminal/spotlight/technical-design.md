# Terminal Spotlight — Technical Design

## Overview

Terminal Spotlight is a modal overlay presenting an expanded terminal view on top of the vibespace canvas. It is managed by `TerminalSpotlightCoordinator` (`ObservableObject`) and supports persistent and temporary terminal sources, related vibespace surfaces, carousel navigation, trackpad swipe transitions, nested restore chains, optical terminal pan/zoom, and a compose input bar.

## Architecture

### Component Hierarchy

```
TerminalSpotlightOverlayView
├── Backdrop and previous/next position controls
├── SpotlightTabShelf (attached, full card width, exactly 44 pt)
│   ├── one complete chip per single/combo position
│   ├── member and whole-combo drag payloads
│   ├── delayed single-select / exclusive double-click overview gesture
│   └── compact trailing grid icon + persistent-member count
├── SpotlightAllTabsOverview
│   └── flat, borderless, no-gradient three-column 16:9 semantic grid
├── TerminalSpotlightCardView
│   ├── focused-member shared header/actions
│   ├── stable NativeSplitView with independently clickable combo halves
│   └── one pane-local compose bar per terminal member
└── Scroll Monitor
    └── start-region axis intent, shelf/carousel/terminal ownership
```

`SpotlightLayoutSnapshot` is the value-only persistence/reducer model. `SpotlightItem` remains the live-reference adapter; resolving a snapshot never creates another terminal session, browser view model, editor group, or ACP store.

### Spotlight Source Types

| Source | Session Ownership | Carousel | Auto-Dismiss |
|--------|------------------|----------|-------------|
| Persistent terminal | References existing `TerminalViewModel` + tab UUID | Yes | No |
| Transient terminal | Owns a temporary `TerminalSession` | No | Process exit restores the previous descriptor or dismisses when empty |
| VibeCast | Reuses the VibeCast store | Yes | No |
| Vibe Lanes | Reuses the app Vibe Lanes owner | Yes | No |
| `.acp` | Reuses the existing ACP store identified by tile/store UUID | Yes | Missing stores are rejected during restore/reconciliation |
| `.filePreview` | Owns a temporary editor group | No | Close routes restore-first; no independent process lifecycle |
| `.file` | Reuses the docked file tile's editor group | Yes | Missing members reconcile out without closing unrelated owners |
| `.browserPreview` | Owns/restores a preview snapshot and preview view model | No | Close routes restore-first and preview teardown occurs at handling boundaries |
| `.browser` | Reuses the persistent board browser tile/view model | Yes | Restore validates the tile on the originating surface |

### Spotlight State Model

`TerminalSpotlightState` carries a unique `id` (UUID), source/live owner, title, optional accent, working directory, temporary flag, optional project root and host `surfaceID`, optional stable navigation override, shortcut/preset definitions, and their split/temporary/shortcut/preset callbacks.

### Native Terminal Double-Click

For Ghostty, `TerminalSessionView` and terminal-board tiles pass the Spotlight action through `TerminalSessionHostView` and `TerminalContainerView` to `GhosttyTerminalView.onDoubleClick`. On `clickCount == 2`, Ghostty cancels pending pointer interaction, invokes the action, and suppresses the matching second mouse-up. The surrounding SwiftUI double-tap handler is disabled for Ghostty to avoid duplicate transitions and remains enabled for SwiftTerm. A nil action is preserved as nil so callback-free Ghostty hosts retain native word selection.

## Data Flow

### Open Flow

1. Caller invokes `presentTerminalSpotlight` / `presentTemporaryTerminalSpotlight` / `presentVibeCastSpotlight`.
2. The source-specific presenter resolves any preview owner it needs, then calls `setSpotlight`:
   - Browser presenters dismiss or restore their preview owner at the presentation boundary; `setSpotlight` itself does not invoke a link-preview dismissal callback.
   - Before a temporary replacement, the coordinator pushes the exact current state once, preserving stable ID, callbacks, live owners, surface affinity, and standalone tile identity.
   - Main carousel reconstruction captures the current host surface before switching and passes it through the canonical item-to-state factory for terminal, standalone, VibeCast, Vibe Lanes, ACP, file, and browser targets.
   - Keeps a stacked transient session alive until restoration or full dismissal; non-restorable replaced transients are terminated.
   - Updates `diagnosticsSnapshot.spotlightActive`.
   - Animates transition: `.easeInOut(duration: 0.22)` (or immediate if `animated: false`).
   - Next main-queue cycle: `onFocusSpotlight` activates the terminal.
3. Focus grant:
   - Persistent → `terminalViewModel.selectTab(tab)`.
   - Transient → `session.startIfNeeded()`.
   - VibeCast → no-op.

### Dismiss Flow

1. Escape, backdrop, close, and native terminal double-click all invoke the host's shared restore-aware close route.
2. The close route tears down any browser preview boundary state, then pops descriptors until it restores a still-valid target. Exact stored state returns the focused member ID, callbacks, live owner, surface, standalone identity, and persisted combo position/orientation.
3. Only when the restore stack is empty or has no valid target does the host call `coordinator.dismiss()`:
   - Resets `swipeDirection`, `swipeOffset`, and `tabPageOffset`.
   - Removes the scroll monitor.
   - Releases current and stacked transient sessions (clears `onProcessTerminated`, calls `session.terminate()`).
   - Animates out with `.easeInOut(duration: 0.18)` when requested.
4. `.onDisappear` removes the scroll monitor; `deinit` removes the monitor and releases any remaining transient sessions.

### Validated Restore and Transient Process Exit

Restore validation differs by persistent source but applies the same malformed-preview rule in both hosts. Main and detached hosts require persistent IDs to remain in the host's live item set; persistent terminals must still contain the tab, ACP must still resolve its store, and file sources must retain an active editor document. Browser-preview restore requires a decodable snapshot URL before rehydrating an ephemeral preview owner in either host. Other invalid descriptors are skipped rather than mounted. Restoration preserves the exact stored state, including focused member identity, callbacks, surface, combo position, and orientation.

A temporary session's `onProcessTerminated` callback calls the shared process-exit handler guarded by Spotlight instance ID. Stale callbacks do nothing. The active exit path and every close route pop the same validated stack; only an empty stack fully dismisses Spotlight. Full dismissal clears callback references, terminates coordinator-owned temporary sessions, releases browser/file preview owners and host-scoped editor leases, removes the scroll monitor, and leaves persistent terminal sessions untouched.

## API / Command Contracts

### Coordinator API

| Method | Source | Notes |
|--------|--------|-------|
| `presentTerminalSpotlight(terminalViewModel:tabID:title:accentColor:...)` | Persistent | No-op if same tab ID already spotlighted |
| `presentTemporaryTerminalSpotlight(title:accentColor:directoryURL:shellResolutionProvider:...)` | Transient | Creates fresh `TerminalSession` with auto-dismiss wiring |
| `presentVibeCastSpotlight(surfaceID:animated:)` | VibeCast | Uses `AppStrings.VibeCast.title`; inherits current surface when no explicit surface is supplied |
| `closeTerminalSpotlight()` | — | Shared Escape/backdrop/close/native-double-click route; restores first, fully dismisses only when no valid descriptor remains |
| `dismissTerminalSpotlight()` | — | Explicit full dismissal; clears the restore stack and releases temporary sessions |

### Card Layout Constants

| Property | Value |
|----------|-------|
| Max size | 1220 × 760 pt |
| Corner radius | `themeManager.theme.radius(11)`, continuous style |
| Border | 1pt stroke, `borderColorValue.opacity(0.72)` |
| Shadow | black 30% opacity, radius 26, y-offset 15 |
| Header padding | 10pt horizontal, 7pt vertical |
| Accessibility ID | `"terminal.spotlight.overlay"` |

### Compact File and Browser Navigation

File and browser content use presentation-appropriate compact navigation in the Spotlight card. File sources render `EditorGroupFileSurface`, whose visible Back/Forward actions and ⌘[/⌘] call the owning `EditorGroupStore`; browser sources render their existing chrome, whose toolbar and mouse Back/Forward actions call the canonical `BrowserPanelViewModel`. File header metadata observes the group's `activeFileDocumentReference`, falling back to the immutable root only before a current file exists. Comments, provider, accessibility context, and detailed promotion resolve from that same current reference. Browser title/comments resolve from its current URL and page state.

These controls navigate content only. They do not pop `TerminalSpotlightCoordinator`'s restore descriptor. Escape, close, backdrop click, or other existing dismissal routes invoke the Spotlight restore chain and return to the prior terminal/Spotlight origin. There is no separate visible Return control in the current implementation.

### Backdrop Composition

| Layer | Material | Opacity |
|-------|----------|---------|
| 1 | `.ultraThinMaterial` | 72% |
| 2 | `windowBackgroundColor` | 42% |
| 3 | Black | 14% |

All layers ignore safe area. Tapping backdrop dismisses spotlight.

## State Management

### Project-Scoped Navigation Identity

Persistent terminal identity is `(SpotlightTerminalProjectScope, tabID)`. Project scope stores `owningProjectRootURL.standardizedFileURL.path`, exactly matching `VibeSpaceSpotlightTerminalOrderEntry` normalization. Item identity derives from `AnyProjectSession.rootURL`; presented-state identity derives from `TerminalSpotlightState.owningProjectRootURL`. If a persistent state has no project root, its Spotlight instance ID supplies a unique `.unscoped` scope. Such a state cannot collide with another terminal and intentionally cannot resolve into the project carousel. Diagnostic tokens pass project paths through `AppDiagnostics.pathToken`; raw paths are never included.

### Switch Generation Transaction

`beginCarouselSwitch` cancels queued direct focus, start, and completion work; advances a monotonic generation; then publishes direction and signed ±200-point entry offset before presentation publishes the target. `setSpotlight` accepts a carousel target only when generation and target identity match. The next main turn animates the current target to zero and requests focus. Completion checks generation, Spotlight instance ID, and target identity before retiring direction and generation. Rapid switches cancel predecessor work. A direct/non-carousel `setSpotlight` also cancels the active generation and tracked focus callback before scheduling its own ID-guarded focus work. The outer overlay and `NativeSplitView` roots remain mounted; target content updates through stable holders without keyed root replacement. Shelf centering uses stable position identity without adding a competing card animation.

### Position Navigation and Scroll Arbitration

The host reconciles its `SpotlightLayoutSnapshot` against the current `SpotlightItem` set. Relative navigation indexes `positions`, not flattened members, so a combo advances in one step. Direct selection resolves the target member: a member in the current combo returns direction zero and changes focus; a member in another position performs the normal generation-guarded transition.

`SpotlightScrollGestureTracker` classifies a precise sequence as shelf, carousel, vertical pass-through, or terminal-owned. Shelf is chosen at begin hit-testing and remains latched through end/cancel and all momentum. Carousel qualification retains the 20-point/two-axis threshold, 0.35 offset damping, and 50-point commit threshold. A terminal magnified strictly above `1×` still wins on non-shelf content. Ownership generations reset tracking on overview, replacement, dismissal, monitor removal, and window/shelf loss.

### Transition Animations

Carousel generations publish direction and ±200-point entry offset before target state, then spring to zero. Direct combo-member focus uses no carousel offset. Only the current generation may complete or request focus.

### Input Bar Draft and History Management

`SpotlightTerminalInputBar` is instantiated once per visible terminal member, including both halves of a combo. Each instance owns its own draft dictionary, pasted-image draft dictionary, and inline-trigger controller. It creates a `ComposeHistoryNavigator` from the `ComposeHistoryStore` in the SwiftUI environment. The shared in-memory store is created by `AppContainer` and explicitly injected at both the main root and `DetachedTerminalBoardWindowRoot`; it is not a singleton or service locator.

All pane-local state binds to `TerminalSpotlightState.composeIdentity`, never only the current tab UUID:

- project terminal: `.persistent(.terminal(projectPath: normalizedProjectPath, tabID: tabID))`
- standalone board terminal: `.persistent(.standaloneTerminal(surfaceID: surfaceID, tileID: tileID, tabID: tabID))`
- temporary terminal: `.transient(session.id)`

The history key, when a navigator exists, is a stable string derived from the safe persistent token or transient session UUID. On identity change, the old text and pasted-image drafts are saved and the new pane drafts are restored. An available navigator reattaches and clears its cursor/pending draft. Deferred focus is accepted only while the same identity requests focus.

`sendInput()` captures the expected full identity, calls the pane's `onActivate`, rechecks identity, resolves the live session after activation, sends exactly once, appends to that pane's history only when a navigator/store is available, then clears only that pane's text/image draft. Thus a nonfocused combo half cannot dispatch to the previously focused terminal. The focused member still owns shared header actions and keyboard focus.

- Send shortcut: `TerminalComposeInputView` handles `Command` + `Return` inside its `NSTextView` first and also registers the visible send action as a SwiftUI key equivalent.
- Rephrase: `VibeCastRephraseService.rephrase(text)` on detached task → replace input.
- Inline trigger parsing:
  - the trigger token is loaded from `AppPreferences.terminalComposeInlineTriggerKey`
  - default token is `` ` ``
  - trigger matching follows the last whitespace-delimited trigger token in the draft rather than only the first character of the draft
- Inline insert picker data sources:
  - local file-system path results come from an app-bundled Rust helper process rooted at the ordered set of local vibespace project roots for the current vibespace, with the current spotlight project root first when available and fallback inclusion of the spotlight working directory when it is local
  - saved shortcuts come from `spotlight.shortcutDefinitions`
  - one built-in prompt action (`Generate Command`) is always available
- Inline path-search lifecycle:
  - the helper process is launched only when the current visible trigger token has a non-empty query and a local file-system root
  - the helper is restarted when the spotlight terminal context changes to a different local root set
  - the helper is stopped when the trigger token is cleared, dismissed, or the spotlight input view disappears
- Inline path-search implementation:
  - the helper bundles the Codex `file-search` engine shape into a separate Rust executable shipped inside the app executable directory (`Contents/MacOS`)
  - the helper maintains one session per spotlight input, streams query updates over stdio, and emits snapshot notifications back to Swift
  - result ordering follows Codex path-search scoring and tie-breaking: descending fuzzy score, then ascending path
- Inline result ranking:
  - local path results are shown ahead of shortcut and prompt rows
  - the picker surfaces path rows up to the helper's streamed limit rather than enforcing a smaller UI-only cap
  - shortcut candidates use fuzzy matching over normalized text instead of exact substring-only scoring
  - the matcher accepts abbreviated in-order queries, rewards tighter spans, and strongly boosts prefix hits
  - shortcut ranking prefers shortcut-name matches over command-text-only matches
- Inline trigger outcomes:
  - selecting a file or directory replaces only the active trigger token with a shell-safe path relative to the spotlight terminal working directory when possible
  - selecting a shortcut replaces only the active trigger token with the shortcut command
  - selecting a prompt action runs the configured text-service CLI and replaces only the active trigger token with the generated result
  - inline picker actions never auto-execute the inserted or generated command text
  - programmatic replacements move the compose insertion point to the end of the inserted text
  - the picker footer exposes `Manage Shortcuts…` when spotlight provides a shortcut-management callback
  - dismissing the picker with `Escape` suppresses that same active trigger token until the token is removed; continuing to type inside that dismissed token does not immediately reopen the picker
- Inline trigger focus:
  - `Tab` confirms the highlighted inline item
  - arrow up/down moves the highlighted inline item while the picker is open
  - `Escape` dismisses the picker while preserving the draft
- Inline trigger panel sizing:
  - the panel presents a bounded result count, caps visible height, and scrolls the selected row into view so long result sets do not extend off-screen

### Attached Shelf, Semantic Overview, and Drag Reducer

The shelf fills the card width, shares its top edge with the card, and has a fixed 44 pt frame. The scrollable start region renders every normalized `SpotlightPositionSnapshot`; a combo chip contains both member labels and a dedicated whole-combo handle. The excluded trailing region contains only a compact `square.grid.2x2` icon and `catalog.ordered.count`, while accessibility exposes **All Tabs**. A member single-click is delayed by `NSEvent.doubleClickInterval`; the simultaneous two-click gesture cancels the work item and calls `onShowAll`, so overview opening does not first select that member.

All Tabs uses three flexible columns and one 16:9 tile per persisted position. It is intentionally flat, borderless, no-gradient, and ordered by `snapshot.positions`/`flattenedMembers`, not by project or metadata group. A combo renders two independently clickable member buttons inside one position tile. Search is focused on appearance; Left/Right moves one member, Up/Down moves three, Return opens the selected member, and Escape closes only the overview.

`SpotlightOverviewArtwork` is semantic and metadata-only. It never captures a screenshot or reads terminal screen buffers, command text, live terminal output, editor pixels, or WebView pixels. Terminal cards show only active/idle plus the current working-directory basename. File metadata resolves the current `activeFileDocumentReference` from the owning editor group and exposes only filename plus parent display name. Browser metadata resolves the current owner, uses page title plus host/path, and removes userinfo, password, query, and fragment. Search and accessibility use the same safe catalog; identifiers use `SpotlightPersistentItemID.safeToken`, never raw project paths.

Drag payloads contain only host ID, layout generation, and a value-only position/member subject. `SpotlightLayoutReducer` validates scope/generation, resolves before/club/after at 25/50/25, caps combos at two distinct persistent members, and emits one accepted snapshot. Hover changes decoration only. The host persists once after drop.

### Combo Rendering, Focus, and Editor Host Leases

A combo is one carousel position. Its members render in persisted order in one stable `NativeSplitView`; each half is independently clickable and receives an explicit `SpotlightMemberInteractionContext`. Side-by-side is default and the orientation action persists stacked layout in the same position snapshot. Exactly one member supplies the shared header metadata/actions and keyboard focus. Every terminal member retains its own `SpotlightTerminalInputBar`; interaction and send activate that member before session lookup.

Terminal panes avoid a competing card-owned selection gesture: an unfocused `TerminalSessionView` delegates one stable-identity transition request, while an already-focused terminal only activates its canonical session. Nonterminal halves retain card-owned pointer selection. Main and detached cards use the same route. Terminal, WebView, editor group, and ACP owners come from existing host registries and are never copied; `NativeSplitView` updates content holders without replacing native hosting roots.

File members use `DockedFileViewerCoordinator.setSpotlightOwnedTileIDs(_:ownerID:)` as a host-scoped lease. Each main or detached Spotlight host publishes the file tile IDs in its current position. The coordinator unions leases across hosts, and docked file tiles suppress their duplicate `EditorGroupFileSurface` while leased. Clearing or changing one host removes only that host's entry, preserving leases held by other windows.

### Host-Scoped Persistence and Reconciliation

Main-host `SpotlightLayoutSnapshot` is stored in the VibeSpace layout state. Its sole production commit route is `VibeSpaceTerminalBoardStore.commitMainSpotlightLayout`: it normalizes once, mirrors the same snapshot onto the primary surface, reorders only flattened visible tile-backed members with destination-slot semantics, enriches a persistence copy through the same `BoardSnapshotProviders` boundary used by normal board commits, and asks `LayoutPersistenceService.commitMainSpotlightLayout` to write the VibeSpace snapshot, legacy terminal order, and complete mirrored board state in one layout-file update. This preserves current externally owned browser URL/history/zoom payloads without injecting those snapshots into the store's in-memory geometry state. Main shelf drops, reconciliation, and orientation changes all use this route; a missing or mismatched active board store rejects the commit rather than performing a snapshot-only write.

Each detached `VibeSpaceTerminalBoardSurface` retains its independent snapshot and existing `setSpotlightLayout` route. Normalization removes stale/duplicate IDs, truncates invalid over-sized combos, and appends new live IDs. The main catalog emits legacy-ordered project terminals first, primary-board standalone terminals second, ACP/file/browser members next, and virtual VibeCast/Vibe Lanes members last. A detached catalog emits all terminal tile members from visible then minimized tiles first, then scans visible then minimized tiles again for VibeCast/Vibe Lanes/ACP/file/browser members; it appends a synthetic Vibe Lanes member when no Vibe Lanes tile exists. These catalogs seed and reconcile the persisted snapshot rather than defining one unified mixed-kind tile traversal. A persistent minimized standalone remains addressable, and user-arranged Spotlight order remains in the snapshot. Board ordering moves visible tile-backed content between existing primary or detached destination slots while column IDs/counts/width weights and destination row height weights stay fixed. Minimized tile placement/order in the board, active tile, sessions, tile count, synthetic host-level members, and non-target surfaces are not changed by Spotlight persistence.

On live changes, `SpotlightLayoutReconciler` collapses one surviving combo member to a single, focuses a surviving partner when the current member disappears, otherwise chooses the nearest surviving position or dismisses. Coordinator layout generations and switch generations prevent stale focus or attachment work.

### Scroll Ownership

The local AppKit monitor classifies each precise sequence once. A sequence beginning in the registered 44 pt shelf start region begins as `shelfPending`; the compact grid-count control is registered as an excluded region. After more than 4 pt of cumulative motion, horizontal-dominant intent becomes shelf-owned and is manually routed to the shelf `NSScrollView` through end/cancel and momentum, even after pointer leave, with no overflow, or at an edge. Vertical-dominant intent becomes pass-through. Events beginning over the excluded control also pass through. Shelf ownership never publishes carousel offset. Non-shelf content retains its 20 pt/two-axis carousel qualification and strict `displayMagnification > 1` terminal arbitration. Overview presentation, direct replacement, layout commit, dismissal, monitor removal, and shelf/window detachment advance the ownership generation and clear offset.

## Dependencies

- `TerminalViewModel` — tab resolution for persistent sources
- `TerminalSession` — process lifecycle for transient sources
- `TerminalFocusCoordinator` — focus grant/relinquish on spotlight transitions
- `VibeCastRephraseService` — compose bar rephrase action
- `TerminalSessionHostView` — terminal surface rendering

## Platform Considerations

- Scroll monitor uses `NSEvent.addLocalMonitorForEvents` (macOS-only AppKit API) and must defer only to an above-normal terminal viewport. Exactly/below normal does not reserve viewport pan; horizontal carousel gestures may be consumed by the monitor and other scrolling passes to terminal scrollback.
- Ghostty double-click routing crosses the SwiftUI/AppKit boundary explicitly; SwiftTerm uses the SwiftUI fallback.
- Momentum phase events are consumed if horizontal gesture is active, otherwise passed through.
- Keyboard shortcut `.escape` bound to close button for system-level Escape handling.
- `.onExitCommand` on overlay provides additional Escape dismissal path.
- Ownership priority: Spotlight hosts = 300 (highest), ensuring spotlight always wins terminal or browser view ownership over rail/board hosts.

## Performance Constraints

- Configured open/replacement animation: 0.22 s; configured close animation: 0.18 s. The prior combined `< 200 ms` target is not met by the open configuration and remains unverified end to end.
- Carousel switch completion work: 0.4 s after switch start. The prior `< 300 ms` completion target is not met by the configured delay and remains unverified end to end.
- No tests, builds, apps, or manual timing runs were performed for this documentation update.
- Restore chain correctly unwinds for up to 3 nested spotlights.
- Transient session termination must be synchronous on dismiss to prevent orphaned processes.
- Session-scoped full-tree path search must remain bounded under sustained external file edits by keeping the filesystem crawl in the bundled Rust helper, cancelling the helper when the trigger is inactive, and avoiding any Swift-side path-tree caching or background crawl after dismissal.

## Migration / Rollout Notes

- Legacy terminal session entries without stable tab IDs continue to restore by directory/name/origin/tmux identity, then persist stable IDs on the next snapshot.
- Reorder changes must be tested in both Spotlight hosts because vibespace Spotlight and terminal-board Spotlight intentionally use different catalog seeds and persistence mirrors.
- VibeSpace Spotlight cross-project reorder requires a vibespace-scoped migration path: existing vibespaces without Spotlight order use default project/tab traversal until the first reorder writes a stable ordered identity list.
- Terminal-board reorder persistence must keep board tile counts and column row counts stable; only the flattened visible tile sequence changes, while minimized placement/order remains unchanged in the board and its Spotlight member order remains in the snapshot.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Final audit fixes: updated source-aligned timing to 0.22 s open/replacement, 0.18 s close, and 0.4 s carousel completion; marked earlier performance targets unmet by configuration and unverified end to end; documented detached AppContainer history injection and browser-preview URL validation in both hosts. No tests or manual UI/timing runs were performed. | — |
| 2026-10-18 | Review fixed shelf geometry at 44 pt and documented grid-count and delayed single/exclusive double-click routing, start-region axis gating, safe persisted-order semantic artwork, per-pane full-identity drafts and activation-before-send, independent combo targets, host-scoped editor leases, host-specific terminal-first catalog seeds, and source validation. Later production-fix status is recorded above; no tests or manual UI flows were run in that documentation pass. | — |
| 2026-10-18 | Added safe canonical metadata resolution, full compose identity, pane-local activation, editor host leases, detached-local previews, validated restore, live drop transactions, full-shelf axis intent, flat-grid order, and explicit snapshot migration. | — |
| 2026-10-16 | Unified native double-click with restore-aware close routing and preserved main-board surface affinity through every direct and carousel-reconstructed Spotlight kind. | — |
| 2026-10-16 | Implemented value-only host snapshots, full-width shelf, metadata overview, sequence-latched shelf routing, pure club/unclub reducer, stable NativeSplitView combos, focused-member ownership, and live reconciliation. | — |
| 2026-10-09 | Clarified that the exact `>1×` terminal boundary reserves precise scrolling for viewport pan; `1.0001×` is intercepted while exactly/below normal retains carousel qualification and terminal scrollback pass-through, with blank optical margins consumed. | — |
| 2026-10-09 | Documented project-scoped terminal identity, unique nil-scope behavior, path-token diagnostics, cancellable generation/focus transactions, stable card rendering, and noncompeting identity-based centering. | — |
| 2026-10-06 | Documented compact Markdown/browser Back/Forward ownership, current-context metadata, and the distinction between content history and Spotlight close/restore without a new Return control. | — |
