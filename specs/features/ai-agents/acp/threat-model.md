# Agent Conversation Protocol (ACP) — Threat Model

## Overview

ACP spawns external agent processes and grants them controlled access to the file system and terminal. The primary trust boundary is between CrispyVibes (the host) and the agent process (untrusted code running with the same OS permissions). This document identifies attack surfaces, threats, and mitigations for the ACP feature.

## Trust Boundaries

```
┌─────────────────────────────────────────────────┐
│  CrispyVibes Process (trusted)                        │
│  ┌───────────────┐  ┌────────────────────────┐  │
│  │ ACPSession    │  │ ACPFileSystemHandler   │  │
│  │ Manager       │  │ (sandboxed to project) │  │
│  └───────┬───────┘  └────────────┬───────────┘  │
│          │ stdio                 │ fs ops        │
│  ┌───────┴───────┐  ┌───────────┴────────────┐  │
│  │ ACPTransport  │  │ ACPTerminalHandler     │  │
│  │ (JSON-RPC)    │  │ (creates terminal tabs)│  │
│  └───────┬───────┘  └───────────┬────────────┘  │
└──────────┼──────────────────────┼───────────────┘
           │ stdin/stdout         │ shell commands
┌──────────┴──────────┐  ┌───────┴────────────────┐
│  Agent Process      │  │  Terminal / Shell       │
│  (untrusted)        │  │  (user's OS context)    │
└──────────┬──────────┘  └───────┬────────────────┘
           │                     │
┌──────────┴─────────────────────┴────────────────┐
│  File System (user's files, project directory)   │
└──────────────────────────────────────────────────┘
```

**Boundary 1: CrispyVibes ↔ Agent Process.** The agent is an external executable communicating over stdio. CrispyVibes controls what the agent can do through handlers and permission gates.

**Boundary 2: CrispyVibes ↔ File System.** File system handlers mediate all agent file access. The sandbox boundary is the project root directory.

**Boundary 3: CrispyVibes ↔ Terminal.** Terminal handlers create shell sessions where agent-requested commands execute with the user's full OS permissions.

## Attack Surfaces

| Surface | Entry Point | Exposure |
|---------|-------------|----------|
| Agent executable spawning | `ACPTransport.start()`, `Process()` | Arbitrary binary execution |
| Stdio message stream | JSON-RPC over stdin/stdout | Malformed JSON, oversized payloads, injection |
| File system handler | `fs/read_text_file`, `fs/write_text_file` | Path traversal, symlink attacks |
| Terminal handler | `terminal/create` | Arbitrary command execution |
| Permission system | `ACPPermissionHandler` | Escalation, UI spoofing |
| Agent discovery | `ACPAgentRegistry`, PATH resolution | Executable substitution |
| Credential exposure | CLI environment, auth tokens | Token leakage to agent process |

## Threats

### F011-T01: Malicious Agent Binary

- **Vector:** User connects to an agent whose executable has been replaced or is itself malicious.
- **Impact:** Full code execution with user's OS permissions. Data exfiltration, file destruction, credential theft.
- **Likelihood:** Low — requires user to explicitly select and connect to the agent.
- **Mitigation:**
  - Agents are never auto-downloaded or auto-installed. Users install agent CLIs through their own package managers.
  - Discovery only finds executables already on PATH or at user-specified absolute paths.
  - No auto-connect on app launch unless the user previously enabled `shouldAutoConnect` for that pane.
  - The agent process inherits Crispy's sandbox but has no elevated privileges.

### F011-T02: Path Traversal via File System Handler

- **Vector:** Agent sends `fs/read_text_file` or `fs/write_text_file` with a path containing `../` or symlinks pointing outside the project root.
- **Impact:** Read or write arbitrary files on the user's system.
- **Likelihood:** Medium — a compromised or malicious agent would attempt this.
- **Mitigation:**
  - `ACPFileSystemHandler.resolvedPath()` calls `URL.resolvingSymlinksInPath()` on both the requested path and the project root.
  - The resolved path must equal or be a child of the resolved project root. Paths outside the boundary return `outsideProjectBoundary` error.
  - Symlink resolution happens before the boundary check, preventing symlink-based escapes.

### F011-T03: Permission Bypass / Escalation

- **Vector:** Agent crafts permission requests that trick the user into granting broader access than intended, or exploits the allow-always mechanism.
- **Impact:** Unrestricted file and terminal access for the session.
- **Likelihood:** Medium — social engineering through permission card content.
- **Mitigation:**
  - Standard trust mode requires per-action approval. Each permission card shows the tool call title and available options.
  - Allow-always only applies to the current session — it does not persist across reconnects.
  - Full trust mode is an explicit user choice, not a default. The UI labels it clearly.
  - Permission cards are rendered by CrispyVibes, not by the agent — the agent cannot control card appearance.

