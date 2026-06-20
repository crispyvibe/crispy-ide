---
title: "Quick Todos & Sticky Notes"
feature: "F053"
domain: "vibespace"
audience: "user"
version: "1.0"
sidebar:
  label: "Todos"
  order: 6
---

# Quick Todos & Sticky Notes

## Overview

Todos let you jot tasks without leaving your flow. Capture one in a second with a hotkey, or open the full **Todos** surface to organize them, add rich-text notes, and keep a per-todo discussion thread. Todos are scoped to a project (or kept at the VibeSpace level), persist across launches, and are fully scriptable from the terminal with the `crispy` CLI.

## Getting Started

- **Capture instantly:** press **⌃⌘T** anywhere — a small field appears. Type your task and press **Return**. It saves to your current project and confirms with a quick ✓. Press **Esc** to cancel.
- **Open the surface:** click the **checklist** button in the toolbar. In **Detailed** view it opens the **Todos** tab (a list on the left, details on the right); in **Terminal Board** view it floats the same surface as a **spotlight** over the board, so you never have to leave board mode to manage todos.

## Workflows

### Capture and forget
1. Press **⌃⌘T**.
2. (Optional) Click **"Lands in › \<project\>"** to send the todo to a different project or to **VibeSpace** (no specific project).
3. Type the title and press **Return** — a brief "Todo added" confirmation shows, then the field disappears. Focus returns to wherever you were.

The target defaults to the project you're currently working in, and updates each time you open the field.

### Manage todos in the surface
- Type in the **quick-add** field at the top of the list and press Return to add.
- Toggle **Project / All** to switch between the focused project's todos and every todo in the VibeSpace.
- Click a card's circle to **complete** it (completed items move down and gray out); hover a card to reveal **Delete**.
- Click a card to open its detail on the right.

### Notes and threads
- In detail, edit the **title** inline (Return to save).
- Click the **Notes** area to write a markdown body; press **⌘Return** to save. Bold, italics, code, and links render in preview.
- Use the **composer** at the bottom to post messages to the todo's **thread**. Messages group by author with a relative time (e.g. "2m"). Messages you post show as **You**; messages added by an AI agent are styled distinctly.

### From the terminal (CLI)
Inside a Crispy terminal:

```bash
crispy todo add --text "fix the login bug" --body "see auth.swift"
crispy todo list --status active
crispy todo show <id>            # prints the todo and its full thread
crispy todo message add <id> --text "started looking into this"
crispy todo complete <id>        # or: reopen, update, remove
```

Todos and messages created from the CLI appear live in the open Todos surface. By default they land in the terminal's project; pass `--project <path>` to target another.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Quick Add Todo (capture HUD) | **⌃⌘T** |
| Save todo (in capture HUD / composer) | **Return** |
| Save notes body | **⌘Return** |
| Cancel capture HUD | **Esc** |
| Scale UI up / down / reset | **⌘+** / **⌘-** / **⌘0** |

The capture shortcut is rebindable in **Settings → Keyboard Shortcuts → "Quick Add Todo"** (record a new key, press Delete to disable, or Reset to return to the default).

## Settings / Configuration

- **Keyboard Shortcuts:** change or disable the capture hotkey.
- **Appearance / font size:** the entire Todos UI follows your theme and scales with the app font-size controls (⌘+ / ⌘- / ⌘0).

## Troubleshooting

- **Pressed ⌃⌘T but nothing happened:** the Todos toolbar button opens the surface; the **⌃⌘T** HUD requires an active VibeSpace. Confirm the shortcut in Settings → Keyboard Shortcuts.
- **Clicked the toolbar button in Terminal Board mode:** Todos now floats as a **spotlight** over the board — you no longer need to switch to **Detailed** view to see it. Dismiss the spotlight to return to the board.
- **My todo didn't go to the project I expected:** the capture target is shown in the HUD's "Lands in" menu — set it before pressing Return.

## Known Limitations

- **Reminders are not available yet** (planned for a later update).
- **Switching VibeSpace** while the Todos tab is open does not auto-refresh the list — reopen the tab to refresh.
- Todos opens as a **content-viewer tab** in Detailed view and as a **spotlight** over the board in Terminal Board view; a dedicated board *tile* (like ACP/Browser tiles) isn't available yet.
- The open Todos tab is **not restored** after relaunch (your todos are — just reopen the tab).
