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

Create file/folder MUST enter immediate inline rename mode with collision handling. Creation from a stale folder selection MUST fall back to the nearest existing project directory. Rename MUST validate names and remap selections. Delete MUST require the shared `ExplorerDeleteConfirmation` for the exact file or folder targeted by the initiating context-menu action, and MUST clear dependent selections only after confirmed deletion. Cancelling MUST perform no filesystem deletion.

### F024-R07: Context Menu and Header Actions

Root context menu MUST provide New File and New Folder. Files header MUST expose quick create actions. Active local file/folder context menus MUST include Open in System, Reveal in Finder, Copy Path, and Copy Relative Path; file menus also include Open in Tab. Active remote file/folder context menus MUST include Open in System and Download… but MUST NOT include Reveal in Finder.

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

### F024-R16: Local Open in System

Active local file and folder menus MUST provide Open in System and pass the original local URL to macOS. The Boolean result from `NSWorkspace.open` MUST be propagated; failure MUST surface through the explorer's existing alert rather than report success.

### F024-R17: Remote Open and Download Actions

Active remote file and folder menus MUST provide Open in System and Download… and MUST omit Reveal in Finder. These explorer actions MUST use the app-wide `RemoteTransferCoordinator`, which permits one explorer file/folder/project-root transfer at a time and owns the shared overlay. The overlay MUST represent preparing, transferring, cancelling, publishing, completed, and failed states; Cancel MUST be unavailable during cancelling, publication, and terminal states, and failure MUST remain in the overlay until dismissed. Before destination replace/move, the service MUST synchronously await the MainActor publication-state acknowledgment and MUST perform a second `Task` cancellation check immediately before the filesystem operation. Structured cancellation MUST retain the coordinator slot until transport termination and staging cleanup finish. A cancellation arriving after the final check may race with the atomic replace/move boundary; no Cancel UI is offered in publishing. Open in System MUST open a protected temporary local copy and remove a newly created copy when `NSWorkspace.open` returns false. Download… MUST prompt for a local destination and publish it only after successful staged transfer; it has manifest/item/byte progress but no size-confirmation prompt. Editor-triggered remote HTML Open in System is independent: it uses `ExternalFileOpenService` plus editor busy/alert state, not this overlay or its dedicated transfer channel. Remote transfer lifecycle and newly relevant diagnostics are recorded, but comprehensive logging of every local file operation is not implemented.

### F024-R18: Remote Drag and Drop Exclusion

Remote explorer drag and drop MUST remain unsupported. Local rows retain native drag recognition and local drag/drop behavior.

### F024-R19: Exact-Target Delete Confirmation Across Explorer Surfaces

Every file or folder filesystem deletion initiated from the AppKit unified explorer, SwiftUI explorer, or Shelf Files sidebar MUST create the shared `ExplorerDeleteConfirmation` from the exact retained right-click target, never from mutable current selection. For both local and remote targets, the dialog title MUST be `Delete “name”?` using the exact item name. Its message MUST present a permanent-deletion warning paragraph that repeats the exact item name and states that deletion cannot be undone, followed by a separate paragraph containing a localized `Path:` block with the exact full local or remote path captured from that same retained target. Its destructive button MUST be `Delete`. Cancelling MUST dismiss the confirmation without invoking deletion. The UI MUST NOT expose an unresolved raw placeholder in place of the target name or path. AppKit, SwiftUI explorer, and Shelf confirmations MUST have content and behavior parity. Displaying the full path is intentional disclosure in this local confirmation dialog so the user can distinguish ambiguous names before a destructive action.

### F024-R20: Repeated-Scroll Responsiveness
The multi-project Files sidebar MUST remain responsive after repeated bidirectional scrolling. The user UI test for F024-R20/S54 MUST verify responsiveness by sending ⌘T after repeated scrolling and observing that Terminal Board becomes reachable; it MUST NOT be described as asserting that every project was listed or that a particular scroll offset was preserved.

### F024-R21: Successful Deletion Closes Open File Presentations
After a local or remote filesystem deletion succeeds, the explorer MUST emit an `ExplorerDeletionEvent` containing the exact target URL and whether the target was a directory. The owning local or remote project session MUST forward that typed event. Detailed editor groups and docked/floating file groups MUST close file tabs at the exact deleted path and, for a directory, every path-component descendant. Those deletion-driven closes MUST set `discardUnsavedChanges` so no close flush or later autosave can recreate a deleted file or descendant. Failed or cancelled deletion MUST emit no event and close no tab.

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

