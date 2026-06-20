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
For each added project that is a git repo, the app MUST resolve its shared git-common-dir (repo identity) and its worktree root (`git rev-parse --show-toplevel`), and enumerate all worktrees via `git worktree list --porcelain`. A project's branch MUST be read from that porcelain list (the single source of truth), not from a separate per-project query. Prunable worktrees and worktrees whose directory no longer exists MUST be excluded. SSH/remote project paths MUST be skipped.

### F055-R02: Clubbing
Added projects that are worktree roots (see F055-R08) and share a git-common-dir MUST be grouped under one repository node. A repository node MUST appear when a repo has more than one worktree total (added or not); a single-checkout repo renders as a plain project node. Projects that merely live inside the repo (subdirectories) MUST NOT cause clubbing.

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

### F055-R08: Worktree-root identity
A project MUST be treated as a worktree only when its opened folder is exactly the worktree root (`relativeSubpath` empty). A subdirectory opened as its own project shares the repo's git-common-dir but MUST NOT be clubbed under, counted among, or labeled as a worktree — it renders as a standalone project node. Path identity (matching projects to git-reported worktree paths, and deduping the "Other worktrees" group) MUST be symlink-resolved (canonical) and case-insensitive to match the default case-insensitive APFS volume.

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

### Scenario F055-S06: Subdirectory project is not mis-clubbed
**Given** a project opened at a subdirectory of a worktree (it shares the repo's git-common-dir but is not the worktree root)
**When** the unified panel loads
**Then** it renders as a standalone project node — not clubbed under the repository, not labeled with a branch, and not listed among the repo's worktrees.

### Scenario F055-S07: Symlinked / differently-cased project still dedups
**Given** a worktree opened as a project via a symlinked or differently-cased path
**When** the panel builds the "Other worktrees" group
**Then** that worktree does not reappear there, because identity is matched on the canonical (symlink-resolved) path, case-insensitively.

## Acceptance Criteria
- Worktree roots club by git-common-dir; subdirectory projects stay standalone; primary worktree never deletable
- Not-added worktrees discoverable + openable; runtime-only (not persisted); deduped by canonical, case-insensitive path
- Branch is sourced from the porcelain worktree list (one source of truth)
- Create/close/delete all funnel through `WorktreeServicing`; parsing is pure + unit-tested

## Test Coverage
| Scope | Test File |
|---|---|
| Porcelain parsing (paths/branches, prunable, detached, missing dirs, canonical-path resolver); probe builds `ProjectGitPlacement` (worktree root vs subdirectory, non-repo skip, SSH skip); canonical + case-insensitive "Other worktrees" dedup; service add/remove via injected runner | `tests/unit/Features/VibeSpace/WorktreeServiceTests.swift` |

## Open Questions
- Remote (SSH) worktree support (deferred).
- Surfacing worktree actions over the agent CLI (deferred).

## Change History
| Date | Change | Author |
|------|--------|--------|
| 2026-06-04 | Initial draft — worktree discovery, clubbing, open/create/close/delete, service boundary | — |
| 2026-06-19 | Worktree-root identity (`ProjectGitPlacement`): subdirectory projects no longer mis-clubbed; branch sourced from porcelain list; canonical + case-insensitive path dedup (R01/R02/R08, S06/S07) | — |
