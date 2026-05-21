# NFR: Reliability

## Scope

Requirements for crash recovery, data integrity, and graceful degradation across all components.

## Requirements

### REL-1: Crash Recovery

- The application MUST persist critical state (open vibespaces, active sessions, unsaved drafts) at regular intervals — not only on explicit save.
- On restart after a crash, the application MUST offer to restore the previous session state.
- Corrupted state files MUST be detected (via integrity checks per SEC-2) and discarded with a user notification — never silently loaded.

### REL-2: Data Loss Prevention

- Unsaved changes MUST be auto-persisted at a configurable interval (default: 30 seconds).
- Closing a vibespace or the application with unsaved changes MUST prompt the user for confirmation.
- Write operations MUST use atomic file writes (write to temp, then rename) to prevent partial writes on crash or power loss.

### REL-3: Graceful Degradation

- Failure of a non-critical subsystem (file watcher, preview renderer, git status) MUST NOT crash the application.
- Failed subsystems MUST report their status (OBS-7) and allow manual retry.
- If a child process (PTY, worker) dies unexpectedly, the UI MUST reflect the failure state and allow restart — not hang or go blank.

### REL-4: Resource Limits

- The application MUST enforce upper bounds on concurrent child processes, open file handles, and active watchers.
- Approaching OS resource limits MUST trigger warnings (OBS-7), not silent failures.
- Buffer and cache sizes MUST be capped with eviction policies — no unbounded growth.

### REL-5: Idempotency

- Persistence operations (save, hydrate, export) MUST be idempotent — repeated calls produce the same result.
- Interrupted operations MUST leave state in a consistent, recoverable condition.

### REL-6: Shutdown

- Application shutdown MUST complete within 5 seconds.
- All child processes MUST be terminated on shutdown — no orphaned processes.
- Pending writes MUST be flushed before exit.

## Verification

- Integration tests for crash recovery: kill process mid-operation, verify state restores.
- Tests for atomic write correctness: simulate write interruption.
- Tests for subsystem failure isolation: kill child process, verify app remains functional.
- CI enforces no orphaned processes after test suite completion.
