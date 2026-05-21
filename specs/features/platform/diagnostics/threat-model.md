# Diagnostics — Threat Model

## Overview

Diagnostics provides developer tools for inspecting app operations, terminal sessions, ACP observability, and metrics. It includes a diagnostics export feature that bundles app state into a JSON file. The primary threat surface is information disclosure through exported diagnostics and the in-memory event store, plus resource exhaustion from unbounded metric collection.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Diagnostics UI ↔ In-memory stores | Developer Tools reads from `DiagnosticsEventStore`, `OperationMetricsStore`, and `ACPObservabilityStore` — all in-memory ring buffers. |
| Diagnostics export ↔ Local filesystem | Export writes a JSON file to a user-chosen location via NSSavePanel. |
| App process ↔ os_signpost/OSLog | `MeasuredPaneWorker` emits signpost intervals to the system logging subsystem. |
| Terminal diagnostics ↔ ~/Library/Logs/ | Terminal snapshot export writes JSON to `~/Library/Logs/CrispyVibes/`. |

## Attack Surfaces

1. **Diagnostics export JSON file** — contains app version, bundle ID, macOS version, defaults snapshot, vibespace summary, operation metrics, ACP events, and diagnostic events. Written to user-chosen path.
2. **Path sanitization in export** — file paths are replaced with SHA-256 tokens (`path#<12-char-prefix>`). If sanitization is incomplete, real paths could leak.
3. **DiagnosticsEventStore** — in-memory ring buffer (1500 events) containing auth events, terminal lifecycle, and remote session metadata.
4. **ACP observability store** — contains agent session details, turn summaries, and event metadata including project tokens and agent IDs.
5. **Terminal diagnostics snapshot** — per-vibespace session counts, startup latencies, written to `~/Library/Logs/`.
6. **UserDefaults snapshot in export** — raw key-value dump of app preferences.

## Threats

### F032-T01: Sensitive data leakage in diagnostics export

- **Vector:** The diagnostics export includes a `defaultsSnapshot` (UserDefaults dump), vibespace catalog JSON, and operation metrics. If the user shares this file for support, it could contain Cognito domain, client ID, SSH hostnames, project paths (even after sanitization), and custom CLI commands.
- **Impact:** Information disclosure of configuration, project structure hints, and potentially sensitive preference values.
- **Likelihood:** Medium — export is designed to be shared for debugging.
- **Mitigation:** File paths MUST be sanitized to SHA-256 tokens via `AppDiagnostics.pathToken()` (confirmed: `"path#" + sha256Hex(path).prefix(12)`). The export MUST NOT include keychain tokens, SSH private keys, or raw file contents. UserDefaults snapshot should exclude keys containing "token", "secret", or "key" values. Linked NFR: SEC-Data-Protection.

### F032-T02: Incomplete path sanitization

- **Vector:** The path sanitization regex replaces strings starting with "/" or containing "/Users/". Paths in non-standard formats (e.g., `~/.ssh/config`, relative paths, or paths embedded in error messages) may not be caught.
- **Impact:** Real filesystem paths leaked in export, revealing username and directory structure.
- **Likelihood:** Medium — error messages often contain unsanitized paths.
- **Mitigation:** Path sanitization MUST be applied to all string values in the export payload, not just known path fields. The `sanitizeDiagnosticValue` function truncates at 600 chars. Export consumers should treat the file as potentially containing residual path fragments. Linked NFR: SEC-Data-Protection.

### F032-T03: Auth event metadata contains sensitive fragments

- **Vector:** Auth diagnostic events include metadata like `domain`, `client_id` (masked), `error` descriptions, and `response_body` (on token exchange failure). Error messages from Cognito could contain user-identifying information.
- **Impact:** Partial credential or identity information in the event store and export.
- **Likelihood:** Low — `clientIdDiagnosticToken` shows only last 6 chars; `sanitizeDiagnosticValue` truncates.
- **Mitigation:** Auth metadata uses `clientIdDiagnosticToken()` (last 6 chars only). Response bodies are truncated via `sanitizeDiagnosticValue(limit: 600)`. Token values are never logged. The event store is capped at 1500 entries (oldest evicted). Linked NFR: SEC-Data-Protection.

### F032-T04: Resource exhaustion via unbounded metric recording

- **Vector:** A rapid sequence of pane worker operations (e.g., recursive file listing, rapid git status polling) could flood the `OperationMetricsStore` and `ACPObservabilityStore`.
- **Impact:** Memory pressure from ring buffer churn; potential main-thread stalls from lock contention.
- **Likelihood:** Low — ring buffers have fixed capacity (500 for metrics, 500 for ACP events, 100 for turns).
- **Mitigation:** All stores use fixed-capacity ring buffers that overwrite oldest entries. `OperationMetricsStore` capacity is 500. `ACPObservabilityStore` capacity is 500 events, 100 turns. `DiagnosticsEventStore` is capped at 1500. Stale traces (>5 min) are auto-pruned. NSLock is used for thread safety. Linked NFR: PERF-Responsiveness.

### F032-T05: Terminal diagnostics snapshot written to predictable path

- **Vector:** Terminal diagnostics snapshots are written to `~/Library/Logs/CrispyVibes/` with ISO 8601 timestamp filenames. A local attacker could monitor this directory for new files to extract session metadata.
- **Impact:** Disclosure of terminal session counts, startup latencies, and vibespace UUIDs.
- **Likelihood:** Very low — requires same-user access (already has full app access).
- **Mitigation:** The logs directory is within the user's Library (standard macOS convention). Snapshots contain only aggregate metrics, not terminal content or commands. File permissions follow the user's umask. Linked NFR: SEC-Data-Protection.

### F032-T06: ACP probe connects to arbitrary agent processes

- **Vector:** The ACP probe in Developer Tools allows connecting to an installed agent. If agent discovery is not validated, a malicious process could masquerade as an agent.
- **Impact:** Probe sends prompts to and displays responses from an untrusted process.
- **Likelihood:** Low — agent discovery uses the ACP agent registry which validates installed agents.
- **Mitigation:** Agent connections go through the standard ACP transport layer with its existing trust model. Probe is a developer tool requiring explicit user action (Cmd+Option+D, then manual agent selection and Connect). Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- The diagnostics export is inherently an information-disclosure feature by design. Users sharing export files accept the risk of revealing app configuration details.
- os_signpost data is visible to any process using Instruments or `log` CLI on the same machine. This is standard macOS behavior.
- The 2-second auto-refresh timer in Developer Tools adds minor ongoing CPU cost while the view is visible; invalidated on disappear.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Data-Protection | Compliant | Path sanitization; ring buffer caps; no token logging; truncation. |
| SEC-Input-Sanitization | Compliant | Agent probe uses validated registry; no user input in export paths. |
| PERF-Responsiveness | Compliant | Fixed-capacity buffers; stale trace pruning; timer invalidation. |
| OBS | Compliant | Feature is itself the observability layer. |
