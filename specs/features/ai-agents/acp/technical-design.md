# Agent Conversation Protocol (ACP) — Technical Design

## Overview

ACP enables CrispyVibes to host AI agent sessions — discovering agent CLIs, spawning them as child processes, communicating over JSON-RPC stdio, rendering streamed responses in a chat timeline, and managing trust and permissions. The system supports three session types unified behind a single protocol, with transport abstraction, handler chains for file system and terminal operations, and a streaming pipeline that feeds SwiftUI views.

## Architecture

### Session Type Hierarchy

All session types conform to `AgentSessionProtocol`:

```
AgentSessionProtocol (protocol)
├── ACPSession           — standard ACP JSON-RPC sessions
├── ClaudeCodeSession    — direct integration with Claude Code CLI
└── CodexSession         — direct integration with OpenAI Codex CLI
```

`ACPSession` is the general-purpose implementation. It uses `ACPTransport` for JSON-RPC communication and supports the full ACP handshake (initialize → session/new → session/prompt → session/update cycle). Any agent that speaks the ACP protocol works through this path.

`ClaudeCodeSession` and `CodexSession` are direct integrations. They spawn the respective CLI tools and parse their proprietary streaming output formats (JSONL for Claude Code, newline-delimited JSON for Codex) into the same `ACPUpdate` enum that `ACPSession` produces. This lets the chat view model consume all three session types identically.

**Why three types exist:** ACP is the standard protocol, but Claude Code and Codex each have CLI-specific features (trust flags, reasoning levels, model selection via CLI args) that the generic ACP handshake doesn't cover. Direct integrations give better feature coverage for these specific agents while ACP remains the open path for any conforming agent.

### Session Management

`ACPSessionManager` owns all active sessions across three categories:

- **Project sessions** — keyed by project identifier, one per project
- **Background sessions** — single session for non-project work
- **Standalone sessions** — keyed by UUID, one per standalone pane or board tile

Connecting a new session for an existing key disconnects the previous one. `disconnectAll()` tears down everything on vibespace close.

### Transport Abstraction

`ACPTransportProtocol` defines the transport interface:

```
ACPTransportProtocol
├── start(executable:arguments:environment:)
├── send(method:params:) → JSONRPCResponse
├── sendNotification(method:params:)
├── setRequestHandler(_:)     ← for incoming agent requests
├── notifications() → AsyncStream<JSONRPCNotification>
└── stop()
```

`ACPTransport` is an `actor` that spawns a `Process`, writes JSON-RPC to stdin, reads line-delimited JSON from stdout, and captures stderr for diagnostics. Each outbound request gets a `CheckedContinuation` stored by request ID, with a timeout task that fails the continuation if no response arrives.

Direct integration sessions (`ClaudeCodeSession`, `CodexSession`) bypass `ACPTransport` entirely — they manage their own `Process` and `Pipe` instances and parse agent-specific output formats directly.

**Why stdio:** Stdio is the simplest transport that works across all platforms and requires no network configuration. The agent runs as a local child process with no port binding, no TLS, and no discovery overhead. It also provides natural process lifecycle management — when the transport stops, the process terminates.

### Handler Chain

When an agent sends a JSON-RPC request back to the host, the transport routes it through registered handlers:

| Method | Handler | Responsibility |
|--------|---------|----------------|
| `fs/read_text_file` | `ACPFileSystemHandler` | Read file content within project sandbox |
| `fs/write_text_file` | `ACPFileSystemHandler` | Write file content within project sandbox |
| `terminal/create` | `ACPTerminalHandler` | Create a terminal tab with a command |
| `terminal/wait_for_exit` | `ACPTerminalHandler` | Block until terminal process exits |
| `terminal/kill` | `ACPTerminalHandler` | Send interrupt to terminal process |
| `terminal/release` | `ACPTerminalHandler` | Clean up terminal mapping |

Handlers are installed on the session at creation time by `ACPSessionManager.makeSession()`. The `ACPHostContext` struct bundles the project root URL, file content provider, and terminal provider — all injected, never discovered.

