---
title: "VibeCast"
feature: "F028"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "VibeCast"
  order: 3
---

# VibeCast

## Overview

VibeCast is a broadcast compose-and-send interface for dispatching text to terminal tabs. You can target a specific terminal or broadcast to all terminals simultaneously. It supports message history, target cycling, AI-powered rephrase, and integrates as both a content viewer tab and a terminal board tile.

## Getting Started

1. Press **⌘⇧V** or click the antenna icon in the toolbar to open VibeCast.
2. VibeCast opens as a tab in the content viewer area.
3. Select a target terminal from the target picker (or leave on broadcast mode).
4. Type your message in the compose area and press Enter to send.

## Workflows

### Sending a Message to a Specific Terminal

1. Open VibeCast (⌘⇧V or toolbar antenna button).
2. Click the target picker to open the terminal selection popover.
3. Terminals are listed grouped by project with accent colors.
4. Select your target terminal — the popover dismisses.
5. Type your message and press Enter to send.
6. The message is delivered to the target terminal via raw text input with Enter.

### Broadcasting to All Terminals

1. Open VibeCast and ensure no specific target is selected (broadcast mode).
2. Type your message in the compose area.
3. Trigger the broadcast action.
4. The message is sent to every available terminal tab across all projects.
5. A separate history entry is recorded for each target.

### Cycling Through Targets via Keyboard

1. With the compose area focused, use the cycle-target keyboard shortcuts.
2. The target advances or retreats through the flat list of all terminal tabs.
3. Cycling wraps at boundaries (last → first, first → last).

### Using Rephrase

1. Type text in the compose area.
2. Trigger the rephrase action.
3. The configured text-service CLI processes your text for clarity.
4. On success, the compose text is replaced with the rephrased version.
5. If the CLI is missing or fails, the original text remains unchanged.

### VibeCast as a Board Tile

1. In Terminal Board mode, VibeCast can appear as a dedicated tile.
2. The tile shows the compose area and message history.
3. Double-tap the tile header to open VibeCast in Terminal Spotlight.
4. The tile persists across sessions via codable board layout.

### Viewing Message History

1. Sent messages appear below the compose area in chronological order.
2. Consecutive messages to the same target are grouped under a single header.
3. Each message shows timestamp and target terminal name.
4. History is capped at 500 messages — oldest messages are removed when the cap is reached.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Toggle VibeCast | ⌘⇧V |
| Send message | Enter |
| Cycle target up | Cycle-target-up (configurable) |
| Cycle target down | Cycle-target-down (configurable) |
| Focus project by number | ⌘1–⌘9 (focuses project and cycles its terminals) |

## Settings

- **Text Service CLI Profile** (App Settings → AI): Determines which CLI tool handles rephrase operations.
- **Trust Mode**: Affects rephrase CLI invocation arguments.

## Tips

- Only one VibeCast tab exists per editor group — reopening focuses the existing tab rather than creating a duplicate.
- VibeCast uses a shared `VibeCastStore` instance, so state is consistent across content viewer and board tile presentations.
- When a target terminal is closed, VibeCast automatically falls back to the first available tab.
- If no terminals exist, the target is set to nil and sending is disabled.
- VibeCast participates in the Terminal Spotlight carousel — swipe navigation can land on VibeCast.
- The inline insert trigger (from Terminal Inline Triggers) works in the VibeCast compose input, using the resolved target terminal as context.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| VibeCast won't open | Ensure a vibespace is active. VibeCast requires an active vibespace context. |
| No terminals in target picker | Open at least one terminal session. VibeCast needs terminal tabs to target. |
| Rephrase does nothing | Check that a text-service CLI is configured in App Settings → AI. The CLI tool must be installed and accessible. |
| Messages not appearing in terminal | Verify the target terminal is active and responsive. Messages are sent as raw text with Enter. |
| Duplicate VibeCast tabs | This should not occur — the singleton behavior prevents duplicates. If seen, close extra tabs manually. |
