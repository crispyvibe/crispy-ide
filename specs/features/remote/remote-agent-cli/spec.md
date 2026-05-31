# Remote Agent CLI — Spec

Status: draft (core implemented on `feature/remoteclisupport`)

## Overview

Remote Agent CLI extends the Agent CLI (F044) so that `crispy` commands work from a shell on a **remote SSH host** — including from AI agents running on that host — **without installing any package or platform binary on the remote**. The only footprint is one small shell wrapper at `~/.local/bin/crispy` (overwritten per connection), plus an SSH-managed socket that is removed on disconnect.

The bundled `crispy` binary is macOS/arm64 and cannot run on a typical (Linux) remote, and the IDE control socket lives on the local Mac. This feature bridges that gap with a **relay**: a tiny, session-scoped wrapper on the remote forwards the invocation's argv + context back over the existing SSH connection to the local app, which runs the real `crispy` against its local socket and returns the result on stdout.

A terminal-escape-sequence ("OSC") tunnel was evaluated and **rejected**: programmatic callers (agents, scripts) capture a command's stdout, so escape codes written to stdout never reach the terminal emulator and the command never executes. The relay returns results on stdout, which captured-output callers require.

## Dependencies

- **F044 (Agent CLI)** — local socket, `CLICommandRouter`, JSON-RPC protocol, and the bundled `crispy` binary, all reused unchanged. Relies on F044's revised authorization (owner-only `0600` socket; no process-ancestry gate).
- **F034 (SSH Remote Development)** — system-`ssh` ControlMaster connection and remote terminal launch (`RemoteProjectSession.makeSSHLaunchInvocation`).
- **F010 (tmux), F011 (ACP)** — agent / multiplexed execution contexts.
- **SEC-1, SEC-3** — socket access control and command authorization.

## Requirements

### F051-R01: No package/binary install; minimal footprint

