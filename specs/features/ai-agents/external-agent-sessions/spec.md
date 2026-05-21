# External Agent Sessions — Spec

Status: implemented

## Overview

External Agent Sessions discovers and previews agent conversations from Codex CLI, Claude Code, and Kiro CLI that were created outside Crispy. Sessions are read-only and appear in the Conversations side panel under an "External" tab. A Rust helper handles file scanning and JSONL parsing off the main thread.

## Dependencies

- F011 (ACP) — reuses ACP selectable text rendering for transcript entries
- F032 (Diagnostics) — parse failures are recorded via AppDiagnostics

## Requirements

### F047-R01: Provider discovery

The system must discover external agent sessions from Codex CLI (`~/.codex/sessions/`), Claude Code (`~/.claude/projects/`), and Kiro CLI (`~/.kiro/sessions/cli/`) by scanning known local provider paths.

### F047-R02: External tab in Conversations panel

External sessions must appear in a dedicated "External" tab in the existing Conversations side panel, separate from Crispy-owned conversations.

### F047-R03: Provider filter

The External tab must provide filter chips (All, Codex, Claude Code, Kiro) to narrow the session list by provider.

### F047-R04: Transcript body search

The External tab must support live search across session titles, metadata, and transcript bodies without persisting an external index.

### F047-R05: Read-only preview

Clicking an external session must open a read-only preview panel showing the parsed transcript timeline, session metadata, provider, project path, session ID, and timestamps.

### F047-R06: Copy resume command

The preview panel must offer a "Copy Resume Command" action that copies the provider's native resume command to the clipboard (e.g., `codex resume <id>`, `claude --resume <id>`, `kiro-cli chat --resume-id <id>`).

### F047-R07: No mutation of provider files

The system must never write to or modify provider-owned session files.

### F047-R08: Parse error visibility

Sessions with parse failures must display a warning indicator in the list row. Parse diagnostics must be visible in an expandable section and recorded to Developer Tools.

### F047-R09: Off-main-thread scanning

All file scanning and JSONL parsing must execute off the main thread via the Rust helper binary to keep SwiftUI responsive.

### F047-R10: Time-bucketed grouping

Discovered sessions must be grouped by recency (This Week, Last Week, Earlier) and sorted by last activity date within each bucket.

## Scenarios

### Scenario F047-S01: Discover sessions on tab open

**Given** the user opens the External tab in the Conversations side panel  
**When** the tab becomes visible  
**Then** the Rust helper scans all configured provider roots and returns session summaries  
**And** sessions are displayed grouped by recency with provider icons

### Scenario F047-S02: Filter by provider

**Given** the External tab is showing all discovered sessions  
**When** the user taps the "Claude Code" filter chip  
**Then** only Claude Code sessions are displayed  
**And** the scan is re-executed with the provider filter

### Scenario F047-S03: Search transcript bodies

**Given** the External tab is showing sessions  
**When** the user types a search query  
**Then** after a 250ms debounce the Rust helper searches titles, metadata, and transcript bodies  
**And** matching sessions are shown with search snippets and match counts

### Scenario F047-S04: Preview a session

**Given** the user clicks an external session row  
**When** the session is selected  
**Then** the Rust helper loads and parses the full transcript  
**And** a read-only preview panel appears with header metadata and a scrollable transcript timeline

### Scenario F047-S05: Copy resume command

**Given** the preview panel is open for a Codex session with ID `abc123`  
**When** the user clicks "Copy Resume Command"  
**Then** `codex resume abc123` is copied to the system clipboard

### Scenario F047-S06: Handle parse failures gracefully

**Given** a provider session file contains malformed JSONL  
**When** the scan completes  
**Then** the session row shows a warning indicator  
**And** the diagnostics section lists the parse errors with source path and line context  
**And** AppDiagnostics records the failure

### Scenario F047-S07: Context menu actions

**Given** the user right-clicks an external session row  
**When** the context menu appears  
**Then** it offers "Copy Resume Command" and "Copy Source Path" actions

## Acceptance Criteria

- External tab lists sessions from all three providers (Codex, Claude Code, Kiro CLI).
- Provider filter chips correctly narrow the displayed sessions.
- Search returns results with snippets within 250ms debounce.
- Preview panel renders transcript entries with role labels and timestamps.
- Resume command is correctly formatted per provider.
- Provider files are never modified.
- Parse errors are surfaced in UI and Developer Tools without crashing.
- Scanning runs off the main thread; UI remains responsive with thousands of session files.

## Open Questions

None — feature is implemented.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-20 | Initial spec from implemented feature | Kiro |
