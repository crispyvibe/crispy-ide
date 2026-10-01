---
title: "Drag & Drop"
feature: "F025"
domain: "explorer"
audience: "user"
version: "1.0"
sidebar:
  label: "Drag & Drop"
  order: 2
---

# Drag & Drop

## Overview

Drag & Drop enables file and folder reorganization within the explorer sidebar. You can move items within a project by dragging them onto directories, or copy items across project boundaries by dragging between different project roots.

## Getting Started

1. Open the file explorer sidebar (Files tab in the side menu).
2. Click and hold a file or folder row to begin dragging.
3. Drag onto a target directory within the same project to move, or onto a directory in a different project to copy.
4. Release to complete the operation.

## Workflows

### Moving Files Within a Project

1. Click and hold a file or folder in the explorer tree.
2. Drag it onto another directory row within the same project.
3. Release the mouse — the item is moved to the target directory.
4. The tree refreshes to reflect the new location.
5. If the item was selected, selection paths remap to the moved destination.

### Copying Files Across Projects

1. Click and hold a file or folder in one project's tree.
2. Drag it onto a directory in a different project root.
3. Release the mouse — the item is copied to the target directory.
4. The original source item remains in place.
5. Both project trees refresh to reflect the change.

### Inserting a File or Folder Path into a Terminal

1. In a local project's side-panel file explorer, click and hold a file or folder row, then begin dragging.
2. Drop it on a Ghostty or SwiftTerm terminal surface.
3. Crispy inserts the shell-escaped path at the terminal cursor, using a relative path when the item is inside the terminal's current directory.
4. A normal folder click still expands or collapses the row; dragging does not toggle it.

Remote explorer items cannot be dragged into a local terminal because their paths refer to the remote host, not the Mac filesystem.

## Keyboard Shortcuts

No dedicated keyboard shortcuts. Drag & drop is a pointer-based interaction.

## Settings

No specific settings affect drag & drop behavior.

## Tips

- Invalid drop targets provide visual feedback — you cannot drop an item onto itself or its own descendants.
- Destination collisions (same-name file already exists at target) are validated and prevented.
- Cross-project operations always copy (never move) to prevent accidental data loss across project boundaries.
- The explorer delegates file and folder mouse-downs to `NSOutlineView` for native drag recognition. Folder expansion occurs on mouse-up only when no drag began.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Can't drop onto a directory | The target may be invalid (self-drop, descendant drop, or name collision). Check that the target directory doesn't already contain an item with the same name. |
| Item disappeared after drag | The item was moved within the same project. Check the target directory. |
| Cross-project drag didn't work | Ensure you're dragging onto a directory in a different project root. The target must be a directory, not a file. |
| Tree didn't refresh | The tree should auto-refresh after operations. Try clicking the refresh button on the project header. |
