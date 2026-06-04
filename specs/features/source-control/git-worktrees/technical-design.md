# Git Worktrees — Technical Design

## Overview

Worktree discovery and mutation are isolated behind `WorktreeServicing`, injected via `AppContainer`. The unified sidebar (F053) consumes the service results to build repository/worktree nodes. Pure porcelain parsing lives in `WorktreeParser` so it is unit-testable without git.

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
- `Features/VibeSpace/Services/WorktreeService.swift` — concrete; `GitRunner` closure injectable for tests; `WorktreeParser.parse(porcelain:pathExists:)` pure.
- `Features/VibeSpace/Canvas/Views/UnifiedSidebarModels.swift` — `ProjectWorktreeInfo`, `WorktreeEntry`, `WorktreeProbeResult`, `UnifiedProjectGroup` (all `Sendable` where they cross the `Task.detached` boundary).

## Data Flow

1. Panel `.task` (keyed by vibespace + project set) and `.onReceive(.vibespaceWorktreesDidChange)` call `worktreeService.probe(paths:)`.
2. Probe resolves git-common-dir + branch per project and runs `git worktree list --porcelain` once per repo, parsed by `WorktreeParser`.
3. The panel groups projects by common-dir into `UnifiedProjectGroup` (members, title, `otherWorktrees`, `primaryPath`).
4. Mutations (`addWorktree`/`removeWorktree`) run off-main; on completion the panel re-probes.

## API / Command Contracts

- `git -C <p> rev-parse --path-format=absolute --git-common-dir` → repo identity
- `git -C <p> rev-parse --abbrev-ref HEAD` → branch
- `git -C <p> worktree list --porcelain` → all worktrees
- `git -C <repoRoot> worktree add -b <branch> <path>` → create
- `git -C <mainRoot> worktree remove [--force] <path>` → delete

## State Management
Discovered worktrees are runtime-only (never persisted). Added worktrees are persisted as normal projects (F021). `primaryPath` = parent of the git-common-dir (the main worktree).

## Dependencies
PaneWorkerExecutor (git runner), F021 add/remove project flows, F053 sidebar.

## Platform Considerations
macOS; local filesystem only. SSH paths skipped (`ssh://` prefix).

## Performance Constraints
Git runs off the main actor (`Task.detached`); one `worktree list` per repo per probe; re-probe only on vibespace/project-set change or worktree mutation.

## Migration / Rollout Notes
Additive; gated behind the opt-in unified sidebar. No persistence/schema changes.
