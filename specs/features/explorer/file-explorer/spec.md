# File Explorer — Spec

Status: draft

## Overview

The File Explorer provides the vibespace file sidebar — a tree-based file browser that lists every project in the active vibespace. It supports lazy-loaded expansion, search, inline create/rename/delete, context menu actions (reveal in Finder, copy path, open in tab), programmatic sidebar reveal, project color tags, and both local and remote project roots.

## Dependencies

- F020 (VibeSpace Lifecycle) — vibespace and project scoping
- F023 (Project Color Coding) — color tag display on project roots
- F026 (Git Operations) — git-ignored item marking

## Requirements

### F024-R01: VibeSpace File Sidebar

The sidebar MUST list every Project in the active VibeSpace with visually distinct project roots. The focused Project MUST auto-expand in detailed mode. Terminal-only mode MUST start all projects collapsed.

### F024-R02: Tree Presentation

The tree MUST sort folders before files, case-insensitively. Hidden items MUST be visible and marked. Git-ignored items MUST be visually de-emphasized.

### F024-R03: Selection

Selecting a file MUST update both file and folder selection. Selecting a folder MUST update folder selection and clear file selection. Selecting a file from a non-focused project MUST focus that project. A successful directory refresh MUST clear selection and rename state for items no longer present and move a removed folder selection to the nearest existing ancestor.

### F024-R04: Expansion and Lazy Loading

First expansion MUST lazy-load children from worker with a loading indicator. Re-expansion MUST reuse cached children. Search mode MUST keep matching ancestry expanded.

### F024-R05: Search

Search MUST filter recursively with ancestry preservation and highlight matching text. Clearing search MUST restore the normal tree.

### F024-R06: Create, Rename, Delete

Create file/folder MUST enter immediate inline rename mode with collision handling. Creation from a stale folder selection MUST fall back to the nearest existing project directory. Rename MUST validate names and remap selections. Delete MUST require confirmation and clear dependent selections.

### F024-R07: Context Menu and Header Actions

Root context menu MUST provide New File and New Folder. Files header MUST expose quick create actions. File/folder context menus MUST include Reveal in Finder, Copy Path, Copy Relative Path, and Open in Tab.

### F024-R08: File Activation Modes

Single click MUST preview; double click MUST open persistent tab. Terminal-only mode MUST not switch canvas mode on file activation.

### F024-R09: Open in Terminal

Folder action MUST open terminal at folder path. File action MUST open terminal at parent folder path.

### F024-R10: Remote Explorer

Remote explorer MUST lazy-load over SSH-backed file services without preloading the entire tree. Transient SSH failures during startup MUST not surface as persistent errors.

### F024-R11: Programmatic Sidebar Reveal

revealInSidebar MUST expand ancestor directories and scroll the target file into view.

### F024-R12: Project Color Tags

Tagged project roots MUST display their color tag indicator. Untagged roots MUST render without a color indicator.

### F024-R13: Error Presentation

Sidebar operation failures MUST surface user-facing dismissible alerts.

### F024-R14: Disclosure Toggles Work Across All Visible Projects

Clicking a visible project or directory disclosure control MUST expand or collapse that row regardless of whether its project is currently focused. Using the disclosure control MUST NOT change the current selection by itself.

### F024-R15: Consistent Incremental Refresh

Refreshes for the same directory MUST be serialized and coalesced so an older snapshot cannot overwrite newer filesystem state. Watcher changes received while the Files tab or initial tree load is inactive MUST be retained and applied when the tree becomes active. File mutations MUST refresh the affected parent before starting inline rename or completing their visible update.

## Scenarios

### Scenario F024-S01: Files sidebar lists every project in the active VibeSpace

**Given** an active VibeSpace exists
**When** the app side menu `Files` item is active
**Then** a vibespace-level file sidebar is shown next to the app activity rail
**And** the sidebar lists every Project in the active VibeSpace
**And** each Project root is visually distinct from regular folders

### Scenario F024-S02: Detailed view auto-expands the focused Project

**Given** an active VibeSpace exists
**And** vibespace canvas mode is `Detailed`
**When** the file sidebar renders
**Then** the focused Project root is expanded automatically
**And** non-focused Project roots remain collapsed unless the user expands them

### Scenario F024-S03: Terminal Board starts with all Projects collapsed

