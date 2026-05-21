---
title: "Terminal Board"
feature: "F002"
domain: "terminal"
audience: "user"
version: "1.1"
sidebar:
  label: "Board"
  order: 2
---

# Terminal Board

## Overview

Terminal Board is a terminal-first vibespace surface for arranging terminals, file previews, browser panes, ACP panes, and VibeCast in a resizable board. A vibespace can have the main board plus additional detached board windows for multi-monitor work.

Detached board windows belong to the same vibespace. They are not separate vibespace shells: settings, detailed view, project switching, and app-wide flows stay owned by the main vibespace window.

## Getting Started

Open a vibespace and switch to Terminal Board mode. The board shows tiles in a bounded grid. Use the board toolbar to create terminals, open board content, or manage board-level actions.

Detached board windows reopen with the vibespace using saved board state and best-effort window placement.

## Workflows

### Create A Terminal Tile

Use `New Terminal` from the board. Choose a project or vibespace terminal and select the working directory. The new terminal is added to the board window where you started the action.

### Split A Terminal

Use `Split Terminal` from a terminal tile, terminal context menu, or terminal spotlight. The persistent split is added to the same board window that initiated the split.

### Move Tiles Inside A Board

Drag a tile header to reposition it in the current board window. Drop targets support left, right, above, below, and swap behavior. Resize columns and rows with the dividers between tiles.

### Send A Tile To Another Board Window

Right-click a visible tile header or minimized tab header.

Choose `Send to New Board Window` to move that single tile into a new detached board window.

Choose `Send to Board Window` to move that single tile into an existing board window. Existing targets are labeled from their current content so multiple windows can be distinguished.

The move is not a clone. The source board loses that tile, the target board gains that tile, and an emptied detached source window closes automatically.

### Use Spotlight In A Detached Window

Opening spotlight from a detached board window presents spotlight in that detached window. Temporary terminals, file previews, browser previews, VibeCast, and ACP panes stay local to the board window that opened them.

## Keyboard Shortcuts

Board spatial navigation uses the terminal-board navigation shortcuts configured by the app. Arrow navigation moves focus between tiles when a tile owns keyboard focus.

Terminal and shortcut commands keep their normal terminal behavior. Board-originated persistent terminal creation always targets the initiating board window.

## Settings / Configuration

Detached board windows have no separate settings shell. App settings and vibespace settings always open from the primary vibespace window.

Window geometry and display placement are persisted per vibespace on a best-effort basis. If the monitor layout changes, detached board windows remain detached and can be repositioned manually.

## Troubleshooting

If a board window target menu shows unexpected labels, move or focus tiles in those windows. Labels are derived from the active or first tile on each surface plus pane count when multiple panes are present.

If a detached board window is empty after moving tiles, it should close automatically. If it remains visible, close it manually; the vibespace layout will normalize on the next persistence cycle.

If a detached window reopens off your preferred display after changing monitors, drag it back to the desired screen. The new placement is saved when the window moves or resizes.

## Known Limitations

Detached windows are board-only surfaces. Detailed editor layout, vibespace settings, and app settings do not detach as separate vibespace windows.

Display restoration is best-effort. The app preserves detached board windows but does not merge detached panes into the primary board solely because a previous monitor is unavailable.
