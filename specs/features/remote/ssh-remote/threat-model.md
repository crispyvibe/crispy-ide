# SSH Remote Development — Threat Model

## Overview

SSH Remote Development enables opening projects, browsing files, running terminals, and performing source control operations on remote machines over SSH. It uses system `/usr/bin/ssh` with ControlMaster for multiplexed connections, a binary SFTP subprocess for file operations, and `/usr/bin/ssh -t` for remote terminal PTYs. This feature performs significant network I/O over encrypted SSH channels. The threat surface includes SSH connection management, host key validation, remote command execution, SFTP file transfers, and local port forwarding.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app ↔ System SSH (`/usr/bin/ssh`) | SSH connections are established via system ssh with ControlMaster. The app manages control sockets at `~/.crispyvibes/ssh/`. |
| Crispy app ↔ SFTP subprocess | Binary SFTPv3 protocol over `ssh -s sftp`. File operations are serialized through a lock-protected subprocess. |
| Crispy app ↔ Remote host | Commands are executed on the remote host via the control socket. Output is parsed locally. |
| `~/.ssh/config` ↔ Profile import | SSH config is parsed to discover connection targets. Parsed values become connection profile fields. |
| `~/.ssh/known_hosts` ↔ Host key validation | Host keys are verified against known_hosts. New keys are written on user acceptance. |
| Local port forward ↔ Network | Port forwards expose remote services on localhost. |
| Connection profile ↔ Disk | Profiles store host, port, username, and key file path. No secrets stored. |

## Attack Surfaces

1. **Remote command execution** — `RemoteCommandExecutor` constructs shell commands from tool name and arguments, executes them on the remote host via SSH.
2. **SFTP file operations** — binary SFTP protocol reads/writes files on the remote host. Paths are user-provided.
3. **SSH config parsing** — `~/.ssh/config` is parsed for host discovery. Malformed config could cause unexpected behavior.
4. **Host key validation** — first-connection TOFU (Trust On First Use) model. User must accept unknown host keys.
5. **Control socket** — Unix domain socket at `~/.crispyvibes/ssh/<hash>` enables connection multiplexing. Socket permissions matter.
6. **Local port forwarding** — exposes remote services on localhost, accessible to any local process.
7. **Remote terminal PTY** — spawns `/usr/bin/ssh -t` with a PTY. The remote shell has full access to the remote system.
8. **Key file path in profile** — profile references a local private key file path.

## Threats

### F034-T01: Command injection via remote command execution

- **Vector:** `RemoteCommandExecutor.execute` constructs a shell command string from tool name and arguments, then passes it to SSH for remote execution. If arguments are not properly escaped, an attacker-controlled file name or argument could inject additional commands on the remote host.
- **Impact:** Arbitrary command execution on the remote host.
- **Likelihood:** Medium — the `shellEscape` function is used, but shell escaping is notoriously error-prone. The implementation uses single-quote wrapping with quote escaping.
- **Mitigation:** `RemoteCommandExecutor.shellEscape` wraps arguments in single quotes with internal quote escaping (`'\\''`). Safe characters (letters, numbers, `-_./:%@=`) bypass quoting. The command is wrapped in a stderr-capture pattern using a UUID-based separator. Code review MUST verify that all user-influenced values pass through `shellEscape`. Consider using `--` separator where applicable. Linked NFR: SEC-Input-Sanitization.

### F034-T02: SFTP path traversal on remote host

- **Vector:** A crafted file path passed to SFTP operations (read, write, delete, rename) could traverse directories on the remote host (e.g., `../../etc/passwd`). The SFTP subprocess operates with the SSH user's permissions.
- **Impact:** Read, write, or delete of arbitrary files on the remote host within the SSH user's permission scope.
- **Likelihood:** Low — paths originate from the explorer UI (user-selected) or from session restore (persisted paths). The SFTP subprocess does not restrict paths.
- **Mitigation:** SFTP operations use the SSH user's permissions — no privilege escalation is possible. Paths displayed in the explorer are relative to the remote project root. The `realpath` SFTP operation resolves canonical paths. File operations are user-initiated through the explorer UI. Consider validating that paths remain within the configured remote project root. Linked NFR: SEC-Input-Sanitization.

### F034-T03: Host key spoofing (MITM attack)

- **Vector:** An attacker performs a man-in-the-middle attack, presenting a different host key than the legitimate server. If the user accepts the key without verification, all subsequent communication is intercepted.
- **Impact:** Full interception of SSH traffic including commands, file contents, and credentials.
- **Likelihood:** Low for first connection (TOFU model); very low for subsequent connections (known_hosts verification).
- **Mitigation:** `KnownHostsValidator` checks host keys against `~/.ssh/known_hosts`. Unknown hosts trigger a fingerprint display prompt (F034-R16). Changed keys trigger a `HostKeyChangedError` with a security warning. Accepted keys are written to `~/.ssh/known_hosts`. The validator uses `ssh-keygen -F` for lookup and detects "REMOTE HOST IDENTIFICATION HAS CHANGED" in ssh output. Linked NFR: SEC-Data-Protection.

### F034-T04: Control socket hijacking

