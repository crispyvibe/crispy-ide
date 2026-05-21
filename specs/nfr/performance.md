# NFR: Performance

## Scope

Performance budgets and constraints applicable to all components of the application.

## Requirements

### PERF-1: Startup

- Cold start to first interactive window MUST be under 500ms on supported hardware.
- VibeSpace hydration (restoring persisted state) MUST complete within 1 second for up to 10 projects.
- No blocking I/O on the main/UI thread during startup.

### PERF-2: Memory

- Idle memory usage (one vibespace, no active operations) MUST stay under 100MB.
- Each additional subsystem instance (session, preview, watcher) MUST NOT exceed 20MB incremental.
- Memory MUST NOT grow unboundedly over time — long-running sessions MUST cap buffers and caches.

### PERF-3: UI Responsiveness

- UI interactions (clicks, key presses, navigation) MUST respond within 100ms.
- Animations MUST target 60fps. Frame drops below 30fps are considered defects.
- Heavy operations (file scanning, git status, search) MUST run off the UI thread with progress indication.

### PERF-4: File Operations

- Opening a file under 1MB MUST complete within 200ms.
- Directory listing of 10,000 entries MUST complete within 500ms.
- File watching MUST detect changes within 1 second of the OS event.

### PERF-5: Rendering

- Content previews (markdown, code, images) MUST render within 300ms for files under 1MB.
- Scrolling through rendered content MUST maintain 60fps.
- Large files (>5MB) MAY defer full rendering with a user-visible loading indicator.

### PERF-6: Measurement

- All performance budgets MUST be validated by automated benchmarks in CI.
- Regressions exceeding 10% on any budget MUST block the PR.
- Key metrics MUST be logged via the observability framework (OBS-4) for production monitoring.

## Verification

- CI benchmark suite covering startup, hydration, file open, and render paths.
- Memory profiling in CI for idle and loaded states.
- Manual performance audit before each release on minimum supported hardware.
