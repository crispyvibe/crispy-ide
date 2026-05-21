# Git Operations — Spec

Status: draft

## Overview

Git Operations covers the vibespace-scoped source control sidebar and per-project git explorer. It provides repository discovery across vibespace projects, per-repo status display with staged/unstaged grouping, branch management, stage/unstage/commit/push/pull/fetch/discard actions, compare mode, commit history, list/tree layout toggle, and settings. The vibespace source control view is the primary UI; the per-project git explorer serves as secondary/fallback behavior.

## Dependencies

- F020 (VibeSpace Lifecycle) — vibespace and project scoping
- F024 (File Explorer) — sidebar structure and project awareness
- F027 (Clone Repository) — clone action from header and empty state

## Requirements

### F026-R01: VibeSpace Repository Discovery

The Git sidebar MUST discover repositories across all active Project roots asynchronously. Shared repository roots MUST be deduplicated. Nested repositories MUST be shown separately. Non-repository projects MUST not suppress vibespace repositories.

### F026-R02: Repository Section Presentation

Each repository section MUST show current branch, refresh/history/branch actions, and commit controls. Changed files MUST be grouped into Staged and Changes with status badges. Repository ordering MUST favor active vibespace context.

### F026-R03: Summary and Limits

The header MUST show total repository count and pending change count. Repositories beyond the auto-presented limit (default 12) MUST be collapsed with an option to expand.

### F026-R04: Per-File and Bulk Index Actions

Stage, unstage, stage all, and unstage all MUST update the git index and refresh status. Commit MUST require a non-empty message and clear the draft on success.

### F026-R05: Publish and Sync Actions

Push, pull, and fetch MUST be scoped per repository and refresh status/branch state after completion.

### F026-R06: Discard Actions

Discard single file MUST restore the working tree copy. Discard All MUST require confirmation before reverting all changes.

### F026-R07: Compare Mode

Selecting a changed file MUST open compare mode for that repository-relative path. Deleted/renamed/copied entries MUST still open compare mode with fallback content.

### F026-R08: Branch Management

Branch menu MUST list local and remote branches with current branch marker. Branch selection MUST check out and refresh status.

### F026-R09: Commit History

Repository history MUST show recent commits with subject, hash, author, and date. File history MUST be scoped to the selected file path.

### F026-R10: Layout Toggle

List/Tree layout toggle MUST re-render changed files in the selected mode and persist the preference.

### F026-R11: Git Status State Machine

The sidebar MUST show appropriate states for loading, git unavailable, non-repository, error with retry, clean working tree, and changed working tree.

### F026-R12: Isolation and Error Handling

Commit drafts MUST be isolated per repository. Mutations MUST not affect sibling repositories. Partial repository failure MUST remain localized with inline error and retry.

### F026-R13: Refresh Triggers

Manual refresh MUST reload status. File save MUST trigger owning repository refresh. Watcher-scoped refresh MUST target only the affected repository.

### F026-R14: Settings

Source control settings MUST allow configuring ignored directories, scan depth, and scan max repos, triggering re-discovery on change.

### F026-R15: Git Unavailable State

When Git is not installed, the sidebar MUST show a vibespace-level unavailable message with no discovery attempted.

## Scenarios

### Scenario F026-S01: Clicking a git status item opens compare preview

**Given** git status list contains a changed file entry
**When** user clicks the entry
**Then** git compare preview is requested for that entry
**And** editor loads staged/unstaged diff text for the selected path when available
**And** compare mode can be shown for text, image, and other file types

### Scenario F026-S02: Clicking missing git file shows error

**Given** git status entry points to a file that no longer exists
**When** user clicks the entry
**Then** sidebar shows an error alert indicating file is missing

### Scenario F026-S03: Deleted and renamed entries still open compare mode

**Given** git status entry code indicates deleted (`D`), renamed (`R`), or copied (`C`) state
**When** user clicks the entry
**Then** compare mode opens even if current working-tree file path is missing
**And** compare content falls back to status information when textual diff is not available

### Scenario F026-S04: Loading state is shown during refresh

**Given** git refresh has been requested
**When** worker response is pending
**Then** sidebar shows loading indicator and loading message

