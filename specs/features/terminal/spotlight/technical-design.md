# Terminal Spotlight — Technical Design

## Overview

Terminal Spotlight is a modal overlay presenting an expanded terminal view on top of the vibespace canvas. It is managed by `TerminalSpotlightCoordinator` (ObservableObject) and supports three source types, carousel navigation across all terminal tabs and VibeCast, trackpad swipe transitions, nested restore chains, and a compose input bar.

## Architecture

### Component Hierarchy

```
TerminalSpotlightOverlayView (z-index: 220)
├── Backdrop (3-layer blur composition)
├── Tab Strip (paginated, max 5 visible items)
├── Chevron Buttons (left/right navigation)
├── TerminalSpotlightCardView (generic over content + input bar)
│   ├── Header Bar (icon, title, rename, working dir, action buttons)
│   ├── Content Area
│   │   ├── TerminalSessionView (persistent)
│   │   ├── TerminalSessionHostView (transient, keyed by session.viewIdentity)
│   │   └── VibeCastView (VibeCast source)
│   └── SpotlightTerminalInputBar (hidden for VibeCast)
│       ├── SpotlightComposeInlinePanel (optional)
│       └── TerminalComposeInputView (send + rephrase actions + inline trigger key routing)
└── Scroll Monitor (NSEvent local monitor for trackpad swipe)
```

### Spotlight Source Types

| Source | Session Ownership | Carousel | Auto-Dismiss |
|--------|------------------|----------|-------------|
| Persistent | Not owned; references existing `TerminalViewModel` + tab UUID | Yes | No |
| Transient | Owned; creates new `TerminalSession` on demand | No (excluded) | Yes, on process exit |
| VibeCast | None; compose-only | Yes | No |
| `.acp` | — | — | — |
| `.filePreview` | — | — | — |
| `.file` | — | — | — |
| `.browserPreview` | — | — | — |
| `.browser` | — | — | — |

### Spotlight State Model

`TerminalSpotlightState` carries: unique `id` (UUID), `title`, optional `accentColor`, `workingDirectoryURL`, `isTemporary` flag, optional `owningProjectRootURL`, and optional closures for split-terminal and temporary-terminal requests.

## Data Flow

### Open Flow

1. Caller invokes `presentTerminalSpotlight` / `presentTemporaryTerminalSpotlight` / `presentVibeCastSpotlight`.
2. `setSpotlight` is called:
   - Dismisses any active link preview (`onDismissLinkPreview`).
   - Releases previous transient session if different ID (terminates session).
   - Updates `diagnosticsSnapshot.spotlightActive`.
   - Animates transition: `.easeInOut(duration: 0.22)` (or immediate if `animated: false`).
   - Next main-queue cycle: `onFocusSpotlight` activates the terminal.
3. Focus grant:
   - Persistent → `terminalViewModel.selectTab(tab)`.
   - Transient → `session.startIfNeeded()`.
   - VibeCast → no-op.

### Dismiss Flow

1. Trigger: Escape key, backdrop click, double-click card, programmatic `dismissTerminalSpotlight()`.
2. `coordinator.dismiss()`:
   - Resets `swipeDirection`, `swipeOffset`, `tabPageOffset`.
   - Removes scroll monitor.
   - Releases transient session (clears `onProcessTerminated`, calls `session.terminate()`).
   - Animates out: `.easeInOut(duration: 0.18)` (or immediate).
3. Cleanup: `.onDisappear` removes scroll monitor; `deinit` removes monitor + releases transient.

### Transient Auto-Dismiss

Transient session's `onProcessTerminated` callback calls `coordinator.dismiss()`, guarded by spotlight ID match to prevent stale dismissals.

## API / Command Contracts

### Coordinator API

| Method | Source | Notes |
|--------|--------|-------|
| `presentTerminalSpotlight(terminalViewModel:tabID:title:accentColor:...)` | Persistent | No-op if same tab ID already spotlighted |
| `presentTemporaryTerminalSpotlight(title:accentColor:directoryURL:shellResolutionProvider:...)` | Transient | Creates fresh `TerminalSession` with auto-dismiss wiring |
| `presentVibeCastSpotlight(animated:)` | VibeCast | Uses `AppStrings.VibeCast.title` and active theme accent |
| `dismissTerminalSpotlight()` | — | Full dismiss with animation |

### Card Layout Constants

| Property | Value |
|----------|-------|
| Max size | 1220 × 760 pt |
| Corner radius | `themeManager.theme.radius(11)`, continuous style |
| Border | 1pt stroke, `borderColorValue.opacity(0.72)` |
| Shadow | black 30% opacity, radius 26, y-offset 15 |
| Header padding | 10pt horizontal, 7pt vertical |
| Accessibility ID | `"terminal.spotlight.overlay"` |

