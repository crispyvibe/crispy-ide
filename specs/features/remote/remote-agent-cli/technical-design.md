# Remote Agent CLI — Technical Design

## Overview

The remote CLI reuses 100% of the local Agent CLI command logic by running the **bundled `crispy` binary on the Mac** and exposing only a thin argv/IO relay to the remote shell. Three pieces: a local exec-relay endpoint, an SSH reverse forward, and a session-scoped remote wrapper.

## Architecture

```
remote shell / agent
  └─ ~/.local/bin/crispy (wrapper, ~15 lines sh)   # on login PATH; no command logic
       │ NUL-framed: cwd \0 projectPath \0 arg0 \0 …   (via nc -N -U / socat)
       ▼  SSH reverse forward (-R remoteSock:localSock, StreamLocal, 0600)
  CLIExecRelayServer  (in-app, ~/.crispyvibes/<bundle>.crispy-relay.sock, 0600)
       │ runs bundled crispy via ManagedProcessRunner (env: CRISPY_SOCKET, CRISPY_PROJECT_PATH)
       ▼
  bundled crispy <argv> ──JSON-RPC──▶ CLISocketServer ──▶ CLICommandRouter ──▶ services
       │ "<exit>\n" + stdout + stderr
       ▲──────────────────────────────────── returned over the tunnel
```

The wrapper carries no protocol knowledge; argv→JSON-RPC parsing stays in the Rust `crispy` binary, run locally. The relay endpoint is **separate** from `crispy.sock` so argv-exec traffic and IDE JSON-RPC never mix.

## Data Flow

1. **Connect.** `RemoteProjectSession.makeSSHLaunchInvocation` (when the profile's `agentCLIEnabled` is on) adds `-R <remoteSock>:<localRelaySock>` (`StreamLocalBindUnlink=yes`) and prepends to the `remoteCommand`: write the `crispy` wrapper to `~/.local/bin`, `export PATH/CRISPY_RELAY_SOCK/CRISPY_PROJECT_PATH`. The local relay socket path is space-free (`~/.crispyvibes/<bundle-id>.crispy-relay.sock`).
2. **Invoke.** Remote `crispy <args>` (wrapper) connects to the forwarded remote Unix socket and writes NUL-separated `cwd \0 projectPath \0 arg0 \0 …`, then half-closes (`nc -N`).
3. **Execute.** `CLIExecRelayServer` reads to EOF, splits on NUL, and runs the bundled `crispy <argv>` via `ManagedProcessRunner` with env `CRISPY_SOCKET=<local crispy.sock>` and `CRISPY_PROJECT_PATH=<remote path>`. That local `crispy` dispatches over `crispy.sock` normally.
4. **Return.** The relay writes `"<exitCode>\n"` + stdout + stderr; the wrapper prints the body and exits with the code.
5. **Disconnect.** SSH teardown removes the forwarded socket (`StreamLocalBindUnlink`). The `~/.local/bin/crispy` wrapper persists (overwritten next connect; inert without a live socket).

## API / Contracts (relay protocol)

NUL-framed, shell-friendly (no JSON on the remote):
- **Request:** `cwd \0 projectPath \0 arg0 \0 arg1 \0 …` (client half-closes write).
- **Response:** `"<exitCode>\n"` followed by the command's combined stdout+stderr.

## Channel choice (decided)

**Remote Unix socket → local Unix socket** (`-R remoteSock:localSock`, StreamLocal). The wrapper reaches it with `nc -N -U` (OpenBSD/Linux netcat; `-N` half-closes on EOF so the relay responds promptly) or `socat - UNIX-CONNECT:…`. A TCP-loopback + bash `/dev/tcp` variant was considered but isn't needed — the bundled binary is cross-arch so the relay is required regardless, and the Unix-socket path avoids remote port allocation. The local relay socket must be space-free (OpenSSH `-R` parsing breaks on spaces).

## State Management

- The relay (`CLIExecRelayServer`) is owned by `AppDelegate`, started alongside the command socket (idempotent, self-healing on `applicationDidBecomeActive`), one per app instance.
- Per-connection: the `-R` forward lives with the terminal's own `ssh` process; the wrapper is rewritten on each connect. Gated by `SSHConnectionProfile.agentCLIEnabled`.

## Wrapper (~/.local/bin/crispy)

```sh
#!/bin/sh
: "${CRISPY_RELAY_SOCK:=<baked remote socket>}"
: "${CRISPY_PROJECT_PATH:=<baked remote project>}"
if command -v nc >/dev/null 2>&1; then __c() { nc -N -U "$CRISPY_RELAY_SOCK"; }
elif command -v socat >/dev/null 2>&1; then __c() { socat - "UNIX-CONNECT:$CRISPY_RELAY_SOCK"; }
else echo "crispy: IDE relay needs nc or socat on the remote host" >&2; exit 127; fi
__r=$({ printf '%s\0' "$PWD" "$CRISPY_PROJECT_PATH"; for a in "$@"; do printf '%s\0' "$a"; done; } | __c)
[ -z "$__r" ] && { echo "crispy: IDE relay unavailable" >&2; exit 127; }
__code=$(printf '%s\n' "$__r" | head -n1); printf '%s' "$__r" | tail -n +2
case "$__code" in ""|*[!0-9]*) exit 1 ;; esac
exit "$__code"
```

The socket/project are baked as `${VAR:=…}` fallbacks so the wrapper works even when the launch env isn't inherited; the launching shell also exports the live values (preferred).

## Remote file operations (F051-R07)

The local `crispy` runs on the Mac, so file commands must detect remote-owned paths and route through SFTP rather than the local filesystem:
- `CLICommandRouter.handleFileOpen` resolves the owning project via `vibespaceCatalogStore` (longest-matching root). If the owner is remote (`sshConnection != nil`), it skips the local `fileExists` check; the open path (`VibeSpaceCanvasFileOpenUseCase`) loads via the project's `fileContent` SFTP provider.
- Dock-pin file tiles resolve the same owning-project SFTP provider and pass it to the editor group.
- **Open:** `shelf.add` still does a local `fileExists` check (needs the same treatment).

## Remote open-file auto-reload (F051-R12)

`MarkdownViewModel` polls the open file's `modificationToken` (size+mtime via `SFTPFileContentProvider`, `stat -c '%s %Y'` / BSD `-f '%z %m'`) every ~4s, gated to remote providers (`requiresMaterializedLocalPreview`). A changed token triggers the existing `reloadExternalEditableFile` when the buffer is clean. (FSEvents/inotify aren't available remotely; `inotifywait` isn't assumed installed.)

## Dependencies

- System `/usr/bin/ssh` (already used) for `-R` StreamLocal forwarding.
- No new Swift packages. Remote needs a POSIX shell plus `nc` (with `-N`) or `socat`. `~/.local/bin` must be on the remote login `PATH` (default on common distros via `~/.profile`).

## Platform Considerations

- Remote is assumed POSIX (Linux/macOS). The bundled `crispy` runs only locally — never shipped to the remote.
- `sshd` must permit forwarding for the relay; otherwise degrade per F051-R08.

## Performance Constraints

- One SSH round-trip per command (interactive latency, acceptable). Relay subprocess spawn is local and cheap.

## Migration / Rollout Notes

- Additive; no change to the bundled `crispy` binary's command logic or to local CLI behavior.
- Per-connection opt-in is implemented (`SSHConnectionProfile.agentCLIEnabled`, default on).
- Open: context passthrough (F051-R06), `shelf.add` remote-awareness, and disconnect cleanup of the `~/.local/bin` wrapper (currently overwritten per connect, not removed).
