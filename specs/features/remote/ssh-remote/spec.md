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

SSH connections for remote project lifecycle, file access, remote command execution, and port forwarding MUST be app-managed through the system `/usr/bin/ssh` using ControlMaster multiplexing. Remote file access MUST use Crispy's custom binary SFTPv3 subprocess over `/usr/bin/ssh -s sftp`. Remote terminals use a separate `/usr/bin/ssh -t` PTY process. Citadel is not part of the current transport.

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

Files exceeding a configurable threshold (default 10 MB) MUST show a confirmation prompt before downloading for editing. **Current status: unmet.** Large-file editing begins without this confirmation today. The explicit Download workflow reports manifest/item/byte progress but has no size-confirmation prompt.

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

Git operations (status, diff, stage, unstage, commit, branch, checkout, history) MUST work on remote projects via `RemoteCommandExecutor` over SSH. Every discovered repository and repository view model MUST retain the originating project's exact host-qualified `projectIdentifier`; repositories from SSH projects that share the same raw root MUST attach only to the exact project, never by root overlap. Remote tracked-file diff actions MUST use that project's `gitExplorer`, combine non-empty staged (`git diff --cached`) and working-tree (`git diff`) output, and open the result as a preloaded diff tab carrying the same project identifier. Remote untracked or newly added files without committed history MUST open with that exact project's `FileContentProviding` instance. The source control sidebar MUST render identically for local and remote projects. Git unavailability on the remote host MUST be detected and surfaced.

### F034-R20: Explorer Refresh Affordance

Remote project roots MUST expose explicit refresh affordances where live file watching is unavailable (`supportsLiveWatching = false`).

### F034-R21: Enhanced Remote Explorer Beta

Settings → Connections MUST expose a per-device **Enhanced remote file explorer (Beta)** toggle that defaults off. Newly-created remote sessions MUST snapshot the setting and use either legacy root-name polling or enhanced SFTP metadata polling. Enhanced mode MUST watch the root plus expanded directories, refresh only affected directories, detect same-name metadata changes, and make create/rename/delete mutations visible without requiring collapse/re-expansion. Changing the setting requires reopening remote projects.

### F034-R22: Remote External Actions

Active remote file, folder, and project-root menus MUST provide Open in System and Download… and MUST NOT provide Reveal in Finder. Remote drag/drop MUST remain unsupported.

### F034-R23: App-Wide Explorer/Root Transfer Presentation

Remote Open in System and Download… initiated from explorer file/folder rows or active project roots MUST use one app-wide `RemoteTransferCoordinator` and overlay. At most one coordinator-backed explorer/root transfer may run at a time. Structured cancellation MUST retain the coordinator slot until transport termination and staging cleanup complete. The overlay MUST represent preparing, transferring, cancelling, publishing, completed, and failed states; Cancel MUST be unavailable during cancelling, publication, and terminal states, and failure MUST remain visible until dismissed. Before replace/move publication, the transfer service MUST synchronously await a MainActor publication-state acknowledgment and MUST perform a second `Task` cancellation check immediately before the filesystem operation. Cancellation after that check MAY coincide with the atomic replace/move boundary and may not prevent publication; no Cancel UI is available in publishing. Remote transfer lifecycle and newly relevant diagnostics MUST be recorded through `AppDiagnostics`, and diagnostics export MUST sanitize path-like strings in event metadata. Editor-triggered remote HTML Open in System MUST remain independent, using `ExternalFileOpenService` and editor busy/alert state rather than the coordinator overlay or dedicated transfer channel. This requirement MUST NOT imply broader global exclusivity.

### F034-R24: Transactional Download Publication

Download… MUST ask the user for a local destination, write into a hidden sibling staging item, and publish or replace the selected destination only after the complete transfer succeeds. Partial regular files MUST be created with owner-only permissions before streamed bytes are written. Failure, or cancellation observed before the final pre-publication check, MUST remove staging and MUST NOT expose partial content as the chosen destination. After the synchronous publishing-state acknowledgment and final cancellation check, cancellation MAY race with atomic replace/move and may not prevent publication. Replacement behavior MUST follow the save panel and destination filesystem replacement semantics.

### F034-R25: Remote Open Snapshot

Coordinator-backed Open in System MUST transfer the selected remote source into an application-owned temporary snapshot with owner-only permissions and launch only after success. `NSWorkspace.open` returning false MUST be treated as failure and the newly created snapshot MUST be removed. The snapshot MUST have no writeback relationship and MUST be retained after a successful launch. The remote transfer service MUST opportunistically remove snapshots older than 24 hours when creating a container. Separately, the app-level `ExternalFileOpenService` used by editor HTML MUST clean stale containers during construction/startup and on later staging. No failure may reuse or open an older snapshot.

### F034-R26: Confined, Verified SFTP Transfer

