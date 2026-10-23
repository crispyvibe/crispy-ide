---
title: "SSH Remote Development"
feature: "F034"
domain: "remote"
audience: "user"
version: "1.5"
sidebar:
  label: "SSH Remote"
  order: 1
---

# SSH Remote Development

## Overview

SSH Remote Development enables opening projects, browsing files, running terminals, and performing source control operations on remote machines over SSH — all from the same Crispy window used for local work. It uses a lightweight, no-server-agent approach: only a standard SSH server is required on the remote host.

## Getting Started

1. Open **App Settings → Connections** (Remote tab).
2. Create a new SSH connection profile with hostname, port, username, and key file.
3. Click **Test Connection** to verify connectivity.
4. Add a remote project to your vibespace: use "Add Remote Folder" during vibespace creation or project addition.
5. Select the connection profile and browse remote directories to choose a project root.

## Workflows

### Creating an SSH Connection Profile

1. Open **App Settings → Connections**.
2. Click **+** to create a new profile.
3. Enter: display name, hostname, port (default 22), username.
4. Select authentication method: key file path or SSH agent.
5. Click **Test Connection** to validate.
6. Save the profile.

### Importing Hosts from SSH Config

1. In App Settings → Connections, click **Import from SSH Config**.
2. Crispy parses `~/.ssh/config` and shows discovered hosts with checkboxes.
3. Select the hosts you want to import.
4. Imported hosts appear as connection profiles without manual configuration.
5. User-created profiles override SSH config entries for the same host.

### Adding a Remote Project to a Vibespace

1. When creating or editing a vibespace, click **Add Remote Folder**.
2. A connection picker appears — select your SSH profile.
3. A remote directory browser loads the remote filesystem.
4. Navigate to and select the desired project directory.
5. The remote project is added to your vibespace with a `ssh://user@host:port/path` URI.

### Browsing Remote Files

1. With a remote project open, the file explorer shows the remote directory tree.
2. Directories load lazily via SFTP — only expanded directories are fetched.
3. A loading indicator appears during directory fetches.
4. Basic file operations (create, rename, and delete) work on remote files. Remote drag and drop is not supported; use **Download…** to copy remote content locally.
5. Remote project roots show an `[ssh]` suffix and expose an explicit refresh button.

### Editing Remote Files

1. Click a remote file in the explorer to open it.
2. Text content is fetched via SFTP and displayed in the editor.
3. Edit normally — saving writes back via SFTP.
4. Image and PDF previews materialize a staged local file for native rendering.
5. Large-file editing confirmation is not currently implemented. Opening a large remote file for editing may begin the read without a size prompt.

### Opening a Remote Item in a System Application

1. Right-click an active remote file, folder, or project root and choose **Open in System**. Remote menus do not show **Reveal in Finder**.
2. Crispy makes an owner-only temporary local copy, then opens it in the default macOS application only after the transfer succeeds.
3. The app-wide explorer/project transfer overlay shows preparation and transfer progress, then cancelling, publication, completion, or failure. Cancel disappears once cancellation or publication begins. Cancelling keeps the transfer slot occupied until the connection and partial-copy cleanup finish; a failure remains visible until you dismiss it.
4. The temporary copy is retained so the other application can keep reading it; stale copies older than 24 hours are cleaned up opportunistically when the remote transfer service stages another item.

The opened item is a copy. Changes made in the external application do not synchronize or write back to the remote source. If transfer, validation, local writing, or the macOS launch fails, Crispy removes the newly created failed-launch copy and does not open an older one. This overlay and its one-at-a-time slot cover explorer file/folder and active project-root actions only. Remote HTML opened from its editor is independent: its app-level staging service cleans stale copies at app startup and later staging, and reports busy/failure in the editor rather than this overlay.

### Downloading a Remote File, Folder, or Project

1. Right-click an active remote item and choose **Download…**.
2. Choose a local destination in the macOS save panel.
3. Crispy downloads into a hidden temporary item beside that destination. The overlay reports manifest, item, and byte progress. The selected destination appears or is replaced only after the entire transfer succeeds; there is currently no size-confirmation prompt.
4. If the operation fails or you cancel it before the final publication boundary, Crispy removes the staged item and does not publish a partial destination.