**Given** the user requests deletion from a file or folder context menu
**When** the confirmation is created
**Then** it represents the exact right-clicked item rather than a stale selection
**When** the destructive `Delete` action is accepted
**Then** that target path is removed from its local or remote filesystem
**And** dependent selections under that subtree are cleared/reset
**And** tree refresh runs
**When** the user cancels instead
**Then** no filesystem deletion is invoked

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

### Scenario F024-S37: Reveal in Finder is local-only

**Given** a local file or folder row context menu is open
**When** user selects `Reveal in Finder`
**Then** the item's path is revealed in macOS Finder
**Given** an active remote file or folder row context menu is open
**Then** `Reveal in Finder` is not present

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

### Scenario F024-S41: File and folder rows preserve native drag recognition

**Given** a local file or folder row is visible in the explorer
**When** the user presses and drags from the row
**Then** the initial mouse-down is handled by `NSOutlineView` so native drag recognition can begin
**And** a folder click toggles expansion only on mouse-up
**And** beginning a folder drag cancels the pending expansion action

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

### Scenario F024-S50: Active local rows open original items in the system

**Given** an active local file or folder row is visible
**When** the user chooses `Open in System`
**Then** macOS opens the item's original local URL
**And** an open failure is surfaced to the user

### Scenario F024-S51: Active remote rows expose transfer-backed external actions

**Given** an active remote file or folder row is visible
**When** its context menu opens
**Then** `Open in System` and `Download…` are available
**And** `Reveal in Finder` is absent
**When** either action runs
**Then** the app-wide coordinator overlay owns the one active explorer file/folder/project-root transfer, reports preparing/transferring/cancelling/publishing progress, and reports completion or persistent failure
**And** Cancel is unavailable while cancelling or publishing
**And** the coordinator slot remains occupied until cancellation cleanup finishes
**And** publication synchronously acknowledges MainActor state before a second cancellation check immediately ahead of replace/move
**And** cancellation after that check may not prevent atomic publication
**And** editor-triggered remote HTML Open in System remains independent
**And** failed or cancelled work does not publish a partial destination or open stale content

### Scenario F024-S52: Remote rows do not start drag and drop

**Given** a remote file or folder row is visible
**When** the user attempts to drag it
**Then** no drag/drop transfer begins
**And** the user can use `Download…` instead

### Scenario F024-S53: Every explorer surface confirms deletion for the exact right-clicked item

**Given** a local or remote file or folder is right-clicked in the AppKit unified explorer, SwiftUI explorer, or Shelf Files sidebar
**And** mutable current selection may identify another item
**When** the user chooses `Delete`
**Then** that surface retains the exact right-clicked item or path and creates `ExplorerDeleteConfirmation` from it rather than current selection
**And** the title is `Delete “name”?` using that retained item's exact name
**And** the first message paragraph repeats the exact name, warns that deletion is permanent, and states that it cannot be undone
**And** a separate following paragraph contains the localized `Path:` block and that retained item's exact full local or remote path
**And** AppKit, SwiftUI explorer, and Shelf present the same content and behavior
**And** the destructive button is `Delete`
**And** no unresolved raw name or path placeholder is shown
**And** full-path disclosure is intentional in this local confirmation dialog so the user can distinguish ambiguous targets
**When** the user cancels
**Then** the dialog closes and no filesystem deletion occurs

### Scenario F024-S54: Files sidebar remains responsive after repeated scrolling

**Given** a fixture with eight projects is open and the Files sidebar exists
**When** the sidebar is scrolled down and up repeatedly
**And** the user presses ⌘T
**Then** the application remains responsive
**And** Terminal Board becomes reachable
**But** this scenario does not assert that all projects are listed or that a specific scroll offset is preserved

### Scenario F024-S55: Successful deletion closes matching file tabs without recreating content

**Given** a local or remote file, or a directory containing open files, is represented in detailed and docked/floating editor groups
**When** confirmed filesystem deletion succeeds
**Then** the explorer emits one typed event with the exact target URL and directory flag
**And** the owning project session forwards it to the file-presentation coordinator
**And** detailed and docked/floating tabs at the exact path, plus directory descendants when applicable, close
**And** each deletion-driven close discards unsaved changes instead of flushing or scheduling autosave
**And** no deleted path is recreated
**But** cancellation or deletion failure emits no event and leaves tabs open

## Acceptance Criteria

