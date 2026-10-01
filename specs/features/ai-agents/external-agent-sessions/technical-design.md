# External Agent Sessions — Technical Design

## Overview

External Agent Sessions uses a Rust helper binary (`crispyvibes-external-sessions-helper`) for file discovery and parsing, with a Swift service layer that invokes the helper as a subprocess and decodes JSON responses. The UI is a SwiftUI pane integrated into the existing Conversations sidebar.

## Architecture

```
VibeSpaceSidebarExternalSessionsPane (SwiftUI View)  — "Terminal" tab
        |
        v
ExternalAgentSessionService (Swift, @unchecked Sendable)
        |  (Process invocation on Task.detached)
        v
crispyvibes-external-sessions-helper (Rust binary)
        |
        +-- Codex adapter: ~/.codex/sessions/YYYY/MM/DD/*.jsonl
        +-- Claude adapter: ~/.claude/projects/<encoded-path>/<session-id>.jsonl
        +-- Kiro metadata: absolute kiro-cli chat --list-sessions --all-cwds --format json
        +-- Kiro V2: ${KIRO_HOME:-~/.kiro}/sessions/cli/<session-id>.json + .jsonl
        +-- Kiro classic: ${KIRO_DATA_DIR:-~/Library/Application Support/kiro-cli}/data.sqlite3
        +-- Pi adapter (JSONL): ~/.pi/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl
        +-- OpenCode adapter (SQLite): ~/.local/share/opencode/opencode.db (session/message/part)
```

The Pi and OpenCode providers were added beyond the original Codex/Claude/Kiro set. Pi reuses the existing JSONL discovery/parse path (new `enrich_pi` / `pi_entry` handlers). OpenCode is backed by a SQLite database; the helper crate gained the bundled `rusqlite` dependency to read it. To avoid touching a live database, the OpenCode adapter copies `opencode.db` plus its `-wal`/`-shm` sidecars into a temp directory, opens the copy read-only, queries the `session` table for discovery and `message`+`part` for the transcript, then deletes the snapshot.

### Kiro 2.26 adapter