A recursive coordinator-backed transfer MUST preserve regular-file hierarchy and hidden files and limit traversal to 250,000 items and 256 levels. The configured remote root MAY itself resolve through its configured symlink to establish the canonical confinement root. Every child MUST receive name validation and `lstat`; symbolic-link and special entries MUST be rejected after `lstat` without `realpath`, while every accepted regular-file or directory child MUST then receive `realpath` and a component-aware canonical-root check. Nested symlinks MUST remain rejected. Every regular file MUST supply size and modification time, be revalidated by type/canonical path/size/mtime before and after streaming, and produce exactly the recorded local byte count. Explorer/root bulk transfer MUST use a dedicated SFTP channel and 128 KiB chunks. SFTP MUST validate response IDs for REALPATH, OPENDIR, READDIR, STAT, LSTAT, OPEN, READ, WRITE, CLOSE, MKDIR, REMOVE, and RENAME; parse NAME replies strictly; require explicit `SSH_FX_EOF` for reads/directory enumeration; require `SSH_FX_OK` for writes and closes; reject packet lengths outside 1…64 MiB; and enforce exact transferred byte counts. SFTP lifecycle state and shared-channel operations MUST be lock protected. Directory caps MUST count accepted non-dot entries, reject before appending an entry beyond the remaining budget, and check task cancellation before each READDIR request and each decoded entry; recursive transfer MUST also check cancellation for each child. Metadata validation and handle open remain a non-atomic TOCTOU.

### F034-R27: SSH Project Identifier, Canonical Migration, and Parked Presentation

New SSH project IDs MUST use `URLComponents` percent encoding. Backward parsing MUST interpret legacy query/fragment delimiters as remote-path content because project IDs define neither. Canonical migration MUST also recognize the prior raw full identifier formed by concatenating `profile.sshURI` and the unescaped remote path, plus the raw remote path and historical malformed local normalization. Every per-project read or mutation—including terminal/session config, browser state, and project shortcuts—MUST resolve through canonical-plus-alias lookup, rewrite the complete config under the canonical identifier, and remove the migrated alias. VibeSpace validation MUST canonicalize live, unresolved, focused, and parked identifiers, deduplicate parked entries, and remove parked collisions with live/unresolved projects; a changed parent config MUST be saved immediately only when its existing integrity signature verified. `loadProjectConfigs` MUST include live, unresolved, and parked projects and key results canonically. Runtime pruning MUST preserve settings and shortcut slots for parked and unresolved projects. Parked rows MUST use the shared parser without activating a session, show a server icon and SSH badge, display literal host plus non-default port and only `…/basename`, omit user and ancestor paths from visible/accessibility text, hash the persisted identifier in the accessibility identifier, remain inactive, and expose only Activate Project and Remove Project. Host/port, abbreviated path, combined detail, badge, and accessibility sentence MUST be produced through localized `AppStrings` formatting.

### F034-R28: Bounded Cancellation, Process Teardown, and Port Validation
SFTP termination MUST close its input, request graceful process termination, wait up to one second, send SIGKILL when the child remains alive, and wait for exit before releasing resources. Timed SSH commands MUST likewise wait for termination and use SIGKILL fallback. SSH URI parsing, connection-form/profile construction, port-forward creation, and SSH-config import MUST each reject zero, malformed/non-numeric, negative, and greater-than-65535 ports before conversion or use; only whole-number ports in 1...65535 are valid.

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
**And** another SSH project may expose the same raw repository root on a different host
**When** user opens the source control sidebar or selects a changed file
**Then** discovery and repository models retain the originating project's exact host-qualified `projectIdentifier`
**And** the repository attaches only to that exact project
**And** status, branch, stage, unstage, commit, checkout, and history use that project's `gitExplorer`
**And** a tracked-file diff combines non-empty staged and working-tree output into a preloaded diff tab carrying that identifier
**And** an untracked/new file opens through that project's exact file-content provider

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

### Scenario F034-S14: Active remote rows expose location-safe external actions

**Given** an active SSH file, folder, or project-root row is visible
**When** its context menu opens
**Then** `Open in System` and `Download…` are available
**And** `Reveal in Finder` is absent
**And** dragging the remote row does not begin a transfer

### Scenario F034-S15: Open in System launches only a successful protected snapshot

**Given** the user chooses Open in System for an active remote item
**When** transfer and validation succeed
**Then** Crispy creates an owner-only application temporary snapshot
**And** launches that snapshot through macOS
**And** retains it for the receiving application with cleanup after 24 hours
**And** external edits to that copy do not write back or synchronize to the remote source
**But** any transfer, validation, snapshot-write, or launch failure opens neither an older snapshot nor stale content

### Scenario F034-S16: Download publishes only a complete staged result

