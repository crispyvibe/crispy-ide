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
| Remote source ↔ Transfer manifest | Canonical SFTP realpath, entry type/name validation, size, and modification time determine what may leave the configured root. |
| Remote transfer ↔ Local staging/destination | Download writes a hidden sibling before final publication; Open in System writes an owner-only retained app temporary snapshot. |
| Temporary snapshot ↔ External application | macOS receives a local copy with no synchronization or writeback relationship to the SSH source. |

## Attack Surfaces

1. **Remote command execution** — `RemoteCommandExecutor` constructs shell commands from tool name and arguments, executes them on the remote host via SSH.
2. **SFTP file operations** — binary SFTP protocol reads/writes files on the remote host. Paths are user-provided.
3. **SSH config parsing** — `~/.ssh/config` is parsed for host discovery. Malformed config could cause unexpected behavior.
4. **Host key validation** — first-connection TOFU (Trust On First Use) model. User must accept unknown host keys.
5. **Control socket** — Unix domain socket at `~/.crispyvibes/ssh/<hash>` enables connection multiplexing. Socket permissions matter.
6. **Local port forwarding** — exposes remote services on localhost, accessible to any local process.
7. **Remote terminal PTY** — spawns `/usr/bin/ssh -t` with a PTY. The remote shell has full access to the remote system.
8. **Key file path in profile** — profile references a local private key file path.
9. **Recursive remote manifest** — attacker-controlled names, symlinks, special files, or deep/wide trees may escape the root or exhaust resources.
10. **Local destination publication** — failure or cancellation can expose partial data or replace an existing destination incorrectly.
11. **System-open snapshots** — sensitive remote data persists temporarily on local disk and is handed to another application.
12. **Concurrent remote mutation** — a remote source can change between metadata checks, handle open, and streamed reads.

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
- **Mitigation:** `SFTPSubprocess` serializes shared-channel wire operations with `NSLock`. A separate lifecycle lock protects running state and one-time resource closure across process termination, explicit disconnect, transfer cancellation, and deinit. Termination closes stdin, requests graceful exit, waits up to one second, sends SIGKILL if needed, and waits for exit; timed generic SSH commands also wait and escalate before releasing pipes. Connection checks replace a subprocess only after protected lifecycle state reports it stopped. Dedicated transfer channels terminate through structured cleanup before the coordinator slot is released. Linked NFR: PERF-Responsiveness, REL-2.

### F034-T09: Sensitive data in remote terminal scrollback

- **Vector:** Remote terminal sessions display sensitive information (passwords, tokens, API keys) that persists in the terminal scrollback buffer. If the local machine is compromised, scrollback content is accessible.
- **Impact:** Credential disclosure from terminal scrollback.
- **Likelihood:** Medium — developers routinely work with secrets in terminals.
- **Mitigation:** Remote terminals use the same Ghostty rendering as local terminals — scrollback is in-memory only. Terminal sessions show a disconnected/terminated state on SSH drop (no stale content). Crispy does not persist terminal scrollback to disk. This is the same risk as local terminal usage. Linked NFR: SEC-Data-Protection.

### F034-T10: Remote explorer mutation and polling abuse

- **Vector:** A crafted rename component could escape its parent directory, or expanding many remote directories could create excessive SFTP polling work.
- **Impact:** Mutation outside the displayed folder or avoidable remote/network load.
- **Likelihood:** Low — mutations are user initiated and the enhanced mode is opt-in.
- **Mitigation:** Enhanced rename rejects empty names, separators, `.` and `..`. Watch requests are normalized, deduplicated, capped at 256 paths, and use one shared two-second polling task. Failed listings preserve the last successful snapshot rather than synthesizing deletion. The legacy behavior remains available through the default-off Connections setting. Linked NFRs: SEC-Input-Sanitization, PERF-Responsiveness.

### F034-T11: Sensitive remote content leaks from a retained local snapshot

- **Vector:** Open in System copies SSH content into local temporary storage and another application reads it. Weak permissions, predictable paths, or missing cleanup could expose data after the operation.
- **Impact:** Confidential source, credentials, or project data persists on the local machine and is available outside Crispy.
- **Likelihood:** Medium because local materialization is required by the feature.
- **Mitigation:** Snapshot paths are app-owned and uniquely named, directories/files use owner-only permissions, no prior snapshot is reused after failure, and stale snapshots older than 24 hours are removed. The system launch happens only after successful verified transfer. Linked NFR: SEC-Data-Protection.
- **Residual risk:** The chosen external application and processes running as the same local user can read the retained copy. A snapshot intentionally remains for up to 24 hours.

### F034-T12: Recursive transfer escapes the remote root through names or links

