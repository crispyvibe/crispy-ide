# SSH Remote Development — Technical Design

## Overview

SSH Remote Development uses a protocol-first, vertical-slice architecture. Local and remote behavior is primarily separated behind shared protocols and type-erased wrappers, while location-aware presentation and routing still perform explicit remote-capability checks where needed. Remote SSH is a standard app feature and is not compiled out or guarded by a default-off feature flag. Only **Enhanced remote file explorer (Beta)** is controlled by a per-device toggle.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  VibeSpace / Views (protocols only via AnyProjectSession)       │
└──────────────────────────┬──────────────────────────────────────┘
              ┌────────────┴────────────┐
   ┌──────────▼──────────┐  ┌──────────▼──────────┐
   │  Local Slice         │  │  Remote Slice        │
   │  (refactored current │  │  (all new code)      │
   │   code)              │  │                      │
   └──────────────────────┘  └──────────────────────┘
```

### Protocol Layer (`Protocols/`)

Every behavioral seam is a protocol. Key protocols:

- `ProjectProviding` — project session identity, sub-service access, lifecycle
- `ProjectMetadata` — identifier, display name/path, `hostLabel` (nil for local), `connectionState` publisher
- `FolderExploring` — tree browsing, file operations, `supportsLiveWatching`
- `GitExploring` — status, diff, stage, commit, branch, history
- `TerminalProviding` — tab management, session creation/restore
- `FileContentProviding` — read/write files, `requiresMaterializedLocalPreview`
- `FileSystemProviding` — directory listing, create/rename/delete/move
- `DirectoryWatching` — file change notifications
- `CommandExecuting` — execute tool with arguments, return stdout/stderr/exit code
- `SSHConnectionProviding` — connect/disconnect, state publisher, port forwarding

### Type-Erased Wrappers

SwiftUI requires concrete `ObservableObject` types. Type-erased wrappers bridge protocols to views:

- `AnyProjectSession` wraps `any ProjectProviding`, forwards `objectWillChange` from sub-objects
- `AnyFolderExplorer`, `AnyGitExplorer` — same pattern

Views use `@ObservedObject var project: AnyProjectSession` and never see concrete types.

### Local Slice (`Features/Local/`)

Refactored from existing code with zero behavioral changes:

| File | Protocol | Wraps |
|------|----------|-------|
| `ProjectSession` | `ProjectProviding` | Current `ProjectSession` |
| `LocalGitExplorer` | `GitExploring` | Current `PaneWorkerExecutorGit` statics |
| `LocalCommandExecutor` | `CommandExecuting` | `Process()` |
| `LocalFileSystemProvider` | `FileSystemProviding` | `FileManager` |
| `LocalFileContentProvider` | `FileContentProviding` | `Data(contentsOf:)` |

### Remote Slice (`Features/Remote/`)

All new code. No shared code with local except protocols and `GitOutputParser`.

| File | Protocol | Transport |
|------|----------|-----------|
| `RemoteProjectSession` | `ProjectProviding` | Wires all remote services |
| `RemoteFolderExplorer` | `FolderExploring` | SFTP via `SFTPSubprocess` |
| `RemoteGitExplorer` (typealias for `LocalGitExplorer`) | `GitExploring` | SSH remote command execution |
| `RemoteTerminalProvider` | `TerminalProviding` | `/usr/bin/ssh -t` PTY |
| `RemoteCommandExecutor` | `CommandExecuting` | SSH command channel |
| `SFTPFileSystemProvider` | `FileSystemProviding` | `SFTPSubprocess` |
| `SFTPFileContentProvider` | `FileContentProviding` | `SFTPSubprocess` |
| `PollingDirectoryWatcher` | `DirectoryWatching` | Periodic SFTP poll |
| `SSHConnectionManager` | manages `SSHConnection` | `SSHConnection` conforms to `SSHConnectionProviding` |

### Shared Utilities (`Features/Local/`)

- `GitOutputParser` — ~400 lines of git output parsing (status, diff, branch, log) extracted from `PaneWorkerExecutorGit`. Used identically by `LocalGitExplorer` and `RemoteGitExplorer`.

## Data Flow

### System SSH and Custom SFTPv3 Transport

1. System `/usr/bin/ssh` establishes and owns app-managed ControlMaster connections for project lifecycle, command execution, keepalive, port forwarding, and shared authentication/host-key behavior.
2. Crispy's `SFTPSubprocess` speaks the binary SFTPv3 protocol over `/usr/bin/ssh -s sftp` for explorer, content, and bulk-transfer file access.
3. Remote terminal PTYs use separate `/usr/bin/ssh -t` processes while reusing the same OpenSSH configuration and credentials.
4. Terminal presentation is gated on the app-managed connection reaching `.connected` state.

No Citadel runtime is used.

### Remote Source Control Identity and Diff Routing

`VibeSpaceSourceControlProjectReference` retains `projectIdentifier` and uses `projectIdentifier|normalizedRepositoryPath` as the repository ID for project-backed SSH Git. Discovery creates `VibeSpaceSourceControlRepositoryViewModel` with that same identifier and the originating `project.gitExplorer`. Attachment first matches the repository's exact identifier and returns only that project; path-overlap attachment is reserved for non-project-backed/local discovery. Thus two remote hosts exposing the same raw root remain separate.

Selecting a remote tracked status item resolves the target project by the repository's preferred identifier and calls that project's `gitExplorer.loadDiff`. `LocalGitExplorer` in remote mode executes both `git diff --cached -- <path>` and `git diff -- <path>`, drops empty sections, and joins staged then working output. The result opens through `previewGitDiffContent` as a preloaded diff tab whose `FileDocumentReference` carries the exact project identifier; it is not re-read from the local filesystem. An untracked or newly added file without committed history instead opens as a normal file tab with that project's exact `FileContentProviding` instance.

### Connection Model

One app-managed SSH connection per remote host for vibespace/project services. The connection owns SSH state, subprocess-based SFTP access, keepalive monitoring, and retry semantics. Dependent file operations use bounded async readiness retries before failing.

### Connection Readiness Error Detection

`isConnectionReadinessError` identifies transient SSH/SFTP errors eligible for bounded async retry. Matched errors:

- `SSHRemoteError.timeout`
- `SFTPError.notConnected`, `SFTPError.timeout`
- POSIX errors: `ENOTCONN`, `ECONNRESET`, `EHOSTUNREACH`, `ENETDOWN`, `ENETUNREACH`

All other errors return `false` (no retry).

### Editor Integration

The editor routes project-backed file access through `FileContentProviding`:
- `readFile(at:)` / `writeFile(at:contents:)` for text content
- `requiresMaterializedLocalPreview` triggers staged local files for image/PDF rendering via `NSImage`/`PDFDocument`
- Save-back always targets the remote source path

## State Management

### Connection State

```swift
enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}
```

Published via `ProjectMetadata.connectionState`. Views bind to this for host badges, disconnected card states, and toolbar status.

### VibeSpace Integration

`VibeSpaceState.projects` is `[AnyProjectSession]`. Settings are keyed by `metadata.identifier` — local path for local projects, SSH URI for remote. Same dictionary, same lookup, no branching.

### SSH Project Identifiers and Parked Remote Presentation

`SSHConnectionProfile.projectIdentifier(remotePath:)` builds identifiers with `URLComponents`, percent-encoding user, host, and path data correctly. `parseIdentifierLocation` is shared by session restoration and parked-row presentation. For backward compatibility, URL query and fragment portions in legacy raw identifiers are decoded and appended to the remote path because SSH project identifiers define no query or fragment semantics.

A parked project has no live `AnyProjectSession`, so this parser classifies it without network access. The row uses a server icon and SSH badge, shows the literal host with the port appended only when it differs from 22, and abbreviates the remote location to `…/basename`. It omits username and ancestor path components from visible and accessibility text. The accessibility identifier contains `AppDiagnostics.pathToken(identifier)` rather than the persisted identifier itself. Badge, host/non-default-port, abbreviated path, combined detail, and accessibility sentence are produced through localized `AppStrings` entries rather than assembled in the view. Only Activate Project and Remove Project are exposed until an authenticated live session recreates explorer, terminal, Open in System, Download…, and mutation actions.

### Canonical SSH Persistence Migration

`VibeSpaceValidator.normalizedPath` parses `ssh://` identifiers and rebuilds them with `SSHConnectionProfile.projectIdentifier(remotePath:)`. Parent validation applies this to live, unresolved, focused, and parked paths, removes duplicate parked values and parked collisions with live/unresolved projects, and `loadVibeSpace` immediately persists a changed parent only when the loaded signature verified. Untrusted parents are normalized for use but are not re-signed by validation.