**Given** the user chooses Download… for a remote file, folder, or project root
**When** the save panel returns a destination
**Then** Crispy transfers into a hidden sibling staging item
**And** the selected destination appears or is replaced only after the complete transfer succeeds
**And** failure or cancellation removes staging without publishing a partial destination

### Scenario F034-S17: Recursive transfer builds a confined regular-file manifest

**Given** a remote directory is selected for Open in System or Download…
**When** Crispy enumerates its recursive manifest
**Then** regular hierarchy and hidden files are preserved
**And** traversal stops with an error above 250,000 items or 256 levels
**And** the configured remote root may resolve through its configured symlink to establish the canonical root
**And** every child receives `lstat`
**And** symlinks and special entries are rejected after `lstat` without `realpath`
**And** every accepted regular-file or directory child receives `realpath` plus a canonical-root check
**And** nested symlinks, invalid names, and root escapes are rejected
**And** source size and modification time are captured for later verification

### Scenario F034-S18: Transfer uses a dedicated streamed SFTP channel

**Given** a validated remote transfer manifest exists
**When** file bytes are copied
**Then** a dedicated SFTP channel is used rather than the explorer channel
**And** local writes are streamed in 128 KiB chunks
**And** the recorded source size and modification time are verified so remote mutation fails the transfer

### Scenario F034-S19: App-wide overlay serializes coordinator-backed explorer/root transfers

**Given** one Open in System or Download… transfer from an explorer file/folder row or active project root is active
**When** another coordinator-backed explorer/root transfer is requested
**Then** it does not run concurrently in a second coordinator slot
**And** the shared overlay shows the active operation's preparing, transferring, cancelling, or publishing state
**And** Cancel is unavailable while cancelling or publishing
**And** structured cancellation retains the slot until transport/staging cleanup completes
**And** completion or failure is reported through the overlay, with failure retained until dismissal
**And** an editor-triggered remote HTML Open in System may proceed independently through `ExternalFileOpenService`

### Scenario F034-S20: Parked SSH rows remain inactive and privacy-minimized

**Given** a parked project identifier is a persisted `ssh://` URI, including a percent-encoded current ID, legacy raw query/fragment delimiters, or the prior raw full SSH identifier
**When** its configuration loads and its row renders through the shared parser
**Then** live, unresolved, focused, and parked parent identifiers canonicalize to the current percent-encoded form
**And** duplicate parked values and parked collisions with live/unresolved projects are removed
**And** a changed verified parent config is saved immediately, while an untrusted parent is not re-signed
**And** the complete per-project config migrates from a supported alias to the canonical key and the alias is removed
**And** live, unresolved, and parked configs load under canonical keys while runtime pruning preserves dormant settings and shortcut slots
**And** the row shows a server icon and SSH badge
**And** visible/accessibility detail contains the literal host, a non-default port when present, and only `…/basename`
**And** username and ancestor path components are omitted
**And** the accessibility identifier hashes the persisted identifier
**And** only Activate Project and Remove Project are available
**And** remote file operations require activation first

### Scenario F034-S21: Remote drag/drop remains unsupported

**Given** an SSH-backed file, folder, or project root is visible
**When** the user attempts a drag/drop transfer
**Then** no remote transfer starts
**And** Download… remains the supported copy-out workflow

### Scenario F034-S22: Enumeration, cancellation, teardown, and ports fail safely

