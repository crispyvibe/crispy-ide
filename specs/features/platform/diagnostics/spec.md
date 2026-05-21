# Diagnostics — Spec

Status: draft

## Overview

Diagnostics provides developer tools for inspecting app operations, terminal sessions, ACP observability, metrics collection, and diagnostics export. Includes the Developer Tools view, operations feed, aggregate summaries, terminal diagnostics, ACP observability tab, diagnostics export, MeasuredPaneWorker decorator, and operation metrics store.

## Dependencies

- F001 (Sessions & Tabs) — terminal diagnostics inspect terminal sessions
- F028 (VibeCast) — ACP observability monitors agent sessions

## Requirements

### F032-R01: Developer Tools View

Developer Tools MUST open via Cmd+Option+D with segmented tabs and auto-refresh on a 2-second timer.

### F032-R02: Operations Feed

Operations feed MUST display chronological operation records with name, duration, status, pane kind, and project context.

### F032-R03: Aggregate Summaries

Summary tab MUST show aggregates by operation and by project with count, average, max, and failure count.

### F032-R04: Terminal Diagnostics

Terminal tab MUST show live session snapshots with startup latency, per-vibespace counts, and JSON export.

### F032-R05: ACP Observability

ACP tab MUST show sessions, turns, events, aggregates, and probe controls when observability is enabled.

### F032-R06: Diagnostics Export

Full export MUST bundle app state, metrics, events into JSON with path sanitization and success/failure events.

### F032-R07: MeasuredPaneWorker

MeasuredPaneWorker MUST record os_signpost and operation metrics for every pane worker execution.

### F032-R08: Operation Metrics Store

Store MUST use fixed-capacity ring buffer with nested ambient traces and codable export.

## Scenarios

### Scenario F032-S01: Developer Tools window opens via Cmd+Option+D

**Given** the app is running
**When** the user presses Cmd+Option+D
**Then** the Developer Tools sheet is presented
**And** it contains four segmented tabs: Operations, Summary, Terminal, and ACP

### Scenario F032-S02: Developer Tools auto-refreshes on a 2-second timer

**Given** the Developer Tools view is visible
**When** the view appears
**Then** a repeating 2-second timer refreshes operation records, aggregates, terminal payload, and ACP payload
**And** the timer is invalidated when the view disappears

### Scenario F032-S03: Operations feed displays a chronological list of recorded operations

**Given** the Developer Tools Operations tab is selected
**When** operation records exist in the metrics store
**Then** root operations are listed newest-first
**And** child operations are grouped under their parent with an indented arrow indicator

### Scenario F032-S04: Each operation row shows name, duration, status, pane kind, and project context

**Given** an operation record is displayed
**Then** the operation name, formatted duration (ms), and a success/failure icon are shown
**And** the pane kind badge and project context (last path component) are displayed when present
**And** error descriptions are shown in red when the operation failed

### Scenario F032-S05: Summary tab shows aggregates by operation and by project

**Given** the Developer Tools Summary tab is selected
**When** aggregated metrics are available
**Then** a "By Operation" section lists each operation name with count, average duration, max duration, and failure count
**And** a "By Project" section lists each project context with the same aggregate fields

### Scenario F032-S06: Terminal tab shows a live snapshot of all terminal sessions

**Given** the Developer Tools Terminal tab is selected
**When** terminal sessions are active
**Then** an overview section shows active session count, Ghostty surface count, host count, polling timer count, visible tile count, and spotlight status
**And** a sessions section lists each session with its debug ID, source badge, visibility/focus status dots, and lifecycle event

### Scenario F032-S07: Terminal session rows include startup latency milestones

**Given** a terminal session has recorded startup milestones
**When** the session row renders
**Then** shell launch duration, render latency, and interactive latency are displayed in milliseconds

### Scenario F032-S08: Terminal diagnostics snapshot captures per-vibespace session counts

**Given** multiple terminal sessions exist across vibespaces
**When** a TerminalDiagnosticsSnapshot capture is taken
**Then** the payload includes a perVibeSpaceSessionCounts dictionary keyed by vibespace UUID

### Scenario F032-S09: Terminal diagnostics snapshot can be exported to a JSON file

**Given** terminal sessions are active
**When** exportToFile is called on TerminalDiagnosticsSnapshot
**Then** a pretty-printed JSON file is written to ~/Library/Logs/CrispyVibes/ with an ISO 8601 timestamp filename
**And** a diagnostics_snapshot_exported event is recorded

