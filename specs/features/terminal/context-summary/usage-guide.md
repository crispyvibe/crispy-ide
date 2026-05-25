---
title: "Terminal Context Summary"
feature: "F041"
domain: "terminal"
audience: "user"
version: "1.2"
sidebar:
  label: "Context Summary"
  order: 8
---

# Terminal Context Summary

## Overview

Terminal Context Summary gives you an at-a-glance view of what's happening in each terminal. When you hover over a terminal tile, a small pill appears with an AI-generated summary of your current activity — like "Building the project after config change" or "Running test suite" — instead of just showing the last command you typed.

The summary is powered by Apple Intelligence running entirely on your device. It keeps track of your terminal activity over time, so the summaries get more contextual as you work — if you go from editing to building to testing, the summary reflects that progression.

The summary follows the terminal across the IDE — when you move a terminal between board view, spotlight, the rail, or a detached window, the headline and the timeline come with it. Switching surfaces never restarts the AI session or drops your earlier commands.

You can expand the pill to see a complete timeline of every command you've submitted in the session, plus the AI summaries that were generated alongside them.

## Getting Started

Context Summary works automatically when Apple Intelligence is available (macOS 26 and later with a supported Mac) and the experimental Terminal Insight setting is enabled. Hover over any terminal tile to see the summary pill.

- When Apple Intelligence is available, the pill shows an AI-generated headline summarizing your recent terminal activity.
- When Apple Intelligence is unavailable (or the model takes too long to respond), the pill shows your last command — the same behavior as before.

No setup or configuration is required beyond toggling the experimental flag.

## Workflows

### Checking terminal status at a glance

Hover over a terminal tile. The collapsed pill appears at the top of the tile showing a one-line summary. A small phase icon indicates the type of activity (building, testing, debugging, etc.) with a color-coded indicator.

### Viewing recent commands

Tap the pill to expand it. The timeline shows every command you've submitted in this terminal session, in reverse chronological order (newest first). Each command is shown with a chevron-right icon and a small copy button. Tap the pill again to collapse.

The timeline does not get truncated at 10 or 15 entries any more — it shows everything you've typed in the current terminal session. Tilting between Summary and Original modes lets you see either the AI's interpretation of each command or the raw text you typed.

### Following a terminal across surfaces

If you spotlight a terminal you were watching from the board view, the spotlight shows the same headline and the same timeline immediately. Hovering anywhere the terminal is rendered — board tile, spotlight, rail, detached window — projects the same summary state. The AI conversation history is preserved across moves, so the next summary still builds on prior context.

### Sensitive prompts (passwords, OTP codes)

When a program asks for a password or another secret with terminal echo disabled (e.g., `sudo`, `git pull` over HTTPS, an SSH key passphrase), the pill shows "sensitive information" with the idle phase. The expanded timeline records the same placeholder. The actual characters you typed are never stored, never sent to the AI model, and never written to compose history. Both Summary and Original modes show the same placeholder for those entries, and copying the entry yields only the placeholder.

### Understanding the phase indicator

The summary includes a phase icon that describes the current type of activity:

| Phase | Icon | Color | Meaning |
|-------|------|-------|---------|
| Idle | ○ | Gray | No recent activity, sensitive input, or unrecognized activity |
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
- **Expanded view, mouse out**: Auto-collapses 0.4 seconds after the mouse leaves the panel; cancelled if you move back in.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Expand/collapse the summary overlay | Tap the pill |
| Dismiss the expanded view | Tap the pill to collapse |

## Settings / Configuration

Terminal Context Summary has no dedicated UI panel. It is gated by an experimental setting and inherits a few behaviors from the existing terminal insight infrastructure:

- **Experimental flag**: `experimental.terminalInsight` (Settings → Experimental → Terminal Insight) gates whether the AI summary session is created at all. When the flag is off, no overlay is shown.
- **Auto-dismiss timing** — the collapsed pill disappears after 4 seconds, same as the previous last-command pill.
- **TUI suppression** — the overlay is automatically hidden when a full-screen terminal application (vim, htop, etc.) is running.

## Troubleshooting

### The pill shows a raw command instead of a summary

This happens when:
- Apple Intelligence is not available on your Mac — the pill falls back to showing your last command.
- The AI model took longer than 20 seconds to generate a summary — the pill shows the last command as a fallback.
- Foundation Models assets haven't finished downloading yet — the system needs a moment after first use on macOS 26.

### The pill doesn't appear on hover

- Check if the terminal is running a TUI application (vim, nano, htop). The overlay is suppressed in TUI mode and reappears when you exit.
- Make sure at least one command has been entered in the terminal — the pill only appears when there's a headline to show.
- Confirm the experimental Terminal Insight setting is enabled.

### The pill shows "sensitive information"

This is intentional. Crispy detected that you submitted input the terminal did not echo — almost always a password prompt or a `read -s` style hidden read. The actual content is not stored, not sent to the AI, and not added to compose history. Once your next visible command runs, the headline updates to reflect that activity.

### The summary seems inaccurate

The AI summary is generated from your recent commands using a persistent conversation with the on-device model. It may occasionally mischaracterize what's happening, especially with ambiguous commands. Expand the overlay to see your actual recent commands and verify.

If the summary seems stuck or consistently wrong, closing and reopening the terminal resets the AI session.

### The generating spinner appears frequently

A small spinner appears in the pill while a new summary is being generated. This is normal after each command. Generation typically completes in well under the 20-second budget; the longer timeout exists to absorb cold-start latency on freshly-available models without dropping the request.

## Known Limitations

- **Apple Intelligence required** — the AI summary requires Apple Intelligence (macOS 26+ with supported hardware). Without it, the pill shows the raw last command.
- **Terminal commands only** — the summary is based on what you type in the terminal. It does not currently incorporate agent session context, tool calls, or conversation threads. Agent integration is planned as a future enhancement.
- **No cross-launch persistence** — the AI session is per-terminal and lives in memory. Closing a terminal resets the session. Restarting Crispy starts fresh.
- **English-only summaries** — the Foundation Models summary is generated in English. Localization of AI-generated content depends on future framework capabilities.
- **Session grows over time** — the persistent chat session accumulates history. Very long terminal sessions may see slightly increased generation latency as the context grows; the LLM prompt window is bounded but the on-device session history is not pruned proactively.

## Change History

| Date | Change |
|------|--------|
| 2026-04-25 | Initial draft |
| 2026-04-25 | Updated to match implementation: terminal-only input (no agent integration), persistent chat session, availability-gated generation, dismiss preserves headline, simplified timeline to commands only |
| 2026-05-24 | Documented cross-surface persistence, the sensitive-information placeholder for echo-disabled prompts, full-session timeline persistence, and the 20-second generation budget. Added experimental-flag note and the matching troubleshooting entry. |