### F011-T04: Terminal Command Injection

- **Vector:** Agent sends `terminal/create` with a malicious command string that executes destructive operations.
- **Impact:** Arbitrary command execution with user's full shell permissions. Data loss, credential theft, system compromise.
- **Likelihood:** High in full-trust mode, low in standard mode (requires user approval).
- **Mitigation:**
  - In standard trust mode, terminal creation requires explicit user approval via permission card.
  - The command string is passed directly to the terminal — no shell interpolation by CrispyVibes.
  - Terminal tabs are visible in the UI, so the user can observe what commands are running.
  - `terminal/kill` sends SIGINT, allowing graceful process termination.
- **Residual risk:** In full-trust mode, terminal commands execute without approval. This is by design but means a malicious agent has unrestricted shell access.

### F011-T05: Credential Leakage to Agent Process

- **Vector:** Agent process inherits environment variables or receives authentication tokens that it exfiltrates.
- **Impact:** Credential theft, unauthorized access to user's services.
- **Likelihood:** Low — agent processes receive a controlled environment.
- **Mitigation:**
  - `ACPTransport.start()` can pass a filtered environment. Sensitive variables are not forwarded by default.
  - Authentication credentials (e.g., Cognito tokens) are one-shot and never persisted in the agent's environment.
  - The agent process does not receive Crispy's keychain access.

### F011-T06: Context Exposure — Agent Reads Project Files

- **Vector:** Agent uses `fs/read_text_file` to read sensitive files within the project boundary (e.g., `.env`, credentials, private keys).
- **Impact:** Exposure of secrets stored in project files.
- **Likelihood:** High — agents routinely read project files to provide assistance.
- **Mitigation:**
  - File access is sandboxed to the project root. The agent cannot read files outside the project.
  - Users should follow standard practices: use `.gitignore` for sensitive files, avoid committing secrets.
  - This is an inherent trade-off — agents need file access to be useful. The sandbox limits scope.
- **Residual risk:** Any file within the project boundary is readable by the agent. Users must be aware that connecting an agent grants it read access to the project.

### F011-T07: Stdio Message Injection / Malformed JSON

- **Vector:** Agent sends malformed JSON-RPC messages, oversized payloads, or messages designed to exploit parsing vulnerabilities.
- **Impact:** Crash, memory exhaustion, or unexpected behavior in the transport layer.
- **Likelihood:** Low — requires a deliberately malicious agent.
- **Mitigation:**
  - `ACPTransport` reads line-by-line and parses each line as JSON independently. Malformed lines are logged and skipped.
  - Request timeouts prevent hanging on unanswered requests.
  - The transport is an `actor`, isolating its state from the main thread.

### F011-T08: Agent Process Resource Exhaustion

- **Vector:** Agent process consumes excessive CPU, memory, or disk I/O.
- **Impact:** System slowdown, CrispyVibes becomes unresponsive.
- **Likelihood:** Low — most agent CLIs are well-behaved.
- **Mitigation:**
  - The agent runs as a child process. Disconnecting the session terminates the process.
  - Stderr output is captured and size-limited for diagnostics.
  - No explicit resource limits are enforced beyond OS defaults.
- **Residual risk:** While the agent process is running, it has access to system resources at the same level as any user process.

## Residual Risks

| Risk | Severity | Acceptance Rationale |
|------|----------|---------------------|
| Full-trust mode grants unrestricted file and terminal access | High | Explicit user opt-in. Clearly labeled in UI. Does not persist across app restarts unless user re-enables. |
| Agent process has same OS permissions as CrispyVibes | High | Inherent to local process spawning. No practical way to sandbox a CLI tool further without OS-level containers. |
| Project files are readable by connected agents | Medium | Required for agent functionality. Sandboxed to project root. Users control which projects they connect agents to. |
| Direct integration sessions parse proprietary formats | Low | Format changes in Claude Code or Codex CLI could cause parsing errors. Mitigated by version checks and graceful error handling. |

## NFR Compliance

| NFR | Requirement | How ACP Complies |
|-----|-------------|-----------------|
| SEC-1 | Input validation | File paths validated and sandboxed via `resolvedPath()`. JSON-RPC messages parsed with error handling. |
| SEC-3a | Least privilege | Standard trust requires per-action approval. File access sandboxed to project root. |
| OBS-1 | Structured logging | `ACPObservabilityStore` records events with category, duration, and metadata. |
| REL-1 | Graceful degradation | Transport timeouts, process termination handling, continuation cleanup on disconnect. |
