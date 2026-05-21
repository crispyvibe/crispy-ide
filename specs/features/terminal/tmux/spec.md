# tmux Integration — Spec

Status: draft

## Overview

tmux Integration provides persistent terminal sessions backed by tmux. It covers tmux availability detection, session lifecycle (create, reattach, detach, terminate), quit/close behavior policies, tab restart preservation, server option management, a session manager UI, settings layout, persistence/backward compatibility, vibespace sessions browser integration, remote tmux support, and bulk cleanup.

## Dependencies

- F001 (Sessions & Tabs) — tmux wraps terminal session lifecycle
- F034 (SSH Remote Development) — remote tmux sessions require SSH connectivity

## Requirements

### F010-R01: tmux Integration Toggle

Toggling tmux integration on MUST enable tmux-backed terminal sessions. Toggling it off MUST revert to direct shell launch for new sessions.

### F010-R02: tmux Binary Detection

TmuxService MUST check `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, and `/usr/bin/tmux` in order and use the first executable found. It MUST fall back to direct shell launch if none found.

### F010-R03: tmux Unavailable Graceful Fallback

When tmux is not installed, the session MUST launch the shell directly without tmux and no error MUST be shown.

### F010-R04: New Tab Creates tmux Session

A unique tmux session name MUST be generated with prefix `crispyvibes-`. The terminal engine MUST launch `tmux new-session -A -s <name> -c <cwd> <shell>`. Server options MUST be applied (mouse on, history-limit 50000, status off, escape-time 0).

### F010-R05: tmux Session Name Persisted

The tmux session name MUST be stored in `TerminalSessionEntry.tmuxSessionName`. On next app launch, the persisted name MUST be passed to `createTab`.

### F010-R06: Reattach to Existing tmux Session

When a persisted tmux session is still alive, `tmux new-session -A` MUST reattach to the existing session. The user MUST see their previous shell state, scrollback, and running processes.

### F010-R07: Fresh Session When Persisted Session Is Dead

When a persisted tmux session no longer exists, `tmux new-session -A` MUST create a new session with the same name.

### F010-R08: Preset Commands Skipped on Reattach

When restoring a tab with a startup preset command and the tmux session already exists, the startup command MUST NOT be sent. The user MUST see their existing shell state.

### F010-R09: Preset Commands Run for New Sessions

When creating a tab with a startup preset command and no tmux session exists yet, the startup command MUST be sent normally after session start.

### F010-R10: Detach Behavior on App Quit

When "On quit" is "Detach (keep alive)", terminal engines MUST be terminated (tmux client disconnects) but tmux sessions MUST remain alive on the server.

### F010-R11: Terminate Behavior on App Quit

When "On quit" is "Terminate", `TmuxService.killSessionAsync` MUST be called for each tmux-backed session. `terminateAllSessions` MUST be called with `skipTmuxCleanup: true`.

### F010-R12: Terminate Behavior on Tab Close

When "On tab close" is "Terminate", `TmuxService.killSessionAsync` MUST be called for that tab's tmux session.

### F010-R13: Detach Behavior on Tab Close

When "On tab close" is "Detach (keep alive)", the terminal engine MUST be terminated but the tmux session MUST remain alive as an orphan visible in the session manager.

### F010-R14: Tab Restart Preserves tmux Session Name

On tab restart, the existing tmux session name MUST be captured before removal and the new session MUST receive the same name.

### F010-R15: Server Options Applied Before First Session

`TmuxService.applyServerOptions` MUST run `tmux start-server` and set `mouse on`, `history-limit 50000`, `status off`, `escape-time 0`.

### F010-R16: Server Options Applied on Every Session Launch

`applyServerOptions` MUST run on every session launch with `-g` (global) flag.

### F010-R17: Session Manager Shows All CrispyVibes-Owned Sessions

The session manager sheet MUST show all crispyvibes-owned tmux sessions when opened from Settings > Terminal > tmux Integration > Manage Sessions.

### F010-R18: Active Sessions Displayed

Active sessions MUST be shown under "Active" with a green status indicator, working directory, current command, and relative last-activity time.

### F010-R19: Orphaned Sessions Displayed

Orphaned sessions (zero attached clients) MUST be shown under "Orphaned" with an orange status indicator and a "Kill" button per row.

### F010-R20: Kill Individual Orphaned Session

Clicking "Kill" MUST call `TmuxService.killSessionAsync` and remove the row with animation.

### F010-R21: Kill All Orphaned Sessions

"Kill All Orphans" MUST call `TmuxService.killSessionAsync` for each orphaned session and remove all orphaned rows with animation.

### F010-R22: Session Manager Empty State

When no crispyvibes-owned sessions exist, "No tmux sessions found." MUST be displayed.

### F010-R23: Refresh Session List

The refresh button MUST call `TmuxService.listSessionDetails` and update the list with current server state.

### F010-R24: Experimental Settings Contains Only Toggle

The Experimental settings section MUST show only the tmux Integration toggle with title and description. No behavior pickers or manage sessions button.

### F010-R25: Terminal Settings Shows tmux Card When Enabled

When enabled, Settings > Terminal MUST show a "tmux Integration" card with "On quit" picker, "On tab close" picker, and "Manage Sessions" button.

### F010-R26: Terminal Settings Hides tmux Card When Disabled

When disabled, Settings > Terminal MUST show only "Terminal Defaults" with no tmux-related UI.

### F010-R27: Backward Compatible Persistence

Old persisted data without `tmuxSessionName` MUST decode as nil and tab restoration MUST proceed normally without tmux.

### F010-R28: tmux Session Name Round-Trip Persistence

`persistLocalSessionState` MUST populate `tmuxSessionName` from `TerminalSession.tmuxSessionName`. `restoreLocalSessionState` MUST pass it through to `createTab(tmuxSessionName:)`.

### F010-R29: VibeSpace Sessions Sidebar Tree

The vibespace `Sessions` sidebar MUST show current-vibespace sessions first, group by Project with local and remote sections, and show non-CrispyVibes sessions by their real tmux session name.

### F010-R30: CrispyVibes-Managed Session Row Titles

CrispyVibes-managed session rows MUST prefer the matching terminal tab title, then the owning Project title, then a generic `Project Terminal` label.

### F010-R31: Sessions Sidebar Preview and Open Actions

Preview MUST use a temporary spotlight surface. `Open in Project` MUST route into a Project terminal surface. Both MUST attach to the existing tmux session by name.

### F010-R32: Sessions Sidebar Terminate Action

`Terminate` MUST kill the tmux session on the correct machine and refresh the sidebar.

### F010-R33: Remote Stable tmux Session Name

For SSH-backed projects, the tmux session name MUST be derived from a stable hash of `ssh://user@host:port/path`. Reopening MUST reconnect to the same name.

