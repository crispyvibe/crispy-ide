---
title: "Clone Repository"
feature: "F027"
domain: "source-control"
audience: "user"
version: "1.0"
sidebar:
  label: "Clone"
  order: 1
---

# Clone Repository

## Overview

Clone Repository allows you to clone a Git repository directly from the source control sidebar. It integrates with GitHub CLI for repository browsing when available, supports manual URL entry, and automatically adds the cloned folder to your active vibespace as a new project.

## Getting Started

1. Open the **Git** tab in the side menu rail.
2. Click **Clone Repository** in the sidebar header (or from the empty state button if no repositories exist).
3. Choose a repository source: browse GitHub repos (if `gh` CLI is available) or paste a URL.
4. Select a destination folder and clone.

## Workflows

### Cloning from GitHub (with GitHub CLI)

1. Open the Git sidebar and click **Clone Repository**.
2. Crispy checks whether GitHub CLI (`gh`) is available on your machine.
3. If available, a GitHub repository picker appears with your accessible repos.
4. Select a repository from the list.
5. Choose a local destination folder for the clone.
6. Click **Clone** — the repository is cloned to the chosen destination.
7. The cloned folder is automatically added to your active vibespace as a project.

### Cloning from a Manual URL

1. Open the Git sidebar and click **Clone Repository**.
2. If GitHub CLI is not available (or you prefer manual entry), switch to the URL input mode.
3. Paste the repository URL (HTTPS or SSH).
4. Choose a local destination folder.
5. Optionally configure advanced options (branch, depth).
6. Click **Clone** to begin the operation.
7. The cloned folder is added to your vibespace on completion.

### Cloning from Empty State

1. When no repositories are discovered in your vibespace, the Git sidebar shows an empty state.
2. The empty state includes a **Clone Repository** button.
3. Click it to open the clone sheet and follow the standard clone workflow.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for clone operations.

## Settings

No specific settings affect clone behavior. GitHub CLI availability is detected automatically.

## Tips

- The clone sheet checks for GitHub CLI availability automatically on open — no manual configuration needed.
- After cloning, the new project is immediately available in the vibespace file explorer and source control sidebar.
- You can clone multiple repositories into the same vibespace to build a multi-project workspace.
- The destination folder picker remembers your last-used location.
- Clone progress and errors are surfaced in the clone sheet UI.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| GitHub repos not showing | Ensure GitHub CLI (`gh`) is installed and authenticated (`gh auth login`). |
| Clone fails with auth error | For SSH URLs, ensure your SSH key is loaded in the agent. For HTTPS, check git credential helper. |
| Clone button disabled | Verify that both a repository source and destination folder are specified. |
| Cloned project not appearing | The project should auto-add to the vibespace. Check the file explorer sidebar. If missing, manually add the folder via Add Project. |
| "Checking providers" spinner stuck | GitHub CLI check may be timing out. Switch to manual URL mode to proceed. |
