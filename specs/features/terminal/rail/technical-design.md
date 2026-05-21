# Terminal Rail — Technical Design

## Overview

The Terminal Rail (`VibeSpaceStackedProjectRailView`) displays a scrolling list of project-local terminal stacks for non-focused projects in Detailed view. It no longer treats every visible terminal tab as a top-level rail card. Instead, each project contributes one collapsed stack whose representative terminal is chosen from that project's visible tabs using activity and recency signals. Hovering or keyboard-focusing that stack expands the project's remaining visible terminals inline without changing vibespace focus.

## Architecture

### Component Hierarchy

```
VibeSpaceCanvasSurfaceView (Detailed mode)
└── NativeSplitView (outer, omitted for single-project)
    ├── VibeSpaceStackedProjectRailView
    │   ├── ScrollView (LazyVStack or LazyHStack based on rail position)
    │   │   └── ProjectTerminalStackView (per non-focused project)
    │   │       ├── Primary StackedTerminalCardView (representative terminal)
    │   │       ├── Peek layers for additional visible terminals in collapsed state
    │   │       └── Expanded StackedTerminalCardView list on hover/focus
    │   └── Hidden Terminals Section (collapsible disclosure group)
    └── detailedContentPane (focused project terminal + editor)
```

### Store Architecture

`StackedRailTerminalStore` subscribes to each project's `TerminalViewModel.tabsPublisher` and maintains:
- `tabsByProjectPath: [String: [TerminalTab]]` — live dictionary of tabs per project.
- Project groups are emitted in the same order as `vibespaceView.stackedProjects`.
- Manual rail-hidden tabs are filtered by excluding `hiddenTerminalIDsByProjectPath`.
- A derived `StackedRailProjectGroup` presentation is built per project with:
  - `orderedVisibleTabs`
  - `primaryTab`
  - `additionalVisibleTabs`
  - `hiddenTabs`
  - `isExpanded`
- Representative-terminal ranking depends on:
  - per-tab `TerminalTabActivityState`
  - a per-tab `lastSignificantOutputAt`
  - a per-project `lastFocusedTerminalID`
  - current `activeTabID` fallback from `TerminalViewModel`

## Data Flow

### Tab Activity Flow

1. Terminal session receives data → `TerminalTabActivityState` evaluates against activity threshold.
2. Suppression windows (startup, resize) prevent false positives.
3. `isActive` set true → activity indicator appears on card + pane header + board tile header.
4. No significant data for ~1 second idle period → `isActive` set false → indicator removed.
5. `TerminalTabActivitySummary` aggregates per-tab states to drive project-level indicators.

### Representative Terminal Selection Flow

1. Collect all non-hidden tabs for a project.
2. Sort visible tabs using this precedence:
   - active tabs first
   - among active tabs, newest `lastSignificantOutputAt`
   - otherwise the project's `lastFocusedTerminalID`
   - otherwise the project's `activeTabID`
   - otherwise stable existing tab order
3. Use the first entry as `primaryTab` for the collapsed rail stack.
4. Render remaining visible tabs as collapsed peeks or expanded cards using the same order.

### Project Stack Ordering Flow

1. Read non-focused projects from vibespace order.
2. Build one `StackedRailProjectGroup` per project in that same sequence.
3. Re-rank only the terminals within each project group.
4. Never float a project stack ahead of another project solely because of terminal activity.

### Stack Interaction Flow

| Gesture | Action |
|---------|--------|
| Single tap on collapsed stack | Focus representative terminal's project; select that tab; bring project to focused pane |
| Single tap on expanded card | Focus that terminal's project; select that specific tab; bring project to focused pane |
| Hover / keyboard focus enter | Expand the project stack and slide additional visible terminals into view |
| Hover / keyboard focus exit | Collapse the project stack after a short grace period |
| Double tap | Open the selected rail terminal in spotlight overlay |
| Context menu | Hide Terminal, Rename Terminal, Restart Terminal |
| Inline rename | Replace title with focused `TextField`; Enter commits (trimmed); Escape cancels |

### Hide/Unhide Flow

1. User hides terminal via context menu → terminal removed from visible project stack and board.
2. Terminal process remains alive (not terminated).
3. Hidden terminal tracked in `[String: Set<UUID>]` dictionary keyed by project path, per-vibespace.
4. Hidden terminals section appears at bottom of rail with disclosure group.
5. Unhide (click chip or "Show All") → terminal restored to visible project stack and board without restarting session.

## API / Command Contracts

### Card Sizing Formulas

**Vertical rail (left/right position):**
- Layout: `LazyVStack` inside vertical `ScrollView`.
- Collapsed project stack height: `availableHeight / visibleProjectCount`, minimum 120pt.
- Card width: full rail width.

**Horizontal rail (top/bottom position):**
- Layout: `LazyHStack` inside horizontal `ScrollView`.
- Collapsed project stack width: `availableWidth / visibleProjectCount`, minimum 220pt.
- Card height: rail height minus outer padding, minimum 120pt.

**Spacing:** outer padding 12pt, inter-card spacing 8pt.