### Scenario F026-S05: Git unavailable state is shown when git is missing

**Given** git command is not available on host machine
**When** refresh completes
**Then** sidebar shows `Git Not Installed` state

### Scenario F026-S06: Non-repository state is shown for plain folders

**Given** selected root folder is not a git repository
**When** refresh completes
**Then** sidebar shows `Not a Git Repository` state

### Scenario F026-S07: Error state supports retry

**Given** git operation fails unexpectedly
**When** refresh completes
**Then** sidebar shows `Git Status Unavailable` state
**And** a `Retry` action is presented

### Scenario F026-S08: Clean working tree state

**Given** repository has no pending changes
**When** refresh completes
**Then** sidebar shows `Working Tree Clean`

### Scenario F026-S09: Changed working tree state

**Given** repository has changed files
**When** refresh completes
**Then** a list of changed files is shown
**And** each row displays a concise status badge (A/M/D/R/U/etc.)

### Scenario F026-S10: Manual refresh reloads status list

**Given** git tab is active
**When** user presses refresh button
**Then** sidebar re-runs git status worker request
**And** state transitions through loading to resolved state

### Scenario F026-S11: Branch menu lists local and remote branches with current branch marker

**Given** selected folder is a git repository
**When** git status refresh completes
**Then** branch options include local and remote refs
**And** current branch is marked in the branch list

### Scenario F026-S12: Branch selection checks out selected branch and refreshes status

**Given** branch options are available
**When** user selects a non-current branch from the branch menu
**Then** checkout is executed through worker
**And** git status and branch list refresh after completion

### Scenario F026-S13: Per-file stage and unstage actions update git index

**Given** changed file rows are shown in git list
**When** user stages or unstages a row
**Then** corresponding worker mutation runs
**And** git status refreshes to reflect index/worktree transitions

### Scenario F026-S14: Stage all action stages all pending changes

**Given** repository has pending changes
**When** user clicks `Stage All`
**Then** worker stages all changes for the repository root
**And** git list updates with staged entries

### Scenario F026-S15: Commit action requires non-empty message and clears draft on success

**Given** commit composer is visible
**When** commit message is empty and user clicks `Commit`
**Then** user-facing validation error is shown
**When** commit succeeds with a non-empty message
**Then** commit message draft is cleared
**And** git status refreshes

### Scenario F026-S16: Push action publishes current branch and refreshes git state

**Given** repository has configured push target
**When** user clicks `Push`
**Then** worker runs push for current branch
**And** sidebar refreshes status and branch payload

### Scenario F026-S17: Repository history sheet shows recent commits

**Given** user opens history from git control strip
**When** history request succeeds
**Then** a history sheet lists commit subject, hash, author, and date

### Scenario F026-S18: File history sheet shows commit history scoped to file path

**Given** changed file row is visible in git list
**When** user opens file history from that row
**Then** worker requests commit history scoped to the selected relative path
**And** history sheet renders file-scoped commits

### Scenario F026-S19: Pull action per repository

**Given** repository has a configured remote tracking branch
**When** user clicks `Pull`
**Then** worker runs pull for the current branch
**And** git status and branch payload refresh after completion

### Scenario F026-S20: Fetch action per repository

**Given** repository has at least one configured remote
**When** user clicks `Fetch`
**Then** worker runs fetch for the repository
**And** branch list refreshes to reflect updated remote refs

### Scenario F026-S21: Unstage All action unstages all staged changes

**Given** repository has staged entries
**When** user clicks `Unstage All`
**Then** worker unstages all entries for the repository root
**And** git list updates with unstaged entries

### Scenario F026-S22: Discard single file action restores working tree copy

**Given** a changed file row is shown in git list
**When** user discards changes for that row
**Then** worker restores the file to its index or HEAD state
**And** git status refreshes to remove the discarded entry

### Scenario F026-S23: Discard All Changes with confirmation

**Given** repository has pending changes
**When** user clicks `Discard All`
**Then** a confirmation prompt is shown
**When** user confirms the discard
**Then** worker restores all changed files to their HEAD state
**And** git status refreshes to show clean working tree

