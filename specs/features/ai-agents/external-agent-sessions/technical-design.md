# External Agent Sessions — Technical Design

## Overview

External Agent Sessions uses a Rust helper binary (`crispyvibes-external-sessions-helper`) for file discovery and parsing, with a Swift service layer that invokes the helper as a subprocess and decodes JSON responses. The UI is a SwiftUI pane integrated into the existing Conversations sidebar.

## Architecture

```
VibeSpaceSidebarExternalSessionsPane (SwiftUI View)
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
```

## Data Flow

1. **Tab opens** → `VibeSpaceSidebarExternalSessionsPane.refresh()` calls `service.scan(provider:)`.
2. **Scan** → `ExternalAgentSessionService` spawns the Rust helper with `["scan", "--limit", "500"]` (optionally `--provider <name>`).
3. **Helper returns** → JSON-encoded `ExternalAgentSessionScanResult` with session summaries and diagnostics.
4. **Search** → Helper invoked with `["search", "<query>", "--limit", "100"]`; returns matching sessions with snippets.
5. **Load** → Helper invoked with `["load", "--provider", "<name>", "--source-path", "<path>"]`; returns full `ExternalAgentTranscript`.
6. **Preview** → `ExternalAgentSessionPreviewPanel` renders the transcript with `ACPSelectableText`.

## API / Command Contracts

### Rust helper CLI interface

| Command | Arguments | Returns |
|---------|-----------|---------|
| `scan` | `--limit N [--provider codex\|claude\|kiro]` | `ExternalAgentSessionScanResult` |
| `search` | `<query> --limit N [--provider ...]` | `ExternalAgentSessionScanResult` |
| `load` | `--provider <name> --source-path <path>` | `ExternalAgentTranscript` |

### Swift data types

- `ExternalAgentSessionProvider` — enum: `.codex`, `.claude`, `.kiro`
- `ExternalAgentSessionSummary` — session metadata (provider, sessionId, title, projectPath, sourcePath, timestamps, messageCount, parseStatus, parseErrors, parentSessionId, searchSnippets, matchCount)
- `ExternalAgentTranscript` — session summary + array of `ExternalAgentTranscriptEntry` + parseErrors
- `ExternalAgentTranscriptEntry` — role, timestamp, text, metadata dictionary
- `ExternalAgentSessionDiagnostic` — provider, sourcePath, parser, line, context, message
- `ExternalAgentSessionScanResult` — sessions array + diagnostics array

## State Management

- `VibeSpaceSidebarExternalSessionsPane` uses `@State` for local UI state (sessions, diagnostics, selectedSession, providerFilter, searchText, loading/searching flags).
- `ExternalAgentSessionService` is stateless — each call spawns a fresh subprocess.
- No persistent index or cache; all data is live-scanned per invocation.
- Search uses a 250ms debounce via `Task.sleep` with cancellation.
- Load and search tasks are stored in `@State` properties and cancelled before replacement.

## Dependencies (frameworks, libraries)

- **Rust helper**: Bundled in the app bundle adjacent to the main executable. Resolved via `Bundle.main.executableURL`.
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
- Helper binary must be included in the app bundle build phase.
- No import or resume functionality in the current release — read-only only.
