---
title: "Terminal Board Multi-Monitor"
feature: "F048"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Multi-Monitor Board"
  order: 7
---

# Terminal Board Multi-Monitor

## Overview

Terminal Board Multi-Monitor lets you spread your terminal board across multiple displays. Open detached board windows on secondary monitors while keeping your primary vibespace window on your main screen. Each window operates independently with its own spotlight, toolbar, and tile layout.

## Getting Started

1. Enter terminal board mode in your vibespace.
2. Right-click any tile header or minimized tab.
3. Select **Send to New Board Window**.
4. A new window opens containing that tile — drag it to another monitor.

You can open as many detached board windows as you need.

## Workflows

### Sending a tile to a new window

1. Right-click the tile header (or a minimized tab).
2. Select **Send to New Board Window**.
3. The tile moves to a new window. Position the window on any display.

### Sending a tile to an existing window

1. Right-click the tile header.
2. Select **Send to Board Window** → choose the target window by name.
3. The tile moves to the selected window.

### Creating terminals in a detached window

When a detached board window is focused:

- The **+** button creates a new terminal on that window's surface.
- Split actions create splits on that window's surface.
- Spotlight temporary terminals promote to that window's surface.

### Using spotlight in a detached window

Press the spotlight shortcut while a detached board window is focused. Spotlight opens within that window — it does not jump to the primary window.

### Adding VibeCast, Agent, or Browser tiles

Each detached window has a toolbar with buttons to add:

- **VibeCast** tile
- **Agent** tile
- **Browser** tile

These tiles are created on the detached window's surface.

### Renaming a detached window

Right-click the window's titlebar and select **Rename Window**. Enter a new name and confirm. The name persists and appears in transfer target menus.

### Closing detached windows

- Close a detached window normally (⌘W or the close button). Its tiles return to the primary board.
- When a vibespace closes, all its detached board windows close automatically.
- If you transfer the last tile out of a detached window, it closes automatically.

## Keyboard Shortcuts

Standard macOS window shortcuts apply:

| Action | Shortcut |
|--------|----------|
| Close window | ⌘W |
| Minimize window | ⌘M |
| Move all of focused project's panes to a new monitor | ⌘⌥M |
| Recall all panes on the current detached window back to primary | ⌘⌥B |

Spotlight and terminal shortcuts work within the focused board window.

### Bulk move project to a new monitor

1. Switch the vibespace to terminal board mode (default `⌘T`).
2. Focus a project that has tiles on the current board surface.
3. Press `⌘⌥M`.

Every tile on the current surface that belongs to the focused project moves to a new detached board window in one operation. Drag the new window to another display.

The shortcut works from both the primary window (source = primary surface) and a detached window (source = that detached window's surface). Tiles belonging to other projects on the same surface stay where they are.

You can also right-click any tile and choose **Send All From This Project to New Window** for the same effect, scoped to the right-clicked tile's project. The menu item is hidden for tiles without a project association (e.g., standalone terminals).

### Bulk recall to primary

1. Click into a detached board window so it becomes the key window.
2. Press `⌘⌥B`.

Every tile on that detached surface moves back to the primary surface and the detached window closes. If the primary surface is already at its 16-tile cap, overflow tiles roll into the minimized tab strip.

The shortcut is a no-op when invoked from the primary window or outside terminal board mode.

Both bindings are editable in App Settings → Shortcuts → Terminal Board.

## Settings / Configuration

No additional settings are required. Detached board windows are a natural extension of terminal board mode.

Window positions are automatically saved per vibespace and restored on next open when the same display topology is available.

## Troubleshooting

### Detached window appears on wrong monitor

If your display topology changed since the last session, macOS may place the window on your primary display. Simply drag it to the desired monitor — the new position will be saved.

### Tiles not appearing after transfer

Tile transfer is instantaneous. If a tile seems missing, check:

- The target window may be behind other windows. Click it in the Dock or use Mission Control.
- The tile may have been minimized on the target surface.

### Detached window won't close

Detached windows close with their owning vibespace. If a window persists unexpectedly, close the vibespace and reopen it.

## Known Limitations

- Detached board windows are terminal-board surfaces only — no file explorer, editor, or settings.
- There is no single continuous board canvas spanning monitors; each window is an independent surface.
- Drag-to-transfer between windows uses screen-point hit testing; very fast drags may not register the target.
- Window placement restoration is best-effort; macOS may adjust frames if displays are rearranged.
