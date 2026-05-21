# ACP Threat Model

**Status**: Active
**Last reviewed**: 2026-04-11
**Scope**: ACP transport, session lifecycle, client handlers, observability, agent discovery, direct integrations (CodexSession, ClaudeCodeSession)

## Architecture Summary

CrispyVibes acts as an ACP client. It spawns agent subprocesses, communicates over newline-delimited JSON-RPC on stdio, and exposes file system, terminal, and permission capabilities to the agent. The agent runs as a local subprocess with the same OS user privileges as the app.

## Trust Boundaries

1. **App ↔ Agent subprocess**: The agent is a local process. CrispyVibes trusts the agent to follow the ACP protocol but enforces project-scoped file boundaries and gates destructive operations through a permission handler.
2. **App ↔ Direct integration subprocess**: Codex and Claude Code run as local processes with their own wire protocols (JSON-RPC and NDJSON respectively). They bypass the ACP file system handler entirely — file operations happen inside the agent process, not through Crispy's handlers. The trust boundary is the agent's own sandbox/permission model, configured via CLI flags.
3. **App ↔ User preferences**: Agent selection, custom agent definitions, and trust mode settings are stored in UserDefaults. A user with write access to preferences can configure any executable as an agent.
4. **App ↔ Diagnostics export**: Observability data is exported as part of diagnostics bundles. Exported data must not contain raw prompts, file contents, or terminal output.

## Threat Categories

| Threat | Severity | Status | Behavior Change |
| --- | --- | --- | --- |
| T1 | High | Fixed | Symlinked paths that resolve outside the project now fail boundary checks instead of reading or writing the target file. |
| T2 | Medium | Fixed | ACP transport requests now fail after the timeout window instead of waiting forever on a stuck agent. |
| T3 | Medium | Fixed | ACP sessions and Developer Tools probes now ask for approval by default instead of auto-allowing operations. |
| T4 | Medium | Fixed | ACP chat retains only the most recent 50,000 timeline entries instead of growing without a bound. |
| T5 | Low | Accepted | No behavior change; the residual TOCTOU race is documented and accepted. |
| T6 | Low | Fixed | `terminal/wait_for_exit` waiters now complete when a session disconnects instead of hanging indefinitely. |
| T7 | Low | Accepted | No behavior change; custom agent executables remain a user-controlled trust decision. |
| T8 | Medium | Fixed | Direct-integration startup errors no longer expose raw stderr in the UI or logs; diagnostics keep only a hash and byte count. |
| T9 | Medium | Fixed | Deeply nested Codex JSON is truncated at the recursion cap instead of recursing without bound. |
| T10 | Low | Accepted | No behavior change; full-trust mode still disables agent-side safety by explicit user choice. |
| T11 | Low | Fixed | Codex tool output keeps only the most recent 256KB per tool call instead of buffering arbitrarily large output. |
| T12 | Low | Fixed | Claude Code prompt turns now evict old stream/tool bookkeeping instead of retaining it for the whole turn. |

### T1: File System Escape via Symlink

**Severity**: High
**Status**: Fixed

`ACPFileSystemHandler.resolvedPath` now resolves symlinks on both the candidate path and the project root before comparing boundaries. The original implementation only used `standardizedFileURL`, which normalized `..` components but still allowed symlink traversal.

**Attack scenario**:
1. Agent calls `terminal/create` to run `ln -s /etc/passwd /project/.secret-link`
2. Agent calls `fs/read_text_file` with path `/project/.secret-link`
3. Boundary check passes because the path starts with the project root
4. Read follows the symlink and returns `/etc/passwd` contents

**Mitigation**: Resolve real paths before boundary comparison:

```swift
let realPath = url.resolvingSymlinksInPath().path
let root = projectRootURL.resolvingSymlinksInPath().path
guard realPath == root || realPath.hasPrefix(root + "/") else {
    throw ACPHandlerError.outsideProjectBoundary(pathString)
}
```

**Note**: The reference implementation had the same gap.

### T2: Hung Session from Missing Request Timeout

**Severity**: Medium
**Status**: Fixed

`ACPTransport.send()` now installs a per-request timeout and fails hung requests with `ACPTransportError.requestTimedOut`. The original implementation only resumed a `CheckedContinuation` on response or process termination, which allowed deadlocked agents to hang a session indefinitely.

The current transport timeout is 20 seconds per request. This bounds handshake and control-plane waits, but it also means a non-responsive agent now fails fast instead of blocking forever.

