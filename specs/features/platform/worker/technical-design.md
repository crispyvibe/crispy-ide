# Worker — Technical Design

## Overview

Worker provides the out-of-process execution model for pane operations (filesystem, git, editor, terminal). The host app spawns its own executable with `--pane-task <pane-kind>`, communicates via JSON over stdin/stdout, and enforces timeouts and generation guards. Instrumentation is layered via `MeasuredPaneWorker` (os_signpost) and long-lived subprocesses via `PaneWorkerPersistentSession`.

## Architecture

### Execution Model

- `PaneWorkerExecutionMode.resolve()` selects between `inProcess` (task runs in host process) and `subprocess` (launches external executable).
- Subprocess mode: the app executable is spawned with `--pane-task <pane-kind>`, request JSON is written to stdin, response JSON is read from stdout.
- Each request carries a generation token; stale responses from older generations are discarded.

### Protocol Stack

```
┌─────────────────────────────────┐
│  PaneWorkerExecuting (protocol) │  ← uniform API for all pane methods
├─────────────────────────────────┤
│  MeasuredPaneWorker (decorator) │  ← os_signpost instrumentation
├─────────────────────────────────┤
│  PaneWorkerPersistentSession    │  ← long-lived subprocess, NDJSON
├─────────────────────────────────┤
│  Subprocess (Process)           │  ← app executable --pane-task
└─────────────────────────────────┘
```

### Method Domains

| Domain | Methods |
|---|---|
| Explorer | `listTree`, `createFile`, `createFolder`, `rename`, `delete`, `move`, `copyItem` |
| Git | `status`, `diff`, `branches`, `stage`, `unstage`, `stageAll`, `unstageAll`, `commit`, `push`, `pull`, `fetch`, `checkout`, `clone`, `discard`, `discardAll`, `discoverRepositories`, `discoverRepositoriesBatch`, `repositorySnapshot`, `fileContent`, `fileHistory`, `commitHistory`, `currentBranch`, `gitHubCloneOptions`, `gitCloneRepository` |
| Editor | `readFile`, `writeFile` |
| Terminal | `ping`, `gitCurrentBranch` |

## Data Flow

### Request/Response Cycle

1. Host encodes request as JSON, writes to subprocess stdin.
2. Subprocess executes the operation, encodes response as JSON, writes to stdout.
3. Host reads response, validates generation, delivers result to caller.
4. If timeout expires before response, the subprocess is terminated and caller receives a timeout error.

### Persistent Session

`PaneWorkerPersistentSession` keeps a long-lived subprocess alive across multiple requests using newline-delimited JSON (NDJSON). The subprocess is reused until explicitly torn down or the session is invalidated.

### Git Probe Caching

- `isGitAvailable` and `isGitRepository` results are cached with a TTL.
- Expired entries re-execute the probe and refresh the cache.

## API / Command Contracts

### Response Contract

All methods return a uniform envelope:

```json
// Success
{ "success": true, "value": { ... } }

// Failure
{ "success": false, "error": "localized failure message" }
```

### Explorer Contracts

- `listTree` — returns immediate children only; skips package descendants; includes hidden entries with metadata flags; annotates git-ignored entries; sorts directories first.
- `createFile` / `createFolder` — collision-safe naming with numeric suffix (`name 1`, `name 2`, …).
- `rename` — validates non-empty name, checks destination conflicts.
- `move` — validates destination exists and is a directory, rejects self-move into descendant.
- `delete` — removes file or directory at path.
- `copyItem` — copies file or folder to target path.

### Git Contracts

- `status` — parses porcelain v1 z-format; extracts index/worktree status per entry; resolves rename/copy to destination path; builds absolute paths from project root; sorts case-insensitively.
- `diff` — returns `Staged Changes` and `Working Tree Changes` sections; falls back to porcelain status when textual diff is unavailable.
- `branches` — returns local and remote refs with current branch marker.
- `repositorySnapshot` — combined status + branches in a single call.
- `commitHistory` / `fileHistory` — bounded commit entries, newest first.
- `fileContent` — returns file content at HEAD revision.

### Editor Contracts

- `readFile` — attempts UTF-8, UTF-16, ISO Latin-1 in order; fails with unsupported encoding error.
- `writeFile` — atomic UTF-8 write; fails with encoding error if content is not encodable.

### Terminal Contracts

- `ping` — returns timestamp.
- `gitCurrentBranch` — returns branch name for given repository root.
- Unknown methods return unsupported method error.

## State Management

- Pane status transitions: `healthy` → `busy` (request in flight) → `healthy` (success) or `unavailable` (failure with user-facing message).
- Generation counter increments on worker client restart; in-flight responses from prior generations are discarded.
- Git probe cache is per-worker-session with configurable TTL.

## Dependencies (frameworks, libraries)

- `Foundation` — `Process`, JSON encoding/decoding
- `os` — `OSSignposter` for `MeasuredPaneWorker` instrumentation
- Git CLI — invoked by worker subprocess for all git operations

## Platform Considerations

- Worker subprocess is the same app executable, ensuring consistent runtime environment.
- SSH-backed operations (remote file-service) retry readiness with bounded async backoff before failing; retries do not block the main thread.
- Materialized local preview URLs: for remote SSH projects, the editor stages a temporary local file from remote bytes before handing off to native image/PDF renderers.
- Git availability is probed via `git --version`; if unavailable, all git methods report `gitAvailable=false`.

## Performance Constraints

- Worker subprocess expected to spawn within 100ms.
- Timeout termination prevents stale processes from accumulating.
- `MeasuredPaneWorker` os_signpost intervals enable Instruments profiling without runtime overhead when not recording.
- Persistent sessions amortize subprocess launch cost across multiple requests.
- Git probe caching avoids redundant `git --version` / `git rev-parse` calls within TTL window.

## Migration / Rollout Notes

_None._
