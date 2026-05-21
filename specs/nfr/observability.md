# NFR: Observability

## Scope

Requirements for logging, diagnostics, performance monitoring, and error reporting across all components.

## Requirements

### OBS-1: Structured Logging

- All backend code MUST use a structured, leveled logging framework.
- Log levels: `error` (user-visible failures), `warn` (recoverable issues), `info` (lifecycle events), `debug` (development detail), `trace` (hot-path, off by default).
- Every log event MUST include source module and relevant context identifiers (e.g., session ID, vibespace ID).
- Frontend errors MUST be forwarded to the backend for unified log collection.

### OBS-2: Event Categories

All structured events MUST be categorized:

| Category | Scope |
|---|---|
| `lifecycle` | Application start, shutdown, window events |
| `vibespace` | VibeSpace create, open, close, persist, hydrate |
| `feature` | Feature-specific operations and state transitions |
| `performance` | Timing measurements for key operations |
| `error` | Unhandled exceptions, IPC failures, I/O errors |

### OBS-3: Diagnostics Export

- The application MUST support exporting a diagnostics snapshot on demand.
- Snapshot includes: app version, OS version, active state summary, recent log tail, resource usage.
- Format: JSON.
- Snapshot MUST NOT include user content, secrets, or identifiable file paths (paths tokenized or hashed).

### OBS-4: Performance Instrumentation

- Application startup time MUST be measured and logged.
- Key user-facing operations MUST be instrumented with duration spans (not manual timers).
- No performance regression > 5% for critical paths between releases.

### OBS-5: Error Handling

- Unrecoverable backend errors MUST be caught at the top level, logged, and surfaced to the user before exit.
- Backend-to-frontend errors MUST use structured error types — not raw strings.
- Unhandled frontend errors MUST be caught and forwarded to the backend log.

### OBS-6: Log Configuration

- Debug builds: verbose logging to stdout and rotating log file.
- Release builds: `info` level by default, configurable via environment variable.
- A CLI flag MUST enable verbose logging in release builds.

### OBS-7: Health Reporting

- Long-running subsystems MUST report health status (running, degraded, stopped).
- Resource-limited subsystems (file watchers, process pools) MUST report when approaching OS limits.

## Verification

- CI tests verify lifecycle events are emitted for key operations.
- Diagnostics export tested in integration tests.
- No unstructured print statements in production code.