- **Vector:** A malicious remote tree contains `..`-style names, separators, symlinks, a similarly prefixed sibling path, special files, or server responses whose canonical path lies outside the selected root.
- **Impact:** The app reads unintended remote files, creates an unsafe local hierarchy, or interacts with devices/FIFOs rather than regular data.
- **Likelihood:** Medium for untrusted or concurrently modified remote trees.
- **Mitigation:** The configured remote root may itself resolve through its configured symlink to establish the canonical confinement root. A selected source and each child are classified with `lstat` before any `realpath`; symbolic links and special entries are rejected immediately. Directory limits count only accepted non-dot entries, are enforced before append, and cancellation is checked per decoded entry and again per transfer child. Every accepted regular-file or directory child then receives `realpath` plus a component-aware canonical-root check. Every regular file must provide size and modification time, and traversal fails above 250,000 items or 256 levels. Linked NFR: SEC-Input-Sanitization, SEC-Data-Protection.
- **Residual risk:** Correctness depends on the remote SFTP server's `lstat`/`realpath` and metadata responses; a malicious server controls them.

### F034-T13: Failed or cancelled download publishes a partial destination

- **Vector:** A network failure, cancellation, disk-full condition, or app exit occurs after some bytes are written, or replacement of an existing destination fails midway.
- **Impact:** Incomplete files appear successful, consumers process corrupt data, or a prior destination is lost.
- **Likelihood:** Medium on slow or unreliable links.
- **Mitigation:** Download writes a uniquely named hidden sibling and publishes/replaces the selected destination only after the full manifest transfers and verifies successfully. Before replace/move, the service synchronously awaits MainActor acknowledgment that publication state is visible and performs a second `Task` cancellation check immediately before the filesystem call. Cancel is unavailable during publishing. Failure or cancellation before that boundary removes staging, and the global overlay reports the terminal state. Replacement behavior follows save-panel consent and filesystem destination semantics. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Final publish/replacement is a separate filesystem operation that may itself fail. Cancellation arriving after the final check can coincide with the atomic replace/move and may not prevent publication. Earlier cancellation can still be delayed by an active chunk or transport call; transfers cannot resume.

### F034-T14: Remote mutation produces an inconsistent snapshot

- **Vector:** Files are modified, replaced, or retargeted after manifest metadata is captured but before or during SFTP open/read.
- **Impact:** A downloaded directory combines revisions, or Open in System launches bytes different from the user's intended saved revision.
- **Likelihood:** Medium on shared or generated remote trees.
- **Mitigation:** Every regular transfer file must have size and mtime and is revalidated before and after streaming for regular type, canonical-path equality/root confinement, size, and mtime. The local byte count must exactly equal the recorded size. SFTP validates request IDs across metadata, directory, handle, read/write/close, and mutation operations; strictly parses NAME; requires explicit EOF for READ/READDIR and OK for WRITE/CLOSE; and bounds packets to 1…64 MiB. Explorer/root transfers fail before publication on mismatch. Independently, HTML Open in System captures buffer/content/file/provider synchronously, suppresses same-buffer autosaves, waits for `activeSaveToken`, and saves via `beginSave(capturedContent:)` before `ExternalFileOpenService` performs a separate unversioned SFTP re-read. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** SFTP metadata check and handle open/read are not atomic, so same-size mutation within timestamp resolution can evade transfer checks. The HTML post-save re-read has a broader risk: it is not version-bound and may open a different remote revision from the one just saved.

### F034-T15: Invalid port values cross parsing boundaries

- **Vector:** A malformed persisted `ssh://` identifier, connection form/profile, port-forward field, or imported SSH config supplies zero, malformed/non-numeric, negative, or greater-than-65535 ports.
- **Impact:** Truncation, wraparound, connection to an unintended endpoint, invalid project identity, or a forward bound to the wrong service.
- **Likelihood:** Low after failable validation at each ingress.
- **Mitigation:** URI parsing range-checks 1...65535 before `UInt16`; connection/profile and forwarding text use failable `UInt16` conversion plus a nonzero guard; SSH config marks the host invalid and omits it when `Port` fails the same constraints. Invalid values never reach process arguments or persisted profile construction. Linked NFR: SEC-Input-Sanitization.
- **Residual risk:** A syntactically valid but unintended in-range port remains user/configuration controlled.

### F034-T16: Same-root remote repository uses the wrong project or provider

- **Vector:** Two SSH hosts expose the same raw repository path and source control attaches by path overlap, loads a diff through the wrong backend, or opens an untracked file with another project's provider.
- **Impact:** Git commands execute on the wrong host, a diff misrepresents staged/working changes, or file content crosses an SSH project boundary.
- **Likelihood:** Medium without host-qualified repository identity.
- **Mitigation:** Project-backed repository IDs and view models retain the exact host-qualified `projectIdentifier`; attachment returns only that project. Tracked diffs call its `gitExplorer`, combine staged then working output, and open a preloaded project-qualified tab. Untracked/new files use the same project's exact file provider. Linked NFR: SEC-Data-Protection, REL-2.
- **Residual risk:** Static source inspection does not replace mounted multi-host testing, and historically incorrect persisted ownership may require separate migration.

