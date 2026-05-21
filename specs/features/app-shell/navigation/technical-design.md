# Navigation — Technical Design

## Overview

The navigation system manages the single-window app shell layout, side menu rail, sidebar tabs, navigation surface priority resolution, canvas mode switching, and the detailed view's NativeSplitView structure. It coordinates which surface is visible at any time and how the project rail, focused project pane, and editor/content viewer are composed.

## Architecture

### Main Window Structure

Single-window `HStack` layout:

1. Side menu rail (52pt wide) — docked left or right edge
2. Split view — optional sidebar panel (file explorer / git) + main content area

Sidebar visibility requires all of: vibespace active, no overlay surface presented, and home screen not showing. Sidebar width is resizable (min 180pt), persisted per session.

When project rail position is `right` in detailed canvas mode, the side menu rail is forced to the left regardless of dock preference.

### Startup Installation Guard

Before the normal shell bootstraps, `AppDelegate.applicationDidFinishLaunching` invokes `AppInstallationGuard.handleLaunchIfNeeded()`. This early gate lets launch-time relocation complete before services, observers, and vibespace restoration begin.

The guard only prompts when the running bundle is in a transient user location such as a mounted DMG, `~/Downloads`, or macOS temporary folders. Launches from `/Applications`, `~/Applications`, and developer checkouts continue without interruption.

### Side Menu Rail

Three groups separated by spacers:

| Group | Items | Icons |
|-------|-------|-------|
| Top | Home | `house.fill` |
| Middle | Files, Git, Sessions, VibeSpace Settings | `folder`, `arrow.triangle.branch`, `square.stack.3d.up`, `slider.horizontal.3` |
| Bottom | CrispyVibes Settings, Account | `gearshape`, `person.crop.circle` |

- Files / Git disabled when no projects exist
- VibeSpace Settings disabled when no vibespace active
- Tapping Files / Git when already active toggles sidebar closed
- Active button shows rounded-rectangle highlight with accent-colored border

### Navigation Surface Priority

Main content area resolves one view at a time, highest priority wins:

| Priority | Surface | Condition |
|----------|---------|-----------|
| 1 | VibeSpace Settings | VibeSpace settings active for a vibespace ID |
| 2 | App Settings | App settings category active |
| 3 | Home / Empty State | No vibespaces or home flag set |
| 4 | Project Canvas | Default when vibespace active |

Presenting a higher-priority surface auto-dismisses lower ones.

Shelf is not a separate navigation surface. It is rendered inside the Files sidebar when pinned files exist.

### Canvas Modes

Per-vibespace persisted `VibeSpaceCanvasMode`:

| Mode | Description |
|------|-------------|
| `detailed` | Project rail + editor/content area + terminal panes |
| `terminalOnly` | Grid of terminal tiles, no editor or project rail |

