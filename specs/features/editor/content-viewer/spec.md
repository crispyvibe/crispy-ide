# F006 Content Viewer

**Domain:** Editor
Status: draft

---

## Requirements

### F006-R01: Editor Pane Lifecycle
The content viewer must open files by extension/UTType detection, show placeholder states when no file is selected or type is unsupported, and clear transient state on selection changes.

### F006-R02: Save and Autosave
Editable documents must show unsaved indicators, autosave after ~450ms debounce, support manual save, and surface save errors.

### F006-R03: Preview vs Persistent Tabs
Single-click opens preview tabs; double-click opens persistent tabs. Reopening a tabbed file reuses the existing tab. Closing tabs selects an adjacent fallback.

### F006-R04: Detached Editor Windows
Files can be opened in independent detached editor windows. Reopening the same file focuses the existing detached window.

### F006-R05: Git Compare Rendering
Git compare mode renders diff content in read-only monospaced preview regardless of file type.

### F006-R06: Remote Editor Startup and Recovery
Remote text tabs suppress transient SSH readiness alerts during vibespace restore and retry with bounded backoff before surfacing failure.

### F006-R07: Editor Pluggable Registry
Content rendering uses a pluggable registry keyed by document type. Legacy routes are represented as plugins. New types require only plugin registration.

### F006-R08: External File Change Detection
The editor reloads content when the underlying file is modified externally, reconciling unsaved changes or notifying the user.

### F006-R09: Non-File Tab Types
The editor supports non-file tab types (terminal, acpPane) with specialized content hosts and standard tab lifecycle.

### F006-R10: Git Historical File Content Preview
Historical file content can be previewed in read-only mode with title reflecting path and commit reference.

### F006-R11: Docked File Viewer
DockedFileViewerCoordinator manages a file viewer in the terminal board context supporting the same document types as the main editor.

### F006-R12: Split Pane Management
The content viewer supports up to 4 independent split panes with horizontal/vertical orientation, drag-to-split, and recursive tree rendering.

### F006-R13: Viewer Scope Filtering
Tabs can be filtered to the focused project or shown across all projects.

### F006-R14: Session Snapshot and Restore
The full split layout, tabs, and viewer scope can be serialized and restored across sessions.

### F006-R15: Tab Types
Five tab kinds are supported: file, vibeCast, webPage, terminal, and acpPane, each with dedicated content views.

### F006-R16: Project Color Tags
File tabs resolve project color from path prefix matching. ACP pane tabs use accent color. Unmatched tabs have no color.

### F006-R17: File Retargeting on Rename
Renaming a file or directory remaps all affected open tabs, content providers, and editor buffers.

### F006-R18: Detailed Tray Terminals Can Be Docked Into the Main View
The content viewer MUST accept the active terminal from the detailed bottom tray as a draggable terminal source. Dropping that terminal into an existing pane or pane split target MUST open or activate a terminal tab for the same live session using the normal content-viewer split rules. Closing that content-viewer terminal tab MUST only remove that presentation and MUST NOT terminate the terminal session.

---

## Scenarios

### F006-S01: Selecting a file opens it in the editor pane
Given a file is selected in explorer
When selection reaches editor view model
Then the editor clears transient state
And determines document type by extension and UTType fallback
And loads content or preview according to detected type

### F006-S02: No file selected placeholder
Given no file is currently selected
When editor content area renders
Then `No File Selected` placeholder is shown

### F006-S03: Generic preview unavailable placeholder
Given document mode is none/unsupported without text fallback
When content area renders
Then `Preview Unavailable` state is shown

### F006-S04: Editable documents show unsaved indicator
Given markdown, HTML, plain text, JSON, Python, or R document is editable
When content differs from last saved content
Then `Unsaved` badge appears in header

### F006-S05: Content edits trigger debounced autosave
Given editable document content changes
When no further edits occur for ~450ms
Then save is executed automatically

### F006-S06: Manual save command persists current content
Given editable document is open
When user invokes save command
Then current content snapshot is written atomically to disk
And unsaved state is reconciled against latest editor content

### F006-S07: Save errors are surfaced to users
Given write fails during save
When save operation completes
Then editor shows a document error alert

### F006-S08: Single click opens file in preview mode
Given a file is selected once from explorer
When editor has no matching persistent tab for that file
Then editor opens file content in preview mode
And preview badge is shown