Per-project lookup tries the canonical key first, then the raw remote path, the prior raw full identifier created as `profile.sshURI + remotePath`, and the historical malformed local-file normalization. An alias hit migrates the entire `ProjectConfigFile` to the canonical key and deletes the alias. Per-project mutations, terminal/session state, browser state, and project shortcuts all pass through this helper. `loadProjectConfigs` enumerates live, unresolved, and parked identifiers and returns a dictionary keyed by canonical `projectPath`. Runtime state canonicalizes those identities before creating sessions, while pruning and shortcut normalization retain unresolved and parked settings/slots.

### Factory

`ProjectSessionFactory` (protocol, with `DefaultProjectSessionFactory` as concrete conformer) creates `AnyProjectSession` via `makeLocal(rootURL:)` or `makeRemote(connection:remotePath:)`. Injected into `VibeSpaceState`.

### Enhanced Remote Explorer

`crispyvibes.remote.enhancedExplorer` is a per-device, default-off beta setting shown under Settings → Connections. `AppContainer` injects its current value when constructing `RemoteProjectSession`; active sessions are not hot-swapped, so remote projects must be reopened after a change.

`PollingDirectoryWatcher` has two snapshot modes:

- **Legacy:** root-only, names-only snapshots on the existing five-second cadence.
- **Enhanced:** immediate SFTP baselines for the root plus expanded directories, followed by two-second snapshots of name, type, size, and modification date.

