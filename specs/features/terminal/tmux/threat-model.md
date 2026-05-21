# tmux Integration — Threat Model

## Overview

tmux Integration wraps terminal sessions in persistent tmux sessions, managing binary detection, session creation/reattach/kill, server option application, and session listing. All tmux interactions use `Process` with explicit argument arrays — no shell interpretation. The threat surface centers on tmux session name injection, binary path trust, synchronous process execution blocking, and orphaned session information disclosure.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app process ↔ tmux binary | `TmuxService` invokes the tmux binary via `Process` with `executableURL` and `arguments` array. Arguments are never shell-interpreted. The binary path is resolved from a hardcoded candidate list. |
| tmux session namespace ↔ Crispy sessions | Session names use the `crispyvibes-` prefix followed by a UUID fragment. The prefix acts as a namespace boundary for bulk operations (`killAllCrispyVibesSessions`). |
| Persistence JSON ↔ tmux session name | `TerminalSessionEntry.tmuxSessionName` is decoded from vibespace JSON and passed directly to tmux `-s` argument. |
| tmux server ↔ other local users | The tmux server socket is user-scoped (`/tmp/tmux-{uid}/`). Other users on the same machine cannot access it under default permissions. |
| tmux `list-sessions` output ↔ Session manager UI | Raw tmux output is parsed by tab-splitting. Malformed output could produce unexpected UI content. |

## Attack Surfaces