Kiro discovery first resolves an absolute executable from `PATH`, then GUI-safe locations `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `/bin`. It invokes the executable directly with Rust `Command`; no shell participates. The JSON decoder accepts either an array of `{complete,cwd,sessions}` envelopes or one envelope. A `(source, sessionId)` key deduplicates repeated listing rows while retaining a V2 and classic row with the same ID. Only `v2` and `classic` are supported; unknown sources are omitted with one aggregate diagnostic.

If executable resolution, invocation, or JSON decoding fails, Kiro V2 discovery falls back to metadata/JSONL files under `${KIRO_HOME}/sessions/cli` when `KIRO_HOME` is nonempty, otherwise `~/.kiro/sessions/cli`. CLI-provided V2 session IDs are accepted only when they are one normal path component. Existing transcript candidates are canonicalized beneath the configured root, symlinked or non-regular files are rejected, and V2 metadata/JSONL reads use no-follow semantics. Source-aware loads re-resolve the configured V2 root instead of trusting the source path returned to Swift. Classic summaries use the CLI metadata and point to `${KIRO_DATA_DIR}/data.sqlite3` when `KIRO_DATA_DIR` is nonempty, otherwise the macOS path `~/Library/Application Support/kiro-cli/data.sqlite3`; classic loads likewise re-resolve that configured database path rather than trusting a caller-provided path.

Classic load and search copy `data.sqlite3`, `data.sqlite3-wal`, and `data.sqlite3-shm` into a unique temporary directory. SQLite opens only the copy with `SQLITE_OPEN_READ_ONLY` and `query_only`; an RAII guard removes the snapshot on success or error. Only `conversations_v2(key, conversation_id, value, created_at, updated_at)` is queried. A search creates one snapshot and one read-only connection, builds a candidate-ID set, and scans `conversations_v2` once; it does not run an unindexed lookup per session. JSON failures become per-row diagnostics and processing continues, so one corrupt conversation cannot erase valid matches. The history parser supports Prompt, Response, ToolUse, ToolUseResults, and CancelledToolUses, including text/JSON tool results and original/normalized tool names and arguments.

## Data Flow

Before returning Kiro summaries, the adapter excludes Crispy-owned one-shot thread-title sessions. New title requests begin with `[Crispy internal request: thread-title generation]`; historical requests are recognized by two app-owned prompt preludes. Classic filtering uses SQLite JSON predicates against the stored first user prompt and requires exactly one history turn, returning only matching session IDs. V2 filtering opens only plausible candidates and verifies the stored `Prompt` event. Display titles are never used as the exclusion decision, so legitimate same-title conversations remain visible. The classic predicate runs against the same temporary read-only snapshot discipline as other classic reads.

1. **Tab opens** → `VibeSpaceSidebarExternalSessionsPane.refresh()` calls `service.scan(provider:)`.
2. **Scan** → `ExternalAgentSessionService` spawns the Rust helper with `["scan", "--limit", "500"]` (optionally `--provider <name>`).
3. **Helper returns** → JSON-encoded `ExternalAgentSessionScanResult` with session summaries and diagnostics.
4. **Search** → Helper invoked with `["search", "<query>", "--limit", "100"]`; matches session title (all providers) and transcript body (file-based providers), never the working-directory path. Title-only matches return no snippet; only body/content matches produce a context snippet. OpenCode matches title only (no body grep). Kiro classic body search reuses one SQLite snapshot for all classic candidates.
5. **Load** → Helper invoked with `["load", "--provider", "<name>", "--source-path", "<path>", "--session-id", "<id>", "--session-source", "<source>"]`; the final two arguments are source-aware additions and `--source-path` remains supported for older callers. Swift replaces the helper-returned summary with the selected scan summary so CLI-owned metadata is preserved. Source-aware Kiro loads use the source and ID as the logical handle, re-resolving the configured V2 root or classic database path before reading.
6. **Preview** → `ExternalAgentSessionPreviewPanel` renders the transcript with `ACPSelectableText`.
7. **Open in Terminal** → The pane resolves the session's working directory and the provider's `resumeCommand`, then asks the focused project's terminal to open a new tab at that directory running the command.

## API / Command Contracts

### Rust helper CLI interface

| Command | Arguments | Returns |
|---------|-----------|---------|
| `scan` | `--limit N [--provider codex\|claude\|kiro\|opencode\|pi]` | `ExternalAgentSessionScanResult` |
| `search` | `<query> --limit N [--provider ...]` | `ExternalAgentSessionScanResult` |
| `load` | `--provider <name> [--source-path <path>] [--session-id <id>] [--session-source v2\|classic]` | `ExternalAgentTranscript` |

All three subcommands (`scan`, `search`, `load`) accept the `--provider` flag. Kiro listing items carry optional `sessionSource`; Swift identity includes provider, source, source path, and session ID so shared IDs and the classic shared DB path do not collide. The OpenCode provider reads its SQLite DB via a read-only snapshot copy; `rusqlite` (bundled) was added to the helper crate for this. The Pi provider is handled by the JSONL path (`enrich_pi` / `pi_entry`).

### Swift data types

- `ExternalAgentSessionProvider` — enum: `.codex`, `.claude`, `.kiro`, `.opencode`, `.pi`, each exposing a per-provider `resumeCommand` (e.g., `.opencode` → `opencode --session <id>`, `.pi` → `pi --session <id>`)
- `ExternalAgentSessionSummary` — session metadata (provider, sessionId, title, projectPath, sourcePath, timestamps, messageCount, parseStatus, parseErrors, parentSessionId, searchSnippets, matchCount)
- `ExternalAgentTranscript` — session summary + array of `ExternalAgentTranscriptEntry` + parseErrors
- `ExternalAgentTranscriptEntry` — role, timestamp, text, metadata dictionary
- `ExternalAgentSessionDiagnostic` — provider, sourcePath, parser, line, context, message
- `ExternalAgentSessionScanResult` — sessions array + diagnostics array

## State Management

- `VibeSpaceSidebarExternalSessionsPane` uses `@State` for local UI state (sessions, diagnostics, selectedSession, providerFilter, searchText, loading/searching flags). Sessions are grouped by working directory into collapsible disclosure sections (alphabetical by directory, most-recently-active first within each). The expansion set starts empty, so normal directory groups load collapsed; a nonempty search query computes matching groups as expanded without mutating the user's normal expansion set. Clearing search restores that set. The whole header row toggles expansion outside search. Rows use the same layout as ACP thread rows (brand icon + title + relative time + inline action buttons, including "Open in Terminal") rather than boxed cards.
- `ExternalAgentSessionService` is stateless — each call spawns a fresh subprocess.
- No persistent index or cache; all data is live-scanned per invocation.
- Search uses a 250ms debounce via `Task.sleep` with cancellation.
- Load and search tasks are stored in `@State` properties and cancelled before replacement. `ExternalAgentSessionService` owns each running `Process` through a lock-protected execution object; task cancellation sends termination and waits for process exit, so the subprocess is reaped before the cancelled call returns.

## Dependencies (frameworks, libraries)

- **Rust helper**: Bundled in the app bundle adjacent to the main executable. Resolved via `Bundle.main.executableURL`. Uses `rusqlite` (bundled/statically linked) for the OpenCode SQLite adapter.
- **Foundation**: `Process`, `Pipe`, `JSONDecoder` for subprocess communication.
- **OSLog**: Logging via `Logger(subsystem:category:)`.
- **AppDiagnostics**: Records parse diagnostics to Developer Tools.
- **ACPSelectableText**: Reused from ACP feature for transcript text rendering.

## Platform Considerations

- macOS only. Helper binary is a macOS ARM64/x86_64 universal binary.
- Helper is resolved at runtime; if missing, `ServiceError.helperUnavailable` is thrown and the UI shows an error state.
- Provider paths use home-directory expansion resolved by the Rust helper. Nonempty `KIRO_HOME` and `KIRO_DATA_DIR` override their respective Kiro defaults.
- Unknown Kiro source formats, including an unverified V3, are deliberately skipped rather than guessed.

## Performance Constraints

- Scanning must not block the main thread — all Process work runs on `Task.detached(priority: .userInitiated)`.
- Scan limit defaults to 500 sessions; search limit to 100.
- Preview renders at most 200 transcript entries via `LazyVStack` with `.prefix(200)`.
- Large transcripts are not fully loaded into Swift memory; the helper streams only the requested session.

## Migration / Rollout Notes

- No persistent state to migrate. Feature is additive.
- Helper binary must be included in the app bundle build phase. The helper crate now links `rusqlite` for OpenCode support.
- Read-only preview plus two resume paths: "Copy Resume Command" (clipboard) and "Open in Terminal" (opens a new terminal tab at the session directory running the resume command in the focused project's terminal). No in-app import of external sessions.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-09-30 | Documented Kiro CLI 2.26 metadata discovery, source-aware load, V2 fallback, classic SQLite parsing, single-pass row-isolated search, cancellation-aware helper ownership, content-based exclusion of Crispy title helpers, and collapsed directory loading | Kiro |