### F034-T17: Legacy SSH identity migration loses state or upgrades untrusted data

- **Vector:** A reserved-character remote path exists under the prior raw full identifier, raw remote-path key, or malformed local normalization. Migration loads only active projects, omits parked/unresolved configs, prunes dormant settings, or immediately re-saves a tampered parent.
- **Impact:** Remote terminals, browser sessions, color/startup/ACP/shell overrides, or shortcut slots disappear; duplicate logical projects survive; or untrusted config receives a valid signature.
- **Likelihood:** Medium during upgrade from raw SSH identifiers.
- **Mitigation:** Canonicalize live, unresolved, focused, and parked values; deduplicate parked values and remove active/unresolved collisions. Persist a changed parent immediately only when its prior signature verified. Resolve every per-project read/mutation through canonical plus raw-path, prior raw-full, and malformed-normalization aliases; migrate the complete config, delete the alias, load live/unresolved/parked configs, and preserve dormant settings/shortcut slots in runtime pruning. Linked NFR: SEC-2, SEC-Data-Protection, REL-2.
- **Residual risk:** Divergent independently persisted aliases are not merged; the first supported alias found becomes authoritative.

## Residual Risks

- The remote host is fully trusted once connected. Any command executed via SSH has the remote user's full permissions. This is inherent to SSH.
- TOFU (Trust On First Use) for host keys means the first connection is vulnerable to MITM. This is standard SSH behavior.
- Port forwarding exposes remote services to local processes. This is by design and documented.
- The system ssh binary handles all cryptographic operations. Vulnerabilities in OpenSSH are outside Crispy's control.
- Owner-only temporary snapshots still expose content to the external application and same-user processes until cleanup.
- Canonical confinement permits the configured remote root itself to resolve through its configured symlink. Each child is classified by `lstat`; symlink/special children are rejected without `realpath`, and accepted regular/directory children are canonicalized and root-checked. Correctness still trusts SFTP server metadata.
- Hidden sibling staging prevents visible partial destinations; final replacement still follows save-panel and filesystem semantics and may fail.
- Source size/mtime validation is check-then-open/read, not a remote atomic snapshot. Same-size, coarse-timestamp changes may evade it.
- Only one coordinator-backed explorer file/folder or active project-root transfer runs at a time. Structured cancellation retains that slot through transport/staging cleanup, Cancel is absent during cancelling and publishing, failure remains visible, and transfers cannot resume. Editor-triggered remote HTML Open in System is independent and uses its own app-level service and editor state.
- Remote drag/drop remains unsupported.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Shell escaping, discrete ssh arguments, bounded config parsing, canonical root confinement, invalid-name checks, and symlink/special-file rejection. |
| SEC-Data-Protection | Partial | No stored secrets, signed profiles, owner-only SSH/temp storage, host-key validation, verified manifests, and staged destination publication; retained copies and SFTP check/open TOCTOU remain. |
| PERF-Responsiveness | Partial | Async connection, dedicated streamed SFTP, bounded manifest, 128 KiB writes, and progress/cancel UI; one transfer slot and transport-bounded cancellation can delay later operations. |
| A11Y | Compliant | Actionable connection status, host badges, privacy-minimized parked-row labels, hashed AX identifiers, and transfer state/completion/failure presentation. |
| OBS | Partial | Remote connection/transfer lifecycle and newly relevant diagnostics are logged via `AppDiagnostics`; exported event metadata sanitizes path-like strings. This does not establish observability for every local file operation. |

## Verification Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static tests cover connection-form invalid ports and SSH-config zero/out-of-range ports; URI and forwarding boundaries remain production-source inspection. Remote discovery/refresh tests do not directly assert exact same-root attachment, staged-then-working preloaded diff routing, or exact untracked providers. `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly covers complete prior-raw-full alias migration, browser/shortcut reads, canonical loading, parked deduplication, and immediate trusted-parent rewrite; raw-path and malformed-normalization aliases also have static cases. Runtime preservation of all unresolved/parked settings remains source inspection. Existing confinement, file-kind, encoded-ID, and coordinator cases are compiled static source, while cap/cancellation placement and process escalation/reaping are production-source inspection.

## Change History

- 2026-10-23: Added F034-T17 for canonical SSH migration loss/trust risks and corrected migration, source-control, and port evidence to final build/test-build-only status.
- 2026-10-23: Expanded F034-T15 across URI, form/profile, forwarding, and SSH-config boundaries; added F034-T16 for exact same-root repository/diff/provider ownership; corrected evidence to static/build-only scope.
- 2026-10-23: Hardened F034-T08/T12 and added F034-T15 for bounded enumeration/cancellation, lstat ordering, process reap/SIGKILL fallback, and port validation; recorded static-only verification.
- 2026-10-20: Corrected configured-root versus nested-symlink confinement, full SFTPv3 response validation, synchronous publication acknowledgment/final cancellation race, broader unversioned HTML reread risk, and partial diagnostics coverage with sanitized exported metadata.
