# Terminal Sessions & Tabs — Spec

Status: draft

## Overview

Terminal Sessions & Tabs covers the full lifecycle of terminal sessions within Crispy: tab creation, shell resolution, environment setup, appearance/density, metadata tracking, clipboard commands, restart/restore behavior, shortcut commands, interactive links/targets, remote terminal activation, vibespace sessions browser, terminal insight, focus coordination, and controlled startup instrumentation.

## Dependencies

- F002 (Terminal Board) — board tiles are backed by terminal tabs/sessions
- F003 (Terminal Spotlight) — spotlight surfaces reuse terminal sessions
- F004 (Terminal Rail) — rail cards reflect session state
- F005 (Terminal Presets) — presets launch terminal sessions
- F010 (tmux) — tmux-backed sessions extend session lifecycle

## Requirements

### F001-R01: Empty Terminal State

The terminal pane MUST show a `No Terminal Tabs` placeholder when no tabs exist.

### F001-R02: Active Terminal Session View

When a tab is active, the terminal header MUST show the active tab working directory path. The pane chrome MUST NOT show a persistent `Running` status label. The terminal session host view MUST be embedded below the header.

### F001-R03: Terminal Unavailable Fallback

When the active tab no longer has a session object, the pane MUST show a `Terminal Unavailable` placeholder.

### F001-R04: New Tab Directory Fallback

When a tab is created without an explicit directory, the new tab working directory MUST default to the active tab directory, or the user home directory if no active tab exists. Keyboard focus MUST move to the new active terminal session.

### F001-R05: Open in Terminal De-duplication

When a tab already exists for a normalized directory path, that existing tab MUST be selected and no duplicate tab MUST be created.

### F001-R06: Open in Terminal New Tab

When no tab exists for a normalized directory path, a new tab MUST be created for that directory and become active.

### F001-R07: Close Tab Active Selection

When the active tab is closed, the tab session MUST be terminated and the active tab MUST fall back to the last remaining tab if any.

### F001-R08: Tab Selection Starts Session

When a user selects a tab, the corresponding terminal session MUST be started if it was not already started.

### F001-R09: Shell Resolution Precedence

The shell executable MUST be resolved by precedence: Project override → VibeSpace default → App default → process `SHELL` → `/bin/zsh`. Unavailable shell candidates MUST fall through to the next level. Shell args MUST include `-i`. Current working directory MUST be the tab's working directory.

### F001-R10: Terminal Environment

The terminal environment MUST set `TERM=xterm-256color` and `COLORTERM=truecolor`. Locale defaults for UTF-8 MUST be enforced if missing. Common color-enabling variables (`CLICOLOR`, `CLICOLOR_FORCE`, `FORCE_COLOR`) MUST be set. `NO_COLOR` MUST be removed if present.

### F001-R11: Regular Density in Focused Pane

The terminal font MUST use regular density sizing when shown in the main terminal pane.

### F001-R12: Compact Density in Stacked Rail Card

The terminal font MUST use compact density sizing when shown inside a stacked project rail card. Compact font size MUST follow app preference `railTerminalCompactFontSize` and be clamped to the supported range.

### F001-R13: Host Ownership Handoff

Only one host container MUST own the terminal view at a time. The non-owning host MUST defer attach until ownership can be acquired.

### F001-R14: Owning Host Controls Density

The owning host MUST apply the target density for that surface. Non-owning hosts MUST NOT overwrite density.

### F001-R15: Inactive Project Terminal Keeps Running

When a project is inactive in the stacked rail, the shell process MUST remain active and output MUST be visible in the rail preview when rendered.

### F001-R16: Terminal Colors Follow System Appearance

When app appearance changes, terminal native colors MUST be reconfigured and background color MUST be updated.

### F001-R17: Terminal Title Updates Tab Title

When shell/command updates terminal title, the tab's session title MUST be updated. Tab display title MAY use that value when no custom name exists.

### F001-R18: Directory Updates Propagate

When shell emits current directory update, the tab working directory metadata MUST update to the emitted path.

### F001-R19: Git Branch Metadata