**Given** an active VibeSpace exists
**And** vibespace canvas mode is `Terminal Only`
**When** the file sidebar renders
**Then** every Project root starts collapsed
**And** Project expansion remains user-driven

### Scenario F024-S04: Selecting a file from the sidebar focuses its Project

**Given** the vibespace file sidebar is visible
**When** the user selects a file that belongs to a non-focused Project
**Then** that Project becomes the focused Project
**And** the file preview or open-tab action is routed through that Project session

### Scenario F024-S05: Opening a file from Terminal Board does not switch to Detailed view

**Given** vibespace canvas mode is `Terminal Only`
**When** the user previews or opens a file from the vibespace file sidebar
**Then** the vibespace canvas remains in `Terminal Only` mode
**And** the selected Project remains focused
**And** the file is not opened in the editor area

### Scenario F024-S06: Sidebar remains project-aware for file operations

**Given** a Project root is expanded in the vibespace file sidebar
**When** the user creates, renames, deletes, moves, previews, or opens a file
**Then** the operation is executed against that Project's file tree state
**And** the Project's selection, rename state, expansion state, and git state remain isolated to that Project

### Scenario F024-S07: Sidebar operations surface user-facing alerts

**Given** any sidebar operation fails (tree load, git load, create, rename, delete)
**When** the failure is raised
**Then** a sidebar error alert is displayed
**And** user can dismiss and continue working

### Scenario F024-S08: Git sidebar remains vibespace-scoped when project focus changes

**Given** the vibespace Git sidebar is visible
**When** the focused Project changes
**Then** repository sections are recomputed from the full VibeSpace scope
**And** repository visibility does not collapse to only the focused Project

### Scenario F024-S09: Remote project roots are labeled in the vibespace file sidebar

**Given** the vibespace file sidebar is visible
**And** a listed Project is backed by SSH
**When** that Project root row renders
**Then** the Project title includes an `[ssh]` suffix
**And** local Project rows do not include that suffix

### Scenario F024-S10: Each project header includes refresh, new file, and new folder buttons

**Given** the app side menu `Files` item is active
**When** a project header row renders in the sidebar
**Then** refresh, new file, and new folder buttons are shown in that project's header row
**And** each button targets that specific project regardless of which project is focused

### Scenario F024-S11: Project roots display assigned color tags in the sidebar

**Given** the vibespace file sidebar is visible
**And** one or more Projects have an assigned color tag
**When** Project root rows render
**Then** each tagged Project root displays its color tag indicator
**And** untagged Project roots render without a color indicator

### Scenario F024-S12: Tree sorts folders before files

**Given** tree data includes both directories and files
**When** items are rendered
**Then** directories appear before files
**And** names are sorted case-insensitively

### Scenario F024-S13: Hidden items are visible

**Given** the filesystem contains hidden entries
**When** tree data is loaded
**Then** hidden files and folders are shown in the explorer
**And** hidden items are marked with hidden metadata

### Scenario F024-S14: Git-ignored items are marked and visually de-emphasized

**Given** tree data includes paths ignored by repository `.gitignore` rules
**When** rows render in the explorer
**Then** ignored items are marked with git-ignored metadata
**And** ignored rows render with reduced emphasis while remaining selectable

### Scenario F024-S15: Root-level context menu provides creation actions

**Given** a root folder is open
**When** user opens context menu on root list background
**Then** actions include `New File` and `New Folder`
**And** `Open in Terminal` is not included in the root context menu

### Scenario F024-S16: Selecting a file updates file and folder selection

**Given** a file row is clicked
**When** selection is applied
**Then** `selectedFileURL` points to the file
**And** `selectedFolderURL` points to the file's parent directory

### Scenario F024-S17: Selecting a folder updates folder selection

**Given** a folder row is clicked
**When** selection is applied
**Then** `selectedFolderURL` points to that folder
**And** `selectedFileURL` is cleared

### Scenario F024-S18: First expansion lazy-loads children

**Given** a directory is not yet loaded
**When** user expands that directory
**Then** immediate children are requested from worker
**And** a loading row is shown while request is in progress
**And** loaded children are cached for subsequent expands

### Scenario F024-S19: Re-expansion reuses loaded children

**Given** a directory was loaded previously
**When** user collapses and re-expands it
**Then** cached children are reused unless a full refresh has occurred

### Scenario F024-S20: Search mode keeps hierarchy expanded

