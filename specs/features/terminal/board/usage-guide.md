---
title: "Terminal Board"
feature: "F002"
domain: "terminal"
audience: "user"
version: "1.7"
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

### Create or preview a terminal

Use **New Terminal** from a board when you want a persistent tile; choose a project or VibeSpace terminal and working directory. Persistent creation and split actions add the tile to the board window where you started.

A detached titlebar can also request a temporary terminal. That opens only in the detached window's Spotlight and does not add a tile. Choose its split/create-new-terminal action to add one separate persistent terminal tile on that detached surface; the temporary terminal itself is not converted into the tile.

### Move Tiles Inside A Board

Drag a tile header to reposition it in the current board window. Drop targets support left, right, above, below, and swap behavior. Resize columns and rows with the dividers between tiles.

### Send A Tile To Another Board Window

Right-click a visible tile header or minimized tab header.

Choose `Send to New Board Window` to move that single tile into a new detached board window.

Choose `Send to Board Window` to move that single tile into an existing board window. Existing targets are labeled from their current content so multiple windows can be distinguished.

The move is not a clone. The source board loses that tile, the target board gains that tile, and an emptied detached source window closes automatically.

### Use Spotlight in a detached window

Spotlight stays in the board window where it opens. Terminals appear first: visible terminal tiles, then minimized terminals. Files, browsers, ACP, VibeCast, and Vibe Lanes tiles appear afterward in a second visible-then-minimized pass. If the board has no Vibe Lanes tile, Vibe Lanes appears as a final built-in item. A saved custom shelf arrangement is restored in its saved order. Spotlight uses the 44 pt shelf, compact grid-count control, three-column semantic overview, and two-member combos. Combo halves are separately clickable, and each terminal half keeps its own compose draft and Up/Down history and activates before sending while the focused half owns the shared header actions.

Terminal links and filesystem targets open browser/file previews in the same detached window. Closing a preview or an active temporary process returns to the nearest still-available local item. While a file is open in Spotlight, the board avoids displaying a second copy of that editor, and closing Spotlight in one window does not disturb the same file in another window.

For remote projects, Spotlight retains the full project identity—including SSH host—through direct opens, temporary terminals, project shortcuts, split/permanent-terminal actions, ACP, links, files, browsers, editor panes, restore, and attachment to a detached window. If two servers expose the same path, nested Spotlight actions stay with the server where they began.

The overview displays only safe status: terminal activity and folder basename, current file name/parent, or current browser title and redacted location. It does not display screenshots, terminal screen excerpts, commands, or live output. Rearranging the shelf preserves rows, columns, resize weights, active/minimized tiles, and running sessions.

## Keyboard Shortcuts

Board spatial navigation uses the terminal-board navigation shortcuts configured by the app. Arrow navigation moves focus between tiles when a tile owns keyboard focus.

Terminal and shortcut commands keep their normal terminal behavior. Board-originated persistent terminal creation always targets the initiating board window.

## Settings / Configuration

Detached board windows have no separate settings shell. App settings and vibespace settings always open from the primary vibespace window.

Window frame coordinates and display identity are persisted per vibespace. Restore reapplies the frame directly on a best-effort basis; it does not currently use display identity to select a screen. If the monitor layout changes, detached board windows remain detached and can be repositioned manually.

## Troubleshooting

If a board window target menu shows unexpected labels, move or focus tiles in those windows. Labels are derived from the active or first tile on each surface plus pane count when multiple panes are present.

If a detached board window is empty after moving tiles, it should close automatically. If it remains visible, close it manually; the vibespace layout will normalize on the next persistence cycle.

If a detached window reopens off your preferred display after changing monitors, drag it back to the desired screen. The new placement is saved when the window moves or resizes.

## Project Park and Remove Cleanup

When you park or remove an active project, Terminal Board automatically clears panes that Crispy can prove belong to it. Cleanup covers visible and minimized tiles and Spotlight items on both the main board and detached board windows. A detached window closes if cleanup leaves it empty.

Parking saves the project's browser snapshot before cleanup. Activating the project later restores pinned browsers to the main board with their original tile identity and saved browsing state; restored terminal sessions are recreated during terminal reconciliation. Removing a project closes its owned board content without saving it for activation.

Remote ownership includes the SSH host, so identical paths on different servers stay isolated across terminal file targets, dock previews, main/detached Spotlight file and browser views, saved Spotlight order, and **Send All From This Project**. Legacy remote file panes are identified before local stale-file cleanup. Crispy keeps an older remote tile when its owner is ambiguous instead of risking deletion or movement from the wrong host; close that legacy tile manually if it is no longer needed. Dragging remote tiles within or between board windows works as before.

If an owned file pane has unsaved text, cleanup closes its tabs and collects both current and previously displaced/outstanding flushes for that exact project before shutting down the session. All matching tasks race a true 30-second timeout; the first result cancels the other monitor and project shutdown runs exactly once. A failed write retains the dirty buffer rather than silently discarding it. An unpinned owned file preview is included. Switching to another VibeSpace eagerly clears the outgoing docked file groups after starting their close flushes.

## Known Limitations

Detached windows are board-only surfaces. Detailed editor layout, vibespace settings, and app settings do not detach as separate vibespace windows.

Display restoration is best-effort. The app preserves detached board windows but does not merge detached panes into the primary board solely because a previous monitor is unavailable.

## Documentation Verification

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed. Static route tests directly cover every detached direct persistent source kind retaining `owningProjectIdentifier`, exact-once temporary shortcut dispatch, and permanent standalone creation on the originating detached surface. The complete mounted main/detached direct, temporary, split, permanent, ACP, link, file, browser, and editor matrix and additional nested interactions remain production-source inspection.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-23 | Version 1.7 corrects static coverage for detached project-qualified terminal routes and records build/test-build-only validation with no executed test pass. | — |
| 2026-10-23 | Version 1.6 documents exact project identity across every main/detached Spotlight route and detached attachment, with static/build-only evidence limits. | — |
| 2026-10-23 | Version 1.5 documents host-qualified preview/Spotlight/Send-All routing, migration-before-prune, and save-safe file-pane cleanup during project or VibeSpace lifecycle changes. | — |
| 2026-10-20 | Documented automatic board cleanup during project park/remove, empty detached-window closure, ownership-preserving restore, same-root SSH isolation, and fail-closed handling of ambiguous legacy panes. | — |
| 2026-10-18 | Version 1.3: documented detached Up/Down history parity and clarified that a temporary Spotlight terminal's split/create action adds a separate persistent tile instead of converting the temporary process. | — |
| 2026-10-18 | Version 1.2: added detached-window Spotlight parity, terminal-first ordering with a built-in Vibe Lanes fallback, separate terminal drafts, temporary versus persistent creation, local previews, safe file display across windows, privacy-safe metadata, restore behavior, and geometry-preserving saved arrangements. Later behavior corrections are recorded above. | — |
| 2026-10-16 | Clarified that Spotlight includes persistent minimized terminals in each board window's order while shelf rearrangement preserves the board's rows, columns, and resize weights. | — |
