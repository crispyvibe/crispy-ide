---
title: "File Explorer"
feature: "F024"
domain: "explorer"
audience: "user"
version: "1.0"
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

1. Right-click a file or folder and choose **Delete**.
2. A destructive confirmation dialog appears.
3. Confirm to remove the item from disk.
4. Dependent selections under the deleted subtree are cleared.
5. Items removed outside Crispy are also deselected when their directory refreshes.

### Opening Files

1. **Single-click**: Previews the file (transient tab).
2. **Double-click**: Opens the file as a persistent editor tab.
3. In Terminal Only mode, file activation does not switch the canvas to Detailed view.

### Context Menu Actions

1. Right-click any file or folder row to access the context menu.
2. Available actions:
   - **Reveal in Finder** — opens the item's location in macOS Finder.
   - **Copy Path** — copies the absolute path to clipboard.
   - **Copy Relative Path** — copies the path relative to the project root.
   - **Open in Tab** — opens the file as a persistent editor tab.
   - **Open in Terminal** — opens a terminal at the folder path (or file's parent path).

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

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Directory won't expand | Check for loading indicator. If stuck, use the project header refresh button. For remote projects, verify SSH connection. |
| Files not appearing after creation | The affected folder refreshes before inline rename begins. If the worker reports an error, dismiss it and retry the operation. |
| Error alert on operation | Sidebar operation failures surface as dismissible alerts. Read the message and retry. |
| Remote explorer shows no files | Check SSH connection status in the toolbar. Use explicit refresh once connected. |
| Git status not showing | Ensure the project is inside a git repository. Check source control settings for ignored directories. |
| Search not finding files | Search filters by filename. Ensure your query matches part of the filename or path. |