**Given** search query is non-empty
**When** folder rows render
**Then** matching ancestry remains visible
**And** manual disclosure toggling is disabled during search mode

### Scenario F024-S21: Search filters recursively with ancestry preservation

**Given** a non-empty search query
**When** displayed tree is computed
**Then** matching files and folders are included
**And** parent folders are retained when descendants match
**And** matching text fragment is highlighted in row labels

### Scenario F024-S22: Clearing search restores normal tree view

**Given** search query transitions to empty
**When** displayed tree is recomputed
**Then** standard tree content is restored

### Scenario F024-S23: Creating a file enters immediate rename mode

**Given** user invokes `New File`
**When** creation succeeds
**Then** a unique file path is created if collision exists
**And** tree refresh runs
**And** the new item enters inline rename mode

### Scenario F024-S24: Creating a folder enters immediate rename mode

**Given** user invokes `New Folder`
**When** creation succeeds
**Then** a unique folder path is created if collision exists
**And** tree refresh runs
**And** the new item enters inline rename mode

### Scenario F024-S25: Rename can be initiated from context menu or Enter

**Given** an item is selected
**When** user picks `Rename` or presses Enter in focused list
**Then** inline rename field is shown for that item

### Scenario F024-S26: Rename commit validates and remaps active selections

**Given** inline rename is active
**When** rename is committed
**Then** empty names are ignored
**And** duplicate destination names produce an error
**And** selection paths are remapped to renamed destination when applicable
**And** tree refresh runs

### Scenario F024-S27: Rename cancel exits edit mode

**Given** rename field is active
**When** user presses Escape
**Then** rename mode is canceled without applying changes

### Scenario F024-S28: Delete requires confirmation

**Given** user requests delete for a file/folder
**When** destructive confirmation is accepted
**Then** target path is removed from disk
**And** dependent selections under that subtree are cleared/reset
**And** tree refresh runs

### Scenario F024-S29: Files header exposes quick create actions

**Given** `Files` tab is active
**When** sidebar header renders
**Then** `New File` and `New Folder` actions are available without opening context menu
**And** invoking either action creates the item in selected folder context or root fallback

### Scenario F024-S30: Single click previews file and double click opens persistent tab

**Given** a file row is visible in explorer
**And** canvas mode is detailed
**When** user single-clicks the row
**Then** file is selected and opened in preview mode
**When** user double-clicks the same row
**Then** file is requested as a persistent editor tab open action

### Scenario F024-S31: File context menu can open detached editor window (not currently wired)

**Given** a file row context menu is open
**When** user selects `Open in New Window`
**Then** explorer emits an open-window request for that file
**And** project session opens or focuses a detached editor window for that path
Note: This action exists in the view model but is not currently wired into any context menu.

### Scenario F024-S32: Terminal-only explorer activation does not switch canvas mode

**Given** a file row is visible in explorer
**And** canvas mode is terminalOnly
**When** user previews or opens the file from the explorer
**Then** canvas mode remains terminalOnly
**And** the sidebar does not trigger a switch to the detailed editor surface

### Scenario F024-S33: Folder action opens terminal at folder path

**Given** user selects `Open in Terminal` on a folder
**When** action executes
**Then** terminal opens or focuses a tab for that folder path

### Scenario F024-S34: File action opens terminal at parent folder

**Given** user selects `Open in Terminal` on a file
**When** action executes
**Then** terminal opens or focuses a tab for file parent folder

### Scenario F024-S35: Remote explorer loads root and child directories lazily over SSH-backed file services

**Given** the focused Project is backed by SSH
**When** the Files sidebar loads or the user expands a remote directory
**Then** only the requested directory contents are fetched over the remote file service
**And** remote directories do not require preloading the entire project tree
**And** manual refresh remains available because live filesystem watching is not supported remotely

### Scenario F024-S36: Remote explorer suppresses transient SSH readiness failures during startup and relies on explicit refresh or retry

**Given** a remote Project is still establishing its SSH or SFTP connection
**When** the explorer performs its initial startup refresh
**Then** transient connection-readiness errors are not surfaced as persistent sidebar failures
**And** the explorer remains usable once the connection becomes active
**When** the connection later needs attention
**Then** the user can retry through the remote status control or by refreshing the explorer explicitly

### Scenario F024-S37: Reveal in Finder context menu action