Folder and project downloads preserve regular folders, files, and hidden items. A configured remote root may resolve through its configured symlink to establish the canonical root. Nested symlinks and special entries are rejected after type inspection; accepted regular-file and directory children are canonicalized and checked against that root. Crispy also stops and reports an error if the source exceeds 250,000 items or 256 directory levels, uses an invalid name, escapes the canonical root, or changes size/modification time during transfer.

Only one Open in System or Download… operation can use the app-wide transfer overlay at a time.

### Using Source Control on Remote Projects

Remote repositories use the selected project's SSH Git backend and remain attached to that exact project, even when another server exposes the same folder path. Selecting a tracked changed file opens a preloaded diff containing its staged changes followed by its working-tree changes (empty sections are omitted). Selecting an untracked/new file opens the remote file through that project's own provider. Status, stage, unstage, commit, branch, checkout, and history remain scoped to the same host-qualified project.

### Opening Remote Terminals

1. With a remote project connected, open a new terminal.
2. The terminal spawns `/usr/bin/ssh -t` with a PTY attached to the remote host.
3. Remote terminals use the same Ghostty rendering as local terminals.
4. Remote terminals appear in the terminal rail with a **host badge** distinguishing them from local sessions.
5. All rail interactions (close, hide, rename, context menu) work on remote terminals.

### Parked Remote Projects

A parked remote project is recognized from its saved SSH address without reconnecting, using the same parser as active project restoration. Current IDs are percent encoded, and legacy `?`/`#` path content remains compatible. Crispy also migrates the earlier raw full SSH address and other supported legacy keys to the canonical address, carrying terminal/browser state, project settings, and shortcuts. Migration covers active, unavailable, and parked projects; duplicate parked identities are removed and dormant settings remain available. A changed integrity-verified VibeSpace record is saved immediately, while an integrity-failed record is not silently re-signed. Its row uses a server icon and **SSH** badge, shows the literal host (plus a non-default port) and only `…/basename`, omits the username and ancestor paths, and hashes the saved address in its accessibility identifier. While parked, the only actions are **Activate Project** and **Remove Project**. Activate it before browsing files, opening or downloading content, or starting a terminal.

### Managing Connections

1. The **Remote Status Control** appears in the toolbar when your vibespace has remote projects.
2. It shows connection state: connected (neutral icon), connecting (progress icon), or failed (warning icon).
3. Click the control to open a popover listing each remote host with status.
4. Available actions: **Retry**, **Retry All**, **Disconnect**.
5. Port forwarding is managed per-host in the same popover.

### Setting Up Port Forwarding

1. Open the Remote Status Control popover.
2. In the connected host section, find the **Port Forwarding** panel.
3. Add a local port forward (e.g., localhost:3000 → remote:3000).
4. Active forwards are listed as local-to-remote mappings.
5. Stop individual forwards without disconnecting the host.
6. Port forwards are configurable per connection profile and per vibespace.
7. Ports must be whole numbers from 1 through 65535. `0`, malformed/non-numeric text, negative values, and values above 65535 are rejected in SSH addresses, connection profiles, this forwarding panel, and imported SSH config.

### Handling Disconnections

1. If the SSH connection drops, the toolbar status control shows disconnected state.
2. Remote terminals show a terminated/disconnected state.
3. File operations fail with an error banner.
4. Reconnect via the status control — connection recovery is user-initiated.
5. Previously running shell state is not assumed to survive disconnect (use tmux/screen for persistence).

### Host Key Verification

1. On first connection to an unknown host, Crispy shows the host key fingerprint.
2. Review the fingerprint and accept or reject.
3. Accepted keys are written to `~/.ssh/known_hosts`.
4. Subsequent connections to the same host proceed without prompting.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for remote operations. Remote terminals use the same shortcuts as local terminals.

## Settings

- **Enhanced remote file explorer (Beta)** (App Settings → Connections): Default off per device. When enabled, expanded directories receive targeted metadata polling and mutations refresh their affected folder. Reopen remote projects after changing it.
- **Connection Profiles** (App Settings → Connections): Named profiles with host, port, username, and key file.
- **Port Forwards**: Configurable per profile and per vibespace.
- **Large-file confirmation**: Not currently implemented. There is no configurable size-prompt setting; editing and explicit Download can begin without size confirmation, although Download reports manifest/item/byte progress.

## Tips

