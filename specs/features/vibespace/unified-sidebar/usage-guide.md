---
title: "Unified Project Side Panel"
feature: "F056"
domain: "vibespace"
audience: "user"
version: "1.1"
sidebar:
  label: "Workspace Side Panel"
  order: 6
---

# Unified Project Side Panel

## Overview

The **Workspace** side panel shows everything for a project in one place — its files, its git changes, and its agent conversations — instead of switching the whole sidebar between separate Files / Git / Conversations tabs. Each project (and each git worktree) is a collapsible row you expand to work in, and your Shelf sits at the top. Workspace is the default side panel and has its own rail button.

## Getting Started

1. Open a vibespace. The **Workspace** panel (grid icon in the left rail) is shown by default.
2. The focused project expands automatically to its file tree.
3. To return to a classic view, click any other rail button (Files / Git / Sessions / Conversations); click **Workspace** again to come back.

## Workflows

### Switch what a project shows
Each project/worktree row has a segmented cluster of three compact toggles on the right: **Files**, **Changes** (with a count), **Chats** (with a count). Tap one to fill the row's body with that view. Files is the default, and the active toggle is highlighted with a neutral fill. Every control gives hover feedback.

### Create things
Use the **+** on a project/worktree row (a gray menu that matches its siblings):
- On **Files**: New File, New Folder, Refresh.
- On **Chats**: New Agent Chat.
On a **repository** row, **+** offers **New Worktree…**.

### Use the Shelf
Your Shelf appears at the top of the Workspace panel when it has items, with the same open / reveal / rename / delete / remove / clear actions as the classic Files pane.

### Work with worktrees
Repositories with multiple git worktrees group them under one repository row. A subdirectory you opened as its own project shows as a standalone row, not under that repository. See the **Git Worktrees** guide for open/create/close/delete.

### Go back to the classic layout
Click any left-rail tab (Files / Git / Sessions / Conversations). Click **Workspace** to return. The classic layouts are unchanged.

## Keyboard Shortcuts
None specific in this version.

## Settings / Configuration
Workspace is the default side panel. The choice between Workspace and a classic tab is made by selecting rail buttons; there is no separate header toggle.

## Troubleshooting
| Issue | Resolution |
|-------|-----------|
| Changes shows green "A" for everything | Those are untracked (new) files; that's git's status, shown with friendly badges. `.DS_Store` and similar noise is hidden. |
| A project's files won't load | Expand the project (focused projects auto-expand); the tree loads on expand. |
| A subdirectory project isn't under its repository | That's intended — a folder opened as its own project (not at a worktree root) stays standalone and isn't clubbed with the repo's worktrees. |
| I don't see Sessions | Sessions remain in the classic layout for now (the Sessions rail tab). |

## Known Limitations
- Sessions aren't folded into Workspace yet.
- Git stage/commit happen in the classic Source Control view, not inline here yet.