**Given** a file or folder row context menu is open
**When** user selects `Reveal in Finder`
**Then** the item's path is revealed in macOS Finder

### Scenario F024-S38: Copy Path and Copy Relative Path context menu actions

**Given** a file or folder row context menu is open
**When** user selects `Copy Path`
**Then** the item's absolute path is copied to the clipboard
**When** user selects `Copy Relative Path`
**Then** the item's path relative to the project root is copied to the clipboard

### Scenario F024-S39: Open in Tab context menu action

**Given** a file row context menu is open
**When** user selects `Open in Tab`
**Then** the file is opened as a persistent editor tab in the active project session

### Scenario F024-S40: revealInSidebar programmatically selects and scrolls to a file

**Given** a file URL is passed to the revealInSidebar method
**When** the method executes
**Then** the file's ancestor directories are expanded
**And** the file row is selected and scrolled into view in the sidebar

### Scenario F024-S41: Single click delegates to native outline view selection for drag recognition

**Given** a file row is visible in the explorer
**When** the user single-clicks the row
**Then** the click is handled by NSOutlineView's native selection handling
**So that** drag recognition can begin from the initial mouse-down event

### Scenario F024-S42: Watcher triggers targeted directory refresh

**Given** the directory watcher receives a file system event
**When** the refresh algorithm runs
**Then** only the affected directories are refreshed (not the entire tree)
**And** the algorithm uses event kind (created/removed/renamed/modified) and directory visibility to determine refresh targets

### Scenario F024-S43: Watcher-triggered refreshes do not show loading spinners

**Given** a file system event triggers a subtree refresh
**When** the affected directories are reloaded
**Then** the refresh runs silently without showing loading indicators (showLoadingState: false)

### Scenario F024-S44: Disclosure arrow toggle does not select the item

**Given** a project or directory row is visible in the explorer
**And** the row may belong to the focused project or a non-focused project
**When** the user clicks the disclosure triangle
**Then** that row expands or collapses
**And** the current selection does not change

### Scenario F024-S45: Tree mutation tracking prevents redundant reloads

**Given** multiple file system events arrive in a batch
**When** changes are tracked via treeMutationRevision counter and changedDirectoryIDs set
**Then** only directories with pending mutations are reloaded in NSOutlineView
**And** redundant reloads for unchanged directories are skipped

### Scenario F024-S46: Concurrent refreshes cannot restore stale entries

**Given** a directory refresh is in flight
**When** another refresh for the same directory is requested
**Then** the second request is coalesced into one follow-up pass
**And** the older snapshot cannot overwrite the follow-up result

### Scenario F024-S47: Watcher changes survive an inactive Files tab

**Given** filesystem changes arrive while the Git tab is active or before the initial tree load completes
**When** the Files tree becomes active and loaded
**Then** the pending paths are refreshed
**And** additions and deletions appear without a manual refresh

### Scenario F024-S48: Creation waits for a visible tree item

**Given** the user creates a file or folder
**When** the worker returns the created path
**Then** the affected parent directory is refreshed
**And** inline rename starts only after the created item exists in the tree

### Scenario F024-S49: Outline updates preserve unchanged subtrees

**Given** a root-level or targeted directory mutation occurs
**When** NSOutlineView applies the update
**Then** unchanged expanded subtrees are not recursively reloaded
**And** cached nodes removed from the model are pruned

## Acceptance Criteria

- Tree load completes within 200ms for projects with up to 10,000 files (PERF-3).
- All file operations logged (OBS-1, OBS-2).
- Keyboard-only navigation supported for all tree operations (A11Y-2).
- Error alerts are dismissible and non-blocking (REL-6).

## Open Questions

- Should the detached editor window action (F024-S31) be wired into the context menu for initial release?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/sidebar (SDB-001–SDB-006, SDB-009–SDB-011, SDB-014, SDB-016) and docs/features/sidebar/folder-explorer (SDF-001–SDF-019, SDF-021–SDF-023, SDF-025–SDF-031) | — |
| 2026-04-16 | Added targeted watcher refresh (S42), silent subtree refresh (S43), disclosure toggle (S44), tree mutation tracking (S45) | — |
| 2026-07-14 | Added serialized refreshes, deferred watcher replay, deterministic create/rename visibility, and incremental outline updates (S46-S49) | — |