### Backdrop Composition

| Layer | Material | Opacity |
|-------|----------|---------|
| 1 | `.ultraThinMaterial` | 72% |
| 2 | `windowBackgroundColor` | 42% |
| 3 | Black | 14% |

All layers ignore safe area. Tapping backdrop dismisses spotlight.

## State Management

### Carousel Navigation

**Flat ordering** (`flatSpotlightItems`): VibeSpace Spotlight lists terminal items by reconciling the persisted vibespace-level Spotlight order with the current live terminal set, followed by any live terminal identities that are not yet in that order using the default project/tab traversal (`activeVibeSpaceProjects`, then each project's `terminalViewModel.tabs`). Missing or closed terminal identities are pruned from the reconciled order. VibeCast remains a fixed non-terminal carousel item after terminal items and is not reordered by terminal tab drag/drop. Terminal-board Spotlight lists items from the active `VibeSpaceTerminalBoardLayout.tiles` order for that board surface.

**Index resolution**: VibeSpace persistent sources match by scoped terminal identity (project scope plus tab ID). Terminal-board persistent sources match by board tile identity on the active surface, with terminal tab ID as a secondary validation field. VibeCast matches by enum case. Transient sources return `nil` (excluded from carousel).

### Trackpad Swipe State Machine

Installed as `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)`.

| Phase | Behavior |
|-------|----------|
| `.began` | Reset cumulative delta and tracking state |
| `.changed` | Accumulate `scrollingDeltaX`. Horizontal gesture recognized when cumulative > 8pt and horizontal > vertical. Offset dampened by **0.35×**, applied with `.interactiveSpring(response: 0.08, dampingFraction: 0.9)` |
| `.ended`/`.cancelled` | If cumulative > **50pt** → trigger switch (+1 or -1). Else snap back with `.spring(response: 0.35, dampingFraction: 0.7)` |

Only precise scrolling deltas (trackpad) activate; mouse wheel events pass through. Horizontal gesture events are consumed (return `nil`).

### Switch Animation (`switchSpotlight(by:)`)

1. Blocked if current spotlight is temporary.
2. Single item → snap offset to 0 with `.spring(response: 0.35, dampingFraction: 0.7)`.
3. Wrap-around index: `(currentIndex + offset + count) % count`.
4. Set `swipeDirection` to `.trailing` or `.leading`.
5. Present new spotlight without animation.
6. Set swipe offset to entry position (±200pt) immediately.
7. Animate offset to 0 with `.spring(response: 0.35, dampingFraction: 0.82)`.

### Transition Animations

| Context | Insertion | Removal |
|---------|-----------|---------|
| No swipe | `.opacity` + `.scale(0.975)` | `.opacity` + `.scale(0.985)` |
| During swipe | Slide from trailing/leading + opacity | Slide opposite direction + opacity |

### Input Bar Draft Management

`SpotlightTerminalInputBar` maintains `[UUID: String]` dictionary keyed by tab/session ID. On spotlight switch, current draft is saved and new terminal's draft is restored.

- Send: trim whitespace → `session.sendRawTextWithEnter(text)` → clear input.
- Send shortcut: `TerminalComposeInputView` handles `Command` + `Return` inside its `NSTextView` first and also registers the visible send action as a SwiftUI key equivalent, so sending still works after focus moves to Spotlight tab/header controls.
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

### Tab Strip

- Displays up to **5 items** in a paginated window.
- The computed window follows the current spotlight item, so carousel switches cannot leave the active item outside the visible strip.
- Page chevrons keep stable 20×20pt slots; each chevron is enabled only when hidden items exist on that side.
- Paging uses the currently visible window start, not stale stored page state, and does not switch spotlight content.
- Each tab: color dot (project color tag) for terminals, tab title (or project title fallback), activity indicator.
- VibeCast tab: antenna icon + VibeCast title.
- Current tab highlighted: `selectionBackgroundColor.opacity(0.3)`.
- Active terminal tabs render `TerminalActivityBar` plus a bottom `TerminalActivityUnderline` inside the existing chip bounds. The underline uses `TimelineView` with a moving highlight segment and does not change chip dimensions.
- Persistent terminal tabs can be dragged within the spotlight strip. Tab-strip entries are keyed by stable item identity, not by visible index, so reordered terminal chips move as identities instead of repainting in fixed slots.
- The drag provider carries a stable Spotlight terminal identity. VibeSpace Spotlight identities include project scope plus terminal tab UUID. Terminal-board Spotlight identities include the board tile identity and terminal scope required to validate the tile still exists on the active surface.
- Each terminal chip has a `DropDelegate` that reads local pointer location. Hovering over the left half marks `.before`; hovering over the right half marks `.after`.
- The hovered target renders a 2pt vertical insertion marker at the indicated edge. The dragged chip dims, scales slightly, and receives a light shadow while a drop target is active. During local drags, valid terminal hover targets call the host reorder closure immediately so the strip behaves like browser tabs; final drop confirms the same host-owned order.
- The overlay does not own persistence. Reordering a terminal tab relative to another terminal tab calls the host-provided reorder closure with dragged terminal identity, target terminal identity, and insertion placement. Non-terminal drops are ignored before persistence is requested.
- VibeSpace Spotlight builds its terminal carousel from the reconciled vibespace-level Spotlight order stored in the centralized vibespace persistence model. Dropping a terminal tab there calls the centralized persistence service through a vibespace-order mutation that moves the dragged identity relative to the target identity and writes the resulting ordered identity list at vibespace scope. It does not rewrite per-project terminal tab arrays as the primary persistence mechanism.
- Terminal-board Spotlight builds its carousel from `VibeSpaceTerminalBoardLayout.tiles`; dropping a tab there must call `VibeSpaceTerminalBoardStore.moveTerminalTabTile(_:relativeTo:placement:surfaceID:)` so the persisted board tile order changes. Terminal-board reorder must not depend on project tab order or vibespace Spotlight order; board tile order is the source of truth for the board carousel.
- `TerminalViewModel.moveTab(_:relativeTo:placement:)` remains the project-local tab-bar reorder operation. It reorders only one project's `tabs` array, preserving sessions, activity state, and `activeTabID`; it is not sufficient to persist vibespace Spotlight order when dragged and target tabs belong to different projects.
- The centralized vibespace persistence model preserves a linear Spotlight order field of terminal identities. Reconciliation on read removes identities that no longer resolve, appends new terminal identities not yet stored, and keeps project-local restore order unchanged.
- `VibeSpaceTerminalBoardLayout.moveTileInLinearOrder(_:relativeTo:placement:)` preserves the current board grid shape while changing the flattened tile order used by terminal-board Spotlight carousel navigation.
- `TerminalSessionEntry.id` stores the stable terminal tab UUID. `ProjectTerminalSessionPersistence.snapshot` writes tab IDs in the current array order and stores the active tab identity as `tab:<uuid>`.
- `TerminalViewModel.restoreTabsFromEntries` restores persisted tab IDs when present and deduplicates by tab ID before falling back to legacy directory/name/origin/tmux identity. This keeps Spotlight reorder persistence reliable even when several tabs look identical.

## Dependencies

- `TerminalViewModel` — tab resolution for persistent sources
- `TerminalSession` — process lifecycle for transient sources
- `TerminalFocusCoordinator` — focus grant/relinquish on spotlight transitions
- `VibeCastRephraseService` — compose bar rephrase action
- `TerminalSessionHostView` — terminal surface rendering

## Platform Considerations

- Scroll monitor uses `NSEvent.addLocalMonitorForEvents` (macOS-only AppKit API).
- Momentum phase events are consumed if horizontal gesture is active, otherwise passed through.
- Keyboard shortcut `.escape` bound to close button for system-level Escape handling.
- `.onExitCommand` on overlay provides additional Escape dismissal path.
- Ownership priority: Spotlight hosts = 300 (highest), ensuring spotlight always wins terminal view ownership over rail/board hosts.

## Performance Constraints

- Spotlight open/close transitions: < 200ms.
- Swipe transitions: < 300ms.
- Restore chain correctly unwinds for up to 3 nested spotlights.
- Transient session termination must be synchronous on dismiss to prevent orphaned processes.
- Session-scoped full-tree path search must remain bounded under sustained external file edits by keeping the filesystem crawl in the bundled Rust helper, cancelling the helper when the trigger is inactive, and avoiding any Swift-side path-tree caching or background crawl after dismissal.

## Migration / Rollout Notes

- Legacy terminal session entries without stable tab IDs continue to restore by directory/name/origin/tmux identity, then persist stable IDs on the next snapshot.
- Reorder changes must be tested in both Spotlight hosts because vibespace Spotlight and terminal-board Spotlight intentionally read from different ordering models.
- VibeSpace Spotlight cross-project reorder requires a vibespace-scoped migration path: existing vibespaces without Spotlight order use default project/tab traversal until the first reorder writes a stable ordered identity list.
- Terminal-board reorder persistence must keep board tile counts and column row counts stable; only the flattened tile sequence changes.