**Given** SFTP returns dot entries, a batch larger than the remaining manifest budget, or cancellation during traversal/transfer
**When** Crispy processes the response
**Then** dot entries do not consume the accepted-entry budget
**And** the cap is enforced before each accepted non-dot entry is appended
**And** cancellation is checked per decoded entry and per transfer child
**And** a selected source or child is classified with `lstat` before any `realpath`
**And** shutdown waits for graceful process exit, escalates to SIGKILL when required, and waits for exit
**And** SSH URI parsing, connection forms/profile construction, port forwarding, and SSH config import each reject `0`, malformed/non-numeric, negative, and greater-than-65535 ports
**And** only whole-number ports in 1...65535 reach conversion or use

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
- Create, rename, and delete operations work on remote files; remote drag/drop remains unsupported.
- Active remote file, folder, and project-root menus provide Open in System and Download… without Reveal in Finder.
- One app-wide overlay serializes coordinator-backed explorer file/folder and active project-root transfers, retains the slot through cancellation cleanup, hides Cancel while cancelling/publishing, and retains failure until dismissal; editor HTML open remains independent.
- Download uses hidden sibling staging, creates partial regular files owner-only, verifies exact byte counts, and publishes/replaces the destination only after success.
- Remote system-open snapshots are owner-only, copy-only, retained after successful launch, removed after failed launch, and cleaned opportunistically after 24 hours; editor staging also cleans at app construction/startup and later use.
- Recursive transfer preserves hidden regular-file hierarchy and enforces 250,000-item/256-depth limits. The configured root may canonicalize through its configured symlink; every child receives `lstat`, symlink/special children are rejected without `realpath`, accepted regular/directory children receive `realpath` plus a canonical-root check, nested symlinks are rejected, and regular files are verified before/after streaming with exact local byte counts.
- SFTP validates request IDs for REALPATH, OPENDIR, READDIR, STAT, LSTAT, OPEN, READ, WRITE, CLOSE, MKDIR, REMOVE, and RENAME; strictly parses NAME; requires explicit EOF for reads/directory enumeration and OK for write/close; bounds packets to 1…64 MiB; and enforces exact byte counts.
- Parked `ssh://` rows use shared current/legacy parsing, show literal host/non-default port plus only `…/basename`, omit user/ancestors, hash the accessibility identifier, and remain inactive with only Activate Project and Remove Project.
- SSH persistence canonicalizes live/unresolved/focused/parked identifiers, deduplicates parked identities, immediately saves only changed verified parents, migrates complete project state from canonical/raw-path/prior-raw-full/malformed aliases, loads parked and unresolved configs under canonical keys, and preserves dormant settings and shortcut slots (F034-R27).
- F034-R12 remains unmet: neither remote editing nor explicit Download provides the required size-confirmation prompt; Download only provides manifest/item/byte progress.
- Remote projects persist in vibespace config across restarts.
- Remote projects connect asynchronously; failures degrade gracefully.
- Local port forwarding works and is visible in the UI.
- No secrets stored on disk.
- Host key verification prompts on first connection.
- All file transfers occur over encrypted SSH channel.
- Git operations work identically on remote projects.
- Git unavailability on remote host is detected and surfaced.
- SFTP caps count accepted non-dot entries with per-entry cancellation, transfer traversal checks cancellation per child, selected symlinks are rejected by `lstat` before `realpath`, and child processes are reaped with SIGKILL fallback (F034-R26, R28).
- SSH URI parsing, connection form/profile construction, port forwarding, and SSH config import reject zero, malformed/non-numeric, negative, and greater-than-65535 ports; only 1...65535 is accepted (F034-R28).

## Verification Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly covers complete prior-raw-full config migration, alias deletion, browser/shortcut reads, canonical `loadProjectConfigs`, parked deduplication, and immediate verified-parent rewrite; raw-path and malformed-normalization alias tests also exist. Runtime preservation of every unresolved/parked settings dictionary is production-source inspection. `RemoteProjectSessionTests.testSSHConnectionFormRejectsInvalidPorts` covers form values `0`, `65536`, malformed text, and accepted `65535`; `.testSSHConfigParserRejectsHostsWithInvalidPorts` covers zero/out-of-range config hosts. URI and forwarding port validation remain production-source inspection. Remote source-control tests cover discovery/refresh plumbing only; exact same-root attachment, non-empty staged-then-working concatenation, preloaded qualified tabs, and exact untracked providers remain production-source inspection. Existing confinement, file-kind, identifier, and coordinator tests are compiled static source, while accepted-entry budgeting, cancellation loops, and process reaping are production-source inspection.

## Open Questions

- Should auto-detected port forwarding from terminal output be included in the initial release or deferred?
- Should exponential backoff auto-reconnect be opt-in or off entirely for the first release?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-23 | Extended F034-R27/S20 with canonical SSH parent/per-project migration, prior raw full alias support, parked/unresolved config loading and preservation, trusted-only rewrite, and corrected static/build evidence. | — |
| 2026-10-23 | Reconciled F034-R19/S11 remote repository identity and tracked/untracked diff routing; tightened F034-R28/S22 to reject zero, malformed, negative, and out-of-range ports at URI, form/profile, forwarding, and SSH-config boundaries; corrected static/build-only evidence limits. | — |
| Unreleased | Added default-off enhanced remote explorer polling and create/rename/delete refresh requirements; remote drag/drop remains unsupported. | — |
| 2026-10-23 | Added F034-R28/S22 and tightened F034-R26 for accepted non-dot entry caps, per-entry/per-child cancellation, lstat-before-realpath, process reap/SIGKILL fallback, localized parked details, port bounds, and precise compile/static-only coverage. | — |
| 2026-10-20 | Corrected transport to system `/usr/bin/ssh` ControlMaster plus custom SFTPv3; corrected accepted-child/root-symlink confinement, complete SFTP response validation, publication acknowledgment/final cancellation boundary, diagnostics metadata sanitization, standard Remote SSH versus Enhanced Explorer toggle scope, and unmet large-file confirmation; validation evidence remained build/test-build only with zero executed cases. | — |
| 2026-04-15 | Initial draft — migrated from phase-12-ssh-remote-development.md. | — |
