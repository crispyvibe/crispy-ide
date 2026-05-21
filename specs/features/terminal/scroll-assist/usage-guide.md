---
title: "Terminal Scroll Assist"
feature: "F046"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Scroll Assist"
  order: 12
---

# Terminal Scroll Assist

## Overview

Every terminal in Crispy has a small floating ball in the bottom-right corner. Hover over it and it expands into a D-pad cross with five buttons — letting you jump back through commands, search scrollback, or open a split/temporary terminal without leaving the current view.

The ball is translucent at rest so it stays out of your way. You can drag it to reposition it anywhere in the terminal.

## Getting Started

1. Open any terminal in Crispy.
2. Look for the small translucent ball (24px circle) in the bottom-right corner of the terminal area.
3. Hover over the ball — it expands with a spring animation into a D-pad cross with five buttons: ⬆ (top), ⬇ (bottom), 🔍 (center), temporary terminal (left), split terminal (right).
4. Move your cursor away and the D-pad collapses back to the ball after 0.8 seconds.
5. Drag the ball to reposition it anywhere in the terminal.

## Workflows

### Jump to the last command you sent

Hover the ball to expand the D-pad, then click ⬆ (top button). The terminal scrolls to the line where you last submitted a command. Click ⬆ again to step back through earlier commands. Click ⬇ (bottom button) to step forward.

The history starts again from the latest command as soon as you type something new in the terminal.

### Search scrollback

1. Hover the ball to expand the D-pad, then click 🔍 (center button). A search bar slides in.
2. Type any text. Matching lines from the scrollback appear in a list below the bar.
3. Click any result to scroll the terminal to that line.
4. Click ✕ or press Escape to close the search. The D-pad stays expanded while search is open.

Search is case-insensitive substring match. The first 200 results are shown.

### Split or temporary terminal

Hover the ball to expand the D-pad. Click the right button to split the terminal, or the left button to open a temporary terminal. These actions were previously in the tile header — they now live exclusively in the D-pad.

### Reposition the ball

Drag the ball (or the expanded D-pad) to move it anywhere within the terminal tile. The position persists for the lifetime of the terminal session.

### Use with tmux sessions

Scroll Assist works the same in tmux-backed terminals. When you click a match, the tmux pane enters copy-mode and scrolls to your match. Press `q` inside the terminal to exit copy-mode and return to live input.

If you reattach to a tmux session that was created in a previous Crispy run, Scroll Assist still works — it reads scrollback directly from tmux, so it sees content from before you reattached.

## Keyboard Shortcuts

The initial release is mouse-driven. Keyboard shortcuts will be added in a future release.

## Settings / Configuration

No configuration. The ball is always present in every terminal. Its position resets to bottom-right when the terminal session is recreated.

## Troubleshooting

### The ⬆ and ⬇ buttons are dim and don't do anything

This means Crispy hasn't recorded any submitted commands yet for this terminal. Type a command and press Enter, then try again.

### Clicking a search result scrolls to the wrong line

Open an issue with the exact text you searched for and the surrounding lines. This is expected to be rare but can happen if a command shows up multiple times verbatim and tmux's `search-forward` finds a different occurrence than the one shown in the result list.

### The ball covers something I want to click

Drag the ball to reposition it anywhere in the terminal tile. It defaults to the bottom-right corner but can be moved out of the way.

## Known Limitations

- Mouse-only for the initial release; keyboard shortcuts coming later.
- After clicking a tmux search result, the pane stays in copy-mode. Press `q` to return to live input.
- Search does not currently support regex or case-sensitive toggles. Substring case-insensitive only.
- Up/Down navigation jumps to the line where the command was typed, not to the start of the command's output.