When a terminal tab is created, selected, or changes directories inside a git repository with a resolvable branch, the tab git branch metadata MUST update to that branch name. Terminal board headers MUST show that branch badge. Non-git directories MUST clear the branch badge.

### F001-R20: Process Termination Metadata

When a terminal process exits, the tab exit code MUST be stored and tab activity state MUST be set inactive.

### F001-R21: Copy Command Targets Active Tab

The copy action MUST execute on the active tab session selection.

### F001-R22: Paste Command Targets Active Tab

Clipboard content MUST be pasted into the active tab session.

### F001-R23: Restart Project Rebuilds Terminal Pane

On project restart, all sessions MUST be terminated, tab/session state MUST be cleared, and a fresh tab MUST be created automatically.

### F001-R24: Terminal Tabs Restore from Persistence

Terminal tabs MUST be restored from per-project config entries. The active tab MUST be restored using saved active directory when available. Only the active restored tab MUST be started immediately.

### F001-R25: Non-Active Restored Tabs Stay Lazy

Non-active restored tabs MUST keep session metadata without starting shell processes. Selecting one MUST start its session on demand.

### F001-R26: Terminal Restore Fallback

When no valid terminal state is available, a terminal tab MUST be created at the Project root directory.

### F001-R27: Shortcut Commands Loaded Together

Both vibespace-scoped and project-scoped shortcut groups MUST appear for the current vibespace context. Updates from vibespace settings MUST reload available shortcut commands.

### F001-R28: Current-Terminal Shortcut Runs In-Place

A `currentTerminal` shortcut MUST queue onto the focused terminal session without creating a new persistent tab.

### F001-R29: Current-Terminal Shortcut Creates Tab When None Exists

A `currentTerminal` shortcut MUST create a terminal tab and queue the command when no tab exists.

### F001-R30: Permanent-Terminal Shortcut Creates Dedicated Tab

A `newPermanentTerminal` shortcut MUST create a dedicated terminal tab and send the command to that session.

### F001-R31: Temporary-Terminal Shortcut Opens Spotlight

A `newTemporaryTerminal` shortcut MUST open a temporary terminal spotlight, execute the command there, and NOT add a persistent tab.

### F001-R32: Queued Commands Wait for Readiness

Command dispatch MUST wait until readiness heuristics succeed. Fallback readiness logic MUST still dispatch queued commands when explicit prompt markers are unavailable.

### F001-R33: Manage Shortcuts Opens Settings

`Manage Shortcuts…` MUST open vibespace settings for the active vibespace with the `Shortcuts` category selected.

### F001-R34: Shortcut Settings Persist Under Target

Shortcuts MUST be persisted under the selected vibespace or project scope. Persisted shortcuts for removed projects MUST NOT be retained.

### F001-R35: Interactive Web Links Open In-App Browser

Interactive targets in terminal output MUST show a subtle hover highlight when the pointer rests on actionable text. A single plain click on a web URL or hyperlink MUST present a contextual popup anchored to that target. The popup for a web URL or hyperlink MUST contain exactly these user-facing actions:

- `Open in Crispy` — opens the URL as an in-app browser spotlight preview
- `Open in Default Browser` — opens the URL through the system browser
- `Copy Link` — copies the original link string

`Cmd`-click MUST continue to open the target directly as an in-app browser spotlight preview without showing the popup. Supported terminal hosts, including Ghostty, SwiftTerm, and tmux-backed local or remote sessions, MUST preserve in-app routing.

### F001-R36: Interactive File Targets Open File Spotlight

File paths or file URLs with optional line/column MUST open inside Crispy as a temporary spotlight preview. A single plain click on a file target MUST present a contextual popup anchored to that target. The popup for a file target MUST contain exactly these user-facing actions:

- `Open` — opens the file inside Crispy as a temporary spotlight preview
- `Open in Shelf` — adds the file to Shelf using the existing Shelf plumbing
- `Open in System` — opens the file through the system default handler
- `Reveal in Finder` — reveals the file in Finder
- `Copy Path` — copies the resolved file path

Pending source selection MUST preserve the requested line and column across supported terminal hosts, including tmux-backed local or remote sessions. `Cmd`-click on a file target MUST continue to open the file directly in Crispy without showing the popup.

