# External Agent Sessions — Spec

Status: implemented

## Overview

External Agent Sessions discovers and previews agent conversations from Codex CLI, Claude Code, Kiro CLI, OpenCode, and Pi that were created outside Crispy. Sessions are read-only and appear in the Conversations side panel under a "Terminal" tab (alongside the "ACP" tab for Crispy-owned threads). A Rust helper handles file scanning and parsing off the main thread — JSONL for file-based providers and a read-only SQLite snapshot for OpenCode. Discovered sessions can be resumed by copying the provider's native command or by opening a new terminal tab that runs it directly.

## Dependencies

- F011 (ACP) — reuses ACP selectable text rendering for transcript entries
- F032 (Diagnostics) — parse failures are recorded via AppDiagnostics

## Requirements

### F047-R01: Provider discovery

The system must discover external agent sessions from Codex CLI (`~/.codex/sessions/`), Claude Code (`~/.claude/projects/`), and Kiro CLI (`~/.kiro/sessions/cli/`) by scanning known local provider paths.

### F047-R02: Terminal tab in Conversations panel

External CLI-agent sessions must appear in a dedicated "Terminal" tab in the existing Conversations side panel, separate from the "ACP" tab that lists Crispy-owned conversations. (The two tabs were previously labeled "Crispy" and "External".)

### F047-R03: Provider filter

The External tab must provide filter chips (All, Codex, Claude Code, Kiro) to narrow the session list by provider.

### F047-R04: Session search

The Terminal tab must support live free-text search without persisting an external index. Search must match the session **title** only for every provider, plus transcript **body/content** for file-based providers (Codex, Claude Code, Kiro, Pi). Search must **not** match the ambient working-directory path, so a query like `vibe` no longer matches every session that merely lives under a `/crispyvibe/` path. OpenCode sessions are matched by title only (no body grep). A title-only match must not echo the title as a snippet; only body/content matches produce a context snippet.

### F047-R05: Read-only preview

Clicking an external session must open a read-only preview panel showing the parsed transcript timeline, session metadata, provider, project path, session ID, and timestamps.

### F047-R06: Copy resume command

The preview panel must offer a "Copy Resume Command" action that copies the provider's native resume command to the clipboard (e.g., `codex resume <id>`, `claude --resume <id>`, `kiro-cli chat --resume-id <id>`, `opencode --session <id>`, `pi --session <id>`).

### F047-R07: No mutation of provider files

The system must never write to or modify provider-owned session files. For OpenCode's live SQLite database, the helper must make a read-only snapshot copy of the database and its `-wal`/`-shm` sidecars into a temp directory, open the copy read-only, and delete the snapshot when done — the original database is never opened for writing.

### F047-R08: Parse error visibility

Sessions with parse failures must display a warning indicator in the list row. Parse diagnostics must be visible in an expandable section and recorded to Developer Tools.

### F047-R09: Off-main-thread scanning

All file scanning and JSONL parsing must execute off the main thread via the Rust helper binary to keep SwiftUI responsive.

### F047-R10: Directory-grouped session list

Discovered sessions in the Terminal tab must be grouped by working **directory** into collapsible disclosure sections, sorted alphabetically by directory. Within each section, sessions are sorted most-recently-active first. Tapping anywhere on a section header row (not only the chevron) must expand or collapse that section.

### F047-R11: OpenCode provider discovery

The system must discover OpenCode sessions from its local SQLite database at `~/.local/share/opencode/opencode.db` (tables `session`, `message`, `part`). The `session` table drives discovery; `message` and `part` drive the transcript. The database and its `-wal`/`-shm` sidecars must be read via a read-only snapshot copy (see F047-R07). The OpenCode resume command is `opencode --session <id>`, and OpenCode sessions display the OpenCode brand icon.

### F047-R12: Pi provider discovery

The system must discover Pi sessions from JSONL files at `~/.pi/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl`. The first line is a session record (`{"type":"session","id","cwd","timestamp"}`) and subsequent message lines are `{"type":"message","message":{role,content:[{text}]}}`. Pi reuses the existing JSONL discovery/parse path. The Pi resume command is `pi --session <id>`.