Toggle via toolbar button. Icon shows the target mode (the mode you'd switch to). Switching dismisses active terminal spotlight or link preview overlay.

## Data Flow

### Detailed View Layout (NativeSplitView)

The detailed canvas (`VibeSpaceCanvasSurfaceView`) uses nested `NativeSplitView` containers layered in a `ZStack` alongside Terminal Board — both kept alive once activated, toggled via opacity and hit-testing.

**Single-project vibespaces:** Skip outer split, render only inner content pane. Project rail hidden.

**Multi-project vibespaces:**

```
Outer NativeSplitView (axis depends on rail position)
├── Stacked Project Rail
└── Inner NativeSplitView (horizontal split)
    ├── Editor / Content Viewer (secondary, min 200pt)
    └── Focused Project Terminal Tray (primaryAtEnd, persisted height, collapsible)
```

### Rail Position Geometry

| Position | Outer Split Axis | Rail Placement | Min Rail | Max Rail | Min Content |
|----------|-----------------|----------------|----------|----------|-------------|
| Left | Vertical | Leading (primary) | 150pt | — | 0pt |
| Right | Vertical | Trailing (`primaryAtEnd`) | 150pt | — | 0pt |
| Top | Horizontal | Top (primary) | 80pt | 420pt | 120pt |
| Bottom | Horizontal | Bottom (`primaryAtEnd`) | 80pt | 420pt | 120pt |

Each position stores independent rail size via `vibespaceView.railSizeBinding(for:)`.

### Stacked Project Rail

`VibeSpaceStackedProjectRailView` — scrolling list of project-local terminal stacks driven by `StackedRailTerminalStore` (subscribes to each project's `TerminalViewModel.tabsPublisher`, maintains `tabsByProjectPath` dictionary).

**Project stack contents:**
- One representative terminal card per non-focused project
- Collapsed peek layers indicating additional visible terminals exist for that project
- Representative terminal chosen by live activity first, then per-project recency
- Activity indicator and project color treatment when any visible terminal in the project stack is active
- Live terminal preview via `TerminalSessionHostView` (compact density, non-interactive)

**Card sizing:**
- Vertical rail (left/right): `LazyVStack`, height = available ÷ visible projects (min 120pt), full width
- Horizontal rail (top/bottom): `LazyHStack`, width = available ÷ visible projects (min 220pt), height fills rail minus padding (min 120pt)
- Outer padding: 12pt, inter-card spacing: 8pt

**Card interactions:**
- Single tap on collapsed stack → focus project, select representative terminal
- Single tap on expanded card → focus project, select that terminal
- Hover / keyboard focus → expand stack to reveal additional visible terminals for that project
- Double tap → terminal spotlight overlay
- Context menu → Hide Terminal, Rename Terminal, Restart Terminal
- Inline rename → text field on Enter commit, Escape cancel

### Hidden Terminals

Tracked per-vibespace in `[String: Set<UUID>]` keyed by project path. Collapsible section at rail bottom with disclosure group, count badge, "Show All" button, and per-terminal chips with eye icon. Manual hidden terminals are excluded from collapsed stack previews and from hover-expanded project stacks.

### Focused Project Terminal Tray

`FocusedProjectView` renders the detailed mode bottom terminal tray:
- 2pt color bar at top (project color tag, omitted if none)
- `TerminalView` with `embedded` header layout
- Double-click session → terminal spotlight
- Exactly one visible terminal session at a time (the active project terminal tab)
- Tray-local split presentation is not supported
- Collapse / restore control adjusts the tray height without terminating sessions
- Dragging the visible tray terminal into the main content viewer opens a `.terminal(projectID, tabID)` tab for the same live session
- After a terminal is moved into the main content viewer, the tray advances to the next available project terminal when one exists
- Close action → removes project from vibespace

The detailed bottom tray is not a general docking surface. In detailed mode, the content viewer remains the only true split/dock surface for files, browser tabs, ACP panes, and docked terminal tabs.

### Modal Sheets

Two mutually exclusive modal sheets:
- Clone Repository (vibespace context)
- VibeSpace Creation (home context)

## State Management

- `VibeSpaceCanvasMode` persisted per vibespace
- `ProjectRailPosition` persisted per vibespace with independent size per position
- Sidebar tab selection and width persisted per session
- Navigation surface priority resolved reactively from shell state flags
- Side menu rail highlight derived from current surface state

### Single-Instance Enforcement

Second instance detects primary (lowest PID), forwards opened URLs via `DistributedNotificationCenter`, then terminates. Primary instance processes forwarded URLs as external open requests.

### Shell Script File Open

Files opened via Finder with shell extensions (`.sh`, `.zsh`, `.bash`, `.fish`, `.command`) set `preferTerminal = true` → terminal-only canvas mode. Mixed file types do not trigger this.

## Dependencies (frameworks, libraries)

- SwiftUI (`NativeSplitView` wrappers for `NSSplitView`)
- AppKit (`DistributedNotificationCenter` for single-instance)
- GhosttyKit (terminal preview rendering in rail cards)

## Platform Considerations

- macOS only — relies on `NSSplitView`, `NSWindow` title bar, `DistributedNotificationCenter`
- Minimum window size: 960×620

## Performance Constraints

- Both canvas modes kept alive in `ZStack` to avoid teardown/rebuild cost on toggle
- Rail terminal previews use compact density and `allowsHitTesting(false)` to reduce interaction overhead
- `StackedRailTerminalStore` uses Combine subscriptions to avoid polling

## Migration / Rollout Notes

- Canvas mode and rail position are per-vibespace; no global migration needed
- Single-instance behavior uses `DistributedNotificationCenter` — no IPC daemon required