### F001-R37: Interactive Directory Targets Reveal in Finder

Directory paths or file URLs pointing to directories MUST be revealed through Finder. A single plain click on a directory target MUST present a contextual popup anchored to that target. The popup for a directory target MUST contain exactly these user-facing actions:

- `Open` — routes through Crispy's terminal file-system target handling for directories
- `Open in System` — opens the directory through the system, which on macOS is Finder
- `Copy Path` — copies the resolved directory path

`Cmd`-click on a directory target MUST continue to perform the direct directory action without showing the popup. Hover affordances and target detection behavior MUST remain consistent with other interactive terminal targets.

### F001-R38: Remote Terminal Activation Waits for SSH

For SSH-backed projects, the SSH connection MUST be established asynchronously first. The terminal pane MUST be presented only after the SSH connection becomes active. Local project hydration MUST remain unaffected.

### F001-R39: Remote Terminal Recovery Is User-Initiated

When a remote connection becomes disconnected, the remote status control MUST surface the problem at the VibeSpace level. The user MUST be able to retry explicitly. Retry MUST NOT block the main thread.

### F001-R40: Remote Project Stable tmux Session Identity

For SSH-backed projects with tmux, each restored tab MUST keep the persisted `tmuxSessionName`. A missing name MUST be seeded from a stable hash of the SSH project identifier. Reopening MUST reattach to the same remote tmux session.

### F001-R41: Explicit Reconnect Revives Remote Tabs

On successful reconnect, existing remote terminal tabs MUST be restarted against the reconnected host. The previously active tab MUST remain active after restart.

### F001-R42: Sessions Browser Lists Sessions

The vibespace `Sessions` sidebar MUST show the current VibeSpace first. Local and remote sessions MUST be shown in one shared tree. Remote session discovery MUST be scoped to connected SSH hosts only.

### F001-R43: Sessions Browser Preview

Previewing a session MUST attach to the tmux session in a temporary spotlight terminal. The preview MUST NOT permanently move the session into a Project terminal pane.

### F001-R44: Sessions Browser Open in Project

`Open in Project` MUST open or reuse a terminal surface for that Project and attach to the selected tmux session instead of creating a fresh shell.

### F001-R45: Sessions Browser Terminate

`Terminate` MUST kill the tmux session on the appropriate machine and refresh the sessions list.

### F001-R46: Controlled Shell Startup Instrumentation

When developer tools are enabled, the startup sequence MUST be instrumented through a controlled integration layer. Lifecycle milestones MUST be captured via TerminalLifecycleLogger.

### F001-R47: Terminal Insight Auto-Dismiss

The last-command overlay MUST auto-dismiss after 4 seconds. The overlay MUST dismiss immediately if new input is detected or streaming output begins.

### F001-R48: Terminal Insight TUI Mode Suppression

The last-command overlay MUST be suppressed when the terminal enters TUI mode and resume when it exits.

### F001-R49: Terminal Insight Overlay Animation

The overlay MUST slide down with a spring animation (0.2s) on appear, fade out with ease-out (0.3s) on dismiss, and cross-fade with timer reset when a new command replaces the current overlay.

### F001-R50: Compose Bar Terminal Input

TerminalComposeInputView MUST provide a text input field for composing terminal commands. Submitted input MUST be dispatched to the active terminal session.

### F001-R51: Terminal Focus Coordinator

TerminalFocusCoordinator MUST arbitrate focus assignment. Only one terminal surface MUST hold keyboard focus at a time.

### F001-R52: Interactive Target Detector

TerminalInteractiveTargetDetector MUST parse and identify actionable targets (URLs, file paths) in terminal output. Detected targets MUST be surfaced as interactive elements.

### F001-R53: Compact Rail Font Updates Live

When user changes `Rail terminal text size` in app settings, the terminal host MUST reapply compact density font size for the active rail preview. Density ownership rules MUST remain unchanged during host handoff.

### F001-R54: Accepted File Drops Preserve Terminal Focus

When a terminal view accepts a file drop, that same terminal view MUST remain the keyboard focus target after the drop is processed. The drop MUST NOT move focus to Shelf, a file preview, or another surface.