### F006-S09: Double click opens file in persistent tab
Given a file row is activated with double click
When open-tab intent is emitted
Then editor creates a persistent tab for the file
And tab strip is shown with close action for that tab

### F006-S10: Reopening an already tabbed file reuses tab
Given a file already exists in editor tab list
When user requests tab-open for the same file again
Then editor activates existing tab
And no duplicate tab is created

### F006-S11: Closing tabs updates active document predictably
Given multiple editor tabs are open
When active tab is closed
Then editor selects adjacent fallback tab when available
When last tab is closed
Then editor clears current document state

### F006-S12: Open-in-window creates detached editor shell
Given explorer emits open-window action for a file
When project session handles the request
Then detached editor window opens with that file loaded
And detached window uses independent editor view model state

### F006-S13: Reopen request focuses existing detached window
Given a detached editor window is already open for a file path
When open-window action is requested again for same file
Then existing detached window is brought to front
And duplicate window is not created

### F006-S14: Git compare mode renders diff content regardless file type
Given editor receives compare-git-status open action
When worker returns diff text or status fallback for target path
Then editor enters git-diff document mode
And compare content is rendered in read-only monospaced preview
And compare title reflects `<relative path> (Changes)`

### F006-S15: VibeSpace-restored remote text tabs suppress transient SSH readiness alerts during startup
Given a VibeSpace restore reopens a text document from an SSH-backed Project
And the SSH or SFTP connection is still starting
When the editor attempts to restore that tab
Then transient connection-readiness failures do not surface a modal document error
And the editor keeps the document in an unavailable state until the user retries after the connection is active

### F006-S16: Remote text opens wait briefly for SSH readiness before surfacing failure
Given the user opens a text document from an SSH-backed Project
When the SSH-backed file service is still becoming ready
Then file open retries asynchronously with a bounded backoff before surfacing failure
And the wait does not block the main thread
And if the connection still is not ready after the retry budget the editor shows an unavailable state instead of hanging indefinitely

### F006-S17: Editor content rendering uses a pluggable registry by document type
Given a file is opened in the editor
When the editor resolves the content renderer
Then the renderer is selected from a pluggable registry keyed by document type
And no monolithic view-body branch determines the renderer

### F006-S18: Legacy editor routes are represented as plugins
Given a file type previously handled by a specialized legacy editor route
When that file type is opened
Then the legacy route is loaded as a registered plugin
And existing behavior is not regressed

### F006-S19: Adding a new document type requires plugin registration only
Given a developer adds support for a new document type
When the new type is integrated
Then only a plugin registration is required
And no changes to a central view-body switch are needed

### F006-S20: Editor reloads content when file changes on disk externally
Given an editable document is open in the editor
When the underlying file is modified by an external process
Then the editor detects the change and reloads the updated content
And unsaved in-editor changes are reconciled or the user is notified

### F006-S21: Editor supports non-file tab types such as terminal and acpPane
Given the editor tab strip is active
When a non-file tab type (terminal, acpPane) is opened
Then the tab renders its specialized content host instead of a file editor
And tab lifecycle follows the same close and activation rules as file tabs

### F006-S22: Git historical file content can be previewed in read-only mode
Given a file has git history available
When the user requests historical content preview for a specific commit
Then the editor displays the file content at that revision in read-only mode
And the title reflects the file path and commit reference

### F006-S23: DockedFileViewerCoordinator manages file viewer in terminal board context
Given the terminal board is active
When a file viewer is docked into the terminal board
Then DockedFileViewerCoordinator manages the viewer lifecycle
And the docked viewer supports the same document types as the main editor

### F006-S24: Split the active pane horizontally
Given a single editor pane is open
When the user triggers a horizontal split on the active pane
Then SplitLayoutEngine inserts a new leaf beside the target leaf
And the tree becomes a .split node with orientation .horizontal and ratio 0.5
And a new EditorGroupStore is created for the new pane
And the new pane becomes the active pane

### F006-S25: Split the active pane vertically
Given a single editor pane is open
When the user triggers a vertical split on the active pane
Then the tree becomes a .split node with orientation .vertical and ratio 0.5
And a new empty pane is activated

### F006-S26: Reject split when at maximum panes
Given 4 panes are already open (SplitPaneNode.maxPanes == 4)
When the user attempts to split any pane
Then split() returns nil and the layout is unchanged