**Mitigation**: Add a configurable timeout to `send()` using `withThrowingTaskGroup` or a deadline timer that resumes the continuation with a timeout error.

### T3: Unsupervised Agent Operations via Auto-Allow

**Severity**: Medium
**Status**: Fixed

ACP session entry points now default `autoAllowPermissions` to `false`, and the Developer Tools probe also defaults to manual approval. This removes the previous deny-by-exception posture where a newly connected background or probe session could write files and run terminal commands without user approval.

A compromised or malicious agent binary on PATH, if selected as the default, gains unsupervised access to the project directory and can execute arbitrary terminal commands.

**Current controls**:
- Background sessions are opt-in (user must configure a default agent)
- Developer Tools probe keeps a visible toggle for explicitly enabling auto-allow
- Standalone and project ACP sessions default to manual approval

### T4: Unbounded Timeline Memory Growth

**Severity**: Medium
**Status**: Fixed

`ACPChatViewModel.timeline` is now capped with oldest-first eviction. The original implementation kept an unbounded array of user messages, assistant chunks, tool call groups, and plans, so a long ACP session could accumulate memory indefinitely.

**Mitigation**: Cap timeline entries at a fixed upper bound with oldest-first eviction. The current implementation keeps the most recent 50,000 entries.

### T5: TOCTOU Race in File Boundary Check

**Severity**: Low
**Status**: Accepted

The file path is validated against the project boundary, then the file operation executes. Between validation and operation, the filesystem could change (a symlink could be created at the validated path). The window is extremely small and requires a concurrent attacker with filesystem write access to the project directory.

**Note**: This is inherent to any path-based boundary check on a mutable filesystem. The symlink resolution fix in T1 reduces the practical attack surface.

### T6: Terminal Exit Continuation Leak

**Severity**: Low
**Status**: Fixed

`ACPTerminalHandler.exitContinuations` are now resumed on explicit release and on session disconnect / transport termination. The original implementation leaked pending `terminal/wait_for_exit` continuations when the agent died without issuing `terminal/release`.

**Mitigation**: Add cleanup logic that resumes all pending exit continuations when the owning `ACPSession` disconnects or the transport terminates.

### T7: Custom Agent Executable Injection

**Severity**: Low
**Status**: Accepted (user-initiated)

`CustomACPAgent` allows users to define arbitrary executables as ACP agents via app settings. No validation is performed on the executable path beyond `which` resolution.

**Current controls**:
- Custom agents are configured through the app settings UI, requiring direct user action
- The executable is spawned via `Process` with an explicit arguments array (no shell interpretation)
- The agent runs with the same OS user privileges as the app

This is accepted because the user already has full system access and can run arbitrary executables directly.

### T8: Raw Stderr Leaked into UI Error Messages (Direct Integrations)

**Severity**: Medium
**Status**: Fixed

Both `CodexSession` and `ClaudeCodeSession` previously included raw `stderrBuffer` in user-facing error messages when auth detection did not match a known pattern:

- Codex: `"Codex initialize failed. \(stderrBuffer)"`
- Claude Code: `"Claude Code exited unexpectedly. \(stderrBuffer)"`

Stderr can contain API keys in error output, internal file paths, AWS credentials or region info in Bedrock error output, or other sensitive runtime details. This error propagates to `connectionError` which renders in the UI.

**Mitigation**: Show a generic message in the UI and log only a redacted diagnostics summary, such as a hash and byte count, rather than the raw stderr payload.

### T9: Unbounded Recursive JSON Traversal (CodexSession)

**Severity**: Medium
**Status**: Fixed

`CodexSession.firstString(in:matching:)`, `firstInt(in:matching:)`, and `appendDiffs(from:fallbackPath:into:)` now cap recursion depth. The original implementation recursed through nested dictionaries and arrays without a limit, allowing a malicious or buggy agent to send deeply nested JSON (e.g., 10,000 levels) and crash the process with stack exhaustion.

**Mitigation**: Add a depth parameter with a reasonable cap:

```swift
private func firstString(in value: Any, matching keys: Set<String>, depth: Int = 0) -> String? {
    guard depth < 8 else { return nil }
    // ... recurse with depth: depth + 1
}
```

Apply the same pattern to `firstInt(in:matching:)` and `appendDiffs(from:fallbackPath:into:)`.

### T10: Full Trust Mode Bypasses All Safety (Direct Integrations)

**Severity**: Low
**Status**: Accepted (user-initiated)

