---
title: "Terminal Board Multi-Monitor"
feature: "F048"
domain: "terminal"
audience: "user"
version: "1.2"
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

The detached toolbar's Terminal action lets you choose the working directory and lifetime:

- **Persistent** adds one terminal tile directly to that detached surface.
- **Temporary** opens a terminal only in that window's Spotlight and adds no tile. Choose split/create new persistent terminal to add one separate persistent tile on the same surface; the temporary terminal itself is not converted.

Tile and Spotlight split actions also create persistent terminals on the initiating detached surface.

### Using Spotlight in a detached window

Open Spotlight from a pane or terminal action in the detached board. Each window keeps its own Spotlight state, return path, previews, and saved shelf arrangement, so nothing jumps to the primary window.

The local 44 pt shelf, compact grid-count control, safe three-column overview, two-member combos, orientation, and focused shared actions support project terminals, standalone terminals, files, browsers, ACP, VibeCast, and Vibe Lanes. Terminals appear first—visible terminal tiles followed by minimized terminals—then the other tile types appear in a second visible-then-minimized pass. If no Vibe Lanes tile exists, Vibe Lanes appears as a final built-in item. A saved custom shelf arrangement is restored in its saved order. Each terminal combo half keeps a separate compose draft and Up/Down history and activates before sending.

Terminal links and filesystem targets open local browser/file previews. Closing them—or exit of the active temporary process—returns to the nearest valid local item. Overview cards show semantic status only and never screenshots, terminal screen excerpts, commands, or live output; file and browser locations are redacted.

### Adding content from the detached toolbar

Each detached window has its own controls in this order:

- **Terminal** (temporary or persistent)
- **Agent**
- **Browser**
- **VibeCast**
- **Vibe Lanes**

Persistent items are created in the detached window, subject to its tile cap. VibeCast and Vibe Lanes each remain singletons across that surface's visible and minimized tiles. If one is minimized, its toolbar add action stays unavailable until the existing tile is removed.

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

The shortcut is a no-op when invoked from the primary window. Both bulk move and bulk recall are also silent no-ops while the primary vibespace is in Detailed mode; switch back to Terminal Board mode before using them.

Both bindings are editable in App Settings → Shortcuts → Terminal Board.

## Settings / Configuration

No additional settings are required. Detached board windows are a natural extension of terminal board mode.

Window frame coordinates and display identity are saved per vibespace. On reopen, the saved frame is reapplied directly. The current restore path does not use the saved display identity to select a monitor or explicitly clamp the frame.

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

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-18 | Version 1.2: documented detached Up/Down history parity, minimized-aware VibeCast/Vibe Lanes singleton controls, the Detailed-mode guard for bulk move and recall, and separate persistent-tile creation from temporary Spotlight without process conversion. | — |
| 2026-10-18 | Version 1.1: documented independent detached-window Spotlight behavior, terminal-first ordering with built-in Vibe Lanes fallback, the shelf and grid overview, combos, separate terminal drafts, canonical toolbar order, temporary versus persistent terminal creation, local previews, privacy-safe metadata, and saved arrangements. Later history, singleton, and shortcut-guard corrections are recorded above. | — |
| 2026-05-23 | Added project bulk-move and detached-to-primary bulk-recall workflows. | Kiro |
| 2026-05-20 | Initial guide for detached terminal-board windows. | Kiro |
