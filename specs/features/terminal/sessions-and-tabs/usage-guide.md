---
title: "Terminal Sessions & Tabs"
feature: "F001"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Sessions & Tabs"
  order: 1
---

# Terminal Sessions & Tabs

## Overview

Terminal Sessions & Tabs manages the full lifecycle of terminal sessions within Crispy: creating tabs, resolving shells, restoring sessions across app launches, and providing interactive links, clipboard commands, and shortcut commands. Each project in a vibespace gets its own set of terminal tabs that persist and restore automatically.

## Getting Started

1. Open a vibespace with at least one project.
2. The terminal pane appears below the editor area (Detailed mode) or as the full canvas (Terminal Board mode).
3. A terminal tab is automatically created at the project root directory on first launch.
4. Click the `+` button in the terminal tab bar to create additional tabs.
5. Type commands directly — the terminal starts an interactive shell in the project directory.

## Workflows

### Creating a New Tab

1. Click the `+` button in the terminal tab bar.
2. The new tab opens in the current active tab's working directory (or the project root if no tab exists).
3. Keyboard focus moves to the new terminal session automatically.

### Opening a Directory in Terminal

1. Right-click a folder in the file explorer.
2. Select "Open in Terminal".
3. If a tab already exists for that directory, it is selected (no duplicate created).
4. If no tab exists, a new tab is created for that directory.

### Closing a Tab

1. Hover over the tab chip and click the close (×) button.
2. The shell process is terminated.
3. The active selection falls back to the last remaining tab.

### Selecting a Tab

1. Click any tab chip in the terminal tab bar.
2. If the tab's session was not yet started (lazy restore), it starts on selection.
3. Keyboard focus moves to the selected terminal.

### Restarting a Tab

1. Right-click the tab chip.
2. Select "Restart" from the context menu.
3. The existing session is terminated and a fresh session is created with the same working directory and tmux session name (if applicable).

### Renaming a Tab

1. Right-click the tab chip.
2. Select "Rename" from the context menu.
3. Enter the new name. Leave empty to revert to the automatic title.

### Restarting the Entire Terminal Pane

1. Use the terminal pane restart action (available in the pane header context menu).
2. All sessions are terminated, state is cleared, and a fresh tab is created at the project root.

### Copy and Paste

1. Select text in the terminal using the mouse.
2. Use the app menu or notification-based commands to copy/paste (routed to the active tab session).

### Using Shortcut Commands

1. Open the shortcuts panel from the terminal tab bar dropdown.
2. Both vibespace-scoped and project-scoped shortcuts appear.
3. Click a shortcut to execute it:
   - **Current Terminal**: Sends the command to the focused terminal (creates a tab if none exists).
   - **New Permanent Terminal**: Creates a dedicated named tab and sends the command.
   - **New Temporary Terminal**: Opens a temporary spotlight terminal for the command.
4. Select "Manage Shortcuts…" to open vibespace settings for editing shortcuts.

### Interactive Links in Terminal Output

1. Hover over a URL, file path, or directory path in terminal output — a subtle highlight appears.
2. **Plain click**: Shows a contextual popup with actions:
   - Web URLs: "Open in Crispy", "Open in Default Browser", "Copy Link"
   - File paths: "Open", "Open in Shelf", "Open in System", "Reveal in Finder", "Copy Path"
   - Directories: "Open", "Open in System", "Copy Path"
3. **Cmd-click**: Opens the target directly (web URL → in-app browser; file → spotlight preview; directory → Finder).

### File Drops onto Terminal

1. Drag one or more files from Finder or the file explorer onto the terminal view.
2. Shell-escaped paths are inserted at the cursor position.
3. Paths within the terminal's current working directory use relative paths; others use absolute paths.
4. Multiple files are space-separated with a trailing space appended.
5. Keyboard focus remains on the terminal that accepted the drop.

### Session Restore

Terminal tabs are automatically persisted when you close a vibespace and restored when you reopen it:
- Only the active tab's session starts immediately on restore.
- Other tabs remain lazy — their shell processes start on first selection.
- If no valid state is available, a single tab at the project root is created as fallback.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Terminal Board | ⌘T |
| Open Detailed View | ⌘D |
| Focus Terminal Down | ⌘⌥↓ |
| Focus Terminal Up | ⌘⌥↑ |
| Focus Left (Board) | ⌘⌥← |
| Focus Right (Board) | ⌘⌥→ |
| Focus Project 1–9 | ⌘1 through ⌘9 |
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |

Copy/Paste in terminal is handled via the app Edit menu (standard ⌘C / ⌘V are routed to the terminal when it has focus).

## Settings

| Setting | Location | Effect |
|---------|----------|--------|
| Default Shell | Settings > Terminal | Sets the app-level shell preference (fallback in resolution chain) |
| Project Shell Override | VibeSpace Settings > Project | Overrides shell for a specific project |
| VibeSpace Default Shell | VibeSpace Settings | Overrides shell for all projects in the vibespace |
| Rail terminal text size | Settings > Appearance | Controls compact density font size for rail previews |
| Terminal Insight | Settings > Experimental | Enables last-command overlay (auto-dismisses after 4s) |

### Shell Resolution Order

The shell executable is resolved by precedence:
1. Project override
2. VibeSpace default
3. App default (Settings > Terminal)
4. Process `SHELL` environment variable
5. `/bin/zsh` (hardcoded fallback)

Unavailable candidates are skipped automatically. Shell is always launched with `-l -i` (login interactive).

## Tips

- **De-duplication**: Opening a directory that already has a tab just selects the existing tab — no duplicates.
- **Git branch badge**: Terminal board tile headers show the current git branch for the tab's working directory. It updates automatically when you `cd` into a different repo.
- **Activity indicators**: Tabs with active output show an animated sweep indicator. The terminal pane header shows an inline activity indicator when any tab is active.
- **Compose bar**: When visible, the compose bar provides a text input field for composing commands before sending them to the active session.
- **Tab reordering**: Drag tabs in the tab bar to reorder them.
- **Split mode**: In single-active-tab presentation, toggle split mode to view two terminal sessions side by side (requires 2+ tabs).
- **Density switching**: The terminal automatically uses regular density in the focused pane and compact density in stacked rail cards.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No Terminal Tabs" placeholder shown | Click `+` to create a tab, or ensure a project is open in the vibespace |
| "Terminal Unavailable" shown | The session object was lost — restart the tab or pane |
| Shell not found / wrong shell | Check Settings > Terminal for the default shell; verify the executable exists at the configured path |
| Tab not restoring on relaunch | Ensure the vibespace was saved properly; check that the directory still exists |
| Interactive links not working | Ensure the terminal host supports interactive targeting (Ghostty and SwiftTerm both support it) |
| Commands queued but not executing | The session may not have reached interactive readiness yet — wait for the shell prompt or check startup command timing |
