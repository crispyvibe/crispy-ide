---
title: "Terminal Context Summary"
feature: "F041"
domain: "terminal"
audience: "user"
version: "1.1"
sidebar:
  label: "Context Summary"
  order: 8
---

# Terminal Context Summary

## Overview

Terminal Context Summary gives you an at-a-glance view of what's happening in each terminal. When you hover over a terminal tile, a small pill appears with an AI-generated summary of your current activity — like "Building the project after config change" or "Running test suite" — instead of just showing the last command you typed.

The summary is powered by Apple Intelligence running entirely on your device. It keeps track of your terminal activity over time, so the summaries get more contextual as you work — if you go from editing to building to testing, the summary reflects that progression.

You can expand the pill to see a timeline of your recent commands.

## Getting Started

Context Summary works automatically when Apple Intelligence is available (macOS 26 and later with a supported Mac). Hover over any terminal tile to see the summary pill.

- When Apple Intelligence is available, the pill shows an AI-generated headline summarizing your recent terminal activity.
- When Apple Intelligence is unavailable (or the model takes too long), the pill shows your last command — the same behavior as before.

No setup or configuration is required.

## Workflows

### Checking terminal status at a glance

Hover over a terminal tile. The collapsed pill appears at the top of the tile showing a one-line summary. A small phase icon indicates the type of activity (building, testing, debugging, etc.) with a color-coded indicator.

### Viewing recent commands

Tap the pill to expand it. The timeline shows your recent terminal commands in reverse chronological order (newest first). Each command is shown with a chevron-right icon. Tap the pill again to collapse.

### Understanding the phase indicator

The summary includes a phase icon that describes the current type of activity:

| Phase | Icon | Color | Meaning |
|-------|------|-------|---------|
| Idle | ○ | Gray | No recent activity or unrecognized activity |
| Building | 🔨 | Orange | Compiling or building a project |
| Testing | ✓ | Green | Running tests |
| Debugging | 🐜 | Red | Investigating errors or issues |
| Deploying | ↑ | Orange | Deploying code or services |
| Reviewing | 👁 | Blue | Reviewing code or changes |
| Editing | ✏️ | Purple | Modifying files |
| Searching | 🔍 | Blue | Searching files or documentation |

The phase updates automatically as your activity changes. The AI builds on its understanding of your session, so transitions (e.g., editing → building → testing) are reflected naturally.

### Dismissing the overlay

- **Collapsed pill**: Auto-dismisses after 4 seconds, or when you move the mouse away.
- **Expanded view**: Tap the pill to collapse it. The headline is preserved — next time you hover, it reappears without needing to regenerate.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Expand/collapse the summary overlay | Tap the pill |
| Dismiss the expanded view | Tap the pill to collapse |

## Settings / Configuration

Terminal Context Summary has no dedicated settings. It inherits behavior from the existing terminal insight preferences:

- **Auto-dismiss timing** — the collapsed pill disappears after 4 seconds, same as the previous last-command pill.
- **TUI suppression** — the overlay is automatically hidden when a full-screen terminal application (vim, htop, etc.) is running.

## Troubleshooting

### The pill shows a raw command instead of a summary

This happens when:
- Apple Intelligence is not available on your Mac — the pill falls back to showing your last command.
- The AI model took longer than 2 seconds to generate a summary — the pill shows the last command as a fallback.
- Foundation Models assets haven't finished downloading yet — the system needs a moment after first use on macOS 26.

### The pill doesn't appear on hover

- Check if the terminal is running a TUI application (vim, nano, htop). The overlay is suppressed in TUI mode and reappears when you exit.
- Make sure at least one command has been entered in the terminal — the pill only appears when there's a headline to show.

### The summary seems inaccurate

The AI summary is generated from your recent commands using a persistent conversation with the on-device model. It may occasionally mischaracterize what's happening, especially with ambiguous commands. Expand the overlay to see your actual recent commands and verify.

If the summary seems stuck or consistently wrong, closing and reopening the terminal resets the AI session.

### The generating spinner appears frequently

A small spinner appears in the pill while a new summary is being generated. This is normal after each command — generation typically completes in under 2 seconds. If it appears to hang, the 2-second timeout will kick in and show your last command instead.

## Known Limitations

- **Apple Intelligence required** — the AI summary requires Apple Intelligence (macOS 26+ with supported hardware). Without it, the pill shows the raw last command.
- **Terminal commands only** — the summary is based on what you type in the terminal. It does not currently incorporate agent session context, tool calls, or conversation threads. Agent integration is planned as a future enhancement.
- **No history persistence** — the AI session is per-terminal and lives in memory. Closing a terminal resets the session. The summary reflects current/recent activity only.
- **English-only summaries** — the Foundation Models summary is generated in English. Localization of AI-generated content depends on future framework capabilities.
- **Session grows over time** — the persistent chat session accumulates history. Very long terminal sessions may see slightly increased generation latency as the context grows.

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial draft |
| 2026-04-25 | Updated to match implementation: terminal-only input (no agent integration), persistent chat session, availability-gated generation, dismiss preserves headline, simplified timeline to commands only |