- Multiple simultaneous connections to different hosts are supported. A single vibespace can contain both local and remote projects.
- Remote projects persist in vibespace config across restarts — connections are re-established asynchronously on open.
- Failed remote connections leave projects in a degraded state rather than removing them. Local projects are never blocked by remote failures.
- Crispy never stores SSH passphrases — authentication goes through the macOS SSH agent / Keychain.
- Connection profiles store only host, port, username, and key file path — no secrets on disk.
- Git operations work identically on remote projects via `RemoteCommandExecutor` over SSH.
- Remote file watching is not supported — use the explicit refresh button on remote project roots.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection fails | Verify hostname, port, and username. Ensure the SSH key is loaded in your agent (`ssh-add -l`). Test with `ssh user@host` in a terminal. |
| Host key verification fails | The host key may have changed. Remove the old entry from `~/.ssh/known_hosts` and reconnect. |
| Remote terminal shows "terminated" | The SSH connection dropped. Use the status control to reconnect. Consider using tmux on the remote for session persistence. |
| File explorer empty after connect | SFTP may still be initializing. Wait a moment and click refresh. Check the status control for connection state. |
| "Git is not installed" on remote | Git must be installed on the remote host. Install it via the remote's package manager. |
| Port forward not working | Ensure the remote service is running on the specified port. Check that the local port isn't already in use. |
| Large remote file opens without confirmation | Large-file editing confirmation is not implemented. Monitor the operation or cancel before publication where the transfer UI offers Cancel. |
| Status control not visible | The control only appears when your vibespace contains remote projects. Add a remote project first. |
| Download failed or was cancelled | The selected destination is not published partially. Correct the connection, permissions, source change, name/link warning, or disk-space issue and restart the download. |
| Open in System reports an error | Crispy did not open stale content. Verify the SSH connection and remote file, then retry. |
| Another remote transfer is already running | Wait for the app-wide transfer overlay to finish or cancel the active operation before starting another. |

## Known Limitations

- Edits made to a remote copy opened in another macOS application do not synchronize or write back to the SSH source.
- Opening a single remote HTML file may not resolve sibling stylesheets, scripts, images, or other relative assets because only that file is copied.
- Remote transfer metadata checks and SFTP file opening remain separate operations. A same-size source can still change within the server's timestamp resolution. Remote HTML Open in System has a broader risk because it performs an unversioned SFTP re-read after save and may open a different remote revision.
- Only one coordinator-backed transfer from an explorer file/folder row or active project root runs at a time. Remote HTML opened from its editor is independent.
- Replacement of an existing local destination follows the macOS save panel and destination filesystem's replacement behavior.
- Cancellation takes effect between transfer chunks or when the SFTP transport returns; the slot remains occupied through cleanup. Before publication, Crispy acknowledges the publishing state and checks cancellation again immediately before replace/move. No Cancel control appears while publishing, and cancellation after the final check may not prevent the atomic publication.
- Interrupted or cancelled transfers cannot resume and must restart from the beginning. Cancellation is checked while listing entries, between child items, and between file chunks; Crispy waits for the transfer process to exit and forcibly stops it if graceful termination stalls.
- Remote drag and drop is unsupported.
- SSH URI, connection profile, port-forward, and imported SSH-config ports must be whole numbers in 1...65535; zero, malformed/non-numeric, negative, and larger values are rejected rather than coerced.

## Documentation Verification

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static tests cover prior raw full SSH config migration with browser/shortcut state, canonical loading, parked deduplication, immediate verified-parent rewrite, invalid connection-form ports, zero/out-of-range SSH-config ports, and remote discovery/refresh plumbing. Runtime preservation of every unavailable/parked settings dictionary, URI/forwarding port boundaries, exact same-root repository attachment, staged-then-working preloaded diffs, and exact untracked providers were verified from production source only. Transfer confinement, SFTP, cancellation, and process teardown evidence remains compiled static source or production inspection.

## Change History

- 2026-10-23: Version 1.5 documents canonical SSH migration for active/unavailable/parked projects, complete state and shortcut preservation, trusted-only rewrite, and corrected final static/build evidence.
- 2026-10-23: Version 1.4 documents exact remote repository/diff/provider ownership and rejection of zero, malformed, negative, and out-of-range ports across URI, profile, forwarding, and SSH-config inputs; narrows verification to static/build-only evidence.
- 2026-10-23: Version 1.3 documents bounded ports and cancellation/process cleanup during remote enumeration and transfer.
- 2026-10-20: Corrected large-file behavior (no editing or Download size prompt), manifest progress, configured-root/nested-symlink handling, unversioned remote HTML reread risk, and the final cancellation/atomic-publication boundary.
