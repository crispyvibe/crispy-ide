---
title: "Shelf"
feature: "F033"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "Shelf"
  order: 3
---

# Shelf

## Overview

Shelf is a pinned-files section at the top of the Files sidebar. Use it for standalone files you want to keep close without turning them into part of a project tree.

## Getting Started

1. Open the **Files** sidebar.
2. If Shelf already has files, it appears above your projects.
3. Click the Shelf header chevron to expand or collapse it.
4. Click any Shelf file to open it in the main content viewer.

Files opened from Finder with **Open With CrispyVibes** or dropped onto the app are added to Shelf automatically.

## Workflows

### Open a Shelf file

- Click a file in the Shelf section.
- Crispy opens it in the main content viewer and keeps the file pinned in Shelf.

### Remove one file

- Open the context menu for a Shelf file.
- Choose **Remove from Shelf**.

### Clear Shelf

- Open the context menu on the Shelf header.
- Choose **Clear**.

### File actions

- Hover a Shelf row to see the full path as a tooltip.
- Open the file row context menu to:
  - open the file
  - open its directory in a terminal
  - reveal it in Finder
  - copy its path
  - rename it
  - remove it from Shelf
  - delete it from disk

### Use Finder or drag and drop

- Drop one or more files onto Crispy, or open them from Finder with CrispyVibes.
- CrispyVibes pins the files to Shelf, reveals the Files sidebar when a vibespace is available, and opens the first file.

## Keyboard Shortcuts

Shelf has no dedicated keyboard shortcuts.

## Settings / Configuration

Shelf is automatic. Its pinned-file list is persisted by the app and restored on the next launch.

## Troubleshooting

| Problem | What to check |
|---------|---------------|
| A Shelf file is dimmed and shows a warning icon | The file was moved or deleted outside CrispyVibes. Remove it from Shelf or restore the file on disk. |
| I dropped files onto Crispy but the Files sidebar did not appear | Shelf still stored the files. Open or create a vibespace, then open the Files sidebar. |
| I cleared Shelf by mistake | Reopen the files from Finder or drag them into Crispy again. |

## Known Limitations

- Shelf only appears when it contains files.
- Shelf pins files; it does not replace the project explorer.
