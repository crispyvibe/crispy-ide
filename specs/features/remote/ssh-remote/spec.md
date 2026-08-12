# SSH Remote Development — Spec

Status: draft

## Overview

SSH Remote Development enables opening projects, browsing files, running terminals, and performing source control operations on remote machines over SSH — all from the same CrispyVibes window used for local work. The feature uses a lightweight, no-server-agent approach: app-managed SSH/SFTP for project services and the system `/usr/bin/ssh` for remote terminal PTYs. Only a standard SSH server is required on the remote host.

Remote SSH is available as a standard app feature. SSH connection profiles are managed from App Settings → Connections.

## Dependencies

- F001 (Terminal Sessions & Tabs) — remote terminals reuse the terminal rail and Ghostty rendering surface
- F002 (Terminal Board) — remote terminal sessions appear on the board
- F004 (Terminal Rail) — remote terminals appear alongside local terminals with host badge
- F024 (File Explorer) — remote explorer uses the same tree view via `FolderExploring` protocol
- F026 (Git Operations) — remote git uses shared `GitOutputParser` and `GitExploring` protocol

## Requirements

### F034-R01: SSH Connection Profiles

Named SSH connection profiles MUST be creatable, editable, and deletable. Each profile stores: display name, hostname, port (default 22), username, and authentication method (key file or SSH agent).

### F034-R02: SSH Config Import

Crispy MUST parse `~/.ssh/config` and surface discovered hosts as connection targets without manual profile creation. User-created profiles override SSH config entries for the same host.

### F034-R03: App-Managed SSH Transport

SSH connections for remote project lifecycle, file access, and remote command execution MUST be app-managed (Citadel SSH/SFTP) so the app owns connection state, SFTP readiness, and port forwarding directly. Remote terminals use the system `/usr/bin/ssh` as a separate PTY transport.

### F034-R04: Connection Lifecycle

Connection lifecycle MUST support connect, disconnect, and reconnect. On unexpected disconnection, a non-blocking vibespace-scoped retry surface MUST appear. Dependent file operations MAY retry readiness briefly, but connection recovery is user-initiated after failure.

### F034-R05: Connection Health Monitoring

Connection health MUST be monitored via SSH keepalive. A connection status control MUST be visible only when the active vibespace contains remote projects, surfacing connected, connecting, disconnected, and failed states plus retry actions.

### F034-R06: Multiple Simultaneous Connections

Multiple simultaneous connections to different hosts MUST be supported. A single vibespace MAY contain both local and remote projects.

### F034-R07: Remote Terminal Sessions

Users MUST be able to open terminal sessions on connected remote hosts. Remote terminals MUST use the same Ghostty-based rendering as local terminals, launched by spawning `/usr/bin/ssh -t` with a PTY attached.

### F034-R08: Remote Terminal Rail Integration

Remote terminal sessions MUST appear in the terminal rail alongside local terminals, distinguished by a host badge. All Phase 9 rail interactions (close, hide, rename, context menu) MUST work on remote terminals.

### F034-R09: Remote Terminal Disconnect State

If the SSH connection drops, active remote terminal sessions MUST show a disconnected/terminated state. Retry is user-initiated. Previously running shell state is not assumed to survive disconnect unless preserved remotely (e.g., tmux).

### F034-R10: SFTP File Explorer

When a remote project is open, the file explorer MUST display the remote directory tree via SFTP with lazy loading (only expanded directories fetched). Basic file operations (create, rename, delete, move) MUST be supported.

### F034-R11: Remote File Editing

Selecting a remote file MUST open it in the editor via the `FileContentProviding` abstraction. Text content is fetched via SFTP into memory. Raster-image/PDF previews MAY materialize a staged local preview file. Saving writes back via SFTP.

### F034-R12: Large File Prompt

Files exceeding a configurable threshold (default 10 MB) MUST show a confirmation prompt before downloading for editing.

### F034-R13: Remote Project Model

A remote project is represented as a project entry with a remote URI scheme (`ssh://user@host:port/path`). Remote projects MUST integrate with the existing vibespace model — per-project config is stored locally, keyed by the remote URI.

### F034-R14: Remote Project VibeSpace Restore

When a vibespace containing remote projects is opened, Crispy MUST attempt SSH connections asynchronously. Failed connections MUST leave projects in a degraded state rather than removing them. Local projects MUST NOT be blocked by remote connection failures.

### F034-R15: Local Port Forwarding

Crispy MUST support local port forwarding (SSH `-L`). Port forwards MUST be configurable per connection profile and per vibespace. Active forwards MUST be visible in the UI and individually stoppable without disconnecting.

### F034-R16: Host Key Validation

Host key verification MUST follow standard SSH behavior (`known_hosts` checking). On first connection to an unknown host, Crispy MUST present the host key fingerprint for user acceptance. Accepted keys are written to `~/.ssh/known_hosts`.

### F034-R17: SSH Agent Authentication

SSH private key passphrases MUST be resolved through the macOS SSH agent / Keychain. Crispy MUST NOT store or cache passphrases. Password authentication is out of scope — key-based auth only.

### F034-R18: No Secrets on Disk

Connection profiles stored in vibespace config MUST NOT contain secrets. Profiles store only: host, port, username, and path to key file.

### F034-R19: Remote Source Control

Git operations (status, diff, stage, unstage, commit, branch, checkout, history) MUST work on remote projects via `RemoteCommandExecutor` over SSH. The source control sidebar MUST render identically for local and remote projects. Git unavailability on the remote host MUST be detected and surfaced.

### F034-R20: Explorer Refresh Affordance