Enhanced watcher callbacks identify changed directories. `RemoteFolderExplorer` routes them through a per-directory refresh coordinator that serializes listings, coalesces one follow-up pass, and rejects responses from prior tree generations after reconnect. Manual refresh lists the root and every expanded directory. Create, rename, and delete refresh their affected parent directories before completing visible selection/rename state. Rename components reject separators, `.` and `..`; creation chooses collision-safe names. Remote drag/drop remains unavailable because path-only drag payloads cannot verify project and SSH host identity.

The watcher still reports `supportsLiveWatching = false`: polling is best-effort, and the explicit refresh affordance remains available. No remote helper or server agent is installed.

## Remote Open and Download Architecture (F034-R22–R26)

### App-Wide Explorer/Root Transfer Coordination

`RemoteTransferCoordinator` is injected from `AppContainer` and owns one user-facing slot shared by remote explorer file/folder rows and active project roots. It publishes operation title, item/byte progress, and explicit preparing, transferring, cancelling, publishing, completed, and failed states to one app-wide overlay. Cancel is offered only during preparing/transferring. Calling it marks the operation cancelling and cancels the structured task, but `operationTask` remains occupied until `RemoteItemTransferService` terminates its SFTP process and removes partial staging. Before destination publication, the service synchronously awaits a MainActor acknowledgment that `.publishing` has been installed, then performs a second `Task` cancellation check immediately before replace/move. Publication has no Cancel UI. A cancellation arriving after the final check can coincide with the atomic replace/move and may not prevent publication. Failure remains in the overlay until dismissed. `AppDiagnostics` records remote transfer lifecycle and newly relevant diagnostics; exported diagnostics sanitize path-like strings in event metadata.

