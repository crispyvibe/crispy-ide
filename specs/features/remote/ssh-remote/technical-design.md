# SSH Remote Development — Technical Design

## Overview

SSH Remote Development uses a protocol-first, vertical-slice architecture. Local and Remote are two independent implementation slices behind shared protocols. No `if isRemote` checks exist anywhere — views and ViewModels consume only protocols via type-erased wrappers. The remote slice can be compiled out or feature-flagged off with zero runtime cost.

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

### Hybrid SSH Transport

1. Subprocess-based SSH/SFTP (`SFTPSubprocess`) for project services: connection state, SFTP file access, remote command execution, keepalive, vibespace-scoped retry UI.
2. System `/usr/bin/ssh -t` for remote terminal PTYs: shell behavior stays isolated from the app's file-service channel.
3. Terminal presentation is gated on the app-managed connection reaching `.connected` state.

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

### Factory

`ProjectSessionFactory` (protocol, with `DefaultProjectSessionFactory` as concrete conformer) creates `AnyProjectSession` via `makeLocal(rootURL:)` or `makeRemote(connection:remotePath:)`. Injected into `VibeSpaceState`.

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
10. Wire into `AppContainer` with feature flag

PRs 1–2 (protocol extraction + vibespace migration) land on main before remote code starts. PR 3 (SSH core) is all new code. PR 4 (UI wiring) adds the feature flag toggle. Feature flag is off by default.

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
