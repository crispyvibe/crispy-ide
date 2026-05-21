---
title: "Terminal Board Dock"
feature: "F037"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Dock"
  order: 7
---

# Terminal Board Dock

## Overview

Terminal Board Dock lets you pin files, browser pages, VibeCast sessions, and ACP sessions as docked tiles on the terminal board. Docked content lives alongside your terminal tiles, persists across sessions, and integrates with spotlight for focused viewing. This turns the terminal board into a multi-content workspace where code, documentation, and AI sessions coexist with your terminals.

## Getting Started

1. Switch to Terminal Board mode (⌘T).
2. Open a file from the file explorer — it appears as a temporary spotlight preview over the board.
3. Click the "Pin to Dock" button in the spotlight chrome to create a permanent docked tile.
4. The file tile now lives on the board alongside your terminal tiles.

## Workflows

### Previewing a File on the Terminal Board

1. In Terminal Board mode, activate a file from the file explorer.
2. The file opens as a temporary spotlight preview overlaid on the board.
3. The board canvas mode remains `terminalOnly` — no mode switch occurs.
4. Activating another file replaces the current preview (no stacking from explorer activation).
5. Press Escape or click outside the spotlight card to dismiss the preview.

### Pinning a File to the Board

1. Open a file in spotlight preview (from the explorer or another source).
2. Click the **Pin** action in the spotlight chrome.
3. A docked file tile is created on the board with the live editor content.
4. The tile supports all standard board interactions: drag, resize, swap, minimize, restore, focus.

### Pinning a Browser to the Board

1. Open a browser in spotlight preview.
2. Click the **Pin** action in the spotlight chrome.
3. A docked browser tile is created on the board with the live browser session.

### Pin Behavior in Detailed Mode

When canvas mode is Detailed (not Terminal Board):
- The Pin action promotes the file or browser content into the detailed content viewer instead.
- No board tile is created.
- This works even when the terminal board has no free tile capacity.

### Minimizing and Restoring Docked Tiles

1. Click the minimize button (−) on a docked tile header, or use the context menu > "Minimize".
2. The tile moves into the minimized tab bar at the bottom of the board.
3. Click the minimized tile in the tab bar to restore it to the board.
4. Minimized tiles persist across sessions.

### Closing a Docked Tile

1. Click the close button (×) on the docked tile header.
2. The tile is removed from the board.

### Opening a Docked Tile in Spotlight

1. Double-click the content area of a docked file or browser tile.
2. The content opens in spotlight mode using the same viewer state.
3. Docked tiles participate in spotlight carousel navigation alongside other persistent spotlight items.

### Dragging and Resizing Tiles

1. Drag a tile by its header to reposition it on the board.
2. Visual decorations indicate valid drop targets during the drag.
3. Resize tiles by dragging their edges (resize constraints are shown during interaction).
4. Layout changes are persisted automatically.

### VibeCast and ACP Tiles

1. Pin a VibeCast session to the board — it renders live VibeCast content as a docked tile.
2. Pin an ACP session to the board — it renders live ACP content and persists its snapshot for session restoration.
3. Both tile types follow standard board interaction rules and participate in spotlight carousel navigation.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Dismiss temporary preview | Escape |
| Open Terminal Board | ⌘T |
| Navigate board left | ⌘⌥← |
| Navigate board right | ⌘⌥→ |

## Settings

No dedicated settings for the dock feature. Board layout and pinned tiles are persisted automatically as part of the vibespace state.

## Tips

- **Capacity limit**: The board has a maximum tile capacity. If the board is full, the pin action is rejected and the spotlight preview remains visible. In Detailed mode, the pin action always works (routes to the content viewer instead).
- **Missing file pruning**: If a pinned file no longer exists when the vibespace reopens, the tile is removed gracefully without crashing.
- **Temporary vs. persistent**: Temporary previews (from explorer activation) are excluded from spotlight carousel navigation. Only pinned/docked tiles participate in carousel navigation.
- **No duplicate pins**: When a docked tile is already in spotlight view, no second pin action is shown.
- **Nested previews**: Opening a preview from within another spotlight item creates a nested stack. Dismissing the nested preview restores the previous spotlight item.
- **Context menu**: Right-click any docked tile for actions including minimize and window transfer options.
- **Board window transfer**: Docked tiles can be sent to detached board windows for multi-monitor workflows.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pin button not appearing | Ensure you're in Terminal Board mode (⌘T). In Detailed mode, pin routes to the content viewer instead. |
| Pin rejected / nothing happens | The board may be at capacity. Close or minimize existing tiles to free space. |
| File tile shows empty content | The file may have been moved or deleted. Close the tile and re-pin from the explorer. |
| Minimized tiles missing after restart | Ensure the vibespace was saved properly before closing. |
| Browser tile not restoring | Browser session snapshots are persisted; if the snapshot is invalid, the tile may need to be re-pinned. |
