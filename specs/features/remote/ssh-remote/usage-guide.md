---
title: "SSH Remote Development"
feature: "F034"
domain: "remote"
audience: "user"
version: "1.0"
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
4. Basic file operations (create, rename, and delete) work on remote files. Remote drag/drop move is unavailable until drag payloads can verify project and SSH host identity.
5. Remote project roots show an `[ssh]` suffix and expose an explicit refresh button.

### Editing Remote Files

1. Click a remote file in the explorer to open it.
2. Text content is fetched via SFTP and displayed in the editor.
3. Edit normally — saving writes back via SFTP.
4. Image and PDF previews materialize a staged local file for native rendering.
5. Files exceeding 10 MB show a confirmation prompt before downloading.

### Opening Remote Terminals

1. With a remote project connected, open a new terminal.
2. The terminal spawns `/usr/bin/ssh -t` with a PTY attached to the remote host.
3. Remote terminals use the same Ghostty rendering as local terminals.
4. Remote terminals appear in the terminal rail with a **host badge** distinguishing them from local sessions.
5. All rail interactions (close, hide, rename, context menu) work on remote terminals.

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
- **Large File Threshold**: Default 10 MB — files above this prompt before download.

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
| Large file prompt keeps appearing | The file exceeds the configured threshold. Accept the prompt to download, or increase the threshold in settings. |
| Status control not visible | The control only appears when your vibespace contains remote projects. Add a remote project first. |
