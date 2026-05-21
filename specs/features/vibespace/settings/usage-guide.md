---
title: "VibeSpace Settings"
feature: F022
domain: vibespace
audience: user
version: "1.0"
sidebar:
  label: Settings
  order: 3
---

# F022 — VibeSpace Settings: Usage Guide

VibeSpace Settings lets you configure startup behavior, terminal defaults, project shortcuts, and source control for your VibeSpace. This guide walks through each settings category.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings you work with together.

---

## Opening VibeSpace Settings

Click **VibeSpace Settings** from the toolbar or Dashboard. A dedicated settings view opens with a split layout: categories on the left, detail content on the right.

There are two categories:

- **VibeSpace Settings** — vibespace name, startup defaults, maintenance, and source control.
- **Projects** — per-project color, shell, shortcuts, and startup overrides.

Click **Done** to close settings. All changes are saved immediately as you make them.

---

## VibeSpace Settings Category

### VibeSpace Name

Edit the vibespace name in the text field and click **Save** (or press Enter). The window title updates to match. The save button is disabled if the name is empty or unchanged.

### Startup Configuration

Control what happens when the vibespace opens:

- **Startup terminals** — set how many terminal tabs open per project (1–8).
- **Startup profiles** — for each terminal slot, choose a startup mode:
  - **None** — terminal opens with no command.
  - **Preset** — select a CLI tool preset (e.g., Kiro CLI, Claude Code). If the preset supports it, you can choose between Standard and Full Trust execution modes. Standard mode runs the tool with safety restrictions. Full Trust gives the tool permission to make changes without asking.
  - **Command** — enter a custom shell command to run on open.
- **Focus terminal on project switch** — when enabled, switching projects automatically focuses the terminal pane.

> **Example:** A typical startup config uses 2 terminals per project — the first runs `npm start`, the second is a plain shell for ad-hoc commands.

Startup defaults apply once per project per session. The focused project starts first; remaining projects defer startup until they receive focus to keep things responsive.

### VibeSpace Maintenance

Click **Reindex Project Folders** to re-scan all project paths. Folders that have reappeared are recovered as live projects; folders still missing remain as unresolved paths.

### Source Control

Configure how CrispyVibes discovers Git repositories in your projects:

| Setting | Description | Default |
|---------|-------------|---------|
| Ignored folders | Comma-separated folder names to skip during scanning | Common build/cache directories |
| Scan depth | How many directory levels deep to search | 8 |
| Max discovered repos | Upper limit on repositories to discover | 64 |
| Rendered repos | How many repositories to display in the sidebar | 12 |

---

## Projects Category

The Projects category shows a list of all project folders in the vibespace. Select a project to configure it.

### Adding Projects from Settings

Click **Add Project Folder** in the toolbar to open a folder picker and add new projects.

### Per-Project Settings

Select a project in the list to see its detail card:

- **Color** — pick a project color using the color picker, or click **Clear** to remove the custom color and fall back to the default accent. See the [Color Coding guide](../color-coding/usage-guide.md) for details.
- **Shell** — choose a terminal shell for this project, or leave it on "Use VibeSpace Default" to inherit the vibespace setting.
- **Shortcut** — assign a keyboard shortcut (⌘1–⌘9) to quickly switch to this project. Duplicate slots are resolved automatically.
- **Startup behavior** — choose "Use VibeSpace Default" to inherit vibespace startup settings, or "Custom Override" to define a project-specific terminal count and startup profiles.

### Reordering and Removing

- Drag rows to reorder projects. Shortcuts reindex to match the new order.
- Click the **Remove** button (trash icon) to remove a project from the vibespace.

---

## Related Guides

- [VibeSpace Lifecycle](../lifecycle/usage-guide.md) — creating, opening, closing, and deleting vibespaces
- [VibeSpace Projects](../projects/usage-guide.md) — adding, removing, and navigating projects
- [Project Color Coding](../color-coding/usage-guide.md) — customizing project colors across the UI
