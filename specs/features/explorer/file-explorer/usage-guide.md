---
title: "File Explorer"
feature: "F024"
domain: "explorer"
audience: "user"
version: "1.6"
sidebar:
  label: "File Explorer"
  order: 1
---

# File Explorer

## Overview

The File Explorer provides a tree-based file browser in the sidebar that lists every project in the active vibespace. It supports lazy-loaded directory expansion, search with ancestry preservation, inline create/rename/delete, context menu actions, project color tags, and both local and remote project roots.

## Getting Started

1. Click the **Files** tab in the side menu rail to open the file explorer.
2. Each project in your vibespace appears as a distinct root node.
3. Click disclosure arrows to expand directories (children load lazily on first expansion).
4. Single-click a file to preview it; double-click to open as a persistent tab.

## Workflows

### Browsing Files

1. Open the Files sidebar from the side menu rail.
2. In Detailed mode, the focused project auto-expands. In Terminal Only mode, all projects start collapsed.
3. Click disclosure arrows to expand directories — children are fetched on first expansion with a loading indicator.
4. Re-expanding a previously loaded directory reuses cached children (no re-fetch).
5. Folders sort before files, case-insensitively. Hidden items are visible and marked.
6. Git-ignored items appear with reduced visual emphasis.

### Searching Files

1. Type in the search field at the top of the explorer.
2. The tree filters recursively — matching files and their ancestor folders remain visible.
3. Matching text is highlighted in row labels.
4. Manual disclosure toggling is disabled during search mode.
5. Clear the search field to restore the normal tree view.

### Creating Files and Folders

1. Use the **New File** or **New Folder** buttons in the project header.
2. Alternatively, right-click the root list background for creation actions.
3. A new item is created and immediately enters inline rename mode.
4. Type the desired name and press Enter to confirm.
5. If a name collision exists, a unique path is generated automatically.
6. If the previously selected folder was removed outside Crispy, creation uses its nearest existing parent in the project.

### Renaming Items

1. Select an item and press **Enter**, or right-click and choose **Rename**.
2. An inline rename field appears.
3. Type the new name and press Enter to commit.
4. Press Escape to cancel without changes.
5. Empty names are ignored; duplicate destination names produce an error.
6. Selection paths remap to the renamed destination.

### Deleting Items

1. Right-click a file or folder in the AppKit unified explorer, SwiftUI explorer, or Shelf Files sidebar and choose **Delete**.
2. Crispy retains the exact item you right-clicked and creates the shared confirmation from that target, not from another row that is or later becomes selected. This is identical for local and remote files and folders on all three surfaces.
3. Verify the title is **Delete “name”?** with the exact item name.
4. Verify the first message paragraph is a permanent-deletion warning that repeats the exact item name and says the action cannot be undone.
5. In the following, separate paragraph, verify the localized **Path:** block displays the exact full local or remote path of the item you right-clicked. The dialog never substitutes an unresolved raw placeholder for the name or path. Showing this full path is intentional in the local confirmation dialog so you can distinguish same-named targets before deleting.
6. Choose the destructive **Delete** button to remove that exact retained item from its filesystem.
7. Choose **Cancel** to close the dialog without deleting anything.
8. After a successful local or remote deletion, Crispy closes open detailed and docked/floating file tabs at that exact path. Deleting a directory also closes tabs for files below it. These deletion-driven closes discard their buffers rather than saving, so Crispy autosave cannot recreate the deleted item. Cancellation or deletion failure leaves tabs open.
9. Dependent selections under the deleted subtree are cleared. Items removed outside Crispy are also deselected when their directory refreshes.

### Opening Files

1. **Single-click**: Previews the file (transient tab).
2. **Double-click**: Opens the file as a persistent editor tab.
3. In Terminal Only mode, file activation does not switch the canvas to Detailed view.

### Context Menu Actions