Expanded cards reuse the same base card size as the collapsed primary card. Expansion claims additional inline slots inside the scroll container instead of shrinking every other project stack during hover.

### Project Stack Anatomy

| Element | Details |
|---------|---------|
| Primary card | Representative terminal preview using `TerminalSessionHostView` in compact density |
| Peek layers | Offset card backs indicating additional visible terminals exist in the project |
| Project identity | Project color bar / accent plus project shortcut badge when configured |
| Primary title | Representative terminal title |
| Activity indicator | Animated indicator when any visible terminal in the stack is active |
| Count affordance | Visible-terminal count when project has more than one visible rail terminal |
| Expanded cards | Same anatomy as primary card but one per additional visible terminal |

### Rail Position Configuration

| Position | Split Axis | Rail Placement | Min Rail | Max Rail | Min Content | Card Scroll |
|----------|-----------|---------------|----------|----------|-------------|-------------|
| Left (default) | Vertical | Leading (primary) | 150pt | — | 0pt | Vertical |
| Right | Vertical | Trailing (`primaryAtEnd`) | 150pt | — | 0pt | Vertical |
| Top | Horizontal | Top (primary) | 80pt | 420pt | 120pt | Horizontal |
| Bottom | Horizontal | Bottom (`primaryAtEnd`) | 80pt | 420pt | 120pt | Horizontal |

Each position stores its own independent rail size via `vibespaceView.railSizeBinding(for:)`. Switching positions preserves previously set sizes.

**Single-project optimization:** When `activeVibeSpaceProjects.count <= 1`, the rail split is omitted entirely. Only `detailedContentPane` renders.

### Expansion Behavior

- Collapsed state shows one project stack per project.
- Hover or keyboard focus expands only the targeted project stack.
- Expansion animates along the rail axis so additional visible terminals slide out from behind the primary card.
- Collapse occurs when neither hover nor keyboard focus remains inside the stack, after a short grace period to avoid flicker.
- Manual hidden terminals never participate in hover expansion.

### Hidden Terminals Section

- Disclosure group header: "Hidden Terminals" label, count badge (capsule), "Show All" button.
- Chips per hidden terminal: eye icon (project color tint), tab title, project title.
- Chip layout: `HStack` (horizontal rail) or `VStack` (vertical rail).
- Chip context menu: "Show in Rail", "Restart Terminal", "Close Terminal".
- Separated from visible cards by a `Divider`.

### Empty Rail States

| Condition | Message | Action |
|-----------|---------|--------|
| No projects | "No Projects in VibeSpace" | "Add Project(s)" button |
| All terminals hidden | "All Rail Terminals Hidden" | Directs to hidden terminals section |
| Default | "No Rail Terminals" | Explains only focused project has visible terminals |

## State Management

### Activity State Model

```
TerminalSession (data received)
  → TerminalTabActivityState (per-tab, threshold + suppression)
    → TerminalTabActivitySummary (any-tab-active aggregation)
      → Rail card indicator
      → Pane header indicator
      → Board tile header indicator
      → Content viewer tab indicator
```

Suppression windows prevent false positives during:
- Session startup (brief window after shell launch).
- Terminal resize events.

### Hidden Terminals State

- Storage: `[String: Set<UUID>]` keyed by project path, per-vibespace.
- Hide: add tab UUID to set → triggers rail re-render + board sync (tile removed).
- Unhide: remove tab UUID from set → triggers rail re-render + board sync (tile restored).
- "Show All": clear all sets → unhide everything.

### Expansion State

- Storage: transient UI state keyed by project path (`expandedProjectPath` or equivalent set when keyboard focus support requires more than one).
- Input sources:
  - pointer hover enter/exit
  - keyboard focus enter/exit
- Expansion MUST NOT mutate project focus or terminal session ownership on its own.
- Expanded stacks reuse the same live session previews already available to the rail; no terminal restart is allowed during stack promotion or collapse.

## Dependencies

- `TerminalViewModel` — tab state and session lifecycle per project
- `TerminalViewModel.activeTabIDPublisher` or equivalent selection source — representative-terminal fallback ordering
- `TerminalSessionHostView` — compact terminal preview rendering
- `TerminalFocusCoordinator` — focus routing on card tap
- `NativeSplitView` — rail/content split container
- `TerminalSpotlightCoordinator` — spotlight open on double-tap

## Platform Considerations

- Rail uses `NativeSplitView` (AppKit `NSSplitView` bridge) for resizable split between rail and content.
- Compact display density uses smaller rail terminal font size for preview rendering.
- Terminal previews are non-interactive (`allowsHitTesting(false)`) to prevent accidental input.
- Hover expansion MUST have a keyboard-focus equivalent because pure hover behavior is insufficient on its own.

## Performance Constraints

- Activity indicator appears within 100ms of data threshold.
- Activity indicator clears within 100ms of idle threshold.
- Representative-terminal promotion must not restart or recreate the underlying terminal session.
- Hover expansion/collapse should animate without blocking scrolling or project focus interactions.
- Hide/unhide operations complete within 100ms.
- Hidden terminals must not leak processes.
- Rail cards must be keyboard-navigable.
