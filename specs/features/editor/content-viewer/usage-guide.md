---
title: Content Viewer
domain: Editor
feature: F006
audience: user
version: "1.0"
sidebar:
  label: Content Viewer
  order: 1
---

# F006 Content Viewer — Usage Guide

The content viewer is where you open, view, and manage files in Crispy. It supports tabbed editing, split panes, and multiple file types — all in one vibespace.

> **Terminology:** A *VibeSpace* is Crispy's name for a vibespace. *VibeCast* is a tool for sending commands to terminals. *ACP Pane* is a chat window for AI coding assistants.

## Getting Started

Open any file from the sidebar to see it in the content viewer. Double-click to keep it as a persistent tab.

## Opening Files

- **Single-click** a file in the explorer to preview it. A "Preview" badge appears, and previewing another file replaces the current one.
- **Double-click** a file to open it in a persistent tab that stays until you close it.
- If a file is already open in a tab, selecting it again activates the existing tab — no duplicates are created.

CrispyVibes detects the file type by extension first, then falls back to system type detection. Text files up to 6 MB can be opened. Image and PDF files have no size limit.

## Tabs

### Tab Types

| Tab Type | What It Shows |
|----------|---------------|
| File | Documents, code, images, PDFs |
| VibeCast | VibeCast panel |
| Web Page | Embedded browser view |
| Terminal | Terminal session |
| ACP Pane | ACP standalone panel |

Each tab type displays a distinct icon so you can tell them apart at a glance.

### Closing Tabs

When you close a tab, CrispyVibes selects the nearest remaining tab. Closing the last tab in a pane clears the editor area. In a split layout, closing the last tab in a pane also removes that pane.

### Project Color Tags

File tabs show a color accent matching their parent project. If a file doesn't belong to a recognized project, no color is shown.

## Split Panes

You can split the editor into up to 4 independent panes, each with its own set of tabs.

### Creating Splits

- Use the split action to divide the active pane horizontally or vertically.
- The new pane becomes active and starts empty.

### Drag-to-Split

Drag a tab toward the left, right, top, or bottom edge of a pane to create a new split in that direction. A highlighted overlay shows where the tab will land. Drop a tab in the center zone to move it into that pane without splitting.

You can also drag a file from Finder or the explorer sidebar onto a pane edge to open it in a new split.

### Managing Splits

- Click anywhere in a pane to make it active (indicated by an accent-colored bar at the top).
- Toggle the orientation of a split between horizontal and vertical.
- Close a pane via its close button or context menu. If the closed pane was active, the first remaining pane takes over.

### Limits

- Maximum of 4 panes at a time. Attempting to split beyond this limit has no effect.
- Each side of a split has a minimum width.

## Filtering Tabs by Project

Control which tabs appear in the tab strip:

- **Focused Project** — shows only file tabs belonging to the currently focused project. VibeCast, terminal, web page, and ACP tabs always remain visible.
- **All Projects** — shows every tab regardless of project.

## Detached Editor Windows

Right-click a file in the explorer and choose "Open in Window" to open it in a standalone editor window. If a detached window for that file already exists, it comes to the front instead of creating a duplicate.

## Git Compare and History

- **Git Changes** — view a side-by-side diff of uncommitted changes for any file. The title shows the file path followed by "(Changes)".
- **Git History** — preview a file at a specific commit in read-only mode, with the title reflecting the file path and commit reference.

## Session Restore

CrispyVibes saves your editor layout automatically — split arrangement, open tabs, active tab per pane, and scope setting. When you reopen a vibespace, everything is restored. Files that no longer exist on disk are skipped, and empty panes are cleaned up.

## External File Changes

If a file you have open is modified by another application, CrispyVibes detects the change and reloads the content. If you have unsaved edits, you'll be notified so you can decide how to proceed.

## File Renaming

Renaming or moving a file (or a directory containing open files) automatically updates all affected tabs and editor buffers. No need to close and reopen anything.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘W | Close tab |
| ⌘S | Save (if applicable) |

## Related Guides

- [Editing](../editing/usage-guide.md)
- [Markdown](../markdown/usage-guide.md)
- [Previews](../previews/usage-guide.md)
