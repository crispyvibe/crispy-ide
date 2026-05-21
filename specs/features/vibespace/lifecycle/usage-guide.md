---
title: "VibeSpace Lifecycle"
feature: F020
domain: vibespace
audience: user
version: "1.0"
sidebar:
  label: Lifecycle
  order: 1
---

# F020 — VibeSpace Lifecycle: Usage Guide

A VibeSpace is your vibespace in Crispy — it groups project folders, terminal sessions, and settings into a single context. This guide covers creating, opening, closing, removing, and deleting vibespaces.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings you work with together.

---

## Creating a VibeSpace

There are four ways to create a new vibespace. Each one replaces the currently active vibespace. You can also press **⌘⇧N** to start creating a new vibespace from anywhere.

### Folder Picker

1. Click **Create VibeSpace** from the toolbar or Dashboard.
2. Select one or more folders in the file picker.
   - A single folder → the vibespace is named after that folder.
   - Multiple folders → the vibespace is named "VibeSpace N" (auto-incremented).
3. Each selected folder becomes a project in the new vibespace.

### Creation Wizard

1. Open the creation wizard from the toolbar or Dashboard.
2. Enter a custom vibespace name.
3. Select folders to include as projects.
4. Optionally choose a CLI profile (a preset for AI coding tools like Kiro CLI or Claude Code) to apply as the initial startup profile.
5. Confirm to create the vibespace.

### External Open (Finder / Other Apps)

- Drag folders onto Crispy or open them via Finder.
- If a vibespace is already active, the folders are added to it as new projects.
- If no vibespace is active, a new vibespace is created automatically.

### Terminal Quick Start

- Click the **Terminal** button in the toolbar buttons at the bottom of the dashboard.
- A vibespace named "Terminal" is created with your home directory as the sole project, opening directly in terminal-only mode.

---

## Opening a VibeSpace

- On launch, CrispyVibes automatically restores the last active vibespace.
- Folders that still exist on disk load as live projects. Folders that have been moved or deleted appear as **unresolved paths** — you can relink or remove them (see below).
- The vibespace name appears in the macOS window title.

### Recent VibeSpaces

The Dashboard shows your most recent vibespaces. Click one to open it. The previous vibespace is closed and replaced.

---

## View Modes

A vibespace supports two canvas modes, switchable from the toolbar or keyboard:

- **Detailed** — full project view with file explorer, editor, and terminal panes.
- **Terminal Only** — each project gets its own terminal pane. You can switch the pane orientation between vertical and horizontal layout from the toolbar.

Switching modes does not restart any running terminal sessions. Your selected mode and orientation are saved per vibespace.

---

## Handling Unresolved Paths

If a project folder is missing when a vibespace opens, it appears as an unresolved path on the Dashboard.

- **Remove** — permanently removes the missing path from the vibespace.
- **Relink** — choose a replacement folder. The new folder takes the place of the missing one and loads as a live project.
- **Reindex Project Folders** — available in VibeSpace Settings. Re-scans all paths and recovers any folders that have reappeared.

---

## Closing a VibeSpace

Closing a vibespace tears down all project sessions and returns you to the home screen. The vibespace remains in your recent vibespaces list — you can reopen it anytime.

---

## Removing a VibeSpace

Removing a vibespace shuts down all sessions and removes it from the displayed vibespace list. If other vibespaces exist, CrispyVibes switches to the next available one.

---

## Deleting a VibeSpace

Deleting a vibespace permanently removes its configuration files from disk and clears it from your recent list. This cannot be undone.

---

## File Integrity & Trust

CrispyVibes signs vibespace and project configuration files to protect against tampering.

- If a config file is modified outside the app, CrispyVibes detects the change on next load.
- The vibespace still opens — you can see the name, projects, and colors — but **startup commands are disabled** for safety.
- A non-dismissable alert identifies the affected vibespace and explains that startup commands are paused.
- To restore full functionality, open **VibeSpace Settings**, review your configuration, and save. This re-signs the file and re-enables startup commands.

Layout files (pane positions, split ratios) are not signed and always load normally.

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Create new vibespace | ⌘⇧N |

---

## Related Guides

- [VibeSpace Projects](../projects/usage-guide.md) — adding, removing, and navigating projects
- [VibeSpace Settings](../settings/usage-guide.md) — startup behavior, terminal defaults, and source control
- [Project Color Coding](../color-coding/usage-guide.md) — customizing project colors across the UI
