---
title: "Shortcuts"
feature: F016
domain: app-shell
audience: "user"
version: "1.0"
sidebar:
  label: Shortcuts
  order: 3
---

# Keyboard Shortcuts

## Overview

CrispyVibes provides keyboard shortcuts for navigating projects, managing terminals, editing documents, controlling the canvas layout, and more. All shortcuts can be customized in App Settings.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace — a collection of projects, terminals, and settings. *VibeCast* is a tool for sending commands to one or all of your terminals. *ACP* (Agent Conversation Protocol) lets you chat with AI coding assistants like Claude Code or Kiro directly inside Crispy.

## Getting Started

Most shortcuts work immediately with no setup. Project shortcuts (⌘1–⌘9) become available once you have projects open in a vibespace. You can assign specific projects to specific shortcut slots in VibeSpace Settings.

To open the shortcut customization panel, go to **App Settings → Shortcuts**.

## Workflows

### Navigating between projects

Use **⌘1** through **⌘9** to jump directly to a project. By default, these map to projects by their position in the rail. You can assign explicit mappings in **VibeSpace Settings → Shortcuts** so a project always stays on the same number regardless of order.

Use **⌘⌥]** and **⌘⌥[** to step forward and backward through projects sequentially.

### Cycling through terminal tabs

Within the focused project, press **⌘⌥↓** to move to the next terminal tab or **⌘⌥↑** for the previous one. Tabs wrap around — going past the last tab returns to the first.

In Terminal Only mode, **⌘⌥→** and **⌘⌥←** navigate between board columns.

### Editing documents

- **⌘S** saves the active document.
- **⌘F** opens the find bar.
- **⌘⇧H** opens find-and-replace.
- **Escape** closes the find bar.

### Switching canvas modes

- **⌘D** switches to Detailed view (editor + terminal).
- **⌘T** switches to Terminal Only board.

### VibeCast shortcuts

VibeCast is Crispy's tool for sending commands to one or all terminals.

When VibeCast is open:

- **⌘⇧V** toggles VibeCast on or off.
- **⌘↩** sends the composed message to the targeted terminal.
- **⌘B** broadcasts the message to all terminals.
- **⌘R** rephrases the composed text with AI (requires non-empty input).
- **⌥↑** / **⌥↓** cycles the target terminal up or down.

### Font size

- **⌘+** increases font size by 1pt.
- **⌘-** decreases font size by 1pt.
- **⌘0** resets to the default size.

## Keyboard Shortcuts

### Full reference

#### App

| Shortcut | Action |
|----------|--------|
| ⌘ , | Open App Settings |
| ⌘⇧N | Open VibeSpace (folder picker for new vibespace) |

#### File Operations

| Shortcut | Action |
|----------|--------|
| ⌘S | Save document |
| ⌘F | Find in document |
| ⌘⇧H | Replace in document |

#### Project Navigation

| Shortcut | Action |
|----------|--------|
| ⌘1–⌘9 | Focus project by shortcut slot |
| ⌘⌥] | Next project |
| ⌘⌥[ | Previous project |

#### Terminal Navigation

| Shortcut | Action |
|----------|--------|
| ⌘⌥↓ | Next terminal tab in project |
| ⌘⌥↑ | Previous terminal tab in project |
| ⌘⌥→ | Next board column (Terminal Only) |
| ⌘⌥← | Previous board column (Terminal Only) |
| ⌃⇧← / ⌃⇧→ | Cycle terminals across all panes (Terminal Only) |

#### Canvas Mode

| Shortcut | Action |
|----------|--------|
| ⌘D | Detailed view |
| ⌘T | Terminal Only board |

#### VibeCast

| Shortcut | Action |
|----------|--------|
| ⌘⇧V | Toggle VibeCast |
| ⌘↩ | Send message |
| ⌘B | Broadcast to all terminals |
| ⌘R | Rephrase with AI |
| ⌥↑ / ⌥↓ | Cycle target terminal |

#### Font Size

| Shortcut | Action |
|----------|--------|
| ⌘+ | Increase font size |
| ⌘- | Decrease font size |
| ⌘0 | Reset font size |

#### Dismiss / Cancel

| Shortcut | Action |
|----------|--------|
| Escape | Dismiss Terminal Spotlight, link preview, find bar, or creation sheet |
| Return | Confirm terminal creation dialog |

#### Developer

| Shortcut | Action |
|----------|--------|
| ⌘⌥D | Open developer tools |
| ⌘⌥⇧D | Terminal diagnostics snapshot (debug builds only) |

## Settings / Configuration

### Customizing shortcuts

1. Open **App Settings** (⌘,).
2. Select the **Shortcuts** category in the left sidebar.
3. Browse or search for the shortcut you want to change.
4. Click the shortcut field and press your new key combination.
5. Changes save automatically.

### Project shortcut slots

To assign a project to a specific ⌘-number slot:

1. Open **VibeSpace Settings**.
2. Go to the **Shortcuts** category.
3. For each project folder, pick a slot from ⌘1 to ⌘9.
4. Slots are unique — assigning a slot that's already taken moves the previous project automatically.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| ⌘1–⌘9 doesn't switch projects | Make sure you have projects open. If no explicit mapping exists, shortcuts fall back to positional order. Check VibeSpace Settings → Shortcuts for assignments. |
| A shortcut conflicts with macOS | CrispyVibes shortcuts may be overridden by system-level shortcuts. Check **System Settings → Keyboard → Keyboard Shortcuts** on your Mac. |
| VibeCast shortcuts don't work | VibeCast must be open (⌘⇧V) for its shortcuts to be active. The compose field needs focus for ⌘↩ and ⌘B. |
| Terminal clipboard not working | Terminal copy/paste targets the active terminal tab only. Make sure the correct tab is selected. |

## Known Limitations

- The ⌘⌥⇧D diagnostics shortcut is only available in debug builds.
- SSH profile management is available in App Settings → Connections.
- Shortcut customization persists in app storage — there is no import/export for shortcut profiles.

## Related Guides

- [Navigation](../navigation/usage-guide.md)
- [Theming](../theming/usage-guide.md)