- **Vector:** The SSH ControlMaster socket at `~/.crispyvibes/ssh/<hash>` could be accessed by another process running as the same user, allowing them to multiplex commands over the established SSH connection without authentication.
- **Impact:** Unauthorized command execution on the remote host via the existing SSH session.
- **Likelihood:** Low — the socket directory is created with `0o700` permissions (owner-only). Only processes running as the same user can access it.
- **Mitigation:** The `~/.crispyvibes/ssh/` directory is created with POSIX permissions `0o700` (owner read/write/execute only). Socket paths use a hash of `user@host:port` to prevent prediction. The socket is only usable by the same user who created it. This is the same security model as OpenSSH's own ControlMaster. Linked NFR: SEC-Data-Protection.

### F034-T05: Local port forward exposing services to local network

- **Vector:** Local port forwarding (`-L`) binds a port on localhost. If the system is configured to allow remote connections to localhost ports (or if another local process connects), the forwarded remote service is accessible without SSH authentication.
- **Impact:** Unauthorized access to remote services via the forwarded port.
- **Likelihood:** Medium — localhost ports are accessible to all local processes. On multi-user systems or with network sharing enabled, exposure increases.
- **Mitigation:** Port forwards bind to `localhost` (127.0.0.1) by default, limiting access to local processes. Forwards are visible in the UI and individually stoppable (F034-R15). Users control which ports are forwarded. Consider binding to `127.0.0.1` explicitly rather than `localhost` to prevent IPv6 exposure. Linked NFR: SEC-Data-Protection.

### F034-T06: SSH config injection via malformed config file

- **Vector:** A malformed or maliciously crafted `~/.ssh/config` file could cause `SSHConfigParser` to produce unexpected profile values (e.g., hostname containing shell metacharacters, port values that overflow).
- **Impact:** Connection to unintended hosts; potential for argument injection if parsed values are used unsafely.
- **Likelihood:** Very low — the SSH config is user-controlled. The parser is simple line-based parsing.
- **Mitigation:** `SSHConfigParser` performs simple key-value extraction. Hostname, user, and port are used as discrete arguments to ssh (via `Process.arguments`). Port is parsed as `UInt16` (bounded). Wildcard hosts (`*`) are excluded. Identity file paths are expanded via `expandingTildeInPath`. Linked NFR: SEC-Input-Sanitization.

### F034-T07: Key file path manipulation

- **Vector:** A connection profile references a key file path. If the path is manipulated (e.g., via tampered vibespace config), ssh could be directed to use an unintended key file, potentially one with weaker security or belonging to a different identity.
- **Impact:** Authentication with wrong identity; potential for using a compromised key.
- **Likelihood:** Very low — profiles are stored in HMAC-signed vibespace config. Key file paths are user-configured.
- **Mitigation:** Key file paths are stored in connection profiles (user-configured). Profiles are persisted in HMAC-signed vibespace config. The path is passed to ssh via `-i` argument. SSH itself validates the key file format and permissions. No secrets (passphrases, private key content) are stored by Crispy (F034-R18). Linked NFR: SEC-Data-Protection.

### F034-T08: Resource exhaustion via SFTP subprocess leak

- **Vector:** If the SFTP subprocess crashes or hangs without being detected, subsequent file operations create new subprocesses. Repeated failures could accumulate zombie processes.
- **Impact:** Process table exhaustion; file descriptor leaks.
- **Likelihood:** Low — the subprocess tracks `isRunning` state via termination handler. `availableSFTP()` checks `isRunning` before reuse.
- **Mitigation:** `SFTPSubprocess` sets `isRunning = false` via `terminationHandler`. `availableSFTP()` creates a new subprocess only when the existing one is not running. The SFTP init handshake has a 10-second timeout — if connection fails, the subprocess is terminated immediately. Connection disconnect terminates the SFTP subprocess explicitly. Linked NFR: PERF-Responsiveness.

### F034-T09: Sensitive data in remote terminal scrollback

- **Vector:** Remote terminal sessions display sensitive information (passwords, tokens, API keys) that persists in the terminal scrollback buffer. If the local machine is compromised, scrollback content is accessible.
- **Impact:** Credential disclosure from terminal scrollback.
- **Likelihood:** Medium — developers routinely work with secrets in terminals.
- **Mitigation:** Remote terminals use the same Ghostty rendering as local terminals — scrollback is in-memory only. Terminal sessions show a disconnected/terminated state on SSH drop (no stale content). Crispy does not persist terminal scrollback to disk. This is the same risk as local terminal usage. Linked NFR: SEC-Data-Protection.

## Residual Risks

- The remote host is fully trusted once connected. Any command executed via SSH has the remote user's full permissions. This is inherent to SSH.
- TOFU (Trust On First Use) for host keys means the first connection is vulnerable to MITM. This is standard SSH behavior.
- Port forwarding exposes remote services to local processes. This is by design and documented.
- The system ssh binary handles all cryptographic operations. Vulnerabilities in OpenSSH are outside Crispy's control.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Shell escaping for remote commands; Process.arguments for local ssh; config parsing bounded. |
| SEC-Data-Protection | Compliant | No secrets on disk; HMAC-signed profiles; 0700 socket directory; host key validation. |
| PERF-Responsiveness | Compliant | SFTP timeout; connection health monitoring; async connection. |
| A11Y | Compliant | Connection status visible; host badge on terminals; error states actionable. |
| OBS | Compliant | Connection events logged via AppDiagnostics. |