Unrecognized methods return a JSON-RPC method-not-found error.

### Discovery

`ACPAgentRegistry` discovers agents from two sources:

1. **CLIToolCatalog** — built-in definitions with `supportsACP` flag and optional `directIntegration` type
2. **Custom agents** — user-defined entries stored in `AppPreferences`

For each agent, the registry resolves the executable via PATH lookup or absolute path validation. Agents whose executable cannot be found are marked `isAvailable = false` and appear disabled in pickers.

## Streaming Pipeline

```
Agent process (stdout)
  → ACPTransport (line-by-line JSON parsing)
    → AsyncStream<JSONRPCNotification> (session/update notifications)
      → ACPSession.prompt() maps to AsyncStream<ACPUpdate>
        → ACPChatViewModel.applyUpdate()
          → @Published timeline: [ACPTimelineEntry]
            → SwiftUI view diffing
```

`ACPUpdate` is the unified enum that all session types produce:

- `.assistantMessage` — streamed text chunks
- `.thought` — reasoning/thinking chunks
- `.toolCall` / `.toolCallUpdate` — tool invocation lifecycle
- `.plan` / `.planUpdate` — multi-step plan entries
- `.permissionRequest` — approval cards
- `.availableCommandsUpdate` — slash command catalog
- `.modeChange` / `.modelChange` — session configuration changes
- `.diff` — file change summaries
- `.turnComplete` — end of turn marker

The chat view model appends or mutates timeline entries as updates arrive. Streaming entries are marked with `completedAt` timestamps when finalized.

## UI Architecture

### Current State

`ACPVibeSpaceConversation.swift` is a 1345-line file containing the vibespace session service, timeline entry model, slash command model, tool call state, chat view model, permission handler, and supporting types. This is a monolith that should be decomposed.

### Target Decomposition

| Component | Responsibility | Source |
|-----------|---------------|--------|
| `ACPChatViewModel` | Timeline state, prompt dispatch, session binding | Extract from conversation file |
| `ACPPermissionHandler` | Permission request queue, allow/deny/allow-always | Extract from conversation file |
| `ACPTimelineEntry` | Timeline entry model and factory methods | Extract to Models/ |
| `ACPMessageRenderer` | Render assistant text, thoughts, markdown | New view component |
| `ACPToolCallCard` | Render tool call groups with status and content | New view component |
| `ACPPermissionCard` | Render permission request with action buttons | New view component |
| `ACPComposeBar` | Text input, slash command suggestions, send/cancel | New view component |
| `ACPSetupStrip` | Agent/project/model/trust pickers, connect button | Already partially in pane view |
| `ACPConversationList` | ScrollView timeline with entry routing | New view component |

### Compose Inline Trigger Integration

`ACPChatView` hosts a `TerminalInlineTriggerController` for ACP compose inputs. The controller is configured from the ACP session's project path and is responsible for:

- parsing the configured typed trigger in the compose buffer
- producing file and directory candidates scoped to the ACP project context
- surfacing saved shortcut rows when that surface has shortcut context
- running the built-in generate action
- replacing only the active trigger token in the compose text

Standalone panes and spotlight use the local inline panel presentation. Board tiles do not render the large picker inside the ACP tile body; instead they publish state into the board's shared `BoardInlinePickerOverlayController`, which renders one centered two-pane popup at the board root and routes confirm/cancel back to the originating ACP compose input.

### Standalone Pane vs Board Tile

Both use `ACPStandaloneSessionStore` as their backing store and `ACPChatViewModel` for conversation state. The standalone pane (`ACPStandalonePaneContentView`) adds a setup strip with pickers. Board tiles render the same chat view within the terminal board grid.

Pane state is persisted via `ACPStandalonePaneSnapshot` (agent ID, model ID, project, trust mode, reasoning level) and restored on vibespace reopen.

## Trust Model

Three trust levels, controlled per-session:

| Mode | Behavior | Use Case |
|------|----------|----------|
| **Standard** | Every tool call requires explicit user approval via permission card | Default for untrusted agents |
| **Full Trust** | All permission requests auto-approved, no cards shown | Trusted agents in controlled environments |
| **Allow-Always** | User approves once with "allow always" option, subsequent requests auto-approved for the session | Progressive trust escalation |

`ACPPermissionHandler` manages the permission queue. In standard mode, each request creates a `CheckedContinuation` that blocks until the user responds. In full trust mode, `allowAll = true` resolves requests immediately with the first allow option. Allow-always sets `allowAll = true` on first escalation.

Trust mode is set at session creation time and cannot be changed mid-session without reconnecting.

## VibeSpace Context

`ACPVibeSpaceContextStore` tracks the focused project and publishes changes. `ACPVibeSpaceSessionService` syncs the focused project to the chat view model, enabling automatic project switching when the user changes focus.

Per-project agent overrides are stored in vibespace state keyed by project path. When an override exists, the vibespace session service uses that agent instead of the global default.

## Persistence Model (Planned)

Currently, conversation history lives only in memory and is lost on disconnect. The planned persistence model:

- Intercept `ACPUpdate` events in the chat view model
- Store timeline entries locally (JSON files per session, keyed by session ID and timestamp)
- Enable offline history browsing and session resume fallback
- SQLite is under consideration for indexed search across sessions; JSON files are the simpler first step

This is not yet implemented. The snapshot system (`ACPStandalonePaneSnapshot`) persists session configuration but not conversation content.

## Observability

`ACPObservabilityStore` records structured `ACPObservedEvent` entries with:

- `category` — event classification (e.g., `session.connect`, `handler.fs_read`, `turn.complete`)
- `duration` — elapsed time for the operation
- `projectToken` — hashed project path for privacy
- `metadata` — additional key-value pairs

Turn summaries aggregate counts for assistant chunks, thought chunks, tool calls, plan updates, permission requests, terminal requests, and file operations.

Observability is gated behind experimental settings and emits no events when disabled.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Stdio transport over HTTP/WebSocket | No port conflicts, natural process lifecycle, no TLS complexity for local communication |
| Direct integrations alongside ACP | Claude Code and Codex have CLI-specific features (trust flags, reasoning, model args) that ACP's generic handshake doesn't expose |
| `AgentSessionProtocol` as unifying abstraction | Chat view model and UI components work identically regardless of session type |
| Actor for transport, `@MainActor` for everything else | Transport does blocking I/O on its own isolation domain; all UI state stays on main actor |
| Permission handler as separate object | Decouples trust logic from session lifecycle; can be observed independently by UI |
| Local persistence as fallback (planned) | Agent may not support session resume; local storage ensures history survives disconnects |

## Known Limitations

- **No multi-agent sessions.** Each session connects to exactly one agent. Multi-agent orchestration is out of scope.
- **No real-time collaboration.** Sessions are single-user. No shared conversation state.
- **Terminal output depends on engine callback.** `ACPTerminalHandler` creates tabs but relies on the terminal engine's exit callback for `wait_for_exit`. If the engine doesn't report, the wait hangs until timeout.
- **No conversation persistence.** History is lost on disconnect. Planned but not implemented.
- **View monolith.** `ACPVibeSpaceConversation.swift` at 1345 lines needs decomposition into focused components.
- **Direct integration maintenance.** Claude Code and Codex sessions must be updated when those CLIs change their output formats.

## Dependencies

| Dependency | Purpose |
|------------|---------|
| F001 (Terminal Sessions) | Terminal handler creates and manages tabs |
| F002 (Terminal Board) | ACP tiles live on the board grid |
| F003 (Terminal Spotlight) | ACP tiles participate in spotlight carousel |
| F006 (Content Viewer) | Standalone pane hosted in detailed content viewer |
| F028 (VibeCast) | Shares vibespace context and terminal provider |