### F001-R55: Detailed Bottom Tray Shows One Terminal Session At A Time

In `Detailed` canvas mode, the focused project's bottom terminal tray MUST show exactly one visible terminal session at a time. Other terminal tabs for that project MUST remain selectable through normal terminal tab selection and MUST NOT be rendered side by side in the tray.

### F001-R56: Detailed Bottom Tray Can Collapse Without Terminating Sessions

In `Detailed` canvas mode, the focused project's bottom terminal tray MUST support collapse/minimize behavior that gives the main content area more space. Collapsing the tray MUST NOT terminate or recreate terminal sessions.

### F001-R57: Detailed Bottom Tray Does Not Offer Split Presentation

The focused project's bottom terminal tray in `Detailed` canvas mode MUST NOT expose a tray-local split presentation control. Side-by-side terminal viewing in detailed mode MUST be achieved by docking a terminal into the main content view instead.

### F001-R58: Moving A Detailed Tray Terminal Into The Main View Preserves Session Identity

When the user docks the visible detailed-tray terminal into the main content view, Crispy MUST move that terminal's presentation using the existing terminal session identity rather than creating a duplicate session. After the move, the detailed tray MUST continue showing at most one project terminal session, advancing to the next available project terminal when one exists.

## Scenarios

### Scenario F001-S01: Empty terminal state when no tabs exist

**Given** terminal pane has no tabs
**When** pane renders
**Then** `No Terminal Tabs` placeholder is shown

### Scenario F001-S02: Active terminal session view when a tab is selected

**Given** terminal has an active tab
**When** pane renders
**Then** terminal header shows the active tab working directory path
**And** pane chrome does not show a persistent `Running` status label
**And** terminal session host view is embedded below header

### Scenario F001-S03: Terminal unavailable fallback

**Given** active tab no longer has a session object
**When** pane renders
**Then** `Terminal Unavailable` placeholder is shown

### Scenario F001-S04: New tab uses active tab directory fallback

**Given** user clicks `+` in terminal tab bar
**When** a tab is created without explicit directory
**Then** new tab working directory is active tab directory
**Or** user home directory if no active tab exists
**And** keyboard focus moves to the new active terminal session

### Scenario F001-S05: Open in Terminal de-duplicates by directory

**Given** user requests terminal for a directory
**When** a tab already exists for that normalized path
**Then** that existing tab is selected
**And** no duplicate tab is created

### Scenario F001-S06: Open in Terminal creates new tab if directory not present

**Given** user requests terminal for a directory
**When** no tab exists for that normalized path
**Then** a new tab is created for that directory
**And** it becomes active

### Scenario F001-S07: Closing active tab updates active selection

**Given** multiple tabs exist and one is active
**When** active tab is closed
**Then** tab session is terminated
**And** active tab falls back to the last remaining tab if any

### Scenario F001-S08: Selecting a tab starts its session if needed

**Given** a tab exists
**When** user selects that tab
**Then** the corresponding terminal session is started if it was not already started

### Scenario F001-S09: Terminal starts interactive shell in target directory

**Given** a terminal session is started
**When** start executes
**Then** shell executable is resolved by precedence: Project override, VibeSpace default, App default, process `SHELL`, `/bin/zsh`
**And** unavailable shell candidates fall through to the next precedence level
**And** shell args include `-i`
**And** current working directory is the tab's working directory

### Scenario F001-S10: Terminal environment advertises color-capable settings

**Given** a terminal session starts
**When** environment is prepared
**Then** `TERM=xterm-256color` and `COLORTERM=truecolor` are set
**And** locale defaults for UTF-8 are enforced if missing
**And** common color-enabling variables are set (`CLICOLOR`, `CLICOLOR_FORCE`, `FORCE_COLOR`)
**And** `NO_COLOR` is removed if present

### Scenario F001-S11: Regular density in focused terminal pane

**Given** active terminal session is shown in main terminal pane
**When** host view attaches session
**Then** terminal font uses regular density sizing

### Scenario F001-S12: Compact density in stacked project card preview