Direct integrations in full trust mode pass flags that bypass all agent-side safety:

- Codex: `"sandbox": "danger-full-access"` gives unrestricted filesystem access beyond the vibespace
- Claude Code: `"--permission-mode", "bypassPermissions"` disables all built-in permission checks

Unlike ACP sessions where `allowAll` still routes operations through Crispy's file system handler (which enforces project boundary checks), direct integrations perform file operations inside the agent process. CrispyVibes has no enforcement layer for these operations.

**Current controls**:
- Full trust mode requires explicit user selection in settings or the standalone pane setup UI
- Standard trust mode uses `vibespace-write` (Codex) and `default` permission mode with `--permission-prompt-tool stdio` (Claude Code)

**Note**: Full trust in direct integrations grants broader access than `allowAll` in ACP sessions, where operations still route through Crispy's file system handler.

### T11: Unbounded Tool Output Buffers (CodexSession)

**Severity**: Low
**Status**: Fixed

`CodexSession.toolOutputBuffers` now cap retained per-tool-call output to a fixed maximum size. The original implementation accumulated output deltas with no limit, so a malicious agent streaming large output (e.g., dumping a binary file via `item/commandExecution/outputDelta`) could exhaust memory.

**Mitigation**: Cap per-tool-call buffer size (e.g., 256KB) and truncate.

### T12: Unbounded Stream Block States (ClaudeCodeSession)

**Severity**: Low
**Status**: Fixed

`ClaudeCodeSession.streamBlockStates`, `seenToolCallIDs`, and the associated tool-name bookkeeping are now capped during a prompt turn. The original implementation cleared them only on result or disconnect, so a single long-running turn could still accumulate unbounded state.

**Mitigation**: Cap per-turn state and evict oldest entries.

## Verified Secure Patterns

- **No shell injection**: All subprocess spawning uses `Process` with explicit argument arrays, never shell string interpolation. This applies to ACP transport, CodexSession, and ClaudeCodeSession.
- **Actor isolation on transport**: `ACPTransport` is an actor. All mutable state (pending requests, process handles, continuations) is actor-isolated. No data races.
- **MainActor isolation on session and handlers**: `ACPSession`, `CodexSession`, `ClaudeCodeSession`, `ACPTerminalHandler`, `ACPPermissionHandler`, and `ACPChatViewModel` are `@MainActor`-isolated.
- **Stderr bounded**: Agent stderr capture is capped at 2KB in all three session types to prevent unbounded memory growth from noisy agents.
- **Stderr diagnostics redacted**: Direct integrations log only a hash-and-size summary of stderr for diagnostics, not the raw stderr content.
- **Observability privacy**: Path-like values use `AppDiagnostics.pathToken()` (SHA-256 hash). ACP transport process metadata stores hashed executable and argument summaries, and stderr diagnostics are reduced to hash-and-size summaries. No raw prompt bodies, file contents, terminal output, or raw stderr payloads are stored in observability events.
- **Permission outcome logging**: Uses the option ID string, not the full response dictionary.
- **Project boundary enforcement**: Uses symlink resolution plus `hasPrefix(root + "/")`, preventing both classic prefix confusion (`/project-evil`) and symlink escape paths.
- **Diagnostics export gating**: ACP observability data is only included in diagnostics export when ACP observability is explicitly enabled. Disabled mode produces no ACP data in exports.
- **Default deny without handler**: Both CodexSession and ClaudeCodeSession deny approval/permission requests when no permission handler is installed, preventing silent auto-allow if handler wiring is missed.
- **Request timeouts**: Both `CodexSession.sendRequest` and `ACPTransport.send()` enforce bounded waits for agent responses, preventing hung sessions from silently stalling forever.
- **Claude Code delta computation**: `ClaudeCodeSession.emitSnapshotText` correctly computes incremental deltas from cumulative text snapshots. `emittedLength` is always ≤ `fullText.count`, so `dropFirst` never overflows.
- **Codex initialized notification**: `CodexSession` correctly sends the `initialized` notification after the initialize response, preventing the permanent hang that occurs when `codex app-server` blocks waiting for it.
- **Pending state cleanup**: All three session types (ACP, Codex, Claude Code) clean up continuations, buffers, tasks, and stream state on both termination and explicit disconnect.

## Review Cadence

Review this threat model when the ACP integration surface changes: new session types, new client handler methods, automatic session lifecycle, MCP passthrough, session persistence, or trust mode changes.
