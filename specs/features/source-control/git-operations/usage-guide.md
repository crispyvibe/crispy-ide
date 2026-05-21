---
title: "Git Operations"
feature: "F026"
domain: "source-control"
audience: "user"
version: "1.0"
sidebar:
  label: "Git Operations"
  order: 2
---

# Git Operations

## Overview

Git Operations provides a vibespace-scoped source control sidebar with repository discovery, per-repo status display, staged/unstaged grouping, branch management, commit/push/pull/fetch/discard actions, compare mode, commit history, and list/tree layout toggle. It discovers repositories across all projects in your vibespace and presents them in a unified view.

## Getting Started

1. Open the **Git** tab in the side menu rail.
2. Repositories are discovered automatically across all projects in your vibespace.
3. Each repository appears as a collapsible section showing current branch and changed files.
4. Use the inline controls to stage, commit, push, pull, and manage branches.

## Workflows

### Viewing Repository Status

1. Open the Git sidebar — repositories are discovered asynchronously.
2. The header shows total repository count and aggregate pending change count.
3. Each repository section displays: current branch, changed file count, and action buttons.
4. Changed files are grouped into **Staged** and **Changes** (unstaged) sections.
5. Each file row shows a concise status badge (A/M/D/R/U).
6. Repositories beyond the auto-presented limit (12) are collapsed with an expand option.

### Staging and Unstaging Files

1. In a repository section, find the file you want to stage.
2. Click the **+** (stage) button on the file row to move it to Staged.
3. Click the **−** (unstage) button on a staged file to move it back to Changes.
4. Use **Stage All** to stage all pending changes at once.
5. Use **Unstage All** to move all staged files back to unstaged.

### Committing Changes

1. Stage the files you want to commit.
2. Type a commit message in the commit composer field.
3. Click **Commit** — the message must be non-empty.
4. On success, the commit message draft is cleared and status refreshes.
5. Commit drafts are isolated per repository — typing in one doesn't affect others.

### Pushing, Pulling, and Fetching

1. Each repository section has **Push**, **Pull**, and **Fetch** action buttons.
2. **Push**: Publishes the current branch to the configured remote.
3. **Pull**: Pulls changes from the remote tracking branch.
4. **Fetch**: Fetches remote refs without merging.
5. All actions are scoped to the specific repository and refresh status on completion.

### Discarding Changes

1. To discard a single file: click the discard button on that file row.
2. The file is restored to its index or HEAD state.
3. To discard all changes: click **Discard All** on the repository section.
4. A confirmation prompt appears before reverting all working-tree changes.

### Viewing Diffs (Compare Mode)

1. Click any changed file row in the git status list.
2. The editor opens compare mode showing the diff for that file.
3. Works for text files, images, and other file types.
4. Deleted, renamed, and copied entries also open compare mode with fallback content.

### Managing Branches

1. Click the branch button in a repository section header.
2. The branch menu lists local and remote branches with the current branch marked.
3. Select a branch to check it out.
4. Status and branch list refresh after checkout completes.

### Viewing Commit History

1. Click the **History** button in a repository section header.
2. A history sheet shows recent commits with subject, hash, author, and date.
3. For file-specific history: use the file history action on a changed file row.
4. File history shows commits scoped to that specific file path.

### Switching Layout Mode

1. Toggle between **List** and **Tree** layout using the layout button.
2. List mode shows a flat list of changed files.
3. Tree mode shows files organized in a directory hierarchy.
4. The selected mode persists across sidebar reloads.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for git operations. All actions are accessible via sidebar controls and context menus.

## Settings

- **Ignored Directories** (Source Control Settings): Directories excluded from repository scanning.
- **Scan Depth**: How deep to scan for nested repositories.
- **Scan Max Repos**: Maximum number of repositories to discover.
- Changes to these settings trigger re-discovery of repositories.

## Tips

- Shared repository roots are deduplicated — if two projects map to the same repo, it appears once.
- Nested repositories (e.g., submodules) are shown as separate sections.
- Non-repository projects don't suppress other vibespace repositories from appearing.
- Repository ordering favors the active context — selecting a file promotes its owning repository.
- File saves automatically trigger a refresh of the owning repository's status.
- File system changes detected by the watcher trigger targeted refreshes (only the affected repository).
- Partial repository failures remain localized — one failing repo doesn't block others.
- The sidebar shows appropriate states: loading, git unavailable, not a repository, error with retry, clean tree, and changed tree.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Git Not Installed" shown | Install Git and ensure it's on your PATH. Restart Crispy after installation. |
| No repositories discovered | Ensure your project folders contain `.git` directories. Check scan depth settings. |
| Repository shows error with retry | Click Retry. The error is localized to that repository — others remain functional. |
| Commit button disabled | Ensure the commit message is non-empty and at least one file is staged. |
| Push fails | Check remote configuration (`git remote -v`). Ensure you have push access and network connectivity. |
| Status not updating after file save | The watcher should trigger a refresh. Try the manual refresh button on the repository section. |
| Too many repositories collapsed | Repositories beyond the limit (12) are collapsed by default. Click to expand them. |
| Branch checkout fails | Ensure you have no uncommitted changes that conflict, or stash them first. |
