---
title: "Pane Workers"
feature: "F013"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "Workers"
  order: 6
---

# Pane Workers

## Overview

Pane Workers are the out-of-process execution engine that powers Crispy's file explorer, git operations, editor file I/O, and terminal utilities. They run as isolated subprocesses to keep the main app responsive, with timeout protection, generation guards against stale processes, and full instrumentation for diagnostics.

## Getting Started

Pane workers operate transparently behind the scenes. When you:
- Browse files in the explorer → the **explorer worker** handles `listTree`, file creation, rename, move, copy, and delete.
- Use source control → the **source control worker** handles git status, diff, branches, stage, unstage, commit, push, pull, fetch, checkout, clone, and discard.
- Open or save files → the **editor worker** handles `readFile` and `writeFile`.
- Interact with terminal utilities → the **terminal worker** handles ping and `gitCurrentBranch`.

No manual setup is required — workers are spawned automatically.

## Workflows

### File Explorer Operations

The explorer worker supports these operations, all triggered through the file explorer UI:

| Operation | Behavior |
|-----------|----------|
| List tree | Returns immediate children only; skips package descendants; includes hidden entries; annotates git-ignored entries |
| Create file | Generates collision-safe names with numeric suffix (`name 1`, `name 2`, …) |
| Create folder | Same collision-safe naming as file creation |
| Rename | Validates non-empty name and no destination conflict |
| Delete | Removes file or directory at the target path |
| Move | Validates destination exists, is a directory, has no name conflict, and prevents self-move |
| Copy | Copies file or folder to target location |

### Git Operations

The source control worker handles all git interactions:

| Operation | Behavior |
|-----------|----------|
| Status | Parses porcelain v1 z-format output; handles renames/copies; sorts case-insensitively |
| Diff | Returns staged and unstaged sections; falls back to porcelain status if textual diff unavailable |
| Branches | Returns local and remote refs with current branch marker |
| Stage / Unstage | Stages or unstages individual paths or all changes |
| Commit | Validates non-empty message before committing |
| Push / Pull / Fetch | Standard remote operations |
| Checkout | Supports local and remote branch checkout |
| Clone | Clones repository to specified destination |
| Discard / Discard All | Reverts unstaged changes for one file or all files |
| Discover repositories | Finds git repos under project root (single or batch) |
| Repository snapshot | Combined status + branches in a single call |
| File content at HEAD | Returns file content as it exists at HEAD revision |
| Commit/file history | Returns bounded commit entries, optionally scoped to a file |
| GitHub clone options | Lists available repos via GitHub CLI (if installed) |

### Editor File Operations

| Operation | Behavior |
|-----------|----------|
| Read file | Supports UTF-8, UTF-16, and ISO Latin-1 encoding detection |
| Write file | Persists UTF-8 content atomically |

### Terminal Worker Operations

| Operation | Behavior |
|-----------|----------|
| Ping | Returns timestamp (health check) |
| Git current branch | Returns current branch name for a repository root |

### Understanding Worker Status

The pane status indicator reflects the worker state:
- **Ready**: Worker is idle and available for requests.
- **Busy**: A request is in progress.
- **Unavailable**: A failure occurred — a user-facing message explains the issue.

## Keyboard Shortcuts

Pane workers have no direct keyboard shortcuts — they are invoked indirectly through explorer, git, and editor interactions.

## Settings

| Setting | Description |
|---------|-------------|
| `CRISPYVIBES_PANE_WORKER_EXECUTION_MODE` | Environment variable to force `inprocess` or `subprocess` mode (default: subprocess) |

## Tips

- Workers run as **subprocesses** by default — the same app executable is spawned with `--pane-task <pane-kind>` and communicates via JSON over stdin/stdout.
- In-process mode is available for testing/debugging by setting the environment variable to `inprocess`.
- **Timeout protection**: If a worker doesn't respond within the configured timeout, the process is terminated and the caller receives a timeout error.
- **Generation guards**: If the worker client restarts, older in-flight processes are ignored or terminated by generation mismatch rules, preventing stale results.
- **MeasuredPaneWorker**: Every worker execution is instrumented with `os_signpost` intervals and recorded in the Operation Metrics Store. View these in Developer Tools → Operations.
- **PaneWorkerPersistentSession**: For performance, workers can maintain a long-lived subprocess using newline-delimited JSON, reusing the process across multiple requests.
- **Git probe caching**: `isGitAvailable` and `isGitRepository` results are cached with a TTL to avoid redundant subprocess spawns.
- **SSH-backed operations**: Remote file operations retry readiness asynchronously with bounded backoff before failing, without blocking the main thread.
- **Response contract**: All worker responses follow a consistent format — `success: true` with optional `value`, or `success: false` with `error` message.
- File listing sorts directories first and includes metadata flags for hidden and git-ignored entries.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Explorer shows "unavailable" status | A worker failure occurred. The status message explains the issue. Try refreshing the explorer or restarting the app. |
| Git operations fail with "git not available" | Git is not installed or not in PATH. Install git and ensure it's accessible from the command line. |
| "Not a git repository" message | The current project root is not inside a git work tree. Initialize a repository with `git init` or open a folder that contains one. |
| File read fails with "unsupported encoding" | The file uses an encoding other than UTF-8, UTF-16, or ISO Latin-1. Convert the file to UTF-8. |
| Worker timeout errors | The operation took too long. This can happen with very large directories or slow git operations on large repos. Check if the underlying git/filesystem operation is hanging. |
| Rename fails with "conflict" | A file or folder with the new name already exists at the destination. Choose a different name. |
| Move fails with "self-move" | You attempted to move a folder into itself or a descendant. Choose a different destination. |
| SSH remote operations fail | The SSH connection may still be coming online. The worker retries with bounded backoff — if it still fails, check your SSH connection status. |