**Given** terminal session is shown inside stacked project rail card
**When** host view attaches session
**Then** terminal font uses compact density sizing
**And** compact font size follows app preference `railTerminalCompactFontSize`
**And** compact font size is clamped to the supported range

### Scenario F001-S13: Host ownership handoff during project focus switch

**Given** a terminal session can appear in both focused pane and stacked rail card
**When** project focus changes
**Then** only one host container owns the terminal view at a time
**And** the non-owning host defers attach until ownership can be acquired

### Scenario F001-S14: Owning host controls display density

**Given** a terminal session moves between focused pane and stacked rail card
**When** new host attach succeeds
**Then** the owning host applies the target density for that surface
**And** non-owning hosts do not overwrite density

### Scenario F001-S15: Inactive project terminal keeps running

**Given** a project is inactive in the stacked rail
**When** terminal commands continue in that session
**Then** the shell process remains active
**And** output is visible in the rail preview when rendered

### Scenario F001-S16: Terminal colors follow system appearance changes

**Given** app appearance changes (light/dark)
**When** terminal host view receives effective appearance update
**Then** terminal native colors are reconfigured
**And** background color is updated

### Scenario F001-S17: Terminal title updates tab title fallback

**Given** shell/command updates terminal title
**When** title callback fires
**Then** tab's session title is updated
**And** tab display title may use that value when no custom name exists

### Scenario F001-S18: Directory updates propagate to tab metadata

**Given** shell emits current directory update
**When** callback fires
**Then** tab working directory metadata updates to emitted path

### Scenario F001-S19: Git branch metadata tracks tab working directory

**Given** a terminal tab is created, selected, or changes directories
**When** tab directory is inside a git repository with a resolvable branch
**Then** tab git branch metadata updates to that branch name
**And** terminal board headers show that branch badge
**And** non-git directories clear the branch badge

### Scenario F001-S20: Process termination updates tab exit metadata

**Given** a terminal process exits
**When** termination callback fires
**Then** tab exit code is stored
**And** tab activity state is set inactive

### Scenario F001-S21: Copy command targets active tab

**Given** a tab is active
**When** user triggers `Copy in Terminal`
**Then** copy action executes on active tab session selection

### Scenario F001-S22: Paste command targets active tab

**Given** a tab is active
**When** user triggers `Paste in Terminal`
**Then** clipboard content is pasted into active tab session

### Scenario F001-S23: Restart Project rebuilds terminal pane

**Given** project restart is triggered
**When** terminal pane restart runs
**Then** all sessions are terminated
**And** tab/session state is cleared
**And** a fresh tab is created automatically

### Scenario F001-S24: Terminal tabs restore from vibespace persistence

**Given** per-project config contains terminal session entries for a Project
**When** the Project session is created
**Then** terminal tabs are restored for those directories
**And** active tab is restored using saved active directory when available
**And** only the active restored tab is started immediately

### Scenario F001-S25: Non-active restored tabs stay lazy until selected

**Given** a Project has multiple restored terminal tabs
**When** the restore completes
**Then** non-active tabs keep session metadata without starting shell processes
**And** selecting one of those tabs starts its session on demand

### Scenario F001-S26: Terminal restore falls back to Project root

**Given** no valid terminal state is available in vibespace persistence
**When** the Project session is created
**Then** a terminal tab is created at Project root directory

### Scenario F001-S27: VibeSpace and project scoped shortcut commands are loaded together

**Given** the active vibespace defines vibespace-scoped shortcuts
**And** the focused project defines project-scoped shortcuts
**When** terminal shortcuts menu is shown
**Then** both shortcut groups appear for the current vibespace context
**And** updates from vibespace settings reload the available shortcut commands

### Scenario F001-S28: Current-terminal shortcut runs in the focused terminal without adding a tab

**Given** a shortcut command uses launch behavior `currentTerminal`
**And** a terminal tab is already focused
**When** user runs that shortcut
**Then** the shortcut command is queued onto the focused terminal session
**And** no new persistent terminal tab is created

### Scenario F001-S29: Current-terminal shortcut creates a terminal when none exists

**Given** a shortcut command uses launch behavior `currentTerminal`
**And** no terminal tab exists yet
**When** user runs that shortcut
**Then** a terminal tab is created
**And** the shortcut command is queued onto that new terminal session