### F010-R34: Remote Reconnect Revives tmux-Backed Tabs

On successful SSH reconnect, existing remote tabs MUST be restarted against the same tmux session names. The previously active tab MUST remain selected.

### F010-R35: Bulk Cleanup of CrispyVibes-Prefixed Sessions

`killAllCrispyVibesSessions` MUST list all sessions matching `crispyvibes-` prefix, kill each via `killSessionAsync`, and return after all are destroyed.

### F010-R36: Remote tmux Unavailability Message

When tmux is not found on the remote host, a message MUST be shown and the session MUST fall back to direct shell launch.

### F010-R37: Pane Command Extraction

TmuxService MUST extract the current pane command via `tmux display-message -p -t <session> '#{pane_current_command}'` and include it in session info.

### F010-R38: Sessions Sidebar Copy Attach Command Action

The vibespace `Sessions` sidebar MUST expose a copy action for each tmux session row that writes a shell command to the clipboard for attaching to that exact session from another terminal app. Local sessions MUST copy a local tmux attach command. Remote sessions MUST copy an SSH command that attaches to the remote tmux session using that row's host configuration.

## Scenarios

### Scenario F010-S01: tmux integration toggle in experimental settings

**Given** user opens Settings > Experimental
**When** the tmux Integration toggle is visible
**Then** toggling it on enables tmux-backed terminal sessions
**And** toggling it off reverts to direct shell launch for new sessions

### Scenario F010-S02: tmux binary detection

