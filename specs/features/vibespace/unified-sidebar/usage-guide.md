---
title: "Unified Project Side Panel"
feature: "F056"
domain: "vibespace"
audience: "user"
version: "1.0"
sidebar:
  label: "Unified Side Panel"
  order: 6
---

# Unified Project Side Panel

## Overview

The unified side panel shows everything for a project in one place — its files, its git changes, and its agent conversations — instead of switching the whole sidebar between separate Files / Git / Conversations tabs. Each project (and each git worktree) is a collapsible row you expand to work in.

## Getting Started

1. Open a vibespace and show the sidebar.
2. Click the layout toggle in the sidebar header to switch to **unified**.
3. The focused project expands automatically to its file tree.

## Workflows

### Switch what a project shows
Each project/worktree row has three compact toggles on the right: **Files**, **Changes** (with a count), **Chats** (with a count). Tap one to fill the row's body with that view. Files is the default.

### Create things
Use the **+** on a project/worktree row:
- On **Files**: New File, New Folder, Refresh.
- On **Chats**: New Agent Chat.
On a **repository** row, **+** offers **New Worktree…**.

### Work with worktrees
Repositories with multiple git worktrees group them under one repository row. See the **Git Worktrees** guide for open/create/close/delete.

### Go back to the classic layout
Click any left-rail tab (Files / Git / Sessions / Conversations), or use the header toggle. Unified mode is off by default and never changes the classic layout.

## Keyboard Shortcuts
None specific in this version.

## Settings / Configuration
The unified/classic choice is a per-session toggle in the sidebar header.

## Troubleshooting
| Issue | Resolution |
|-------|-----------|
| Changes shows green "A" for everything | Those are untracked (new) files; that's git's status, shown with friendly badges. `.DS_Store` and similar noise is hidden. |
| A project's files won't load | Expand the project (focused projects auto-expand); the tree loads on expand. |
| I don't see Sessions/Shelf | Those remain in the classic layout for now. |

## Known Limitations
- Opt-in; Sessions and Shelf aren't folded in yet.
- Git stage/commit happen in the classic Source Control view, not inline here yet.
