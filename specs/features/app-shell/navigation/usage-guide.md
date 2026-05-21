---
title: "App Navigation"
feature: "F014"
domain: "app-shell"
audience: "user"
version: "1.0"
sidebar:
  label: "Navigation"
  order: 1
---

# App Navigation

## Overview

App Navigation covers the core window management, canvas layout, sidebar tab system, title bar controls, project rail, view mode switching, and vibespace lifecycle within Crispy. It provides the structural shell that organizes projects, terminals, editors, and sidebars into a cohesive workspace.

## Getting Started

1. Launch Crispy — the main window opens with a minimum size of 960×620.
2. If no vibespace is active, the Dashboard appears with quick actions.
3. Create a vibespace or open an existing one to begin working.
4. Add projects via the **Add Project** button or toolbar action.
5. Use the side menu rail to switch between Files, Sessions, and Git sidebars.

## Workflows

### Creating a Vibespace

1. Click **Create VibeSpace** from the toolbar or Dashboard.
2. Select one or more project folders in the folder picker.
3. The new vibespace becomes active with selected folders as projects.
4. The focused project's terminal hydrates first; other projects hydrate progressively.

### Switching View Modes

1. Use the toolbar view mode picker or keyboard shortcuts to switch between:
   - **Detailed** (⌘D): Editor + terminal split with sidebar file navigation.
   - **Terminal Only** (⌘T): Grid-based terminal board layout.
2. Switching modes does not restart terminal sessions.
3. The selected mode persists per vibespace.

### Managing the Project Rail

1. The project rail shows stacked project cards alongside the focused project.
2. Click a stacked card to focus that project.
3. Double-click a stacked card to open a Terminal Spotlight overlay for that project.
4. Rail position (left, right, top, bottom) is configurable and persisted per vibespace.
5. Rail width/height is persisted independently for each position.
6. When only one project exists, the rail shows an "Add Project(s)" call to action.

### Working with the Focused Project

1. The focused project occupies the main canvas area.
2. In Detailed mode: project header, editor content above, terminal below.
3. If no file is active, the terminal takes the full canvas area.
4. Drag splitters between editor and terminal to adjust proportions.
5. Layout fractions persist per project path across restarts.
6. Collapse the terminal tray to give the editor full space (session stays alive).

### Using the Side Menu Rail

1. The side menu rail provides tabs: **Files**, **Sessions**, **Git**.
2. The rail can dock on the left or right edge.
3. Clicking a tab opens its paired sidebar content on the same edge.
4. The sidebar and rail position are independent of the project rail.

### Managing the Title Bar

1. The title bar shows the active vibespace name as the window title.
2. App actions: appearance toggle, App Settings (⌘,).
3. VibeSpace actions: view mode, Add Project, VibeSpace Settings, Close VibeSpace, Create VibeSpace.
4. VibeSpace actions are hidden when no vibespace is active.
5. Remote status control appears only when the vibespace has SSH-backed projects.

### Terminal Only Mode

1. Switch to Terminal Only mode (⌘T) for a grid-based terminal layout.
2. Each project gets its own terminal pane.
3. Selecting a pane doesn't reflow surrounding panes.
4. Orientation (vertical/horizontal) is user-selectable and persisted.
5. Use ⌃⇧← / ⌃⇧→ to cycle terminal focus across all project panes.
6. Opening a file from the explorer in this mode does not switch to Detailed view.

### Closing Projects

1. Click the close icon in the project header to remove the focused project.
2. Focus falls back to the last remaining project.
3. Closing the last project returns to the empty state UI.
4. Use **Restart Project** to restart all pane workers (explorer, editor, terminal) without removing the project.

### VibeSpace Settings

1. Click **VibeSpace Settings** from the toolbar or Dashboard.
2. A dedicated settings view opens with split navigation.
3. Categories: VibeSpace (general), Shortcuts, Projects.
4. Configure startup defaults, per-folder overrides, and shortcut assignments.
5. Shortcut slots (⌘1–⌘9) map to specific project folders for quick focus.

### Handling Unresolved Paths

1. If a project folder is unavailable (moved/deleted), it appears as an unresolved path.
2. From the Dashboard or VibeSpace Settings, you can:
   - **Remove**: Delete the missing path entry.
   - **Relink**: Choose a replacement folder.
3. Use **Reindex Project Folders** to reconcile availability.

### Checking for Updates

1. Automatic update checks run on launch when enabled (configurable interval).
2. Manual check: App menu → **Check for Updates…** (bypasses interval gating).
3. If an update is available, a prompt shows the target version with Download and Later options.
4. Configure update settings in App Settings → Updates.

### Developer Tools

1. Press **⌘⌥D** to open the Developer Tools view.
2. Export diagnostics for troubleshooting via the diagnostics export action.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Detailed View | ⌘D |
| Open Terminal Board | ⌘T |
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |
| Focus Project 1–9 | ⌘1–⌘9 |
| Focus Terminal Down | ⌘⌥↓ |
| Focus Terminal Up | ⌘⌥↑ |
| Board Navigate Left | ⌘⌥← |
| Board Navigate Right | ⌘⌥→ |
| Terminal Only Cycle Left | ⌃⇧← |
| Terminal Only Cycle Right | ⌃⇧→ |
| Open Settings | ⌘, |
| Open Developer Tools | ⌘⌥D |
| Increase Font Size | ⌘= |
| Decrease Font Size | ⌘- |
| Reset Font Size | ⌘0 |

## Settings

- **Rail Position**: Left, Right, Top, or Bottom — persisted per vibespace.
- **Side Menu Dock**: Left or Right — independent of project rail.
- **View Mode**: Detailed or Terminal Only — persisted per vibespace.
- **Terminal Only Orientation**: Vertical or Horizontal.
- **Startup Defaults**: Terminal count and per-terminal startup profiles per vibespace.
- **Per-Folder Overrides**: Custom startup commands/presets for specific project folders.
- **Shortcut Assignments**: Map ⌘1–⌘9 to specific project folders.
- **Automatic Updates**: Toggle and configure update feed URL.

## Tips

- The window title always reflects the active vibespace name — no picker control needed.
- Window dragging is restricted to the title bar and toolbar regions. Content areas (editor, terminal, rail) don't move the window.
- Stacked cards show a representative terminal chosen by activity-first, then recency-based ordering.
- Cards with terminal activity show an inline activity indicator that clears when idle.
- Cards without a terminal session show a "Loading Terminal" placeholder until hydration completes.
- Config files are HMAC-SHA256 signed. Tampered files load for display but disable startup commands until re-saved.
- Layout files (layout.json) are exempt from signing.
- The app detects transient install locations and offers to move to /Applications on first launch.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Empty state shown unexpectedly | No projects are open. Click "Add Project(s)" to add folders. |
| Rail position not saving | Ensure you're working within a vibespace. Rail position persists per vibespace. |
| Startup commands not running | Config file may be untrusted (modified outside app). Open VibeSpace Settings and re-save to restore trust. |
| Window won't move | Only the title bar and toolbar are draggable. Click and drag from those regions. |
| Shortcuts not working | Check App Settings → Shortcuts for conflicts. Some shortcuts are reserved for text editing when a text field is focused. |
| Update check fails | Verify network connectivity. Check that the update feed URL in settings is valid. |
| Project layout not restoring | Layout is keyed by normalized project path. If the path changed, layout resets. |
