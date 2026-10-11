---
title: "Terminal Spotlight"
feature: "F003"
domain: "terminal"
audience: "user"
version: "1.4"
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

- Switch items with the side chevrons or a two-finger horizontal trackpad swipe when the active terminal is at `1×` or optically shrunk below normal.
- Spread two fingers apart to magnify a Spotlight terminal and use two-finger scrolling to pan it only while it is above `1×`. Above normal, scrolling stays with the terminal instead of switching the carousel. Use the tab strip or side chevrons, or return to `1×`/below to restore horizontal carousel swipes. At `1×` or below, non-carousel vertical scrolling continues to terminal scrollback.
- Double-click a terminal to open Spotlight. Double-click the Spotlight terminal again to return to its original layout.
- Use the tab strip above the card to jump directly to a visible item. One arrow, swipe, or tab-chip action selects and focuses that item; a second action is not required, even when switching quickly.
- When the tab strip has more items than fit, use the small left and right strip controls to reveal hidden tabs without changing the active Spotlight item.
- Drag a terminal tab chip across another terminal tab to reorder Spotlight tabs. A vertical marker shows the exact insertion point, and the chips move as you drag over valid targets. In vibespace Spotlight, terminal tabs can be organized across projects and the new order follows the vibespace Spotlight order. In terminal-board Spotlight, the new order follows the active board surface's tile order.
- Type a command in the compose box and press `Command` + `Return` to send it to the active Spotlight terminal.
- For Markdown content, use the visible **Back** and **Forward** buttons or **⌘[**/**⌘]** to move through section jumps and linked files. The Spotlight title, folder, comments, and file actions follow the file currently shown.
- For browser content, use its visible Back/Forward controls or mouse Back/Forward buttons. The page title, address, and comments follow the current page.

## Keyboard Shortcuts

VibeSpace navigation shortcuts shown beside the side chevrons can switch to the previous or next Spotlight carousel item. Markdown **⌘[** and **⌘]** navigate content; they do not switch or close Spotlight.

## Settings / Configuration

No user-facing settings are required for Spotlight tab paging, reordering, or activity animation.

## Troubleshooting

- If a tab is not visible in the strip, use the small strip chevrons; side chevrons switch Spotlight content, while strip chevrons only page the tab strip.
- If a reordered tab returns to its old position, check whether the Spotlight was opened from the vibespace or from a terminal board. Each view preserves its own order.
- Temporary terminal, file preview, and browser preview Spotlights do not participate in carousel navigation.
- If a horizontal swipe pans instead of switching Spotlight items, the terminal is above `1×`. Return it to `1×` or below, or use the tab strip/side chevrons.
- If a below-normal terminal will not pan, this is intentional: optical shrink keeps the fixed grid centered. Horizontal gestures can navigate the carousel; ordinary vertical scrolling continues through terminal scrollback.
- Non-terminal carousel items cannot be reordered from the Spotlight strip.
- **Back** inside Markdown or a browser changes that content only. To return to the terminal or Spotlight item you came from, dismiss the current Spotlight with `Esc`, close, or the backdrop. There is no separate Return button in the current version.

## Known Limitations

Spotlight tab reordering is limited to persistent terminal tabs. VibeSpace Spotlight supports cross-project ordering; terminal-board Spotlight is scoped to the active board surface. Carousel swipe is intentionally suspended only while a terminal is above `1×`, so panning cannot accidentally change the active item. At exactly/below normal, viewport pan is unavailable and horizontal carousel gestures remain active. Returning to a prior terminal origin uses the existing Spotlight dismissal/restore behavior rather than a dedicated Return control.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-09 | Version 1.4: clarified that only above-normal terminal scale reserves scrolling; `1×` and below retain carousel and ordinary scrollback behavior. | — |
| 2026-10-09 | Version 1.3: clarified one-input target/focus convergence and rapid-switch behavior. | — |
| 2026-10-06 | Version 1.2: added compact Markdown/browser navigation controls and clarified that content Back differs from Spotlight close/return behavior. | — |
