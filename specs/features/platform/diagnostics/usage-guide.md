---
title: "Diagnostics"
feature: "F032"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "Diagnostics"
  order: 4
---

# Diagnostics

## Overview

Crispy provides Developer Tools for inspecting app operations, terminal sessions, ACP agent observability, and full diagnostics export. This feature helps developers and power users understand app behavior, debug issues, and collect diagnostic data for support.

## Getting Started

1. Press **Cmd+Option+D** to open the Developer Tools window.
2. Browse the tabbed interface: Operations, Summary, Terminal, ACP, Remote, Auth, External.
3. Data auto-refreshes every 2 seconds while the window is open.

## Workflows

### Viewing Operation Metrics

1. Open Developer Tools (Cmd+Option+D).
2. Select the **Operations** tab.
3. View a chronological list of recorded pane worker operations, newest first.
4. Each row shows:
   - Operation name
   - Duration in milliseconds
   - Success/failure icon (green checkmark or red X)
   - Pane kind badge (explorer, sourceControl, editor, terminal)
   - Project context (last path component)
   - Error description in red (if failed)
5. Parent operations show a folder icon; child operations are indented with an arrow indicator.

### Viewing Aggregate Summaries

1. Select the **Summary** tab.
2. View two sections:
   - **By Operation**: Each operation name with count, average duration, max duration, and failure count.
   - **By Project**: Each project context with the same aggregate fields.
3. Aggregates are sorted by total duration (highest first).

### Inspecting Terminal Sessions

1. Select the **Terminal** tab.
2. View an overview section showing:
   - Active session count
   - Ghostty surface count
   - Host count
   - Polling timer count
   - Visible tile count
   - Spotlight status
3. View individual session rows with:
   - Debug ID and source badge
   - Visibility/focus status dots
   - Lifecycle event
   - Startup latency milestones (shell launch, render latency, interactive latency in ms)
4. Per-vibespace session counts are included in the snapshot.

### Monitoring ACP Agent Sessions

1. Select the **ACP** tab.
2. If ACP observability is disabled, a message instructs you to enable it in Settings → Experimental.
3. When enabled, view:
   - Overview counts (sessions, turns, events)
   - Session rows: agent ID, transport kind, connection state, origin, project, mode, model
   - Turn rows: chunk counts for assistant, thought, tool, plan, permission, terminal, file operations
   - Recent events: category, method, agent, project, duration, status
   - Aggregates by agent, project, method, and error class
4. Use probe controls to connect to an installed agent, send prompts, and view responses.

### Exporting Full Diagnostics

1. The diagnostics export bundles comprehensive app state into a single JSON file.
2. The export includes:
   - Export timestamp, bundle ID, app version, build number, macOS version
   - Deep diagnostics flag
   - UserDefaults snapshot
   - Vibespace summary
   - Operation metrics (records and aggregates)
   - ACP observability payload
   - Recent diagnostic events
3. All file paths in the export are sanitized to SHA-256 tokens (12-character prefix) for privacy.
4. On success, a `diagnostics_export_succeeded` event is recorded.
5. On failure, a `diagnostics_export_failed` event is recorded and an alert is shown.

### Exporting Terminal Diagnostics

- Terminal diagnostics can be exported to a JSON file at `~/Library/Logs/CrispyVibes/` with an ISO 8601 timestamp filename.
- A `diagnostics_snapshot_exported` event is recorded on export.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Developer Tools | Cmd+Option+D |

## Settings

| Setting | Location | Description |
|---------|----------|-------------|
| ACP Observability | Settings → Experimental | Enable/disable ACP event recording (baseline or verbose mode) |

## Tips

- The Operations and Summary tabs use a fixed-capacity ring buffer (default 500 entries). Oldest records are overwritten when capacity is reached — no unbounded memory growth.
- The ACP observability store also uses a ring buffer (500 events, 100 turns).
- The auto-refresh timer fires every 2 seconds and is automatically invalidated when Developer Tools is closed.
- Operation metrics support nested ambient traces (up to 32 levels deep). Stale traces older than 5 minutes are auto-pruned.
- The `MeasuredPaneWorker` decorator emits `os_signpost` intervals for every pane worker execution, enabling Instruments profiling.
- All timestamps in exported payloads use ISO 8601 format with fractional seconds.
- The Developer Tools window is also accessible from the Crispy menu → Developer Tools.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Developer Tools won't open | Verify the Cmd+Option+D shortcut hasn't been reassigned in Settings → Shortcuts. Also try Crispy menu → Developer Tools. |
| Operations tab is empty | No pane worker operations have been recorded yet. Perform file explorer, git, or editor operations to generate metrics. |
| ACP tab shows "observability is off" | Enable ACP observability in Settings → Experimental. |
| Diagnostics export fails | Check that you have write permission to the chosen save location. The error alert shows the specific failure reason. |
| Terminal tab shows no sessions | No terminal sessions are currently active. Open a terminal to see diagnostics. |