### F047-R13: Row styling consistent with ACP threads

Terminal-tab session rows must be styled identically to ACP thread rows (brand icon + title + relative time + inline action buttons), not as boxed cards.

### F047-R14: Open in Terminal action

Each session must offer an "Open in Terminal" action (as an inline row action and in the context menu) that opens a new terminal tab at the session's working directory in the focused project's terminal, running the agent's resume command.



### Scenario F047-S01: Discover sessions on tab open

**Given** the user opens the Terminal tab in the Conversations side panel  
**When** the tab becomes visible  
**Then** the Rust helper scans all configured provider roots and returns session summaries  
**And** sessions are displayed grouped by working directory with provider icons

### Scenario F047-S02: Filter by provider

**Given** the Terminal tab is showing all discovered sessions  
**When** the user taps the "Claude Code" filter chip  
**Then** only Claude Code sessions are displayed  
**And** the scan is re-executed with the provider filter

### Scenario F047-S03: Search matches title and body, not path

**Given** the Terminal tab is showing sessions  
**When** the user types a search query  
**Then** after a 250ms debounce the Rust helper matches the session title (all providers) and transcript body (file-based providers)  
**And** the working-directory path is not matched  
**And** body/content matches are shown with a context snippet while title-only matches show no snippet

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
**Then** it offers "Open in Terminal", "Copy Resume Command", and "Copy Source Path" actions

### Scenario F047-S08: Discover an OpenCode session

**Given** the user has OpenCode sessions in `~/.local/share/opencode/opencode.db`  
**When** the Terminal tab scans providers  
**Then** the helper makes a read-only snapshot of the database and its `-wal`/`-shm` sidecars, opens the copy read-only, queries the `session` table, and deletes the snapshot  
**And** the sessions appear with the OpenCode brand icon and a `opencode --session <id>` resume command

### Scenario F047-S09: Discover a Pi session

**Given** the user has Pi session JSONL files under `~/.pi/agent/sessions/<encoded-cwd>/`  
**When** the Terminal tab scans providers  
**Then** the helper parses the session record from the first line and message lines via the JSONL path  
**And** the sessions appear with a `pi --session <id>` resume command

### Scenario F047-S10: Sessions grouped by directory

**Given** the Terminal tab has discovered sessions across several working directories  
**When** the list renders  
**Then** sessions are grouped into collapsible sections by working directory, sorted alphabetically, with most-recently-active sessions first in each section  
**And** tapping anywhere on a section header expands or collapses that section

### Scenario F047-S11: Open in Terminal

**Given** the user selects "Open in Terminal" on a session with working directory `/work/api` and provider Codex with ID `abc123`  
**When** the action runs  
**Then** a new terminal tab opens at `/work/api` in the focused project's terminal running `codex resume abc123`

### Scenario F047-S12: Search does not match ambient path

**Given** many sessions live under paths containing `/crispyvibe/`  
**When** the user searches for `vibe`  
**Then** only sessions whose title (or body, for file-based providers) contains `vibe` are returned  
**And** sessions that merely live under a `/crispyvibe/` path are not matched

## Acceptance Criteria

- Terminal tab lists sessions from all five providers (Codex, Claude Code, Kiro CLI, OpenCode, Pi).
- Provider filter chips correctly narrow the displayed sessions.
- Search matches session title (all providers) and body (file-based providers) but never the working-directory path; title-only matches show no duplicate snippet.
- Sessions are grouped into collapsible directory sections, sorted alphabetically, most-recently-active first.
- Preview panel renders transcript entries with role labels and timestamps.
- Resume command is correctly formatted per provider.
- "Open in Terminal" opens a new terminal tab at the session directory running the resume command.
- Provider files are never modified; OpenCode's SQLite DB is read via a read-only snapshot copy.
- Parse errors are surfaced in UI and Developer Tools without crashing.
- Scanning runs off the main thread; UI remains responsive with thousands of session files.

## Open Questions

None — feature is implemented.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-20 | Initial spec from implemented feature | Kiro |
| 2026-07-07 | Added OpenCode + Pi providers; title-scoped search fix; Terminal/ACP tab relabel with directory grouping; Open in Terminal action | Kiro |