**Given** tmux integration is enabled
**When** a terminal session is about to start
**Then** TmuxService checks `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, and `/usr/bin/tmux` in order
**And** uses the first executable found
**And** falls back to direct shell launch if none found

### Scenario F010-S03: tmux unavailable graceful fallback

**Given** tmux integration is enabled but tmux is not installed
**When** a terminal tab is created
**Then** the session launches the shell directly without tmux
**And** no error is shown to the user

### Scenario F010-S04: New terminal tab creates a tmux session

**Given** tmux integration is enabled and tmux is available
**When** a new terminal tab is created
**Then** a unique tmux session name is generated with prefix `crispyvibes-`
**And** the terminal engine launches `tmux new-session -A -s <name> -c <cwd> <shell>`
**And** tmux server options are applied (mouse on, history-limit 50000, status off, escape-time 0)

### Scenario F010-S05: tmux session name is persisted across app restarts

**Given** a terminal tab has an active tmux session
**When** the vibespace state is saved
**Then** the tmux session name is stored in `TerminalSessionEntry.tmuxSessionName`
**And** on next app launch, `restoreTabsFromEntries` passes the persisted name to `createTab`

### Scenario F010-S06: Reattach to existing tmux session on restore

**Given** a persisted terminal entry has a tmux session name
**And** that tmux session is still alive on the server
**When** the tab is restored
**Then** `tmux new-session -A` reattaches to the existing session
**And** the user sees their previous shell state, scrollback, and running processes

### Scenario F010-S07: Fresh session created when persisted tmux session is dead

**Given** a persisted terminal entry has a tmux session name
**And** that tmux session no longer exists on the server
**When** the tab is restored
**Then** `tmux new-session -A` creates a new session with the same name
**And** the user gets a fresh shell

### Scenario F010-S08: Preset commands are skipped on tmux reattach

**Given** a terminal tab is being restored with a startup preset command
**And** the tmux session already exists (reattach scenario)
**When** `runStartupCommandOnTab` executes
**Then** `TmuxService.sessionExists` returns true before `startIfNeeded`
**And** the startup command is not sent to the session
**And** the user sees their existing shell state without duplicate command execution

### Scenario F010-S09: Preset commands run normally for new tmux sessions

**Given** a terminal tab is being created with a startup preset command
**And** no tmux session with that name exists yet
**When** `runStartupCommandOnTab` executes
**Then** `TmuxService.sessionExists` returns false
**And** the startup command is sent normally after session start

### Scenario F010-S10: Detach behavior on app quit (default)

**Given** tmux "On quit" setting is "Detach (keep alive)"
**When** the app quits or vibespace shuts down
**Then** terminal engines are terminated (tmux client disconnects)
**And** tmux sessions remain alive on the server
**And** sessions can be reattached on next app launch

### Scenario F010-S11: Terminate behavior on app quit

**Given** tmux "On quit" setting is "Terminate"
**When** the app quits or vibespace shuts down
**Then** `TmuxService.killSessionAsync` is called for each tmux-backed session
**And** tmux sessions are destroyed on the server
**And** `terminateAllSessions` is called with `skipTmuxCleanup: true` to avoid double-kill

### Scenario F010-S12: Terminate behavior on tab close (default)

**Given** tmux "On tab close" setting is "Terminate"
**When** a terminal tab is closed
**Then** `TmuxService.killSessionAsync` is called for that tab's tmux session
**And** the tmux session is destroyed on the server

### Scenario F010-S13: Detach behavior on tab close

**Given** tmux "On tab close" setting is "Detach (keep alive)"
**When** a terminal tab is closed
**Then** the terminal engine is terminated (tmux client disconnects)
**And** the tmux session remains alive on the server as an orphan
**And** the orphan is visible in the tmux session manager

### Scenario F010-S14: Restarting a tab preserves tmux session name

**Given** a terminal tab has an active tmux session
**When** the user restarts the tab
**Then** the existing tmux session name is captured before the old session is removed
**And** the new session receives the same tmux session name
**And** `tmux new-session -A` reattaches to the existing tmux session (if detach behavior) or creates fresh (if terminate behavior)

### Scenario F010-S15: Server options applied before first session

**Given** tmux integration is enabled
**When** the first terminal session is about to launch
**Then** `TmuxService.applyServerOptions` runs `tmux start-server`
**And** sets `mouse on` (scroll events scroll buffer instead of sending arrow keys)
**And** sets `history-limit 50000` (generous scrollback)
**And** sets `status off` (hides tmux status bar since CrispyVibes has its own tab UI)
**And** sets `escape-time 0` (eliminates Escape key delay for vim/neovim)

### Scenario F010-S16: Server options applied on every session launch

**Given** tmux server options were previously applied
**When** another terminal session launches
**Then** `applyServerOptions` runs again to ensure settings persist
**And** options use `-g` (global) flag so they apply server-wide

### Scenario F010-S17: Opening the session manager

**Given** tmux integration is enabled
**When** user navigates to Settings > Terminal > tmux Integration card
**And** clicks "Manage Sessions"
**Then** a sheet opens showing all crispyvibes-owned tmux sessions

### Scenario F010-S18: Active sessions displayed

**Given** tmux sessions exist with attached clients
**When** the session manager is open
**Then** active sessions are shown under the "Active" section header
**With** a green status indicator, working directory, current command, and relative last-activity time

### Scenario F010-S19: Orphaned sessions displayed

**Given** tmux sessions exist with zero attached clients
**When** the session manager is open
**Then** orphaned sessions are shown under the "Orphaned" section header
**With** an orange status indicator and a "Kill" button per row

### Scenario F010-S20: Kill individual orphaned session

**Given** an orphaned tmux session is shown in the manager
**When** user clicks "Kill"
**Then** `TmuxService.killSessionAsync` is called for that session
**And** the row is removed from the list with animation

### Scenario F010-S21: Kill all orphaned sessions

**Given** orphaned tmux sessions exist
**When** user clicks "Kill All Orphans"
**Then** `TmuxService.killSessionAsync` is called for each orphaned session
**And** all orphaned rows are removed from the list with animation

### Scenario F010-S22: Empty state

**Given** no crispyvibes-owned tmux sessions exist
**When** the session manager is open
**Then** "No tmux sessions found." is displayed

### Scenario F010-S23: Refresh session list

**Given** the session manager is open
**When** user clicks the refresh button
**Then** `TmuxService.listSessionDetails` is called
**And** the session list is updated with current server state

### Scenario F010-S24: Experimental settings contains only the toggle

**Given** user opens Settings > Experimental
**Then** the tmux Integration toggle is visible with title and description
**And** no behavior pickers or manage sessions button are shown in this section

### Scenario F010-S25: Terminal settings shows tmux card when enabled

**Given** tmux integration is enabled via the experimental toggle
**When** user navigates to Settings > Terminal
**Then** a "tmux Integration" card appears below "Terminal Defaults"
**With** "On quit" picker (Detach / Terminate, default: Detach)
**And** "On tab close" picker (Detach / Terminate, default: Terminate)
**And** "Manage Sessions" button

### Scenario F010-S26: Terminal settings hides tmux card when disabled

**Given** tmux integration is disabled
**When** user navigates to Settings > Terminal
**Then** only the "Terminal Defaults" card is shown
**And** no tmux-related UI is visible

### Scenario F010-S27: Old persisted data loads without tmux session name

**Given** vibespace config was saved before tmux integration existed
**When** `TerminalSessionEntry` is decoded from JSON
**Then** `tmuxSessionName` decodes as nil (optional field, auto-synthesized Codable)
**And** tab restoration proceeds normally without tmux

### Scenario F010-S28: tmux session name round-trip persistence

**Given** a terminal tab has a tmux session name
**When** `persistLocalSessionState` saves the vibespace
**Then** `TerminalSessionEntry.tmuxSessionName` is populated from `TerminalSession.tmuxSessionName`
**And** when `restoreLocalSessionState` loads the vibespace
**Then** the tmux session name is passed through to `createTab(tmuxSessionName:)`

### Scenario F010-S29: VibeSpace sessions sidebar shows local and remote tmux sessions in one tree

**Given** tmux sessions exist locally, remotely, or both
**When** the user opens the vibespace `Sessions` sidebar
**Then** current-vibespace sessions appear before sessions from other VibeSpaces
**And** the tree groups sessions by Project with local and remote sections
**And** non-CrispyVibes sessions remain visible by their real tmux session name

### Scenario F010-S30: CrispyVibes-managed session rows prefer a terminal or project title over the raw tmux id

**Given** a tmux session name starts with the CrispyVibes-managed `crispyvibes-` prefix
**When** the vibespace `Sessions` sidebar renders that row
**Then** the row title prefers the matching terminal tab title when available
**And** otherwise falls back to the owning Project title
**And** only unowned CrispyVibes-managed sessions fall back to a generic `Project Terminal` label

### Scenario F010-S31: VibeSpace sessions sidebar preview and open actions attach to existing tmux sessions

**Given** a tmux session is listed in the vibespace `Sessions` sidebar
**When** the user previews it or opens it in a Project
**Then** Crispy attaches to the existing tmux session by name
**And** preview uses a temporary spotlight surface while `Open in Project` routes it into a Project terminal surface

### Scenario F010-S32: VibeSpace sessions sidebar terminate action kills local or remote tmux sessions

**Given** a tmux session is listed in the vibespace `Sessions` sidebar
**When** the user chooses `Terminate`
**Then** Crispy kills the tmux session on the correct machine
**And** the sidebar refreshes to remove the terminated session from the tree

### Scenario F010-S33: Remote project terminals use a stable tmux session name derived from the SSH project identifier

**Given** a Project is backed by SSH and tmux is available on that host
**When** CrispyVibes seeds a tmux session name for that Project without a saved entry
**Then** the name is derived from a stable hash of `ssh://user@host:port/path`
**And** reopening the same VibeSpace reconnects to that same remote tmux session name