### F006-S27: Toggle the orientation of the parent split
Given two panes exist in a horizontal split
When the user triggers toggleOrientation on either pane
Then SplitLayoutEngine.toggleOrientation flips the parent .split node's orientation to .vertical
And the ratio and child order are preserved

### F006-S28: Close a pane in a multi-pane layout
Given 3 panes are open
When the user closes a pane via the close button or context menu
Then SplitLayoutEngine.removePane collapses the target leaf from the tree
And all tabs in the closed pane's EditorGroupStore are closed (including browser/ACP cleanup handlers)
And stale split ratios are pruned
And if the closed pane was active, the first remaining leaf becomes active

### F006-S29: Auto-close empty pane
Given a split layout with 2+ panes
When the last tab in a pane is closed (group.tabs.count reaches 0)
Then the pane is automatically removed via splitStore.closePane

### F006-S30: Drop a tab onto a pane edge to create a new split
Given a tab is being dragged over an existing pane
And the drop location falls in the left, right, top, or bottom zone (3-column grid detection)
When the user drops the tab
Then splitActiveWithTab removes the tab from the source group
And creates a new split with the appropriate orientation (horizontal for left/right, vertical for top/bottom)
And opens the tab in the newly created pane

### F006-S31: Drop a tab onto the center zone
Given a tab is being dragged over an existing pane
And the drop location falls in the center zone
When the user drops the tab
Then the tab is moved to the target group without creating a new split

### F006-S32: Drop a file URL onto a pane
Given a file URL is dragged from Finder or the explorer
When the user drops it onto a pane edge
Then a .file tab is created from the URL and the split-or-move logic applies

### F006-S33: Drop overlay visual feedback
Given a tab drag is in progress over a pane
Then EditorDropZoneOverlay renders a highlighted rectangle in the detected zone (left/right/top/bottom/center)
And the overlay uses the accent color at 15% fill with a 2px stroke

### F006-S34: Filter tabs to focused project
Given viewerScope is .focusedProject and a focusedProjectRootPath is set
When the pane renders its tab strip
Then EditorGroupStore.filteredTabs returns only tabs whose file path starts with the project root
And .webPage tabs are filtered by matching projectPath
And .vibeCast, .terminal, and .acpPane tabs always pass the filter

### F006-S35: Show all tabs across projects
Given viewerScope is .allProjects
When the pane renders its tab strip
Then all tabs in the group are shown unfiltered

### F006-S36: Snapshot the editor session
Given a split layout with open tabs across multiple panes
When snapshot() is called
Then the full SplitPaneNode tree is serialized to SplitNodeSnapshot
And each pane produces an EditorPaneSnapshot containing:
| openFiles | FileDocumentReference list |
| terminalTabs | TerminalTabReference list |
| browserTabs | BrowserPaneTabSnapshot list (with session snapshot from provider) |
| acpTabs | ACPStandalonePaneSnapshot list (from provider) |
| activeTabID | the currently active tab ID |
And split ratios are stored as [String: Double] keyed by UUID
And the current viewerScope is included

### F006-S37: Restore the editor session
Given a persisted EditorSessionState
When restore() is called
Then the SplitPaneNode tree is rebuilt from the snapshot
And for each pane, tabs are reopened in order: files → terminals → browsers → ACP panes
And file tabs with missing files on disk are skipped (fileExists check)
And browserTabRestoreHandler and acpPaneRestoreHandler are invoked for their respective tab types
And the active tab is restored per pane
And empty panes (all files deleted) are collapsed from the tree

### F006-S38: Open file tab type
When a file tab is opened in an editor group
Then the tab renders MarkdownEditorView
And icon is doc.text / photo / doc.richtext variant

### F006-S39: Open vibeCast tab type
When a vibeCast tab is opened in an editor group
Then the tab renders VibeCast view (or unavailable)
And icon is antenna.radiowaves.left.and.right

### F006-S40: Open webPage tab type
When a webPage tab is opened in an editor group
Then the tab renders BrowserContentView
And icon is globe

### F006-S41: Open terminal tab type
When a terminal tab is opened in an editor group
Then the tab renders TerminalSessionHostView
And icon is terminal

### F006-S42: Open acpPane tab type
When an acpPane tab is opened in an editor group
Then the tab renders ACPStandalonePaneContentView
And icon is sparkles

