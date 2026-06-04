# Git Worktrees — Spec

Status: draft

## Overview

Git Worktrees surfaces a repository's git worktrees inside the unified project side panel (F056): worktrees of the same repository are clubbed under one repository node, worktrees the user hasn't added appear in an "Other worktrees" group, and the user can open, close, create, and delete worktrees. Discovery and mutations run through an injected `WorktreeServicing` service that shells out to git off the main actor. Local repositories only in this version.

## Dependencies

- F056 (Unified Project Side Panel) — the surface that renders worktree nodes
- F021 (VibeSpace Projects) — a worktree opens as a normal project session (`addProjects`/`removeProject`)
- F026 (Git Operations) — shares the `PaneWorkerExecutor` git runner

## Requirements

### F055-R01: Worktree Discovery
For each added project that is a git repo, the app MUST resolve its shared git-common-dir (repo identity) and current branch, and enumerate all worktrees via `git worktree list --porcelain`. Prunable worktrees and worktrees whose directory no longer exists MUST be excluded. SSH/remote project paths MUST be skipped.

### F055-R02: Clubbing
Added projects sharing a git-common-dir MUST be grouped under one repository node. A repository node MUST appear when a repo has more than one worktree total (added or not); a single-checkout repo renders as a plain project node.

### F055-R03: Not-added Worktrees
Worktrees that exist in git but are not added as projects MUST be listed in a collapsed "Other worktrees" group with an "Open as Project" action that adds the worktree via the standard add-project flow.

### F055-R04: Create Worktree
The repository node MUST offer "New Worktree…": prompt for a branch name, create a sibling worktree on a new branch (`git worktree add -b <branch> <path>`), and open it as a project. Failures MUST surface a user-facing error.

### F055-R05: Close Worktree
An added worktree MUST offer "Close Worktree", which removes it from the sidebar (reuses `removeProject`) without touching the on-disk worktree; it reappears under "Other worktrees".

### F055-R06: Delete Worktree
A non-primary worktree MUST offer "Delete Worktree…": confirm, remove the project if added, then `git worktree remove`. On failure (dirty/locked) the user MUST be offered a force delete with an explicit data-loss warning. The primary/main worktree MUST NOT be deletable.

### F055-R07: Service Boundary
Worktree discovery and mutations MUST go through `WorktreeServicing` (Protocols/), injected via `AppContainer`; views/coordinators MUST NOT shell out to git directly. Porcelain parsing MUST be a pure function (`WorktreeParser`).

## Scenarios

### Scenario F055-S01: Club two worktrees of one repo
**Given** two added projects resolve to the same git-common-dir
**When** the unified panel loads
**Then** they appear as worktree children under one repository node labeled with the repo name and worktree count.

### Scenario F055-S02: Discover and open a not-added worktree
**Given** a repo with a worktree not added as a project
**When** the user expands "Other worktrees" and clicks Open
**Then** the worktree is added as a project and re-clubs under the repository node.

### Scenario F055-S03: Create a worktree
**Given** a repository node
**When** the user chooses "New Worktree…" and enters a branch name
**Then** a sibling worktree is created on that branch and opened as a project.

### Scenario F055-S04: Delete blocked on dirty, then forced
**Given** a worktree with uncommitted changes
**When** the user deletes it
**Then** git refuses, the app offers Force Delete with a data-loss warning, and forcing removes it.

### Scenario F055-S05: Primary worktree is protected
**Given** the repo's primary worktree
**Then** no "Delete Worktree…" action is offered.

## Acceptance Criteria
- Worktrees club by git-common-dir; primary worktree never deletable
- Not-added worktrees discoverable + openable; runtime-only (not persisted)
- Create/close/delete all funnel through `WorktreeServicing`; parsing is pure + unit-tested

## Test Coverage
| Scope | Test File |
|---|---|
| Porcelain parsing (paths/branches, prunable, detached, missing dirs); service probe/add/remove via injected runner | `tests/unit/Features/VibeSpace/WorktreeServiceTests.swift` |

## Open Questions
- Remote (SSH) worktree support (deferred).
- Surfacing worktree actions over the agent CLI (deferred).

## Change History
| Date | Change | Author |
|------|--------|--------|
| 2026-06-04 | Initial draft — worktree discovery, clubbing, open/create/close/delete, service boundary | — |