### Scenario F026-S24: List/Tree layout toggle switches git status display mode

**Given** git status list is visible with changed files
**When** user toggles between list and tree layout
**Then** git status entries re-render in the selected layout mode
**And** layout preference is persisted

### Scenario F026-S25: VibeSpace Git sidebar discovers repositories across all active projects

**Given** an active VibeSpace contains one or more Projects
**When** the user opens the `Git` sidebar tab
**Then** the sidebar discovers repositories across all active Project roots
**And** the sidebar renders one section per discovered repository

### Scenario F026-S26: Shared repository is deduplicated across projects

**Given** two or more Projects resolve to the same Git repository root
**When** the `Git` sidebar loads
**Then** the shared repository is shown once
**And** the repository section indicates that multiple Projects map into it

### Scenario F026-S27: Nested repositories are shown separately

**Given** a Project root contains a parent repository and a nested child repository
**When** the `Git` sidebar loads
**Then** the parent repository is shown as one section
**And** the nested child repository is shown as a separate section
**And** descendant paths of the child repository are grouped under the child repository section

### Scenario F026-S28: Non-repository project does not suppress vibespace repositories

**Given** the focused Project is not itself a Git repository
**And** another Project in the same VibeSpace belongs to a Git repository
**When** the `Git` sidebar loads
**Then** the repository-backed Project still appears in the sidebar
**And** the sidebar does not show a blocking `Not a Git Repository` state for the entire VibeSpace

### Scenario F026-S29: VibeSpace Source Control header shows summary counts

**Given** one or more repositories are discovered in the active VibeSpace
**When** the `Git` sidebar renders
**Then** the header shows `Source Control`
**And** the header shows the total repository count
**And** the header shows the total pending change count across visible repositories

### Scenario F026-S30: Each repository section exposes repository-scoped controls

**Given** the `Git` sidebar shows a repository section
**When** the section is expanded
**Then** the section shows the current branch
**And** the section shows refresh, history, and branch actions for that repository
**And** the section shows repository-scoped commit controls

### Scenario F026-S31: Repository section preserves staged and unstaged grouping

**Given** a repository has staged and unstaged changes
**When** the repository section is expanded
**Then** changed files are grouped into `Staged` and `Changes`
**And** each row shows the file status badge for that repository-relative path

### Scenario F026-S32: Repository ordering favors active vibespace context

**Given** the active VibeSpace contains multiple repositories
**When** the user selects a file that belongs to one repository
**Then** that repository section is promoted ahead of unrelated repositories
**And** the repository ordering remains deterministic for the remaining sections

### Scenario F026-S33: Selecting a changed file opens compare mode in owning repository

**Given** a repository section contains a changed file row
**When** the user selects that row
**Then** the editor opens compare mode for that repository-relative path
**And** the action is routed through the owning repository root

### Scenario F026-S34: Commit draft is isolated per repository

**Given** the active VibeSpace contains multiple repositories
**When** the user types a commit message into one repository section
**Then** the draft is stored only for that repository
**And** other repository sections keep their own draft state unchanged

### Scenario F026-S35: Repository-scoped mutations do not affect sibling repositories

**Given** the active VibeSpace contains multiple repositories with pending changes
**When** the user stages, commits, pushes, or checks out from one repository section
**Then** only that repository runs the Git mutation
**And** sibling repository sections remain unchanged until their own refreshes or mutations occur

### Scenario F026-S36: Partial repository failure remains localized

**Given** one repository fails to load status or branch information
**And** another repository in the same VibeSpace loads successfully
**When** the `Git` sidebar renders
**Then** the failing repository shows an inline error state with retry
**And** the successful repository remains visible and interactive

### Scenario F026-S37: Async non-blocking repository discovery

**Given** a vibespace with multiple projects
**When** the source control sidebar initializes
**Then** repository discovery runs asynchronously without blocking vibespace rendering
**And** the sidebar progressively populates as repositories are discovered

### Scenario F026-S38: Watcher-scoped refresh targets affected repository only

**Given** a vibespace with multiple discovered repositories
**When** a file system change is detected in one repository's working tree
**Then** only the affected repository refreshes its status
**And** other repositories retain their cached state
Note: If a changed path does not match any existing repository but matches a project root, a full refresh (re-discovery) is triggered as fallback.