1. **tmux session name as `-t` / `-s` argument** — Session names from persistence or generated UUIDs are passed to tmux commands. A tampered persistence file could inject metacharacters.
2. **tmux binary path resolution** — Hardcoded paths (`/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, `/usr/bin/tmux`) are checked in order. A malicious binary placed at a higher-priority path would be executed.
3. **Synchronous `Process.waitUntilExit()`** — `applyServerOptions()` and `run()` block the calling thread. A hung tmux process could stall the app.
4. **tmux `list-sessions` output parsing** — Tab-delimited output is parsed without strict validation. Crafted session names containing tabs or newlines could confuse parsing.
5. **Pane command extraction** — `paneCommand()` reads `#{pane_current_command}` from tmux. The result is displayed in the session manager UI.
6. **Bulk kill operations** — `killAllCrispyVibesSessions()` kills all sessions matching the `crispyvibes-` prefix. A race condition could kill a session created between list and kill.

## Threats

### F010-T01: Session name injection via tampered persistence

- **Vector:** An attacker modifies the vibespace JSON to set `tmuxSessionName` to a value containing shell metacharacters (e.g., `; rm -rf /` or newlines). This name is passed as the `-s` argument to `tmux new-session -A`.
- **Impact:** No shell injection — `Process.arguments` passes each element as a discrete argv entry, not through a shell. However, tmux itself may interpret certain characters in session names (e.g., `:` as pane separator, `.` as window separator).
- **Likelihood:** Very low — persistence is HMAC-signed; tmux session names are generated as `crispyvibes-` + UUID prefix (alphanumeric + hyphen only).
- **Mitigation:** Session names are generated via `generateSessionName()` using UUID prefix (safe character set). Persisted names originate from this generator. `Process.arguments` array prevents shell interpretation. HMAC signing on persistence detects tampering. Linked NFR: SEC-Input-Sanitization.

### F010-T02: Malicious tmux binary at higher-priority path

- **Vector:** An attacker places a malicious executable at `/opt/homebrew/bin/tmux` (which is checked first). If the user has Homebrew installed but tmux is not the expected binary, Crispy executes the attacker's code.
- **Impact:** Arbitrary code execution as the user on every terminal session launch when tmux is enabled.
- **Likelihood:** Very low — requires write access to `/opt/homebrew/bin/` which is user-owned but typically managed by Homebrew.
- **Mitigation:** `tmuxPath` uses `FileManager.default.isExecutableFile(atPath:)` to verify the candidate exists and is executable. The paths are hardcoded system locations (not user-writable temp directories). Users who enable tmux integration implicitly trust their Homebrew installation. No additional signature verification is performed. Linked NFR: SEC-Input-Sanitization.

### F010-T03: Main thread stall from hung tmux process

- **Vector:** `applyServerOptions()` calls `run()` which uses `process.waitUntilExit()` synchronously. If the tmux server is hung or the binary blocks indefinitely, the calling thread stalls.
- **Impact:** UI freeze if called on the main thread; utility thread stall if called from `DispatchQueue.global`.
- **Likelihood:** Low — tmux operations are typically fast (<100ms). A corrupted tmux server socket or resource exhaustion could trigger this.
- **Mitigation:** `applyServerOptions()` is called from `launchArguments()` which runs during session start (already off main actor via `startProcessAsync`). `killSessionAsync()` dispatches to `DispatchQueue.global(qos: .utility)`. `listSessionDetailsAsync()` uses `Task.detached`. The synchronous `run()` helper redirects stdout/stderr to null device to prevent pipe buffer deadlocks. Linked NFR: PERF-Responsiveness.

### F010-T04: Information disclosure via session listing

- **Vector:** `listSessionDetails()` returns working directories and current commands for all `crispyvibes-` prefixed sessions. If the session manager UI is visible, another person viewing the screen sees directory paths and running commands.
- **Impact:** Disclosure of working directory paths and command names (e.g., `ssh user@host`, database CLI tools).
- **Likelihood:** Low — requires physical access or screen sharing while the session manager sheet is open.
- **Mitigation:** The session manager is only accessible via Settings > Terminal > Manage Sessions (not always visible). Working directories and commands are standard tmux metadata already visible via `tmux ls` in any terminal. No secrets are extracted. Linked NFR: SEC-Data-Protection.

### F010-T05: Race condition in bulk session cleanup

- **Vector:** `killAllCrispyVibesSessions()` lists sessions then kills each one sequentially. A new session created between the list and kill operations survives cleanup. Conversely, a session terminated externally between list and kill produces a benign error.
- **Impact:** Incomplete cleanup — orphaned sessions may persist. No data loss or security impact.
- **Likelihood:** Low — bulk cleanup is a manual user action; session creation during cleanup is unlikely.
- **Mitigation:** `killSession()` is idempotent — killing a non-existent session produces no error (tmux exits with non-zero, which is ignored via `try?`). Users can refresh the session list and re-run cleanup. Linked NFR: REL-Reliability.

### F010-T06: tmux output parsing confusion from crafted session names

- **Vector:** If a non-Crispy tmux session has a name containing tab characters or newlines, `listSessionDetails()` parsing (tab-split) could misalign fields, producing incorrect working directory or command display.
- **Impact:** UI confusion — wrong metadata displayed for a session row. No code execution.
- **Likelihood:** Very low — tmux session names cannot contain newlines (tmux rejects them). Tab characters are theoretically possible but extremely unusual.
- **Mitigation:** The parser uses `split(separator: "\t", omittingEmptySubsequences: false)` and validates `parts.count >= 5` before constructing `SessionInfo`. Malformed lines are skipped via `compactMap`. The session manager only displays data — it does not use parsed fields for command execution. Linked NFR: SEC-Input-Sanitization.

### F010-T07: Orphaned session accumulation as resource exhaustion

- **Vector:** With "On tab close" set to "Detach (keep alive)", closing many tabs accumulates orphaned tmux sessions. Each orphan holds a shell process, file descriptors, and scrollback memory.
- **Impact:** Gradual resource exhaustion (memory, process table entries) on the local machine.
- **Likelihood:** Medium — users who frequently open/close tabs with detach behavior will accumulate orphans.
- **Mitigation:** The session manager UI surfaces orphaned sessions with "Kill" and "Kill All Orphans" actions. `killAllCrispyVibesSessions()` provides bulk cleanup. The default "On tab close" behavior is "Terminate" which kills the session immediately. Linked NFR: PERF-Responsiveness.

## Residual Risks

- Crispy trusts the tmux binary at the resolved path without signature verification. A compromised Homebrew installation could substitute a malicious binary. This is a system-level trust assumption shared by all CLI tools.
- The tmux server socket permissions are managed by tmux itself (mode 0700 on the socket directory). Crispy does not verify socket permissions.
- `waitUntilExit()` has no timeout. An extremely slow tmux operation could block a utility thread indefinitely, though this would not freeze the UI.
- Session names from persistence are trusted after HMAC validation. If the HMAC key is compromised, arbitrary session names could be injected.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | `Process.arguments` array used exclusively; no shell string interpolation; session names are UUID-derived. |
| SEC-Data-Protection | Compliant | HMAC-signed persistence; session metadata is standard tmux info (no secrets extracted). |
| PERF-Responsiveness | Compliant | Async variants for kill and list operations; server options applied during off-main-actor session start. |
| A11Y | Compliant | Session manager UI is keyboard-navigable per spec acceptance criteria. |
| OBS | Compliant | tmux lifecycle events logged via `AppDiagnostics`; session start metadata includes tmux flag. |
