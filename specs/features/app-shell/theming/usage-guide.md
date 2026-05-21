---
title: "Theming"
feature: F015
domain: app-shell
audience: "user"
version: "1.0"
sidebar:
  label: Theming
  order: 2
---

# Theming

## Overview

Crispy's theme system controls colors, typography, and container styling across the entire app. Choose from 28 built-in theme presets, create your own custom palette, adjust fonts, and configure border styles — all without restarting.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings. *VibeCast* is a tool for sending commands to one or all of your terminals. *ACP* (Agent Conversation Protocol) lets you chat with AI coding assistants like Claude Code or Kiro directly inside Crispy.

## Getting Started

Open **App Settings** (⌘,) and select the **General** category. The theme controls are organized into sections for appearance mode, theme presets, typography, and container style.

For a quick change, use the theme picker in the title bar to switch between Auto, Light, and Dark modes.

## Workflows

### Choosing an appearance mode

The title bar includes a quick picker with three options:

| Mode | Behavior |
|------|----------|
| Auto | Follows your macOS system appearance — light during the day, dark at night if you use automatic switching. |
| Light | Forces light mode regardless of system setting. |
| Dark | Forces dark mode regardless of system setting. |

Your choice is saved and restored on next launch.

### Browsing theme presets

CrispyVibes ships with 28 theme presets. Open **App Settings → General** to browse them. Presets are grouped by category:

**Dark themes:** Midnight Mono, Graphite Dark, Ocean Dusk, Forest Night, Nord Frost, Dracula Night, Solarized Night, Mall Goth, Gas Station Slushie, Arcade Carpet, Radioactive Spreadsheet, Christmas, St. Patrick, Diwali, 4th of July, After Hours

**Light themes:** Sunlit Paper, Pearl Light, Mint Light, Latte Bloom, Alucard Light, Beach Day, Citrus Deadline, Mossy Fax Machine, Tomato Bisque, Pool Tile

**Adaptive:** System Vibes (follows your appearance mode)

**User-defined:** Custom Vibes (your own palette)

Select a preset and the entire app updates immediately. A preview strip shows five color swatches (Window, Canvas, Canvas Secondary, Border, Accent) so you can see the palette at a glance.

> When a non-System preset is active, a banner in settings notes that the theme overrides your appearance setting, with a quick link to switch back to System.

### Creating a custom theme

1. Select **Custom Vibes** from the preset list.
2. If you're switching from another preset, the current palette is copied as your starting point.
3. Edit any of the 10 color roles using the color pickers or by typing hex values (`#RRGGBB` or `#RRGGBBAA`).
4. Changes apply live as you edit.

The 10 editable color roles:

| Role | What it controls |
|------|-----------------|
| Window | Window frame and title bar |
| Canvas | Primary pane surfaces |
| Canvas Secondary | Cards, panels, and pop-up areas |
| Border | Split lines, strokes, separators |
| Accent | Interactive highlights, active controls |
| Success | Positive status indicators |
| Warning | Caution status indicators |
| Error | Error and destructive states |
| Selection Background | Text and item selection highlight |
| Terminal Foreground | Default text color in editors and terminals |

Additional colors (text shades, Git status badges, caret color) are derived automatically from your palette.

To start over, use **Reset Custom** (returns to the Midnight Mono base) or **Use Midnight Base**.

### Changing typography

In **App Settings → General**, the typography section offers:

| Setting | Options | Default |
|---------|---------|---------|
| Font family | System Monospace, SF Mono, Menlo, Monaco, Courier | System Monospace |
| Code + terminal font size | 1–100 pt (slider) | 13 pt |
| Rail terminal font scale (the stacked project cards on the side) | 1/4×, 1/2×, 1:1× | 1/2× |
| Text color | Color picker + hex field | Follows theme |

Font family changes apply to all text across the app immediately. Font size and rail scale are independent — adjusting one doesn't affect the other.

You can also use keyboard shortcuts for quick font size changes:

- **⌘+** to increase
- **⌘-** to decrease
- **⌘0** to reset to default

### Adjusting border style

In the container style section of App Settings:

- **Border shape** — choose between Square (sharp corners) and Rounded (8pt radius). Applies to all panes: sidebar, terminal board, file previewer, VibeCast, settings panels, explorer, and Git explorer.
- **Show borders** — toggle pane borders on or off entirely.

Both settings take effect immediately with no restart.

### Project colors

Each project in a vibespace can have its own color tag. The color appears on the project title, folder icon, frame accent, and stacked rail card.

To set a project color:

1. Click the color swatch next to the focused project name.
2. Pick a color from the popover.
3. The color is saved with your vibespace.

To clear a project color, use the clear option in the color popover. The project reverts to default styling.

When you add new folders to a vibespace, CrispyVibes auto-assigns an initial color so projects are visually distinct from the start. You can change it at any time.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘, | Open App Settings (theme controls are in General) |
| ⌘+ | Increase font size |
| ⌘- | Decrease font size |
| ⌘0 | Reset font size |

## Settings / Configuration

All theme preferences are stored in app-level storage and persist across launches:

| Setting | Where to find it |
|---------|-----------------|
| Appearance mode (Auto/Light/Dark) | Title bar picker or App Settings → General |
| Theme preset | App Settings → General |
| Custom palette (JSON) | App Settings → General → Custom Vibes |
| Font family | App Settings → General |
| Font size | App Settings → General (or ⌘+/⌘-/⌘0) |
| Rail font scale | App Settings → General |
| Border shape | App Settings → General |
| Border visibility | App Settings → General |
| Project colors | Click the color swatch on any project |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Custom theme shows wrong colors | Check for invalid hex values — they show inline errors. Use `#RRGGBB` or `#RRGGBBAA` format. |
| Theme didn't restore after relaunch | Preferences are stored in app preferences. If they were cleared (e.g., by a defaults reset), your custom theme will fall back to the system palette. |
| Appearance mode seems ignored | If you have a non-System preset active, it overrides the appearance setting. Switch to **System Vibes** to let Auto/Light/Dark take effect. |
| Font looks different than expected | Some font families may not be installed on your system. CrispyVibes falls back through candidate fonts — e.g., for SF Mono it tries SFMono-Regular, then SF Mono Regular, then SFMono-Medium. |
| Border color not visible | Make sure **Show borders** is toggled on. Border color only applies when borders are visible. |

## Known Limitations

- If your custom theme data becomes corrupted, CrispyVibes will fall back to the default palette.
- Border color is a single global setting — you cannot set different border colors per pane.
- Project colors are stored per vibespace. If you use the same folder in different vibespaces, it can have a different color in each.
- There is no import/export for theme presets. Custom palettes live in your local app storage only.

## Related Guides

- [Navigation](../navigation/usage-guide.md)
- [Keyboard Shortcuts](../shortcuts/usage-guide.md)
