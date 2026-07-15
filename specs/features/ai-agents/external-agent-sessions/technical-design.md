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
        +-- Kiro adapter: ~/.kiro/sessions/cli/<session-id>.json + .jsonl
        +-- Pi adapter (JSONL): ~/.pi/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl
        +-- OpenCode adapter (SQLite): ~/.local/share/opencode/opencode.db (session/message/part)
```

The Pi and OpenCode providers were added beyond the original Codex/Claude/Kiro set. Pi reuses the existing JSONL discovery/parse path (new `enrich_pi` / `pi_entry` handlers). OpenCode is backed by a SQLite database; the helper crate gained the bundled `rusqlite` dependency to read it. To avoid touching a live database, the OpenCode adapter copies `opencode.db` plus its `-wal`/`-shm` sidecars into a temp directory, opens the copy read-only, queries the `session` table for discovery and `message`+`part` for the transcript, then deletes the snapshot.

## Data Flow

1. **Tab opens** → `VibeSpaceSidebarExternalSessionsPane.refresh()` calls `service.scan(provider:)`.
2. **Scan** → `ExternalAgentSessionService` spawns the Rust helper with `["scan", "--limit", "500"]` (optionally `--provider <name>`).
3. **Helper returns** → JSON-encoded `ExternalAgentSessionScanResult` with session summaries and diagnostics.
4. **Search** → Helper invoked with `["search", "<query>", "--limit", "100"]`; matches session title (all providers) and transcript body (file-based providers), never the working-directory path. Title-only matches return no snippet; only body/content matches produce a context snippet. OpenCode matches title only (no body grep).
5. **Load** → Helper invoked with `["load", "--provider", "<name>", "--source-path", "<path>"]`; returns full `ExternalAgentTranscript`. (For OpenCode, `--source-path` identifies the session within the snapshotted DB.)
6. **Preview** → `ExternalAgentSessionPreviewPanel` renders the transcript with `ACPSelectableText`.
7. **Open in Terminal** → The pane resolves the session's working directory and the provider's `resumeCommand`, then asks the focused project's terminal to open a new tab at that directory running the command.

## API / Command Contracts

### Rust helper CLI interface

| Command | Arguments | Returns |
|---------|-----------|---------|
| `scan` | `--limit N [--provider codex\|claude\|kiro\|opencode\|pi]` | `ExternalAgentSessionScanResult` |
| `search` | `<query> --limit N [--provider ...]` | `ExternalAgentSessionScanResult` |
| `load` | `--provider <name> --source-path <path>` | `ExternalAgentTranscript` |

All three subcommands (`scan`, `search`, `load`) accept the `--provider` flag. The OpenCode provider reads its SQLite DB via a read-only snapshot copy; `rusqlite` (bundled) was added to the helper crate for this. The Pi provider is handled by the JSONL path (`enrich_pi` / `pi_entry`).

### Swift data types

- `ExternalAgentSessionProvider` — enum: `.codex`, `.claude`, `.kiro`, `.opencode`, `.pi`, each exposing a per-provider `resumeCommand` (e.g., `.opencode` → `opencode --session <id>`, `.pi` → `pi --session <id>`)
- `ExternalAgentSessionSummary` — session metadata (provider, sessionId, title, projectPath, sourcePath, timestamps, messageCount, parseStatus, parseErrors, parentSessionId, searchSnippets, matchCount)
- `ExternalAgentTranscript` — session summary + array of `ExternalAgentTranscriptEntry` + parseErrors
- `ExternalAgentTranscriptEntry` — role, timestamp, text, metadata dictionary
- `ExternalAgentSessionDiagnostic` — provider, sourcePath, parser, line, context, message
- `ExternalAgentSessionScanResult` — sessions array + diagnostics array

## State Management

- `VibeSpaceSidebarExternalSessionsPane` uses `@State` for local UI state (sessions, diagnostics, selectedSession, providerFilter, searchText, loading/searching flags). Sessions are grouped by working directory into collapsible disclosure sections (alphabetical by directory, most-recently-active first within each); the set of expanded/collapsed directories is tracked in `@State`, and the whole header row toggles expansion. Rows use the same layout as ACP thread rows (brand icon + title + relative time + inline action buttons, including "Open in Terminal") rather than boxed cards.
- `ExternalAgentSessionService` is stateless — each call spawns a fresh subprocess.
- No persistent index or cache; all data is live-scanned per invocation.
- Search uses a 250ms debounce via `Task.sleep` with cancellation.
- Load and search tasks are stored in `@State` properties and cancelled before replacement.

## Dependencies (frameworks, libraries)

- **Rust helper**: Bundled in the app bundle adjacent to the main executable. Resolved via `Bundle.main.executableURL`. Uses `rusqlite` (bundled/statically linked) for the OpenCode SQLite adapter.
- **Foundation**: `Process`, `Pipe`, `JSONDecoder` for subprocess communication.
- **OSLog**: Logging via `Logger(subsystem:category:)`.
- **AppDiagnostics**: Records parse diagnostics to Developer Tools.
- **ACPSelectableText**: Reused from ACP feature for transcript text rendering.

## Platform Considerations

- macOS only. Helper binary is a macOS ARM64/x86_64 universal binary.
- Helper is resolved at runtime; if missing, `ServiceError.helperUnavailable` is thrown and the UI shows an error state.
- Provider paths use `~` expansion resolved by the Rust helper.

## Performance Constraints

- Scanning must not block the main thread — all Process work runs on `Task.detached(priority: .userInitiated)`.
- Scan limit defaults to 500 sessions; search limit to 100.
- Preview renders at most 200 transcript entries via `LazyVStack` with `.prefix(200)`.
- Large transcripts are not fully loaded into Swift memory; the helper streams only the requested session.

## Migration / Rollout Notes

- No persistent state to migrate. Feature is additive.
- Helper binary must be included in the app bundle build phase. The helper crate now links `rusqlite` for OpenCode support.
- Read-only preview plus two resume paths: "Copy Resume Command" (clipboard) and "Open in Terminal" (opens a new terminal tab at the session directory running the resume command in the focused project's terminal). No in-app import of external sessions.