### Scenario F001-S30: Permanent-terminal shortcut creates a dedicated terminal tab

**Given** a shortcut command uses launch behavior `newPermanentTerminal`
**When** user runs that shortcut
**Then** a dedicated terminal tab is created for that shortcut
**And** the shortcut command is sent to that terminal session

### Scenario F001-S31: Temporary-terminal shortcut opens spotlight terminal without adding a persistent tab

**Given** a shortcut command uses launch behavior `newTemporaryTerminal`
**When** user runs that shortcut
**Then** a temporary terminal spotlight opens
**And** the shortcut command executes in that spotlight terminal
**And** no persistent terminal tab is added to the terminal pane

### Scenario F001-S32: Queued shortcut and startup commands wait for terminal readiness

**Given** a terminal session has not yet reached interactive readiness
**When** the app queues startup commands or shortcut commands
**Then** command dispatch waits until readiness heuristics succeed
**And** fallback readiness logic still dispatches queued commands when explicit prompt markers are unavailable

### Scenario F001-S33: `Manage Shortcuts` opens vibespace settings to the shortcuts category

**Given** a vibespace is active and the terminal shortcuts menu is available
**When** user selects `Manage Shortcuts…`
**Then** vibespace settings open for the active vibespace
**And** the `Shortcuts` category is selected

### Scenario F001-S34: Shortcut settings persist rows under the selected vibespace or project target

**Given** vibespace settings are open to the `Shortcuts` category
**When** user assigns a shortcut row to the vibespace target or to a specific project target
**Then** the shortcut is persisted under that selected scope
**And** persisted shortcuts for removed projects are not retained

### Scenario F001-S35: Interactive web links open in-app browser spotlight

**Given** terminal output contains a web URL or hyperlink
**When** the pointer hovers the interactive target
**Then** the terminal shows a subtle hover highlight over the actionable token
**When** user plain-clicks the interactive target
**Then** Crispy shows a contextual popup for that link
**And** the popup includes `Open in Crispy`
**And** the popup includes `Open in Default Browser`
**And** the popup includes `Copy Link`
**When** user chooses `Open in Crispy`
**Then** the link opens as an in-app browser spotlight preview
**When** user chooses `Open in Default Browser`
**Then** the link opens through the system browser
**When** user chooses `Copy Link`
**Then** the original link string is copied
**When** user `Cmd`-clicks the interactive target
**Then** the link opens as an in-app browser spotlight preview
**And** supported terminal hosts preserve the in-app routing instead of falling back to the system browser

### Scenario F001-S36: Interactive file targets open in file spotlight and preserve source location

**Given** terminal output contains a file path or file URL with optional line and column
**When** the pointer hovers the interactive target
**Then** the terminal shows a subtle hover highlight over the actionable token
**When** user plain-clicks the interactive target
**Then** Crispy shows a contextual popup for that file
**And** the popup includes `Open`
**And** the popup includes `Open in Shelf`
**And** the popup includes `Open in System`
**And** the popup includes `Reveal in Finder`
**And** the popup includes `Copy Path`
**When** user chooses `Open`
**Then** the file opens inside Crispy as a temporary spotlight preview
**And** pending source selection preserves the requested line and column when provided
**When** user chooses `Open in Shelf`
**Then** the file is added to Shelf
**When** user chooses `Open in System`
**Then** the file opens through the system default handler
**When** user chooses `Reveal in Finder`
**Then** Finder reveals the file
**When** user chooses `Copy Path`
**Then** the resolved file path is copied
**When** user `Cmd`-clicks the interactive target
**Then** the file opens inside Crispy as a temporary spotlight preview
**And** pending source selection preserves the requested line and column when provided

### Scenario F001-S37: Interactive directory targets reveal in Finder

