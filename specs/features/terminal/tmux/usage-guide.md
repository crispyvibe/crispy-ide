---
title: "tmux Integration"
feature: "F010"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "tmux"
  order: 10
---

# tmux Integration

## Overview

tmux Integration provides persistent terminal sessions backed by tmux. When enabled, terminal tabs are wrapped in tmux sessions that survive app quits and restarts — you can close Crispy, reopen it, and find your shell state, scrollback, and running processes exactly where you left them. The feature includes configurable quit/close behavior, a session manager for orphan cleanup, and remote tmux support for SSH-backed projects.

## Getting Started

1. Ensure tmux is installed on your system (Homebrew: `brew install tmux`).
2. Open Settings > Experimental.
3. Enable the "tmux Integration" toggle.
4. New terminal tabs will now be backed by tmux sessions automatically.
5. Existing tabs continue as direct shell sessions until restarted or recreated.

## Workflows

### Creating a tmux-Backed Terminal Tab

1. With tmux integration enabled, create a new terminal tab (click `+` or open a directory in terminal).
2. A unique tmux session name is generated with prefix `crispyvibes-` (e.g., `crispyvibes-a1b2c3d4e5f6`).
3. The terminal launches via `tmux new-session -A -s <name> -c <cwd> <shell>`.
4. Server options are applied automatically: mouse on, 50000 line history, status bar hidden, zero escape-time.

### Reattaching to a Previous Session

1. Close and reopen the vibespace (or quit and relaunch Crispy).
2. On restore, the persisted tmux session name is passed to the new tab.
3. `tmux new-session -A` reattaches to the existing session if it's still alive.
4. You see your previous shell state, scrollback, and any running processes.
5. If the session no longer exists, a fresh session is created with the same name.

### Configuring Quit Behavior

1. Open Settings > Terminal.
2. In the "tmux Integration" card, find the "On quit" picker:
   - **Detach (keep alive)** (default): tmux sessions remain alive on the server when you quit. You can reattach on next launch.
   - **Terminate**: All tmux sessions are killed when you quit. Fresh sessions are created on next launch.

### Configuring Tab Close Behavior

1. In the same "tmux Integration" card, find the "On tab close" picker:
   - **Terminate** (default): Closing a tab kills its tmux session on the server.
   - **Detach (keep alive)**: Closing a tab leaves the tmux session alive as an orphan (visible in the session manager).

### Managing Sessions

1. Open Settings > Terminal > tmux Integration card.
2. Click "Manage Sessions".
3. The session manager sheet shows all `crispyvibes-`-prefixed tmux sessions:
   - **Active** (green indicator): Sessions with attached clients, showing working directory, current command, and last activity time.
   - **Orphaned** (orange indicator): Sessions with zero attached clients, with a "Kill" button per row.
4. Click "Kill" on any orphaned session to destroy it.
5. Click "Kill All Orphans" to destroy all orphaned sessions at once.
6. Click the refresh button (↻) to reload the session list from the tmux server.

### Restarting a Tab with tmux

1. Right-click the tab and select "Restart".
2. The existing tmux session name is preserved.
3. If quit behavior is "Detach", the restart reattaches to the same tmux session.
4. If quit behavior is "Terminate", a fresh session is created with the same name.

### Preset Commands and tmux Reattach

When restoring a tab that has both a startup preset command and an existing tmux session:
- The startup command is **not** re-sent (you see your existing shell state instead of duplicate command execution).
- For new sessions where no tmux session exists yet, the startup command runs normally.

### Remote tmux Sessions (SSH Projects)

1. For SSH-backed projects with tmux available on the remote host, each tab gets a stable tmux session name derived from the SSH project identifier.
2. Reopening the vibespace reattaches to the same remote tmux session.
3. On SSH reconnect, existing remote tabs are restarted against the same tmux session names.
4. If tmux is not found on the remote host, a message is shown and the session falls back to direct shell launch.

### VibeSpace Sessions Sidebar

1. Open the vibespace "Sessions" sidebar.
2. The current vibespace's sessions appear first, grouped by project.
3. Local and remote sessions are shown in one shared tree.
4. Actions per session:
   - **Preview**: Attaches in a temporary spotlight terminal (does not move the session into a project pane).
   - **Open in Project**: Routes the session into a project terminal surface.
   - **Terminate**: Kills the tmux session on the appropriate machine.
   - **Copy Attach Command**: Copies a shell command for attaching from another terminal app.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for tmux management. All terminal keyboard shortcuts (tab creation, focus navigation) work identically whether tmux is enabled or not.

## Settings

| Setting | Location | Default | Effect |
|---------|----------|---------|--------|
| tmux Integration | Settings > Experimental | Off | Enables/disables tmux-backed sessions |
| On quit | Settings > Terminal > tmux card | Detach (keep alive) | Controls whether sessions survive app quit |
| On tab close | Settings > Terminal > tmux card | Terminate | Controls whether sessions survive tab close |
| Manage Sessions | Settings > Terminal > tmux card | — | Opens the session manager sheet |

When tmux integration is disabled, the "tmux Integration" card is hidden from Settings > Terminal entirely.

## Tips

- **Graceful fallback**: If tmux is not installed, sessions launch the shell directly without error — you don't need tmux to use Crispy.
- **Binary detection order**: Crispy checks `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, and `/usr/bin/tmux` in order.
- **Server options**: Crispy applies `mouse on`, `history-limit 50000`, `status off`, and `escape-time 0` globally on every session launch. The status bar is hidden because Crispy provides its own tab UI.
- **Backward compatibility**: Vibespace configs saved before tmux integration existed load normally — the `tmuxSessionName` field decodes as nil and tabs restore without tmux.
- **Orphan visibility**: With "Detach on tab close", closed tabs become orphaned sessions visible in the session manager — useful for long-running processes you want to check on later.
- **Bulk cleanup**: The session manager's "Kill All Orphans" button destroys all orphaned `crispyvibes-` sessions in one action.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| tmux card not showing in Terminal settings | Ensure the toggle is enabled in Settings > Experimental |
| "No tmux sessions found" in manager | No `crispyvibes-`-prefixed sessions exist on the tmux server |
| Session not reattaching on restore | Verify the tmux session is still alive: run `tmux list-sessions` in a separate terminal |
| Startup command running twice | This shouldn't happen — Crispy checks `sessionExists` before sending startup commands on reattach. If it does, file a bug. |
| Remote tmux not working | Ensure tmux is installed on the remote host and accessible via the SSH connection |
| Orphaned sessions accumulating | Use "Manage Sessions" > "Kill All Orphans" periodically, or switch "On tab close" to "Terminate" |