### Scenario F010-S34: Explicit remote reconnect revives existing remote tmux-backed tabs

**Given** a remote tmux-backed Project terminal already exists in the app
**When** the SSH connection drops and the user reconnects it explicitly
**Then** CrispyVibes restarts those existing remote tabs against the same tmux session names
**And** the previously active tab remains selected after reconnect

### Scenario F010-S35: Bulk cleanup of all crispyvibes-prefixed tmux sessions

**Given** one or more tmux sessions with the `crispyvibes-` prefix exist on the server
**When** `killAllCrispyVibesSessions` is invoked
**Then** TmuxService lists all sessions matching the `crispyvibes-` prefix
**And** kills each one via `killSessionAsync`
**And** returns after all sessions have been destroyed

### Scenario F010-S36: Remote tmux unavailability message

**Given** a Project is backed by SSH
**And** tmux is not installed or not found on the remote host
**When** CrispyVibes attempts to start a tmux-backed terminal session on that host
**Then** a message is shown indicating tmux is not available on the remote host
**And** the session falls back to a direct shell launch

### Scenario F010-S37: Pane command extraction for session info enrichment

**Given** a tmux session is active with a running pane
**When** TmuxService gathers session details
**Then** it extracts the current pane command via `tmux display-message -p -t <session> '#{pane_current_command}'`
**And** includes the command in the session info returned to the caller

### Scenario F010-S38: Sessions sidebar copies an attach command for the selected tmux session

**Given** a tmux session is listed in the vibespace `Sessions` sidebar
**When** user selects the row action to copy its attach command
**Then** CrispyVibes writes a shell command to the clipboard for that exact session
**And** local sessions copy a local tmux attach command
**And** remote sessions copy an SSH command that attaches to the remote tmux session

## Acceptance Criteria

- tmux binary detection completes within 100ms (PERF-1).
- Session reattach completes within 500ms (PERF-4).
- No orphaned tmux sessions after terminate-on-quit (REL-6).
- Session manager UI is keyboard-navigable (A11Y-2).
- All tmux lifecycle events logged (OBS-1, OBS-2).
- Backward-compatible persistence decoding (REL-1).

## Open Questions

- Should tmux integration be promoted from experimental to default?
- Should the session manager support filtering by project?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/terminal/tmux-integration.md (TMUX-001–037) | — |