**Given** terminal output contains a directory path or file URL
**When** the pointer hovers the interactive target
**Then** the terminal shows a subtle hover highlight over the actionable token
**When** user plain-clicks the interactive target
**Then** Crispy shows a contextual popup for that directory
**And** the popup includes `Open`
**And** the popup includes `Open in System`
**And** the popup includes `Copy Path`
**When** user chooses `Open`
**Then** Crispy routes the directory through its terminal file-system target handling
**When** user chooses `Open in System`
**Then** the directory opens through Finder
**When** user chooses `Copy Path`
**Then** the resolved directory path is copied
**When** user `Cmd`-clicks the interactive target
**Then** the directory is revealed through Finder instead of opening an in-app editor preview

### Scenario F001-S38: Remote project activation waits for SSH connectivity before presenting terminals

**Given** a Project is backed by SSH
**When** the Project is activated during vibespace hydration or focus
**Then** the SSH connection is established asynchronously first
**And** the terminal pane is presented only after the SSH connection becomes active
**And** local Project hydration remains unaffected while the remote connection is still starting

### Scenario F001-S39: Remote terminal recovery is user-initiated after connection problems

**Given** a VibeSpace contains one or more SSH-backed Projects
**When** a remote connection becomes disconnected or failed
**Then** the remote status control surfaces the problem at the VibeSpace level
**And** the user can retry the connection explicitly from that control
**And** retry does not block the main thread while the connection attempt runs

### Scenario F001-S40: Remote project terminals persist a stable tmux session identity per SSH project

**Given** a Project is backed by SSH and tmux is available on that host
**When** the Project creates or restores its primary terminal tabs
**Then** each restored tab keeps the persisted `tmuxSessionName` when available
**And** a missing tmux session name is seeded from a stable hash of the SSH project identifier
**And** reopening the VibeSpace reattaches to the same remote tmux session instead of inventing a new one

### Scenario F001-S41: Explicit reconnect revives existing remote terminal tabs

**Given** a remote Project already has one or more terminal tabs
**And** the SSH connection later becomes disconnected or failed
**When** the user retries that connection successfully
**Then** the existing remote terminal tabs are restarted against the reconnected host
**And** the previously active tab remains the active tab after restart

### Scenario F001-S42: Sessions sidebar lists local and remote tmux sessions for the active vibespace first

**Given** tmux sessions are available locally, remotely, or both
**When** the user opens the vibespace `Sessions` sidebar
**Then** the current VibeSpace is shown first
**And** local and remote sessions are shown in the same browser using one shared tree
**And** remote session discovery is scoped to connected SSH hosts only

### Scenario F001-S43: Previewing a session opens a temporary live terminal spotlight

**Given** a tmux session is visible in the vibespace `Sessions` sidebar
**When** the user previews that session
**Then** Crispy attaches to the tmux session in a temporary spotlight terminal
**And** the preview does not permanently move that session into a Project terminal pane on its own

### Scenario F001-S44: Open in Project attaches a browsed session to its target project terminal

**Given** a tmux session is visible in the vibespace `Sessions` sidebar
**And** the session can be associated with a Project launch context
**When** the user chooses `Open in Project`
**Then** Crispy opens or reuses a terminal surface for that Project
**And** the terminal attaches to the selected tmux session instead of creating a fresh shell

### Scenario F001-S45: Sessions sidebar can terminate local and remote tmux sessions

**Given** a tmux session is visible in the vibespace `Sessions` sidebar
**When** the user chooses `Terminate`
**Then** Crispy kills that tmux session on the local machine or remote host as appropriate
**And** the sessions list refreshes to remove the terminated session

### Scenario F001-S46: Controlled shell startup instrumentation

**Given** developer tools are enabled
**When** a terminal session starts with a supported shell
**Then** the startup sequence is instrumented through a controlled integration layer
**And** lifecycle milestones (sessionCreate, surfaceCreate, hostAttach, surfaceFocus) are captured via TerminalLifecycleLogger

### Scenario F001-S47: Terminal insight overlay auto-dismiss

**Given** terminal insight is enabled in experimental settings
**And** the user executes a command in a terminal
**When** the last-command overlay appears
**Then** the overlay auto-dismisses after 4 seconds
**And** the overlay dismisses immediately if new input is detected or streaming output begins

### Scenario F001-S48: Terminal insight TUI mode suppression

**Given** terminal insight is enabled
**When** the terminal enters TUI mode (full-screen application)
**Then** the last-command overlay is suppressed
**And** the overlay resumes when the terminal exits TUI mode