1. Right-click any active file or folder row to access its context menu.
2. Local items can provide:
   - **Open in System** — opens the original item in its default macOS application.
   - **Reveal in Finder** — reveals the item in Finder.
   - **Copy Path** — copies the absolute path to clipboard.
   - **Copy Relative Path** — copies the path relative to the project root.
   - **Open in Tab** — opens a file as a persistent editor tab.
   - **Open in Terminal** — opens a terminal at the folder path (or file's parent path).
3. Remote items provide **Open in System** and **Download…**, but never **Reveal in Finder**. Open in System first creates a protected temporary local copy. Download… asks you to choose a local destination.
4. Remote explorer and active project-root actions use one app-wide transfer overlay. Only one of those transfers runs at a time. The overlay shows preparation and manifest/item/byte transfer progress, **Cancelling…**, publication, completion, or failure. Cancel is available only before publication; cancelling keeps the slot occupied until network shutdown and partial-file cleanup finish, and a failure remains visible until dismissed. Publication is acknowledged before a final cancellation check immediately ahead of the atomic replace/move. A cancellation arriving after that check may not stop publication, so no Cancel control is shown while publishing. The Download action does not currently ask for size confirmation. Remote HTML opened from its editor is independent and uses the editor's busy indicator and normal alert instead of this overlay.

### Programmatic Sidebar Reveal

1. When code or another feature calls `revealInSidebar` with a file URL:
2. Ancestor directories are expanded automatically.
3. The target file row is selected and scrolled into view.

### Working with Remote Projects

1. Remote (SSH-backed) project roots display an `[ssh]` suffix in the sidebar.
2. Directories load lazily over SFTP — no preloading of the entire tree.
3. By default, use the refresh button for remote updates.
4. Testers can enable **Enhanced remote file explorer (Beta)** in Settings → Connections; reopen remote projects afterward. Enhanced mode polls the root and expanded directories and applies targeted refreshes.
5. The explicit refresh button remains available in both modes.
6. Use **Open in System** on an active remote file/folder to create and open a temporary local copy, or **Download…** to choose a durable local destination.
7. Remote drag and drop is not supported. Use Download… to copy remote content locally.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Rename selected item | Enter |
| Cancel rename | Escape |
| Focus Next Project | ⌘⌥] |
| Focus Previous Project | ⌘⌥[ |
| Focus Project 1–9 | ⌘1–⌘9 |

## Settings

- **Project Color Tags**: Assigned in VibeSpace Settings → Projects. Tagged project roots display their color indicator in the sidebar.
- **Source Control Settings**: Ignored directories and scan depth affect which items appear with git status.

## Tips

- Clicking a disclosure arrow expands/collapses the row without changing the current selection.
- File system events trigger targeted directory refreshes (not full tree reloads) — only affected directories update.
- Changes received while another sidebar tab is active are applied when you return to Files.
- Watcher-triggered refreshes run silently without loading spinners.
- Tree mutation tracking prevents redundant reloads when multiple events arrive in a batch.
- Each project header includes dedicated refresh, new file, and new folder buttons that target that specific project regardless of focus.
- Selecting a file from a non-focused project automatically focuses that project.
- The explorer uses NSOutlineView for native macOS tree performance and drag recognition.
- Repeatedly scrolling a multi-project Files sidebar should not make the app unresponsive; ⌘T should still open Terminal Board. This responsiveness check does not guarantee that every project row is visible at once or that a prior scroll offset is restored.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Directory won't expand | Check for loading indicator. If stuck, use the project header refresh button. For remote projects, verify SSH connection. |
| Files not appearing after creation | The affected folder refreshes before inline rename begins. If the worker reports an error, dismiss it and retry the operation. |
| Error alert on operation | Sidebar operation failures surface as dismissible alerts. Read the message and retry. |
| Delete dialog names or paths the wrong item, shows a raw placeholder, or combines warning and path | Cancel so no deletion occurs, then reopen the exact item's context menu. Report the mismatch; the title and permanent warning should repeat the retained target's exact name, and a separate following localized **Path:** paragraph should show its exact full local or remote path on AppKit, SwiftUI explorer, and Shelf. |
| Remote explorer shows no files | Check SSH connection status in the toolbar. Use explicit refresh once connected. |
| Git status not showing | Ensure the project is inside a git repository. Check source control settings for ignored directories. |
| Search not finding files | Search filters by filename. Ensure your query matches part of the filename or path. |

## Known Limitations

- Remote drag and drop is unsupported; use **Download…** for a local copy.
- Edits made to a remote item opened in another macOS application do not synchronize or write back to the SSH source.
- Only one coordinator-backed remote transfer from an explorer file/folder row or active project root runs at a time. Cancellation retains the slot through cleanup and interrupted transfers cannot resume. Before publication, Crispy synchronously acknowledges publishing and checks cancellation again immediately before replace/move; cancellation after that check may not prevent the atomic publication. Editor-triggered remote HTML Open in System is independent.
- Explicit Download shows manifest/item/byte progress but does not provide a size-confirmation prompt. Large-file editing confirmation is also not implemented.
- Replacing an existing download follows the save panel and destination filesystem's replacement behavior.

## Documentation Verification

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static unit source directly checks shared confirmation formatting only. Test-source search found no direct use of `ExplorerDeletionEvent`, `closeFileTabs`, `handleDeletion`, or `discardUnsavedChanges`; typed local/remote emission and forwarding plus exact/descendant detailed+docked+floating discard closure were verified from production source. `VibeSpaceAndNavigationUITests.testFilesSidebarRemainsResponsiveAfterRepeatedProjectScrolling` sends ⌘T after six scroll pairs and waits for Terminal Board without asserting all rows or scroll offset.

## Change History

- 2026-10-23: Version 1.6 records the exact successful-deletion production pipeline, detailed+docked+floating discard closure, no-recreation guarantee, and build/test-build-only validation.
- 2026-10-23: Version 1.5 documents post-success local/remote deletion-driven tab closure with discarded buffers, names the F024-R20/S54 user UI test exactly, and narrows verification to static/build-only evidence.
- 2026-10-23: Version 1.4 adds repeated-scroll responsiveness guidance and narrows documentation verification to the assertions present in static source.
- 2026-10-20: Expanded exact-target delete guidance across AppKit, SwiftUI, and Shelf; static evidence is limited to shared-model formatting and does not exercise each surface's right-click target, Cancel, or deletion route.
- 2026-10-20: Reconciled publication acknowledgment and final cancellation/atomic-move boundary; documented manifest/item/byte progress and the absence of editing or Download size-confirmation prompts.
