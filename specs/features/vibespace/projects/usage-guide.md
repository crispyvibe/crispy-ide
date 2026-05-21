---
title: "VibeSpace Projects"
feature: "F021"
domain: "vibespace"
audience: "user"
version: "1.0"
sidebar:
  label: "Projects"
  order: 2
---

# VibeSpace Projects

## Overview

VibeSpace Projects covers project creation, focus management, add/remove operations, terminal hydration, stacked card previews, and layout persistence within a vibespace. Projects are the fundamental unit of work — each represents a directory with its own terminal sessions, file explorer state, and editor context.

## Getting Started

1. Open or create a vibespace in Crispy.
2. Click **Add Project** in the toolbar or Dashboard to add project folders.
3. Select one or more directories in the folder picker.
4. Projects appear in the project rail; the last added project becomes focused.
5. Each project gets its own terminal session, file tree, and editor state.

## Workflows

### Adding Projects

1. Click **Add Project** from the toolbar, Dashboard, or project rail CTA.
2. The folder picker supports multi-select — choose one or more directories.
3. One project is created per selected folder.
4. Duplicates are ignored (matched by normalized path).
5. If a selected folder is already open, it becomes focused instead of duplicated.
6. The last processed project becomes the focused project with an active terminal ensured.

### Focusing Projects

1. Click a stacked project card in the rail to focus that project.
2. Terminal availability is ensured for the newly focused project.
3. Keyboard focus moves to the focused project's active terminal.
4. Use **⌘⌥]** / **⌘⌥[** to cycle focus between projects.
5. Use **⌘1–⌘9** to focus projects by their assigned shortcut slot.

### Understanding Hydration Order

1. When a vibespace opens, the focused project's terminal hydrates first.
2. Non-focused project terminals hydrate progressively in background order.
3. This ensures the focused project is immediately interactive.
4. Rail previews become live as background hydration completes.
5. Startup defaults are applied once per project per session.

### Viewing Stacked Project Cards

1. Non-focused projects appear as stacked cards in the project rail.
2. Each card shows one representative terminal (chosen by activity, then recency).
3. Additional terminals are grouped behind the representative as a collapsed stack.
4. Cards with terminal activity show an inline activity indicator.
5. Cards without a terminal session show "Loading Terminal" until hydration completes.
6. Double-click a card to open a Terminal Spotlight overlay without changing focus.

### Closing Projects

1. Click the close icon in the focused project's header to remove it.
2. Focus falls back to the last remaining project.
3. Closing the last project returns to the empty state UI.
4. The empty state shows an "Add Project(s)" call to action.

### Restarting a Project

1. With a project focused, trigger **Restart Project** from the project header.
2. This restarts all pane workers:
   - Explorer worker restarts (file tree reloads).
   - Editor worker restarts and reloads the current file if one is open.
   - Terminal pane restarts and recreates an active tab.

### Adjusting Layout

1. In Detailed mode, drag the splitter between editor and terminal to adjust proportions.
2. Layout fractions are stored per project (keyed by normalized path).
3. Fractions persist across app restarts.
4. When a project is reopened, its saved layout is restored.

### Single-Project Rail Behavior

1. When exactly one project is open, the rail shows an "Add Project(s)" call to action.
2. No passive "No Stacked Projects" placeholder is shown.
3. This encourages building multi-project workspaces.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |
| Focus Project 1–9 | ⌘1–⌘9 |

## Settings

- **Startup Defaults** (VibeSpace Settings): Terminal count and per-terminal startup profiles applied when a project first receives focus.
- **Per-Folder Overrides** (VibeSpace Settings → Projects): Custom startup commands/presets for specific project folders that supersede vibespace defaults.
- **Shortcut Assignments** (VibeSpace Settings → Shortcuts): Map ⌘1–⌘9 to specific project folders for deterministic focus switching.
- **Project Color Tags** (VibeSpace Settings → Projects): Assign colors to project roots for visual identification.

## Tips

- Startup defaults are applied once per project per session — switching focus back to a project doesn't re-run startup.
- Non-focused projects still hydrate terminal sessions in background order for live rail previews, even though startup profiles defer until first focus.
- Each startup profile can launch either a preset or a custom command for its terminal slot.
- Shortcut slots are unique across folders — assigning the same slot to a different folder reassigns ownership.
- The representative terminal on stacked cards uses activity-first ordering: if a terminal has recent output, it's shown first.
- Terminal Spotlight from a stacked card doesn't change the focused project, file preview, or main terminal selection.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Project not appearing after add | Check that the folder exists and isn't already open (duplicates are silently ignored). |
| Terminal not starting for new project | Hydration runs asynchronously. Wait a moment — the "Loading Terminal" placeholder should resolve. |
| Layout not restoring | Layout is keyed by normalized path. If you moved the project folder, the layout association is lost. |
| Startup command not running | Check VibeSpace Settings for the startup configuration. Ensure the vibespace config is trusted (not tampered). |
| Focus shortcut not working | Verify the shortcut assignment in VibeSpace Settings → Shortcuts. Ensure no conflict with other shortcuts. |
| Stacked card shows no terminal | The project's terminal hasn't hydrated yet. It will show "Loading Terminal" until ready. |
| Close button missing | The close icon is in the focused project's header. Stacked cards don't have a direct close — focus the project first. |
