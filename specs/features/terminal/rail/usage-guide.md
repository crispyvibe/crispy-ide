---
title: "Terminal Rail"
feature: "F004"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Rail"
  order: 4
---

# Terminal Rail

## Overview

The Terminal Rail shows compact terminal previews for non-focused projects in Detailed canvas mode. Terminals are grouped by project into collapsible stacks, with the most active terminal promoted to the top. Hover or keyboard focus expands a stack to reveal all visible terminals for that project, and a context menu provides hide/unhide controls for managing which terminals appear in the rail.

## Getting Started

1. Open a vibespace with multiple projects in Detailed mode (⌘D).
2. The focused project's terminal appears in the bottom tray.
3. Non-focused projects appear in the stacked rail (left or right side, depending on rail position setting).
4. Each project shows one representative terminal in its collapsed stack.
5. Hover over a project stack to expand and see all its visible terminals.

## Workflows

### Viewing the Rail

1. In Detailed mode, non-focused projects render as compact terminal stacks in the rail.
2. Each project stack shows:
   - Project identity (name and color)
   - Representative terminal title
   - Activity state indicator
   - Visible-terminal count badge (when more than one terminal is available)
3. The rail follows vibespace project order — it does not reshuffle based on terminal activity.

### Expanding a Project Stack

1. Hover the pointer over a collapsed project stack.
2. The remaining visible terminals for that project slide out in ranked order.
3. Terminals are ranked by:
   - Active terminals (live output) rank first, most recently active on top.
   - Among idle terminals, the most recently selected terminal ranks first.
   - Fallback: the project's active tab, then original tab order.
4. Move the pointer away — the stack collapses back after a short grace period (prevents flicker).
5. Keyboard focus also expands the stack (accessible equivalent of hover).

### Focusing a Terminal from the Rail

1. Expand a project stack (hover or keyboard focus).
2. Click the terminal you want to focus.
3. The project becomes the focused project, and the selected terminal becomes active.

### Activity Indicators

Terminal activity is surfaced at multiple levels:

1. **Tab-level**: When a terminal receives meaningful output past the activity threshold, an animated sweep indicator appears on the tab.
2. **Project stack**: When any visible terminal in a project has activity, the project's rail card shows the project color on the stack icon with an inline activity indicator.
3. **Content viewer tab**: When any terminal in a project is active, the content viewer tab for that project shows the same inline activity indicator.
4. **Idle clearing**: Activity indicators clear after ~1 second of no significant terminal data.
5. **Suppression**: Startup output and resize events do not trigger activity indicators.

### Hiding a Terminal from the Rail

1. Right-click a terminal in the expanded project stack.
2. Select "Hide" from the context menu.
3. The terminal is removed from the visible project stack and the board.
4. The terminal process remains alive (not terminated).
5. The hidden terminal appears in a "Hidden Terminals" section at the bottom of the rail.

### Unhiding a Terminal

1. Find the "Hidden Terminals" section at the bottom of the rail (appears when terminals are hidden).
2. Right-click the hidden terminal entry.
3. Select "Unhide" from the context menu.
4. The terminal is restored to its project stack and the board.
5. The session resumes display without restarting.

### Opening Spotlight from Rail

1. Double-click a terminal in the expanded rail stack.
2. The terminal opens in a spotlight overlay for focused viewing.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Focus Terminal Down | ⌘⌥↓ |
| Focus Terminal Up | ⌘⌥↑ |
| Open Detailed View | ⌘D |
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |

Hover-only behavior has a keyboard-reachable equivalent: use tab/arrow keys to move focus into a project stack to expand it.

## Settings

| Setting | Location | Effect |
|---------|----------|--------|
| Rail terminal text size | Settings > Appearance | Controls the compact density font size for rail terminal previews (clamped to supported range) |
| Rail position | VibeSpace Settings | Controls whether the rail appears on the left, right, top, or bottom |

### Compact Density Font

Rail terminals use compact density sizing. The font size follows the `railTerminalCompactFontSize` app preference. Changes to this setting apply live — no restart needed.

## Tips

- **Project order is stable**: Rail stacks follow vibespace project order and never reshuffle based on activity. This keeps the layout predictable.
- **Representative terminal**: The top terminal in a collapsed stack is always the most relevant — either the one with the most recent activity, or the most recently selected terminal for that project.
- **Hidden terminals stay alive**: Hiding a terminal only removes it from the visual rail and board. The shell process continues running. Use this for background tasks you don't need to monitor.
- **Grace period on collapse**: When moving the pointer between terminals in an expanded stack, a short grace period prevents the stack from collapsing during pointer movement.
- **No split icon on rail**: Terminal splitting is managed from the board or terminal tab bar only — the rail card intentionally omits split controls to keep the compact presentation clean.
- **No temporary terminal icon on rail**: Temporary terminal creation is accessible from the board toolbar only.
- **Live font updates**: Changing the rail terminal text size in settings immediately reapplies the compact density font for the active rail preview.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Rail not visible | Ensure you're in Detailed mode (⌘D) with multiple projects in the vibespace |
| "No Rail Terminals" shown | Non-focused projects have no terminal tabs, or all terminals are hidden |
| "All Rail Terminals Hidden" shown | Use the hidden terminals section to unhide terminals |
| Activity indicator not appearing | The terminal may be in the startup suppression window (~0.9s) or resize suppression window (~0.35s) |
| Stack not expanding on hover | Ensure the pointer is over the project stack card. The grace period may delay collapse but expansion should be immediate. |
| Hidden terminal process died | Hiding preserves the process, but if the shell exits naturally the tab becomes inactive. Restart the tab to get a fresh session. |