### Scenario F001-S49: Terminal insight overlay animation

**Given** terminal insight is enabled
**When** a new last-command overlay appears
**Then** it slides down with a spring animation (0.2s)
**And** on dismiss it fades out with ease-out (0.3s)
**And** if a new command replaces the current overlay, it cross-fades with timer reset

### Scenario F001-S50: Compose bar provides terminal input

**Given** a terminal session is active
**When** the compose bar is visible
**Then** TerminalComposeInputView provides a text input field for composing terminal commands
**And** submitted input is dispatched to the active terminal session

### Scenario F001-S51: Dedicated service manages terminal keyboard focus

**Given** multiple terminal surfaces exist across the app
**When** a terminal surface requests keyboard focus
**Then** TerminalFocusCoordinator arbitrates focus assignment
**And** only one terminal surface holds keyboard focus at a time

### Scenario F001-S52: Detection engine for interactive links and file targets

**Given** terminal output contains text that may include URLs or file paths
**When** the output is processed
**Then** TerminalInteractiveTargetDetector parses and identifies actionable targets
**And** detected targets are surfaced as interactive elements in the terminal view with a hover highlight
**And** supported Ghostty and SwiftTerm hosts share the same detector behavior for local, remote, and tmux-backed sessions

### Scenario F001-S53: Compact rail font updates live when app setting changes

**Given** a stacked project card terminal is visible
**When** user changes `Rail terminal text size` in app settings
**Then** terminal host reapplies compact density font size for the active rail preview
**And** density ownership rules remain unchanged during host handoff

### Scenario F001-S54: Dropping files onto terminal inserts shell-escaped paths

**Given** one or more files are dragged onto a terminal view
**When** the drop is accepted
**Then** file paths are shell-escaped before insertion
**And** keyboard focus remains on the terminal view that accepted the drop
**And** paths within the terminal's current working directory use relative paths
**And** paths outside the current working directory use absolute paths
**And** multiple files are joined with spaces
**And** a trailing space is appended after the last path

### Scenario F001-S55: Detailed mode bottom tray shows only the active terminal session

**Given** vibespace canvas mode is `Detailed`
**And** the focused Project has multiple terminal tabs
**When** the focused project terminal tray renders
**Then** only the active terminal tab's session is visibly hosted in the tray
**And** the tray does not render a second side-by-side terminal session

### Scenario F001-S56: Collapsing the detailed bottom tray keeps sessions alive

**Given** vibespace canvas mode is `Detailed`
**And** the focused project terminal tray is visible
**When** the user collapses the tray
**Then** the tray's terminal session stays alive
**And** expanding the tray restores terminal access without creating a new session

### Scenario F001-S57: Detailed bottom tray does not expose split presentation

**Given** vibespace canvas mode is `Detailed`
**And** the focused project terminal tray is visible
**When** the tray chrome renders
**Then** no tray-local split presentation control is shown
**And** side-by-side terminal viewing is achieved by docking a terminal into the main content view

### Scenario F001-S58: Docking the detailed tray terminal into the main view reuses the same live session

**Given** vibespace canvas mode is `Detailed`
**And** the focused project bottom tray is showing one visible terminal session
**When** the user docks that terminal into the main content view
**Then** the target main-view host reuses the same terminal session identity
**And** CrispyVibes does not create a duplicate shell process for that move
**And** the detailed tray advances to the next available project terminal when one exists
**And** otherwise the tray remains empty or collapsed without terminating the moved session

## Acceptance Criteria

- Shell resolution completes within 50ms (PERF-1).
- Tab create/close operations complete within 100ms (PERF-3).
- Session restore completes within 500ms for up to 10 tabs (PERF-4).
- No orphaned shell processes after tab close or project restart (REL-6).
- Keyboard focus is always routable to the active terminal (A11Y-2).
- All session lifecycle events logged (OBS-1, OBS-2).
- Remote terminal activation does not block the main thread (PERF-2).

## Open Questions

- Should shortcut commands support parameterized templates (e.g., `$FILE`, `$DIR`)?
- Should terminal insight be promoted from experimental to default?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-001–076) | — |