This slot does not include editor-triggered HTML Open in System. F009 synchronously captures its buffer/content/file/provider, serializes the captured revision, then calls the separately injected app-level `ExternalFileOpenService`. That path uses editor busy state and the existing editor alert, does not display the remote overlay, and reads through the editor's captured provider rather than a dedicated bulk-transfer channel. An explorer/root transfer and an editor HTML open are therefore independent; no broader global exclusivity is claimed.

Both paths propagate the Boolean result of `VibeSpaceInteractionService.open`/`NSWorkspace.open`, fail closed on `false`, and remove a newly created remote snapshot when launch fails. Neither reuses a prior snapshot.

### Destination and Temporary Snapshot Publication

Download… presents the macOS save panel before transfer. The service creates a uniquely named hidden sibling of the selected destination. Streamed regular files are created with owner-only mode `0600` before the first bytes are written; staged directories use `0700`. Only after enumeration, byte transfer, exact byte-count checking, and source verification succeed does the service publish or replace the selected destination. Failure or cancellation removes the hidden sibling and leaves the chosen destination unpublished or unchanged. Existing-destination behavior follows save-panel and filesystem replacement semantics.

Coordinator-backed Open in System writes to an application-owned temporary snapshot. The remote transfer service applies owner-only permissions and opportunistically removes containers older than 24 hours when creating another temporary container. A successful snapshot is retained for lazy readers; it has no observer, upload, or writeback route. Separately, the app-level `ExternalFileOpenService` used by editor HTML performs stale-container cleanup during its construction at application startup and again before later staging. Both paths propagate a false `NSWorkspace.open` result, remove the newly created failed-launch snapshot, and never reuse an older copy.

### Recursive Manifest and Root Confinement

Before copying, the service resolves the configured project's SFTP `realpath` as the canonical confinement root. The configured root itself may resolve through its configured symlink for this one canonicalization step. Enumeration preserves relative hierarchy and hidden regular files, permits at most 250,000 entries and 256 directory levels, and validates each path component. Empty, `.`, `..`, separator-containing, and NUL-containing names fail the operation. Each child receives `lstat` first. Symbolic links and non-regular/non-directory special entries are rejected immediately after `lstat` without a `realpath` call. Every accepted regular-file or directory child then receives `realpath` and a component-aware canonical-root check. `listDirectory(maximumEntries:)` checks cancellation before each READDIR and each decoded entry; `.` and `..` are skipped before budget accounting, and the cap is checked before appending every accepted non-dot entry. The recursive child loop performs another cancellation check before validating each returned child. Nested symlinks are therefore rejected even though the configured root may canonicalize through its configured symlink.

Every regular file must provide size and modification time. Immediately before streaming, the service revalidates type, canonical path equality/root confinement, size, and mtime. It requires the streamed local byte count to equal the recorded size, then repeats type, canonical path, root, size, and mtime validation after the read. Any mismatch removes staging and prevents publication. These checks narrow inconsistent-snapshot risk but do not make metadata validation and handle open atomic; the SFTP check/open TOCTOU remains.

### Dedicated Streamed SFTP Transfer and Protocol Validation

