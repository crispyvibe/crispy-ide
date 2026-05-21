---
title: "Project Color Coding"
feature: F023
domain: vibespace
audience: user
version: "1.0"
sidebar:
  label: Color Coding
  order: 4
---

# F023 — Project Color Coding: Usage Guide

Every project in a VibeSpace has a color identity. Colors help you visually distinguish projects across the interface — in the project rail, terminal tiles, sidebar, editor tabs, and more. This guide covers how colors are assigned and how to customize them.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings you work with together.

---

## Auto-Assigned Colors

When you create a vibespace or add a folder, CrispyVibes automatically assigns a color to each new project. The color is derived from the folder path, so the same folder always gets the same initial color. Auto-assigned colors are chosen to be vivid enough to tell apart but comfortable in both light and dark themes.

---

## Where Colors Appear

Your project color shows up in 13 places across the interface:

**Project Rail**
- Focused project header bar
- Stacked project rail cards (pill indicator, shortcut badge, card border)

**Terminal**
- Terminal board tile cards (icon, git badge, active border and shadow)
- Terminal board minimized tab bar
- Terminal spotlight overlay (header icon, tab navigation dots)

**Sidebar**
- Sidebar files pane (project section header)
- Sidebar source control pane (repository section header)

**Settings & Other**
- VibeSpace Settings project list and per-project detail
- Content viewer tab strip
- VibeCast message dots and target indicators — VibeCast message dots show which terminal a command was sent to

When no custom color is set, the app's theme accent color is used as the fallback.

---

## Choosing a Custom Color

1. Click the **color swatch** on the focused project header, or go to **VibeSpace Settings** → **Projects** and select a project.
2. Use the **color picker** to choose a color.
3. For more options, click **More** to open an expanded picker popover.

The selected color immediately applies to the project title, folder icon, frame accent, and all other color locations. Your choice is saved to the vibespace and persists across sessions.

---

## Clearing a Color

To remove a custom color and return to default styling:

1. Open the color picker for the project.
2. Click **Clear Color**.

The custom color is removed. The project falls back to the theme accent color until a new color is assigned (for example, on the next vibespace load, the auto-assignment runs again for projects without a color).

---

## Related Guides

- [VibeSpace Lifecycle](../lifecycle/usage-guide.md) — creating, opening, closing, and deleting vibespaces
- [VibeSpace Projects](../projects/usage-guide.md) — adding, removing, and navigating projects
- [VibeSpace Settings](../settings/usage-guide.md) — startup behavior, terminal defaults, and source control