### Scenario F032-S10: ACP tab shows a disabled status when observability is off

**Given** ACP observability is disabled in experimental settings
**When** the ACP tab renders
**Then** a status message explains that ACP observability is off
**And** instructs the user to enable it in Settings > Experimental

### Scenario F032-S11: ACP tab shows sessions, turns, events, and aggregates when data is available

**Given** ACP observability is enabled and ACP sessions have been active
**When** the ACP tab renders
**Then** overview counts for sessions, turns, and events are shown
**And** session rows display agent ID, transport kind, connection state, origin, project, mode, and model
**And** turn rows display chunk counts for assistant, thought, tool, plan, permission, terminal, and file operations
**And** recent events are listed with category, method, agent, project, duration, and status
**And** aggregate sections show breakdowns by agent, project, method, and error class

### Scenario F032-S12: ACP probe controls allow connecting to an installed agent

**Given** the ACP tab is open
**When** the user selects an agent from the picker and clicks Connect
**Then** the probe connects to the selected agent for the focused project
**And** the user can send prompts and view responses in the probe text area
**And** auto-allow permissions can be toggled

### Scenario F032-S13: ACP observability store uses a ring buffer for events

**Given** the ACPObservabilityStore is initialized with a capacity (default 500)
**When** events are recorded beyond capacity
**Then** the oldest events are overwritten in circular fashion
**And** turn history is capped at turnCapacity (default 100) with oldest turns evicted

### Scenario F032-S14: Full diagnostics export bundles app state, metrics, and events into a JSON file

**Given** the user triggers an interactive diagnostics export
**When** a save panel is presented and the user confirms
**Then** a JSON file is written containing: export timestamp, bundle ID, app version, build number, macOS version, deep diagnostics flag, defaults snapshot, vibespace summary, operation metrics, ACP observability payload, and recent diagnostic events

### Scenario F032-S15: Exported diagnostics sanitize file paths to SHA-256 tokens

**Given** the diagnostics payload contains file system paths
**When** the JSON is serialized
**Then** strings that look like paths (starting with "/" or containing "/Users/") are replaced with "path#" followed by a 12-character SHA-256 prefix

### Scenario F032-S16: Diagnostics export records success or failure events

**Given** a diagnostics export completes
**When** the export succeeds
**Then** a diagnostics_export_succeeded event is recorded with the path token and event count
**When** the export fails
**Then** a diagnostics_export_failed event is recorded with the error description and an alert is shown

### Scenario F032-S17: MeasuredPaneWorker records operation metrics for every pane worker execution

**Given** a PaneWorkerExecuting is wrapped in a MeasuredPaneWorker
**When** execute is called with a method, arguments, and timeout
**Then** an os_signpost begin/end pair is emitted on the operation.metrics log
**And** on success, an operation record is stored with the method name, pane kind, project context, and duration
**And** on failure, the record additionally includes succeeded=false and the error description

### Scenario F032-S18: MeasuredPaneWorker delegates restart to the inner worker

**Given** a MeasuredPaneWorker wraps an inner PaneWorkerExecuting
**When** restart is called
**Then** the call is forwarded to the inner worker without recording metrics

### Scenario F032-S19: OperationMetricsStore uses a fixed-capacity ring buffer

**Given** the store is initialized with a capacity (default 500)
**When** records are added beyond capacity
**Then** the oldest records are overwritten in circular fashion
**And** snapshot returns records in insertion order

### Scenario F032-S20: OperationMetricsStore supports nested ambient traces

**Given** a trace is begun with beginTrace
**When** operations are recorded before endTrace is called
**Then** each operation is tagged with the trace ID and parent ID
**And** endTrace emits a parent operation record spanning the trace duration
**And** traces can nest up to 32 levels deep with stale traces (>5 min) auto-pruned

### Scenario F032-S21: OperationMetricsStore exports a codable payload with records and aggregates

**Given** operation records exist in the store
**When** exportPayload is called
**Then** the payload contains codable records, by-operation aggregates, and by-project aggregates
**And** all timestamps are formatted as ISO 8601 with fractional seconds

## Acceptance Criteria

- Developer Tools opens within 200ms of Cmd+Option+D.
- Auto-refresh timer fires every 2 seconds and invalidates on disappear.
- Diagnostics export sanitizes all file paths.
- Ring buffers enforce capacity limits without memory growth.
- ACP probe connects and displays responses.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/diagnostics/feature.md (DGN-001–021) | — |