Remote project roots MUST expose explicit refresh affordances where live file watching is unavailable (`supportsLiveWatching = false`).

### F034-R21: Enhanced Remote Explorer Beta

Settings → Connections MUST expose a per-device **Enhanced remote file explorer (Beta)** toggle that defaults off. Newly-created remote sessions MUST snapshot the setting and use either legacy root-name polling or enhanced SFTP metadata polling. Enhanced mode MUST watch the root plus expanded directories, refresh only affected directories, detect same-name metadata changes, and make create/rename/delete mutations visible without requiring collapse/re-expansion. Changing the setting requires reopening remote projects.

## Scenarios

### Scenario F034-S01: Create and connect an SSH profile

**Given** user opens App Settings → Remote tab
**When** user creates a new SSH connection profile with host, port, username, and key file
**Then** the profile appears in the connection list
**And** "Test Connection" validates connectivity

### Scenario F034-S02: Import hosts from SSH config

**Given** user has hosts defined in `~/.ssh/config`
**When** user clicks "Import from SSH Config"
**Then** discovered hosts appear with checkboxes for selective import

### Scenario F034-S03: Add remote project to vibespace

**Given** user has a connected SSH profile
**When** user clicks "Add Remote Folder" in VibeSpace creation
**Then** a connection picker and remote directory browser appear
**And** selecting a directory creates a remote project in the vibespace

### Scenario F034-S04: Remote file explorer lazy loading

**Given** a remote project is open
**When** user expands a directory in the file explorer
**Then** only that directory's contents are fetched via SFTP
**And** a loading indicator appears during the fetch

### Scenario F034-S05: Edit and save a remote file

**Given** a remote project is open
**When** user opens a text file from the remote explorer
**Then** content is fetched via SFTP and displayed in the editor
**And** saving writes back via SFTP

### Scenario F034-S06: Remote terminal session with host badge

**Given** a remote project is connected
**When** user opens a remote terminal
**Then** the terminal appears in the rail with a host badge
**And** uses the same Ghostty rendering as local terminals

### Scenario F034-S07: Connection drops during active session

**Given** user has an active remote project with open terminals and editor tabs
**When** the SSH connection drops unexpectedly
**Then** the toolbar status control shows disconnected state
**And** remote terminals show terminated state
**And** file operations fail with an error banner
**And** reconnect is available via the status control

### Scenario F034-S08: VibeSpace restore with remote projects

**Given** a vibespace contains both local and remote projects
**When** the vibespace is reopened
**Then** local projects load immediately
**And** remote projects connect asynchronously
**And** failed remote connections show degraded state without blocking startup

### Scenario F034-S09: Host key verification on first connection

**Given** user connects to a host not in `~/.ssh/known_hosts`
**When** the SSH handshake presents the host key
**Then** Crispy shows the fingerprint and asks user to accept or reject
**And** accepted keys are written to `~/.ssh/known_hosts`

### Scenario F034-S10: Port forwarding

**Given** user has an active SSH connection
**When** user adds a local port forward (e.g., localhost:3000 → remote:3000)
**Then** the forward appears in the port forwarding panel
**And** the remote service is accessible at localhost:3000
**And** the forward can be stopped without disconnecting

### Scenario F034-S11: Remote git operations

**Given** a remote project has git installed on the remote host
**When** user opens the source control sidebar
**Then** git status, diff, branch, and commit work identically to local projects

### Scenario F034-S12: Git unavailable on remote host

**Given** a remote project's host does not have git installed
**When** user opens the source control sidebar
**Then** the sidebar shows "Git is not installed" — same as local behavior

### Scenario F034-S13: Opt into enhanced remote explorer refresh

**Given** Enhanced remote file explorer is disabled by default on a device
**When** the user enables it in Settings → Connections and reopens a remote project
**Then** the project root and expanded directories are polled using metadata snapshots
**And** creating, renaming, or deleting an item refreshes its affected directory
**And** a newly-created nested item appears and enters inline rename without collapsing its parent
**And** disabling the setting and reopening the project restores legacy behavior

## Acceptance Criteria

- SSH connection profiles can be created, edited, deleted, and tested.
- `~/.ssh/config` hosts are importable as connection targets.
- App-managed SSH connection owns state, SFTP, and keepalive monitoring.
- Connection status control appears only when vibespace has remote projects.
- Multiple simultaneous connections to different hosts work.
- Disconnection is detected; reconnect is user-initiated via toolbar control.
- Remote terminals open with host badge, support all rail interactions.
- Remote file explorer displays lazy directory tree via SFTP.
- Files can be opened, edited, and saved remotely.
- Create, rename, and delete operations work on remote files; drag/drop move remains deferred until payloads include project and SSH host identity.
- Large file prompt appears above configured threshold.
- Remote projects persist in vibespace config across restarts.
- Remote projects connect asynchronously; failures degrade gracefully.
- Local port forwarding works and is visible in the UI.
- No secrets stored on disk.
- Host key verification prompts on first connection.
- All file transfers occur over encrypted SSH channel.
- Git operations work identically on remote projects.
- Git unavailability on remote host is detected and surfaced.

## Open Questions

- Should auto-detected port forwarding from terminal output be included in the initial release or deferred?
- Should exponential backoff auto-reconnect be opt-in or off entirely for the first release?

## Change History

| Date | Change | Author |
|------|--------|--------|
| Unreleased | Added default-off enhanced remote explorer polling and create/rename/delete refresh requirements; remote drag/drop remains deferred pending host identity. | — |
| 2026-04-15 | Initial draft — migrated from phase-12-ssh-remote-development.md | — |
