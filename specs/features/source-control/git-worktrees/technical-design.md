# Git Worktrees — Technical Design

## Overview

Worktree discovery and mutation are isolated behind `WorktreeServicing`, injected via `AppContainer`. The unified sidebar (F056) consumes the service results to build repository/worktree nodes. Pure porcelain parsing lives in `WorktreeParser` so it is unit-testable without git.

## Architecture

```
VibeSpaceSidebarPanelView ──uses──> WorktreeServicing (injected)
        │                                  ▲
        │ builds groups                    │ conforms
        ▼                                  │
UnifiedProjectGroup            WorktreeService (Features/VibeSpace/Services/)
                                    │ runGit closure (default: PaneWorkerExecutor)
                                    │ parses with WorktreeParser (pure)
```

- `Protocols/WorktreeServicing.swift` — `probe(paths:)`, `addWorktree(repoRoot:worktreePath:branch:)`, `removeWorktree(path:force:)`.
- `Features/VibeSpace/Services/WorktreeService.swift` — concrete; `GitRunner` closure injectable for tests; `WorktreeParser.parse(porcelain:pathExists:resolve:)` pure. `WorktreeParser.resolveCanonical(_:)` symlink-resolves a path (filesystem touch — runs in the service, never in a SwiftUI body).
- `Features/VibeSpace/Canvas/Views/UnifiedSidebarModels.swift` — `ProjectGitPlacement`, `WorktreeEntry`, `WorktreeProbeResult`, `UnifiedProjectGroup` (all `Sendable` where they cross the `Task.detached` boundary).

### Identity model: `ProjectGitPlacement`

Each opened project resolves to a `ProjectGitPlacement`:

- `commonDir` — shared git-common-dir; the repository identity used for clubbing.
- `worktreeRoot` — the symlink-resolved `git rev-parse --show-toplevel`: the root of the worktree the project lives in.
- `relativeSubpath` — the project folder's path relative to `worktreeRoot`; `""` when the project IS the worktree root.
- `isWorktreeRoot` (computed) — `relativeSubpath.isEmpty`.

A project is treated as a worktree only when `isWorktreeRoot`. A **subdirectory opened as its own project** shares the repo's `commonDir` but has a non-empty `relativeSubpath`, so it renders as a standalone node — never clubbed under, nor mislabeled as, the worktree it lives in. `relativeSubpath` is computed case-insensitively (default APFS volumes are case-insensitive); a non-descendant path falls back to the project's own folder name so it stays standalone. Branch is intentionally **not** stored on the placement — it is read from the authoritative porcelain `WorktreeEntry` for `worktreeRoot` (one source of truth), so a subdirectory project and its worktree can never disagree.

`WorktreeEntry` carries a `canonicalPath` (symlink-resolved real path, matching what git reports). `WorktreeEntry.notOpened(_:openedCanonicalPaths:)` dedups the "Other worktrees" group against opened projects by canonical path, case-insensitively — so a project opened via a symlinked or differently-cased path does not duplicate in the list.

## Data Flow

1. Panel `.task` (keyed by vibespace + project set) and `.onReceive(.vibespaceWorktreesDidChange)` call `worktreeService.probe(paths:)`.
2. Probe resolves git-common-dir + worktree root (`--show-toplevel`) per project into a `ProjectGitPlacement`, and runs `git worktree list --porcelain` once per repo, parsed by `WorktreeParser`. Branch is read from the parsed porcelain list keyed by the worktree root, not from a per-project query.
3. The panel clubs only `isWorktreeRoot` projects by common-dir into `UnifiedProjectGroup` (members, title, `otherWorktrees`, `primaryPath`); subdirectory and non-git projects always render standalone. `otherWorktrees` is the repo's porcelain worktrees minus the opened roots, deduped by canonical path via `WorktreeEntry.notOpened`.
4. Mutations (`addWorktree`/`removeWorktree`) run off-main; on completion the panel re-probes.

## API / Command Contracts

- `git -C <p> rev-parse --path-format=absolute --git-common-dir` → repo identity
- `git -C <p> rev-parse --show-toplevel` → worktree root (symlink-resolved for identity matching)
- `git -C <p> worktree list --porcelain` → all worktrees (source of truth for branches)
- `git -C <repoRoot> worktree add -b <branch> <path>` → create
- `git -C <mainRoot> worktree remove [--force] <path>` → delete

## State Management
Discovered worktrees are runtime-only (never persisted). Added worktrees are persisted as normal projects (F021). `primaryPath` = parent of the git-common-dir (the main worktree).

## Dependencies
PaneWorkerExecutor (git runner), F021 add/remove project flows, F056 sidebar.

## Platform Considerations
macOS; local filesystem only. SSH paths skipped (`ssh://` prefix).

## Performance Constraints
Git runs off the main actor (`Task.detached`); one `worktree list` per repo per probe; re-probe only on vibespace/project-set change or worktree mutation.

## Migration / Rollout Notes
Additive; surfaced through the unified "Workspace" sidebar (now the default side-panel layout, `AppShellStore.vibespaceSidebarUnified` default `true`). No persistence/schema changes.