### Scenario F026-S39: Pull action per repository (vibespace-scoped)

**Given** a repository section is visible in the sidebar
**When** the user invokes the pull action on that repository section
**Then** the app runs a Git pull scoped to that repository only

### Scenario F026-S40: Fetch action per repository (vibespace-scoped)

**Given** a repository section is visible in the sidebar
**When** the user invokes the fetch action on that repository section
**Then** the app runs a Git fetch scoped to that repository only

### Scenario F026-S41: Discard single file per repository

**Given** a repository section shows a changed file
**When** the user invokes discard on that file
**Then** the app reverts that single file within the owning repository

### Scenario F026-S42: Discard All Changes per repository with confirmation alert

**Given** a repository section has one or more pending changes
**When** the user invokes Discard All Changes on that repository section
**Then** the app presents a confirmation alert before proceeding
**And** upon confirmation all working-tree changes in that repository are reverted

### Scenario F026-S43: Unstage All per repository

**Given** a repository section has one or more staged changes
**When** the user invokes Unstage All on that repository section
**Then** all staged changes in that repository are moved back to the unstaged group

### Scenario F026-S44: List/Tree layout mode toggle (vibespace-scoped)

**Given** the Git sidebar is showing repository sections
**When** the user toggles the layout mode between List and Tree
**Then** changed files are presented as a flat list or a directory tree accordingly
**And** the selected mode persists across sidebar reloads

### Scenario F026-S45: Summary bar showing repo count and change count

**Given** one or more repositories are discovered
**When** the Git sidebar renders
**Then** a summary bar displays the total number of repositories and the aggregate pending change count

### Scenario F026-S46: Repository presentation limit

**Given** the vibespace discovers more repositories than `autoPresentedRepositoryLimit` (default 12)
**When** the Git sidebar renders
**Then** only the first 12 repositories are expanded by default
**And** remaining repositories are collapsed with an option to expand

### Scenario F026-S47: Source control settings

**Given** the user opens source control settings
**Then** the user can configure ignored directories, scan depth, and scan max repos
**And** changes to these settings trigger a re-discovery of repositories

### Scenario F026-S48: File save triggers repository refresh

**Given** a file belonging to a discovered repository is open in the editor
**When** the user saves that file
**Then** the owning repository refreshes its status

### Scenario F026-S49: Git unavailable state at vibespace level

**Given** Git is not installed or not found on the system PATH
**When** the Git sidebar loads
**Then** the sidebar shows a vibespace-level message indicating Git is unavailable
**And** no repository discovery is attempted

### Scenario F026-S50: Git sidebar shows repositories for the active VibeSpace scope

**Given** an active VibeSpace exists
**When** the app side menu `Git` item is active
**Then** the sidebar shows Git repositories discovered from the VibeSpace's Projects
**And** shared repository roots are shown once even when multiple Projects map to them

### Scenario F026-S51: Git sidebar shows placeholder when VibeSpace scope contains no repositories

**Given** an active VibeSpace exists and no Project root is inside a Git repository
**When** the app side menu `Git` item is active
**Then** the sidebar shows a `No Git Repositories` placeholder

### Scenario F026-S52: Git sidebar header includes a Clone Repository button

**Given** the app side menu `Git` item is active
**When** the sidebar header renders
**Then** a `Clone Repository` button is available in the sidebar header

## Acceptance Criteria

- Repository discovery completes asynchronously without blocking UI (PERF-3).
- Git mutations scoped per repository with no cross-contamination (REL-6).
- All git operations logged (OBS-1, OBS-2).
- Keyboard-only navigation for all git sidebar actions (A11Y-2).
- Error states provide retry actions (REL-6).

## Open Questions

- Should the per-project git explorer (SDG) be deprecated once vibespace source control is fully stable?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/sidebar/git-explorer (SDG-001–SDG-024), docs/features/sidebar/source-control-vibespace (SCM-101–SCM-112, SCM-114–SCM-126), and docs/features/sidebar (SDB-007, SDB-008, SDB-010, SDB-015) | — |