Coordinator-backed explorer/root bulk operations acquire a dedicated SFTP channel rather than using the explorer's shared interactive channel. Local writes stream in 128 KiB chunks, report progress, and observe cancellation between requests. The dedicated subprocess is terminated at completion or cancellation. Termination closes stdin, requests graceful termination, polls for up to one second, sends SIGKILL if the child remains alive, and waits for exit; timed generic SSH commands likewise await termination and use SIGKILL fallback before releasing pipes. Structured cancellation returns through service cleanup before the coordinator releases its slot. Transfers are restart-only. Port validation is failable at every ingress: `SSHConnectionProfile.parseIdentifierLocation` rejects URI ports outside 1...65535; the connection form/profile builder rejects `0`, malformed/non-numeric, negative, and overflow text; `PortForwardPanel` requires both local and remote `UInt16` values to be greater than zero; and `SSHConfigParser` marks a host invalid and omits it when `Port` is zero, malformed, negative, or above 65535. No invalid value is truncated or wrapped into use.

`SFTPSubprocess` serializes shared-channel wire operations with a lock. A separate lifecycle lock protects `running` and one-time resource closure across termination handlers, cancellation, and teardown. Response request IDs are validated for REALPATH, OPENDIR, READDIR, STAT, LSTAT, OPEN, READ, WRITE, CLOSE, MKDIR, REMOVE, and RENAME. NAME replies are parsed strictly, including record counts and attributes. Whole-file and streamed reads accept only nonempty `SSH_FXP_DATA` packets and terminate successfully only on explicit `SSH_FX_EOF`; READDIR likewise requires explicit EOF. Transport EOF or empty progress before protocol EOF is an error. WRITE and CLOSE require matching `SSH_FXP_STATUS` responses carrying `SSH_FX_OK`. Packet framing accepts lengths from 1 byte through 64 MiB only, and transfer completion requires exact byte counts.

Remote drag/drop remains unsupported. Path-only drag payloads are not promoted into this transfer path; Open in System and Download… are the explicit supported copy-out actions.

## Dependencies (frameworks, libraries)

- `SFTPSubprocess` — subprocess-based SFTP client for remote file operations. No third-party SSH library is used.
- Ghostty (GhosttyKit) — terminal rendering, unchanged. Remote terminals use the same surface with a different backing process.

## Platform Considerations

- macOS only. No server-side component required — only a standard SSH server on the remote host.
- SSH agent integration via macOS Keychain / `ssh-agent`.
- Host key verification writes to `~/.ssh/known_hosts`.

## Performance Constraints

| Operation | Remote Timeout | Rationale |
|-----------|---------------|-----------|
| Git status/diff/branch | 30s | SSH round-trip + remote disk I/O |
| Git probe (availability) | 10s | First probe includes SSH channel setup |
| SFTP directory listing | 15s | Large directories over slow connections |
| SFTP file read/write | 30s | Scales with file size |
| SSH connection establish | 15s | Includes key exchange, auth |
| SSH health check poll | 5s | Lightweight keepalive |

Lazy loading: only expanded directories fetched, file content on open (not selection), git status on project focus.

External-transfer constraints:

- one active coordinator-backed explorer file/folder or active project-root transfer;
- recursive manifest maximum 250,000 items and 256 levels;
- streamed local write chunk size 128 KiB;
- one dedicated SFTP channel for the active coordinator-backed transfer;
- cancellation checked between chunks and transport operations, with the slot retained through cleanup;
- SFTP packet length bounded to 1…64 MiB, request IDs matched, reads ended only by explicit `SSH_FX_EOF`, and write chunks acknowledged by `SSH_FX_OK`;
- no resumability or persisted transfer checkpoint.

## Known Limitations

- Large-file editing confirmation remains an unmet requirement. Neither editing nor explicit Download presents a size-confirmation prompt; Download does provide manifest/item/byte progress.
- A system-open snapshot is a copy. External edits do not synchronize or write back to the remote source.
- Opening one remote HTML file materializes only that file, so relative sibling assets may not resolve in the external application.
- Remote HTML Open in System saves and then performs an unversioned SFTP re-read; the opened copy may contain a different remote revision. This is broader than the manifest metadata-check/open TOCTOU.
- SFTP source metadata checks, handle opening, and reading are not one atomic operation; remote check/open TOCTOU remains, especially with coarse modification times.
- Only one coordinator-backed explorer/root transfer runs at a time. Editor-triggered remote HTML Open in System is independent. Cancellation latency is bounded by the active chunk or transport call, the slot remains occupied through cleanup, and interrupted work restarts from the beginning. Publishing has no Cancel UI; after the synchronous publication acknowledgment and final cancellation check, a cancellation can still race with atomic replace/move and may not prevent publication.
- Existing-destination replacement follows save-panel confirmation and destination filesystem replacement behavior.
- Remote drag/drop is unsupported.