### F006-S43: Terminal tab unavailable
Given a terminal tab references a session that cannot be resolved
When the pane body renders
Then a ContentUnavailableView is shown with the terminal unavailable message

### F006-S44: ACP pane unavailable
Given an acpPane tab references a store ID not found in standaloneACPStores
When the pane body renders
Then a ContentUnavailableView is shown with the ACP unavailable message

### F006-S45: Resolve project color for a file tab
Given projectColorTagsByPath maps project root paths to ProjectColorTag values
And a file tab's URL starts with a known project root path
When the tab item is rendered
Then ContentViewerTab.projectColor returns the matching ProjectColorTag.color
And the longest matching prefix wins when multiple roots match

### F006-S46: ACP pane tabs use accent color
Given an acpPane tab is rendered
Then projectColor returns the fallback accent color

### F006-S47: No color for unmatched tabs
Given a file tab whose path does not match any project root
Then projectColor returns nil

### F006-S48: Rename a file that is open in tabs
Given a file at /old/path.swift is open in one or more editor groups
When retargetFileSystemLocation(from: oldURL, to: newURL) is called on ContentViewerStore
Then every EditorGroupStore iterates its tabs
And any .file tab whose URL matches or is a descendant of oldURL is remapped to newURL
And fileContentProviders and gitPresentations are re-keyed to the new tab IDs
And the active tab ID is updated if it was affected
And markdownViewModel.retargetOpenDocuments is called to update the editor buffer

### F006-S49: Rename a directory containing open files
Given files under /project/src/ are open
When the directory /project/src is renamed to /project/lib
Then all tabs with paths prefixed by /project/src/ are remapped under /project/lib/

### F006-S50: Open file in new split from explorer context menu
Given a file is already open in the editor
When the user opens a second file via explorer context menu or drag targeting a split zone
Then a new split pane is created alongside the existing pane
And the user can choose horizontal or vertical orientation for the new split

### F006-S51: Open VibeCast alongside a file in split layout
Given a file is open in the editor
When the user adds a VibeCast panel to the split layout
Then VibeCast renders in its own split pane beside the file pane
And both panes are independently resizable and closable

### F006-S52: Render a recursive split tree
Given a SplitPaneNode tree with nested .split and .leaf nodes
When SplitContainerView renders
Then SplitNodeView recursively produces NativeSplitView for each .split node
And leaf nodes render the pane content closure keyed by pane ID
And split ratios are bound via store.ratioBinding / store.setRatio
And NativeSplitView enforces minPrimary=100 and minSecondary=100

### F006-S54: Content area drop surface excludes file URLs when active tab is a terminal

**Given** the active tab in a pane is a terminal tab
**When** a file URL drag enters the content area drop surface
**Then** the drop is rejected by the content area delegate
**And** only tab drag types are accepted
**So that** file drops pass through to the underlying terminal view

### F006-S53: Active pane indicator
Given a split layout with multiple panes
Then the active pane shows a 2px accent-colored bar at the top
And tapping any pane activates it via the simultaneousGesture tap handler

### F006-S55: Dragging the detailed tray terminal into a pane centers it as a terminal tab

**Given** vibespace canvas mode is `Detailed`
**And** the focused project bottom terminal tray is showing one active terminal session
**And** the content viewer has an existing pane
**When** the user drags that terminal onto the center of the pane
**Then** the pane opens or activates a `.terminal(projectID, tabID)` tab for the same session
**And** the terminal session remains live
**And** no duplicate terminal process is created

### F006-S56: Dragging the detailed tray terminal to a pane edge creates a split

**Given** vibespace canvas mode is `Detailed`
**And** the focused project bottom terminal tray is showing one active terminal session
**And** the content viewer has an existing pane
**When** the user drags that terminal onto the left, right, top, or bottom split target of the pane
**Then** the content viewer creates a new split using the normal split rules
**And** the target split hosts a `.terminal(projectID, tabID)` tab for the dragged session
**And** the terminal session remains live during the move

### F006-S57: Closing a main-view terminal tab does not terminate the session

**Given** a terminal from the detailed bottom tray has been docked into the content viewer
**When** the user closes that terminal tab from the content viewer
**Then** only the content-viewer presentation is removed
**And** the underlying terminal session continues running