- Tree load completes within 200ms for projects with up to 10,000 files (PERF-3).
- Observability is partial: remote transfer lifecycle and newly relevant diagnostics are recorded, and diagnostics export sanitizes path-like event-metadata strings; comprehensive logging of every local file operation required by OBS-1/OBS-2 is not implemented.
- Keyboard-only navigation supported for all tree operations (A11Y-2).
- Error alerts are dismissible and non-blocking (REL-6).
- Active local file/folder menus open original URLs through macOS; active remote menus instead provide transfer-backed Open in System and Download… without Reveal in Finder (F024-R16, R17).
- Coordinator-backed remote explorer file/folder and active project-root actions share one app-wide transfer slot, retain it through cancellation cleanup, expose cancelling/publishing/persistent-failure states, and never publish partial downloads or open stale content; editor-triggered remote HTML Open in System is independent (F024-R17).
- Remote drag/drop remains unsupported while local native drag recognition is retained (F024-R18).
- AppKit unified explorer, SwiftUI explorer, and Shelf Files sidebar deletions share exact-target `ExplorerDeleteConfirmation` content and cancellation behavior for local and remote files and folders: the exact name appears in the title and permanent warning paragraph, and a separate following localized `Path:` paragraph displays the exact full path captured from the retained right-click target rather than mutable current selection (F024-R06, R19).
- Successful local/remote deletion emits and forwards a typed exact-target event; detailed and docked/floating file tabs at that path or below a deleted directory close with `discardUnsavedChanges`, preventing close flush/autosave from recreating deleted items (F024-R21, S55).
- The F024-R20/S54 user UI test sends ⌘T after repeated Files-sidebar scrolling and waits for Terminal Board; it does not enumerate all projects or assert scroll-offset preservation.

## Verification Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Production source for F024-R21/S55 is `FolderExplorerTypes.swift`, `FolderExplorerViewModelActions.swift`, `RemoteFolderExplorer.swift`, `ProjectSession.swift`, `RemoteProjectSession.swift`, `VibeSpaceCanvasFileOpenUseCase.swift`, `ContentViewerStore.swift`, `EditorGroupStore.swift`, and `DockedFileViewerCoordinator.swift`. `FolderExplorerViewModelTests` directly checks only shared `ExplorerDeleteConfirmation` formatting for representative names and paths; no static test directly invokes `ExplorerDeletionEvent`, `closeFileTabs`, `handleDeletion`, or `discardUnsavedChanges`, so emission/forwarding and exact/descendant detailed+docked+floating discard closure remain production-source inspection. The F024-R20/S54 UI source is `VibeSpaceAndNavigationUITests.testFilesSidebarRemainsResponsiveAfterRepeatedProjectScrolling`; it creates eight projects, performs six down/up scroll pairs, sends ⌘T, and waits for Terminal Board without enumerating rows or checking scroll offset.

## Open Questions

- Should the detached editor window action (F024-S31) be wired into the context menu for initial release?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-23 | Final reconciliation names the complete typed deletion production path, confirms exact/descendant detailed+docked+floating discard closure with no recreation, and corrects static/build evidence. | — |
| 2026-10-23 | Added F024-R21/S55 for post-success typed local/remote deletion events, project-session forwarding, and exact/descendant detailed+docked discard closure that prevents autosave resurrection; identified the F024-R20/S54 user UI test exactly and narrowed all evidence to static/build-only scope. | — |
| 2026-10-23 | Added F024-R20/S54 with the exact repeated-scroll responsiveness assertion; narrowed delete-confirmation evidence to direct shared-model formatting; final validation reached build/test-build only with no executed pass. | — |
| 2026-10-20 | Expanded F024-R19/S53 exact-target confirmation requirements across AppKit, SwiftUI, and Shelf. Static evidence is limited to direct shared-model formatting for representative file, folder, and remote-style inputs; it does not prove per-surface target retention, Cancel, or delete dispatch. | — |
| 2026-10-20 | Reconciled remote publication with synchronous MainActor acknowledgment plus a final cancellation check and residual atomic boundary; marked all-file-operation observability partial, documented metadata sanitization and absent size confirmation, and recorded build/test-build-only evidence with no executed test pass. | — |
| 2026-10-01 | Updated S41 so local folder rows preserve native drag recognition by deferring expansion until mouse-up and cancelling it when a drag begins. | — |
| 2026-07-14 | Added serialized refreshes, deferred watcher replay, deterministic create/rename visibility, and incremental outline updates (S46–S49). | — |
| 2026-04-16 | Added targeted watcher refresh (S42), silent subtree refresh (S43), disclosure toggle (S44), and tree mutation tracking (S45). | — |
| 2026-04-15 | Migrated from the legacy sidebar and folder-explorer documents. | — |
