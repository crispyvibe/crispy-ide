---
title: "Terminal Spotlight"
feature: "F003"
domain: "terminal"
audience: "user"
version: "2.2"
sidebar:
  label: "Spotlight"
  order: 3
---

# Terminal Spotlight

## Overview

Spotlight opens a focused overlay for persistent terminals, files, browser tabs, agent panes, VibeCast, and Vibe Lanes. Its attached Tab Shelf keeps every persistent item available and can combine two items into one carousel position.

## Getting Started

Open Spotlight from a terminal tile, rail card, session preview, or a shortcut that targets Spotlight. Dismiss it with `Esc`, the close button, a backdrop click, or a double-click on the focused terminal.

## Workflows

### Switch and find tabs

- Select any complete member chip on the attached 44 pt shelf.
- Use the side arrows or a two-finger horizontal gesture over non-shelf content to move by one saved position. A combo counts as one position.
- Start a horizontal gesture over the shelf to browse it. Once horizontal intent wins, the gesture stays with the shelf through momentum even after pointer leave or at an edge. Vertical shelf gestures pass through.
- The compact grid-and-number control shows the total persistent-member count. Select it to open All Tabs.
- You can also double-click a shelf member to open All Tabs without first switching to that member; search receives focus.
- All Tabs is a flat three-column grid in the same saved position/member order as the shelf, not a project-grouped list. Its 16:9 cards show safe semantic status only: terminal active/idle and folder name, current file name/parent, or current browser title and redacted location. It never shows screenshots, terminal screen excerpts, commands, or live terminal output.
- Use the pointer, `Left`/`Right`/`Up`/`Down`, and `Return`; press `Esc` to close only the overview.

### Arrange and combine tabs

Drag a tab toward another shelf position:

- Drop in the first quarter to place it **before**.
- Drop in the middle half to create a two-item **combo**.
- Drop in the last quarter to place it **after**.

A combo holds at most two distinct persistent items. Drag the combo handle to reorder both together, or drag one member out to unclub and reposition it. The highlight is only a preview; the layout is saved once when the drop succeeds.

### Work with a combo

Both existing live items remain visible in persisted order. Combos start side by side; use the split-orientation button in the shared header to stack them. Each half is independently clickable. The focused half owns the shared title, actions, and keyboard focus.

Each terminal half keeps its own compose box, draft, pasted images, and Up/Down history. Clicking or sending from a nonfocused terminal half activates it before the command is delivered, so the other terminal cannot receive that pane's draft. This separation applies in both the main window and detached board windows.

### Terminal gestures and compose

- At exactly `1×` or when optically shrunk, a qualifying horizontal gesture over terminal content can switch Spotlight positions. Ordinary vertical scrolling continues to terminal scrollback.
- Above `1×`, two-finger scrolling pans the terminal instead of changing Spotlight.
- Type a command in the compose box and press `Command` + `Return` to send it to the focused terminal.

### Content navigation

For Markdown, use **Back**, **Forward**, `⌘[`, or `⌘]`. For browsers, use their Back/Forward controls or mouse navigation buttons. Content history does not close Spotlight; use `Esc`, close, or the backdrop to return to the previous Spotlight item or the view where Spotlight opened.

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `Esc` | Close All Tabs first; otherwise dismiss or restore Spotlight |
| `Up` / `Down` | Move through filtered All Tabs results |
| `Return` | Open the selected All Tabs member |
| `Command` + `Return` | Send the focused terminal compose draft |
| `⌘[` / `⌘]` | Navigate Markdown content history |

## Settings / Configuration

No setting is required. Shelf order, combos, and orientation are saved separately for the main VibeSpace and each detached board surface.

## Troubleshooting

- Temporary terminal, file-preview, and browser-preview Spotlights do not appear in the persistent shelf and cannot be clubbed. Closing one, clicking the backdrop, pressing `Esc`, double-clicking its terminal, or letting its temporary process exit returns to the nearest still-valid prior item. Terminal, ACP, and file restore entries are validated, and malformed browser-preview URLs are rejected in both main and detached windows.
- If a member closes, a surviving combo partner becomes a normal single tab. If both close, Spotlight selects the nearest available position or dismisses when none remain.
- A drag from another window or an older shelf generation is intentionally ignored.
- Main and detached board windows keep independent saved order, combo orientation, and preview state. A file shown in one window's Spotlight is not duplicated in its board tile, and closing Spotlight in one window does not disturb the same file in another window.
- Detached board windows include persistent project and standalone terminals, files, browsers, ACP, VibeCast, and Vibe Lanes. Rearranging Spotlight does not change board rows, columns, resize weights, tile identity, or terminal lifetime.
- If a swipe pans the terminal, return its magnification to `1×` or use the shelf/arrows.

## Known Limitations

Combos contain at most two persistent items. Temporary previews remain single and outside carousel navigation. Above-normal terminal magnification intentionally reserves non-shelf precise scrolling for viewport pan.

## Change History

| Date | Change | Author |
|---|---|---|
| 2026-10-18 | Version 2.2: documented Up/Down history parity in main and detached windows and malformed browser-preview URL rejection on both restore paths. | — |
| 2026-10-18 | Version 2.1: finalized the 44 pt shelf, compact grid-count control, exclusive double-click search, horizontal shelf scrolling, persisted-order safe semantic grid, independently clickable combo halves, separate terminal drafts and activation-before-send, and safe return/cleanup behavior. Later history and restore parity corrections are recorded above. | — |
| 2026-10-16 | Version 2.0: added the attached Tab Shelf, searchable All Tabs overview, sequence-latched shelf scrolling, two-member combos, focused shared actions, and window-specific return behavior. | — |
| 2026-10-09 | Version 1.4: clarified above-normal terminal scroll ownership. | — |
