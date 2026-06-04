# Git Worktrees — Threat Model

## Overview
Worktree features execute git subprocesses with user-influenced arguments and can delete directories on disk. This model covers injection, data loss, and path-trust risks.

## Trust Boundaries
- User input: branch name (New Worktree), selected worktree paths.
- git subprocess: invoked via `PaneWorkerExecutor.runGitCommand` (argument array, no shell).
- Filesystem: worktree directories created/removed on the local disk.

## Attack Surfaces
- Branch-name text field → `git worktree add -b <branch> <path>`.
- Worktree path (from `git worktree list`) → `git worktree remove`.
- `git worktree list --porcelain` output parsing.

## Threats

### F052-T01: Argument/command injection via branch name
- Vector: a crafted branch name (e.g. `--option`, path traversal, or shell metacharacters).
- Impact: unexpected git behavior or worktree created outside the intended location.
- Likelihood: Low (single user, local).
- Mitigation: arguments are passed as a non-shell argv array (no shell interpolation); `/` in the branch is sanitized when deriving the sibling directory name; the worktree path is computed by the app, not the user. Further hardening: reject branch names beginning with `-` and validate against `git check-ref-format` (follow-up).

### F052-T02: Data loss via force delete
- Vector: "Force Delete" runs `git worktree remove --force`, discarding uncommitted changes.
- Impact: loss of uncommitted work.
- Likelihood: Medium (user-initiated).
- Mitigation: two-step flow — non-force delete first; force only after an explicit second confirmation that warns changes will be lost. Primary worktree is never deletable.

### F052-T03: Deleting the active project's directory
- Vector: deleting a worktree currently open as a live project.
- Impact: dangling session pointing at a removed directory.
- Likelihood: Low.
- Mitigation: the project is removed (session shut down) before `git worktree remove`; the panel re-probes afterward.

### F052-T04: Stale/prunable worktree paths
- Vector: `git worktree list` may report worktrees whose directory is gone.
- Impact: acting on a non-existent path.
- Mitigation: parser skips `prunable` entries and verifies the directory exists before listing it.

## Residual Risks
- Branch names are not yet validated against `git check-ref-format` (T01 hardening pending).
- Remote/SSH worktrees are out of scope.

## NFR Compliance
- SEC-1 (input handling): argv-based git invocation, no shell.
- REL: destructive actions gated by confirmation; primary worktree protected.
