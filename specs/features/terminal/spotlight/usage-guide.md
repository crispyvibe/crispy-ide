---
title: "Terminal Spotlight"
feature: "F003"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Spotlight"
  order: 3
---

# Terminal Spotlight

## Overview

Terminal Spotlight opens a focused overlay for a terminal or related vibespace surface. Persistent terminal tabs, docked files, browser tiles, ACP panes, and VibeCast can be reached from the Spotlight carousel.

## Getting Started

Open Spotlight from a terminal tile, rail card, session preview, or a shortcut that targets Spotlight. Dismiss it with `Esc`, the close button, a backdrop click, or a double-click on the card.

## Workflows

- Switch items with the side chevrons or a two-finger horizontal trackpad swipe.
- Use the tab strip above the card to jump directly to a visible item.
- When the tab strip has more items than fit, use the small left and right strip controls to reveal hidden tabs without changing the active Spotlight item.
- Drag a terminal tab chip across another terminal tab to reorder Spotlight tabs. A vertical marker shows the exact insertion point, and the chips move as you drag over valid targets. In vibespace Spotlight, terminal tabs can be organized across projects and the new order follows the vibespace Spotlight order. In terminal-board Spotlight, the new order follows the active board surface's tile order.
- Type a command in the compose box and press `Command` + `Return` to send it to the active Spotlight terminal.

## Keyboard Shortcuts

VibeSpace navigation shortcuts shown beside the side chevrons can switch to the previous or next Spotlight carousel item.

## Settings / Configuration

No user-facing settings are required for Spotlight tab paging, reordering, or activity animation.

## Troubleshooting

- If a tab is not visible in the strip, use the small strip chevrons; side chevrons switch Spotlight content, while strip chevrons only page the tab strip.
- If a reordered tab returns to its old position, check whether the Spotlight was opened from the vibespace or from a terminal board. Each view preserves its own order.
- Temporary terminal, file preview, and browser preview Spotlights do not participate in carousel navigation.
- Non-terminal carousel items cannot be reordered from the Spotlight strip.

## Known Limitations

Spotlight tab reordering is limited to persistent terminal tabs. VibeSpace Spotlight supports cross-project ordering; terminal-board Spotlight is scoped to the active board surface.
