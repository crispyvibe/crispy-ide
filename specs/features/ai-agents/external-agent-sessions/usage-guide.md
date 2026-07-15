---
title: "External Agent Sessions"
feature: "F047"
domain: "ai-agents"
audience: "user"
version: "1.1"
sidebar:
  label: "External Sessions"
  order: 4
---

# External Agent Sessions

## Overview

External Agent Sessions lets you discover and preview agent conversations from Codex CLI, Claude Code, Kiro CLI, OpenCode, and Pi directly within Crispy. Sessions created by these tools are automatically found and displayed in a read-only view — no import or configuration required.

## Getting Started

1. Open the Conversations side panel (click the conversations icon in the sidebar or use the keyboard shortcut).
2. Switch to the **Terminal** tab at the top of the panel (the other tab, **ACP**, holds your Crispy-owned conversations).
3. Crispy automatically scans your local provider directories and displays discovered sessions, grouped by their working directory.

No setup is needed. If you have used Codex CLI, Claude Code, Kiro CLI, OpenCode, or Pi on your machine, their sessions will appear automatically.

## Workflows

### Browsing external sessions

The Terminal tab groups discovered sessions by their working directory. Each group is a collapsible section, sorted alphabetically by directory; the most recently active sessions appear first within each section. Tap anywhere on a section header (not just the chevron) to expand or collapse it. Each session row displays:

- Provider brand icon
- Session title (derived from the provider's metadata or first prompt)
- Relative timestamp
- Inline action buttons

Rows use the same compact styling as the ACP thread list.

### Filtering by provider

Use the filter chips at the top of the Terminal tab to narrow results:

- **All** — show sessions from all providers
- **Codex** — show only Codex CLI sessions
- **Claude Code** — show only Claude Code sessions
- **Kiro** — show only Kiro CLI sessions

### Searching sessions

Type in the search field to search sessions. Search matches the session **title** for every provider, plus the transcript **body** for file-based providers (Codex, Claude Code, Kiro, Pi). It does **not** match the working-directory path — so searching for something like `vibe` no longer returns every session that merely lives under a `/crispyvibe/` path. When a match is found in the transcript body, a context snippet is shown; a match on the title alone shows no extra snippet.

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
- OpenCode: `opencode --session <session-id>`
- Pi: `pi --session <session-id>`

You can also right-click a session row and select "Copy Resume Command" from the context menu.

### Opening a session in the terminal

To resume a session without leaving Crispy:

1. Select **Open in Terminal** — either the inline action on a session row or the "Open in Terminal" item in the right-click context menu.
2. Crispy opens a new terminal tab at the session's working directory in the focused project's terminal and runs the provider's resume command for you.

The right-click context menu also offers **Copy Resume Command** and **Copy Source Path**.

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
- OpenCode: `~/.local/share/opencode/opencode.db` (SQLite database, read via a read-only snapshot copy)
- Pi: `~/.pi/agent/sessions/`

## Troubleshooting

### No sessions appear

- Verify that you have used one of the supported CLI agents on this machine.
- Check that the provider directories exist (e.g., `~/.codex/sessions/`) or, for OpenCode, that `~/.local/share/opencode/opencode.db` exists.
- Click the refresh button (↻) in the search bar to re-scan.

### Sessions show a warning icon

This means some events in the session file could not be parsed. The session is still displayed with successfully parsed content. Check the diagnostics section or Developer Tools for details.

### "External session helper is unavailable"

The bundled helper binary could not be found. This may indicate a corrupted app installation. Re-install Crispy to resolve.

## Known Limitations

- Preview displays at most 200 transcript entries for performance.
- No persistent search index — search re-parses files each time.
- Sessions cannot be imported into Crispy as native conversations; you can resume them via "Open in Terminal" or by copying the resume command.
- Sessions are not scoped to the current vibespace — all local sessions are shown.
