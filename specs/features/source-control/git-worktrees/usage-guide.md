---
title: "Git Worktrees"
feature: "F055"
domain: "source-control"
audience: "user"
version: "1.1"
sidebar:
  label: "Git Worktrees"
  order: 3
---

# Git Worktrees

## Overview

Crispy understands git worktrees. When projects in a vibespace are worktrees of the same repository, they're grouped under one repository in the unified side panel, and you can open, create, close, and delete worktrees right from there.

## Getting Started

1. Open the **Workspace** rail item (the grid icon in the side menu). It shows the unified per-project/worktree panel and is on by default.
2. A repository with more than one worktree appears as a collapsible **repository** row (e.g. `myrepo · 2 worktrees`).
3. Expand it to see each worktree (labeled by branch), each with its own Files / Changes / Chats.

## Workflows

### Open a worktree that isn't added
Expand the repository → **Other worktrees (N)** → click **Open** (or right-click → **Open as Project**). It moves up into the repository as a full worktree.

### Create a new worktree
Click the **+** on the repository row → **New Worktree…** → enter a branch name. Crispy creates a sibling worktree on that branch and opens it.

### Close a worktree
Right-click a worktree → **Close Worktree**. It's removed from the sidebar but stays on disk, reappearing under "Other worktrees". Nothing is deleted.

### Delete a worktree
Right-click a worktree → **Delete Worktree…** → confirm. This removes the directory from disk and unregisters it from git. If it has uncommitted changes git will refuse; you can then choose **Force Delete** (which discards those changes). The repository's main worktree can't be deleted.

## Keyboard Shortcuts
None specific to worktrees in this version.

## Settings / Configuration
None. Worktrees are discovered automatically from git; nothing is persisted beyond the projects you add.

## Troubleshooting
| Issue | Resolution |
|-------|-----------|
| A worktree isn't showing | It must belong to a git repo you've added; non-git folders and SSH/remote projects aren't grouped. |
| Delete failed | The worktree likely has uncommitted changes or is locked — use Force Delete only if you accept losing those changes. |
| "Other worktrees" is empty | The repo has only the worktrees you've already added. |
| A folder inside a repo shows as its own project, not a worktree | Only folders opened at a worktree's root are grouped as worktrees. A subdirectory you opened as its own project stays a standalone node, even though it's in the same repo. |

## Known Limitations
- Local repositories only (no SSH/remote worktrees yet).
- Branch-name validation is minimal; use normal git branch names.
- No agent-CLI commands for worktrees yet.