Enabling the remote CLI MUST NOT require installing a package or platform binary on the remote host. The only remote artifact is a single shell wrapper at `~/.local/bin/crispy`, overwritten on each connect. (A temp-dir-on-`PATH` wrapper was tried first but isn't found by fresh login/agent shells, which rebuild `PATH`; `~/.local/bin` is on the login `PATH` on common distros.) The reverse-forwarded socket is removed on disconnect via `StreamLocalBindUnlink=yes`.

### F051-R02: Relay execution model

The remote `crispy` wrapper MUST forward its argv, working directory, and `CRISPY_*` context to the local app over the SSH connection. The local app MUST execute the **bundled `crispy` binary locally** with that argv/context and return stdout, stderr, and exit code to the remote wrapper, which reproduces them. No CLI command logic is reimplemented on the remote.

### F051-R03: Reverse-forwarded relay channel

The local app MUST expose a relay endpoint reachable from the remote shell via an SSH **reverse forward** (`ssh -R`). The implementation forwards a **remote Unix socket → the local relay Unix socket** (StreamLocal). The local relay socket MUST live on a **space-free path** (`~/.crispyvibes/<bundle-id>.crispy-relay.sock`), because OpenSSH's `-R` forward-spec parser breaks on spaces (ruling out paths under "Application Support"). The remote socket MUST be owner-only (`0600`).

### F051-R04: stdout-capture compatibility

A remote caller that captures the command's stdout (every AI agent, and shell scripts) MUST receive the command result on stdout. The implementation MUST NOT depend on terminal rendering or escape-sequence interpretation.

### F051-R05: Cross-shell command resolution

`crispy` MUST be invocable in the contexts agents actually use — fresh non-interactive shells (`bash -lc "crispy …"`), `zsh`, `sh`, and direct exec — not only the interactive launch shell. This is satisfied by placing the wrapper at `~/.local/bin/crispy` (on the login `PATH`) with the relay socket + project path **baked in as fallbacks**, so it works even when the launch env isn't inherited.

### F051-R06: Remote context injection

The remote shell receives `CRISPY_PROJECT_PATH` (the **remote** project root) and the relay address. `CRISPY_CONTEXT`/`CRISPY_VIBESPACE` forwarding is **not yet complete** — the relay currently uses its own process's context, so `whoami` may report a stale vibespace. (Open item; `project_path` resolves correctly.)

### F051-R07: Remote path semantics

File commands invoked remotely (e.g. `file.open <path>`) MUST treat the path as a **remote** path within the remote project and route through the remote/SFTP providers, enforcing the project boundary (F044-R10) against the remote root. **Implemented** for `file.open` and dock-pin file tiles (owning-project detection via `sshConnection`; render via the SFTP `fileContentProvider`). `shelf.add` still applies a local existence check (open item).

### F051-R08: Graceful degradation

If the remote sshd forbids forwarding (`AllowTcpForwarding no` / `AllowStreamLocalForwarding no`) or the relay is otherwise unreachable, `crispy` on the remote MUST fail with a clear, actionable message and MUST NOT hang. Absence of the relay MUST NOT break the remote shell or the SSH session.

### F051-R09: Lifecycle cleanup

On SSH disconnect (clean or abrupt), the reverse forward MUST be torn down and the session-scoped wrapper removed, leaving no orphaned sockets, ports, or files on the remote.

### F051-R10: Authorization

The relay relies on (a) the SSH channel's own authentication for who reaches the remote endpoint, (b) the remote socket's owner-only (`0600`) permission to exclude other users on the remote host, and (c) F044's owner-only `0600` local socket. There is no token/ancestry gate, so the trust unit is "processes running as the remote user." Driving the local IDE from a remote host is an explicit trust decision (see F051-R11, threat-model F051-T01/T02).

### F051-R11: Per-connection opt-in

Each SSH connection profile MUST carry an `agentCLIEnabled` flag controlling whether the relay (reverse forward + wrapper) is set up for its terminals. **Implemented**: `SSHConnectionProfile.agentCLIEnabled` (Optional for JSON back-compat; absent = enabled), a toggle in the connection sheet, and gating in `RemoteProjectSession`. Default is enabled; disable for shared/untrusted hosts.

### F051-R12: Remote open-file auto-reload

When an open **remote** file changes on the host, the editor SHOULD reload it (buffer permitting). Since the remote FS can't push FSEvents and `inotifywait` isn't assumed present, this is done by polling the open file's `stat` token (size+mtime via the SFTP provider) and reloading via the existing external-change path when the buffer is clean. **Implemented** in `MarkdownViewModel` (gated to remote providers).

## Scenarios

### Scenario F051-S01: Human runs `crispy` in a remote terminal

**Given** a connected remote project terminal,
**When** the user runs `crispy ping`,
**Then** the wrapper relays to the local app, the local `crispy` executes, and the version/app response prints in the remote terminal.

### Scenario F051-S02: Agent on the remote captures output

**Given** an AI agent running on the remote host invokes `bash -lc "crispy whoami --json"` and captures stdout,
**When** the command runs,
**Then** the agent receives the JSON result on stdout (no escape-sequence artifacts), and the resolved context reflects the remote project.

### Scenario F051-S03: Forwarding disabled on the remote

**Given** the remote sshd has `AllowTcpForwarding no`,
**When** the user/agent runs `crispy ping`,
**Then** `crispy` exits non-zero with a message explaining the relay is unavailable and how to enable it — and the shell remains usable.

### Scenario F051-S04: Disconnect cleans up

**Given** a remote session with the relay active,
**When** the SSH connection closes,
**Then** the reverse-forwarded socket is removed (`StreamLocalBindUnlink`). The `~/.local/bin/crispy` wrapper persists (overwritten next connect) but is inert without a live forward.

### Scenario F051-S05: Remote file boundary

**Given** an agent on the remote runs `crispy file open ../../etc/passwd`,
**When** the path resolves,
**Then** it is rejected with `permission_denied` because it escapes the remote project root.

## Acceptance Criteria

- `crispy ping`/`whoami` work from a remote terminal and from an agent that captures stdout (`bash -lc`), with no package/binary installed on the remote.
- The wrapper resolves on a fresh login shell's `PATH` (`~/.local/bin`); the reverse-forwarded socket is removed on disconnect.
- Forwarding-disabled hosts produce a clear error, not a hang.
- Remote `file.open` (and dock-pin) resolve via the SFTP provider and enforce the remote project boundary.
- The relay is gated per connection by `agentCLIEnabled`.
- No change required to the bundled `crispy` binary's command logic.

## Open Questions

- **Context passthrough (F051-R06)** — forward the remote terminal's `CRISPY_CONTEXT`/`CRISPY_VIBESPACE` so `whoami`/context-implicit commands resolve to the right terminal (currently uses the relay's own env). Open.
- **`shelf.add` (and other `file.*`) remote-awareness** — same owning-project/SFTP treatment as `file.open`. Open.
- Resolved: wrapper delivery → `~/.local/bin` (login `PATH`); relay channel → remote Unix socket + `nc -N`/`socat` (the bundled binary is cross-arch so `/dev/tcp` alone is moot); opt-in → per-connection `agentCLIEnabled`.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-30 | Initial draft from design discussion (relay model; OSC rejected) | Manu |
| 2026-05-31 | Updated to implementation: `~/.local/bin` wrapper (R01/R05), space-free relay socket + `nc -N` remote-Unix-socket channel (R03), per-connection opt-in (R11), remote auto-reload (R12), file.open/pin remote routing (R07); R06 context passthrough + shelf.add remote noted as open | Manu |
