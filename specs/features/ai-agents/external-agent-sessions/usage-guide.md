---
title: "External Agent Sessions"
feature: "F047"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "External Sessions"
  order: 4
---

# External Agent Sessions

## Overview

External Agent Sessions lets you discover and preview agent conversations from Codex CLI, Claude Code, and Kiro CLI directly within Crispy. Sessions created by these tools are automatically found and displayed in a read-only view — no import or configuration required.

## Getting Started

1. Open the Conversations side panel (click the conversations icon in the sidebar or use the keyboard shortcut).
2. Switch to the **External** tab at the top of the panel.
3. Crispy automatically scans your local provider directories and displays discovered sessions.

No setup is needed. If you have used Codex CLI, Claude Code, or Kiro CLI on your machine, their sessions will appear automatically.

## Workflows

### Browsing external sessions

The External tab shows all discovered sessions grouped by recency (This Week, Last Week, Earlier). Each row displays:

- Provider icon and name
- Session title (derived from the provider's metadata or first prompt)
- Project name
- Relative timestamp
- Short session ID

### Filtering by provider

Use the filter chips at the top of the External tab to narrow results:

- **All** — show sessions from all providers
- **Codex** — show only Codex CLI sessions
- **Claude Code** — show only Claude Code sessions
- **Kiro** — show only Kiro CLI sessions

### Searching sessions

Type in the search field to search across session titles, metadata, and transcript bodies. Results update after a brief pause and show match counts and text snippets.

### Previewing a session

Click any session row to open the preview panel. The preview shows:

- Provider, project path, session ID, and timestamps in the header
- Source file path
- Full transcript timeline with role labels (User, Assistant, System, Tool)

The preview is read-only. You cannot edit or modify the session content.

### Copying the resume command

To continue a session in its original CLI tool:

1. Open the session preview.
2. Click **Copy Resume Command** in the header.
3. Paste the command into your terminal.

The copied command is the provider's native resume syntax:

- Codex: `codex resume <session-id>`
- Claude Code: `claude --resume <session-id>`
- Kiro CLI: `kiro-cli chat --resume-id <session-id>`

You can also right-click a session row and select "Copy Resume Command" from the context menu.

### Viewing parse diagnostics

If some sessions have parse warnings or errors, a diagnostics section appears at the bottom of the session list. Expand it to see details including the source file path and error message. Full diagnostics are also available in Developer Tools.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Dismiss preview panel | Escape |

## Settings / Configuration

No configuration is required. External Agent Sessions automatically scans the default provider paths:

- Codex CLI: `~/.codex/sessions/`
- Claude Code: `~/.claude/projects/`
- Kiro CLI: `~/.kiro/sessions/cli/`

## Troubleshooting

### No sessions appear

- Verify that you have used Codex CLI, Claude Code, or Kiro CLI on this machine.
- Check that the provider directories exist (e.g., `~/.codex/sessions/`).
- Click the refresh button (↻) in the search bar to re-scan.

### Sessions show a warning icon

This means some events in the session file could not be parsed. The session is still displayed with successfully parsed content. Check the diagnostics section or Developer Tools for details.

### "External session helper is unavailable"

The bundled helper binary could not be found. This may indicate a corrupted app installation. Re-install Crispy to resolve.

## Known Limitations

- Preview displays at most 200 transcript entries for performance.
- No persistent search index — search re-parses files each time.
- Import and native resume within Crispy are not yet available.
- Sessions are not scoped to the current vibespace — all local sessions are shown.
