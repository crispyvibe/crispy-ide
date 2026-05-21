# Git Operations — Technical Design

## Overview

Git operations run on a dedicated pane-worker lane (`sourceControl` kind) with a persistent helper session. Repository discovery is vibespace-scoped, publishing incrementally per project. Local repositories use a single `gitRepositorySnapshot` round trip combining status, branches, and availability checks. File watching uses filtered `DirectoryWatcher` (FSEvents) for locals and polling for remotes.

## Architecture

### Worker Runtime

`AppContainer` creates one shared `PaneWorkerClient` for the `sourceControl` kind, reused across the app lifetime. This dedicated lane avoids contention with the explorer worker.

The `gitRepositorySnapshot` worker request combines:

- Git availability check
- Repository validation
- `git status --porcelain=v1 -z -uall`
- Branch enumeration

into one round trip, avoiding separate calls for status and branches.

The helper process keeps worker-local git probe caches alive across requests. Process/pipe cleanup is hardened so terminated or timed-out git subprocesses do not leave pipe readers or termination waits behind.

### Repository Discovery

Discovery runs project-by-project across the active vibespace, publishing progress incrementally.

- Local projects → `sourceControl` pane worker with `gitDiscoverRepositories`.
- Remote projects → project's SSH-backed `gitExplorer`.

Discovered repositories deduplicated by root path. Sorted by multi-key: repositories containing selected file rank first (deeper paths preferred) → focused project → earliest attached project order index → alphabetical by path.

Each repository associated with attached projects (project path inside repo root, or repo root inside project path). Existing view models reused across refreshes when root path matches.

Discovery failures accumulated per project. Git unavailable on one project does not discard repositories from others; view model remains `ready` if discovery can produce state elsewhere.

### Repository State Machine

Top-level view model states:

| State | Condition |
|-------|-----------|
| `idle` | No projects open |
| `loading` | Discovery in progress, no repositories loaded yet |
| `ready` | At least one discovery cycle completed |
| `gitUnavailable` | Discovery payload indicated Git not installed |
| `error` | Discovery failed with exception |

Per-repository states: `idle`, `loading`, `ready`, `error`.

## Data Flow

### Status Items

Each status item carries:

- Two-character git status code (index status + work-tree status)
- Relative path within repository
- Resolved file URL

Classification:

| Category | Condition |
|----------|-----------|
| Staged | Index status ≠ space, not untracked |
| Unstaged/changed | Work-tree status ≠ space, or untracked, or not staged |
| Untracked | Status `??`, or either status is `?` |
| Deleted | Status contains `D` |

`lacksCommittedHistory` when untracked or index status `A`.

Capability flags: `canStage` (unstaged/untracked), `canUnstage` (staged), `canDiscardChanges` (unstaged, not untracked).

Pending change count = total status items per repo. Top-level sums across all repositories.

### Mutation Operations

All mutations follow the same pattern: set `isOperating` → display activity message → execute worker method with timeout → refresh on success → clear message and show error on failure.

| Operation | Worker Method | Timeout |
|-----------|--------------|---------|
| Stage | `gitStage` (relative path) | 12 s |
| Unstage | `gitUnstage` (relative path) | 12 s |
| Stage all | `gitStageAll` (repo root) | 12 s |
| Discard | `gitDiscard` (relative path) | 12 s |
| Discard all | `gitDiscardAll` (repo root) | 12 s |
| Commit | `gitCommit` (trimmed message) | 12 s |
| Push | `gitPush` (repo root) | 12 s |

Commit validates non-empty message after trimming whitespace. On success, clears commit draft.

### Branch Management

Current branch name and branch options loaded as part of `gitRepositorySnapshot`. Remote repositories may issue separate requests via SSH backend. Each branch option: name, display name, current flag, remote flag.

Checkout: `gitCheckoutBranch` with branch name and remote flag. Refreshes status and branches on success.

### History

Two scopes:

- **Repository** — last 100 commits via `gitCommitHistory`.
- **File** — last 100 commits for a relative path via `gitFileHistory`.

Each entry: full hash, short hash, author name, authored date, subject line. Opening clears previous entries and sets loading flag. Dismissing clears scope, entries, and loading state.

## State Management

### File Watching

Local projects: root-scoped `DirectoryWatcher` (FSEvents). Remote projects: `observedFileSystemChanges` from polling watcher.

Watchers torn down and rebound when project sessions change.

Changed paths accumulated into pending set. Debounce: **250 milliseconds** (reset on new changes, previous task cancelled).

Path filtering before queue entry:

- Configured ignored/generated directories skipped.
- Internal `.git` churn (`.git/index`, object storage, logs) skipped.
- User-visible refs allowed: `.git/HEAD`, `FETCH_HEAD`, `ORIG_HEAD`, `packed-refs`, `refs/...`.

Queue consumption:

- Changed path matched to deepest repository whose root contains it → that repository refreshed.
- Path within project but no matching repository → full discovery refresh.
- State not `ready` or no repositories → queue discarded.

### Refresh Coalescing

Each repository coalesces refreshes: if refresh in flight when another arrives, follow-up queued and runs after current snapshot completes.

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| `gitDiscoverRepositories` | — | Discover repos in vibespace |
| `gitRepositorySnapshot` | 12 s | Combined status + branches |
| `gitStage` / `gitUnstage` | 12 s | Index mutations |
| `gitStageAll` | 12 s | Stage all changes |
| `gitDiscard` / `gitDiscardAll` | 12 s | Working tree restore |
| `gitCommit` | 12 s | Commit staged changes |
| `gitPush` | 12 s | Push current branch |
| `gitCheckoutBranch` | 12 s | Branch checkout |
| `gitCommitHistory` / `gitFileHistory` | 12 s | Commit log (100 entries) |

### Source Control Settings

| Setting | Range | Default |
|---------|-------|---------|
| Ignored directory names | — | `.build`, `.cache`, `.derived`, `.next`, `.nuxt`, `.swiftpm`, `Build`, `Carthage`, `DerivedData`, `Pods`, `SourcePackages`, `build`, `checkouts`, `dist`, `node_modules`, `out` |
| Scan max depth | 1–16 | 8 |
| Scan max repositories | 1–256 | 64 |
| Auto-presented repository limit | 1–48 | 12 |

Settings normalized: names trimmed, deduplicated case-insensitively, sorted; numerics clamped. Changes to project paths or settings trigger full discovery refresh.

## Dependencies (frameworks, libraries)

- `PaneWorkerClient` (sourceControl kind) — dedicated worker lane
- `DirectoryWatcher` — FSEvents-backed file monitoring
- `VibeSpaceSourceControlViewModel` — vibespace-level discovery and presentation
- `FolderExplorerViewModel` — per-project git state

## Platform Considerations

- FSEvents for local file watching; polling for remote (SSH-backed).
- Git subprocess cleanup hardened to prevent leaked pipe readers.
- Worker-local git probe caches persist across requests.

## Performance Constraints

- All mutation operations: 12-second timeout.
- File watcher debounce: 250 milliseconds.
- History limited to 100 entries per scope.
- Auto-presented repository limit: 12 (configurable up to 48).
- Refresh coalescing prevents overlapping snapshots per repository.