## Migration / Rollout Notes

### Refactoring Sequence

1. Extract protocols (no behavioral changes)
2. Create local slice (rename + conform existing code)
3. Create type-erased wrappers, update view `@ObservedObject` declarations
4. Extract shared `GitOutputParser`
5. Update `VibeSpaceState` to `[AnyProjectSession]`, key settings by `metadata.identifier`
6. Update `VibeSpaceSourceControlViewModel` to use `project.gitExplorer`
7. Update editor for `FileContentProviding`
8. Update views: `project.rootURL` → `project.metadata.*`
9. Build remote slice (all new code)
10. Wire the standard Remote SSH feature into `AppContainer`; expose only Enhanced Explorer through its per-device beta toggle

Remote SSH is part of the standard app path and is not controlled by a default-off feature flag. The only relevant toggle is **Enhanced remote file explorer (Beta)**, which selects polling behavior for newly created remote sessions and defaults off.

## External Dependencies

### SSH Remote Development Integration

Purpose:

- Power SSH-backed projects, remote file access, and vibespace-scoped remote connection state

Behavior:

- SSH connections use system ssh with ControlMaster multiplexing
- Remote file operations use ssh commands over the control socket
- Remote file access uses shared file-system and file-content abstractions
- Remote image and PDF previews stage temporary local files for native renderers
- Connection problems surface through a vibespace-scoped remote status control with retry actions
- The same vibespace-scoped popover hosts per-connection port forwarding controls
- Remote tmux sessions are discoverable from the vibespace `Sessions` sidebar when the host is connected

Technical reference:

- `docs/technical/ssh-remote-development.md`

## Verification Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly checks complete migration from the prior raw full SSH identifier, canonical browser/shortcut reads, alias deletion, canonical loading, parked deduplication, and immediate verified-parent persistence; raw-path and malformed-normalization aliases have separate static cases. Full unresolved/parked runtime settings preservation remains production-source inspection. Static tests cover remote discovery/refresh plumbing and connection-form/SSH-config invalid ports, but not complete same-root attachment, non-empty staged-then-working diff concatenation, exact untracked provider, URI-port, or forwarding-port routes. Accepted-entry cap placement, per-entry/per-child cancellation, and child-process wait/SIGKILL/reap also remain production-source inspection. No build, test, app, or process was run during this documentation reconciliation.

## Change History

- 2026-10-23: Added canonical SSH alias migration and dormant project-state preservation architecture and corrected migration/source-control/port final build/test-build evidence.
- 2026-10-23: Documented project-qualified remote repository identity, exact project `gitExplorer` routing, combined staged+working preloaded diffs, exact untracked providers, and all URI/form/profile/forwarding/config port rejection boundaries; narrowed evidence to static/build-only scope.
- 2026-10-23: Reconciled accepted-entry budgeting/cancellation, selected-source and child lstat ordering, process reap/SIGKILL fallback, localized parked details, port bounds, and compile/static-only verification.
- 2026-10-20: Corrected system OpenSSH ControlMaster/custom SFTPv3 transport and standard-feature rollout; documented accepted-child confinement with configured-root symlink canonicalization, complete request-ID/NAME/EOF/OK/packet/byte validation, synchronous publication acknowledgment and residual cancellation boundary, sanitized diagnostic metadata, unmet size prompts, and unversioned editor-HTML reread risk.
