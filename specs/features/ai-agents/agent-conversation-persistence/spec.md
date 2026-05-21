# Agent Conversation Persistence — Spec

Status: implemented

## Overview

Agent Conversation Persistence makes AI agent conversations durable across app launches, vibespace switches, and session restarts. This feature is transport-neutral — it attaches to the shared `AgentSessionProtocol` abstraction, persisting conversations regardless of which transport produced them (ACP, Claude Code direct, Codex direct, etc.). Threads, messages, and activities are automatically persisted to an encrypted local database (libSQL) managed by a Rust subprocess (`crispyvibes-persistence-helper`). Users browse conversation history in the existing side panel, resume previous sessions, search across all conversations by keyword or meaning, and export threads for external use. If the persistence layer is unavailable, agent sessions fall back to ephemeral mode transparently.

Every agent interaction is a **thread**. A thread is permanent. An agent session is a transient connection attached to a thread. There is no distinction between "standalone pane" and "project session" — the persistence layer treats all threads uniformly. The compose bar is always visible on any thread. No session ever "expires" from the user's perspective. When the user opens a thread, history loads from the database immediately and the compose bar is ready. If the agent is disconnected, typing silently triggers reconnection using the best available resume strategy.

The schema is extensible by design. A `thread_kind` field, `parent_thread_id` for hierarchical relationships, a `metadata` JSON column, and a `tags` JSON array enable future thread types (workflow steps, sub-conversations, reviews, template instances) without schema migrations.

This feature implements the persistence capability referenced by F011-R14 (Conversation Management) as a dedicated, self-contained feature.

## Dependencies

- F011 (ACP) — provides the agent session lifecycle, transport, and chat UI that this feature persists
- F001 (Terminal Sessions & Tabs) — terminal context referenced in thread metadata
- F006 (Content Viewer) — conversation sidebar hosted in the existing side panel

## Requirements

### F040-R01: Auto-Persistence of Threads, Messages, and Activities

Every conversation thread, user message, assistant message, tool call, file change, and activity event MUST be persisted automatically as it occurs. Persistence writes MUST be async queued with request/response pairs — the UI MUST NOT block on persistence, but the Swift side MUST track ACK/error responses for health monitoring. No explicit save action is required from the user.

The following content types MUST be persisted per turn:

- **User messages** — the full text sent by the user.
- **Assistant messages** — the full response text after streaming completes.
- **Thinking/reasoning content** — persisted as a `system` role message associated with the turn. Rendered in a collapsible section on restore.
- **Tool calls** — persisted as activities with the tool call ID, kind, status, title, and file paths affected.
- **File change content** — tool call activities MUST include file paths extracted from diff content in the activity payload. The payload SHOULD include additions/deletions counts per file. A separate `file_change` activity MUST summarize the total files changed per turn.
- **System messages** — agent capability announcements, context window warnings, and other system-level messages MUST be persisted with `role: "system"`.

### F040-R02: Global Encrypted Database

All conversation data MUST be stored in a single libSQL database at `~/Library/Application Support/CrispyVibes/acp/conversations.db`. The database MUST be encrypted at rest using AES-256 via libSQL's `EncryptionConfig` (spike required to verify local encryption works). The encryption key MUST be a 256-bit key stored in the standard macOS Keychain without Data Protection keychain attributes. The Keychain service name MUST be resolved from Info.plist to isolate `crispyvibes` and `crispyvibes-local` builds. The key MUST be generated on first launch and reused thereafter.

### F040-R03: Startup Initialization

The persistence helper (`crispyvibes-persistence-helper`) MUST be spawned during `AppContainer.makeDefault()` at app launch. The Swift side MUST load or create the database encryption key from the Keychain, send it to the helper via stdin, and wait for a ready acknowledgment. The helper MUST open the database with `EncryptionConfig`, run forward-only idempotent schema migrations, and report readiness. The helper MUST be ready within 500ms of spawn and MUST NOT block app window appearance.

### F040-R04: Conversation Sidebar

Conversation history MUST be displayed in the existing side panel. The default view MUST be scoped to the current vibespace, with threads grouped by project and sorted by date (most recent first) within each group. Each thread entry MUST show the title, agent name, and relative timestamp. Active sessions MUST display a live status indicator. A "Show all conversations" affordance MUST reveal threads from other vibespaces and from projects that have been removed from the current vibespace (orphaned conversations). No thread MUST ever display an "expired" or "session ended" state — the user sees the conversation, not the session infrastructure.

### F040-R05: Unified Thread Model — Always-Ready Compose Bar

Every thread MUST present the compose bar at all times, regardless of whether an agent session is currently connected. When the user opens any thread, the system MUST load the full conversation history from the database immediately and render the compose bar ready for input. There MUST be no "read-only" state for restored conversations and no "Start new turn" button. The user simply types and the system handles connection transparently.

### F040-R06: Seamless Reconnection on User Input

When the user types in a thread whose agent session is disconnected, the system MUST silently initiate reconnection using the best available resume strategy:

- **Session resume** (`resume_strategy: native_resume`, ACP `session/resume`): If the agent advertises `sessionCapabilities.resume`, the system MUST use `session/resume` with the stored provider session ID, `cwd`, and `mcpServers`. This is a lightweight reconnect — the agent restores internal state without replaying history. Preferred over `session/load` because the client already has the conversation history in the local database.
- **Session load** (`resume_strategy: native_resume`, ACP `session/load`): If the agent advertises `loadSession` but not `sessionCapabilities.resume`, the system MUST use `session/load` with the stored provider session ID, `cwd`, and `mcpServers`. The agent replays the full conversation via `session/update` notifications.
- **CLI resume** (`resume_strategy: native_resume`, direct integrations): For Claude Code, the stored session ID is passed via `--resume` on the next CLI invocation. For Codex, the stored thread ID is passed to `thread/start` for continuation.
- **Transcript replay** (`resume_strategy: transcript_replay`): If the agent does not support any native resume, the system MUST start a fresh agent session, load the conversation transcript from the database, and replay it as context. Timeline types MUST be `Codable` to support serialization for replay.
- **None** (`resume_strategy: none`): If the agent is one-shot or does not support any form of resume, the system MUST start a fresh session with no prior context.

The system MUST read the stored session metadata from the database before attempting reconnection. Session identity (transport kind, provider session ID, resume strategy) MUST be derived from `AgentSessionProtocol` properties — not from type-checking session implementations. The user MUST NOT choose between these strategies — the system MUST detect the agent's capabilities and pick the best strategy automatically.

If resume fails (agent rejects the session ID, process crashes, or returns an error), the system MUST NOT silently fall back to a fresh session. Instead, it MUST disconnect, present the failure reason to the user, and offer the choice to start a fresh session or stay disconnected.

A brief connecting indicator MAY be shown during reconnection, but the compose bar MUST remain visible and the user's typed message MUST be sent once the connection is established.

The `connectAndSend` callback MUST handle the case where no session store exists yet for the thread — it MUST create one on the fly using the thread's stored metadata (agent ID, transport kind, model, project path).

### F040-R07: Session Status Model

Agent sessions MUST track the following statuses: `connecting`, `ready`, `running`, `interrupted`, `error`, `disconnected`. These statuses are internal infrastructure — the user mostly just sees the conversation. The sidebar MAY show a subtle live indicator for active sessions but MUST NOT expose raw session status to the user. Session status transitions MUST be managed by the system, not by user action.

### F040-R08: Opaque Resume Cursors and Session Metadata

Each agent session MUST store: an opaque resume cursor as a raw JSON blob, the `transport_kind` (e.g., `acp`, `claude_code_direct`, `codex_direct`), the `resume_strategy` (`native_resume`, `transcript_replay`, `none`), a `capabilities` JSON blob recording what the agent reported, and a `provider_session_id` for agents that expose one. The cursor MUST be stored exactly as returned by the agent after each turn. On session resume, the stored cursor MUST be passed back to the agent without interpretation or normalization.

The resume cursor MUST be updated via `session.upsert` after **every completed turn**, not only on connect/disconnect. This ensures the cursor reflects the latest conversation state if the app crashes or the session is interrupted between turns. The `capabilities` JSON MUST be stored at session start and updated if the agent reports changed capabilities during the session. The `provider_session_id` MUST be stored at session start for agents that expose one.

### F040-R09: Keyword Search (FTS5)

The system MUST support full-text keyword search across all message content using an FTS5 virtual table. Search MUST return matching threads with message snippets and timestamps. Keyword search MUST complete within 50ms for up to 10,000 messages.

### F040-R10: Semantic Search (Runtime-Adaptive Vector Embeddings)

> **Status: Deferred.** Backend fully implemented (schema, Rust handlers, vector search). Swift-side `NLContextualEmbedding` integration not started — no embedding generation, no embeddings sent with messages. Search falls back to FTS5 only (R11).

The system MUST support semantic search using on-device vector embeddings generated by Apple's `NLContextualEmbedding` framework. Embedding dimensions MUST NOT be hardcoded — the system MUST query the runtime for `dimension`, `modelIdentifier`, `revision`, and `hasAvailableAssets`. Each embedding batch MUST store `model_id`, `revision`, `dimension`, and `language` alongside the vectors. The vector column MUST adapt to the actual dimension reported by the runtime. Semantic search MUST complete within 200ms. Search results MUST show thread title, matched message snippet, and timestamp. Clicking a result MUST navigate to that thread at the matched message.

### F040-R11: Embedding Fallback

If `NLContextualEmbedding` is unavailable, assets are not downloaded, or embedding generation fails for a message, the message MUST still be persisted without a vector. Search MUST fall back to FTS5-only for messages without embeddings. No user-facing error is required.

### F040-R12: Thread Title Generation

When the user sends the first message in a new thread, the system MUST auto-generate a thread title. The title generation MUST follow a two-phase approach:

1. **Immediate seed**: Set the title to a truncated prefix of the first message (max 60 characters) as a placeholder so the sidebar shows something immediately.
2. **Async replacement**: After the first assistant response completes, generate a concise summary title (not the full message text) and replace the seed. The summary SHOULD be derived from the first user message content — either by extracting the first sentence/clause, by using a lightweight local heuristic, or by asking the connected agent to summarize. The replacement MUST NOT overwrite a title that the user has already manually renamed.

The title MUST be a concise summary (e.g., "Fix auth token refresh") rather than a truncated prefix (e.g., "Fix the auth token refresh bug in the login ser…").

### F040-R13: Thread Title Rename

Users MUST be able to rename a thread title by double-clicking the title in the sidebar. The rename MUST be persisted immediately.

### F040-R14: Delete Conversation

Users MUST be able to delete a conversation thread via a right-click context menu action. A confirmation dialog MUST be shown before deletion. Deletion MUST remove the thread, all its messages, activities, session records, and associated embeddings from the database.

### F040-R15: Auto-Cleanup by Age

> **Status: Not implemented.** No settings UI, no cleanup logic, no `maintenance.cleanup` calls. The Rust handler stub exists but is never invoked.

The app MUST provide a setting under Settings → Privacy for auto-deleting conversations older than a configurable threshold: Never, 7 days, 30 days, or 90 days. The default MUST be Never. Cleanup MUST run on app startup. Threads older than the threshold (based on last activity timestamp) MUST be permanently deleted.

### F040-R16: Export as Markdown

Users MUST be able to export a conversation thread as a Markdown file via a right-click context menu action. The export MUST include all messages (full history, not capped), tool calls, and file changes in a human-readable format. The user MUST be prompted for a save location via a standard file dialog.

### F040-R17: Export as JSON

Users MUST be able to export a conversation thread as a JSON file via a right-click context menu action. The export MUST include all thread metadata, messages (full history, not capped), activities, and session records in a machine-readable format. The user MUST be prompted for a save location via a standard file dialog.

### F040-R18: Graceful Degradation — Ephemeral Fallback

If the persistence helper fails to start, crashes, or the database is corrupt, agent sessions MUST continue to function in ephemeral mode (identical to current behavior). No blocking error MUST be shown to the user. The sidebar MUST indicate that history is unavailable. Ephemeral mode MUST be entered silently — the user is only aware if they explicitly look for history.

### F040-R19: Persistence Helper Crash Recovery

If the Rust persistence helper process dies during the app session, the Swift side MUST detect the pipe closure and attempt exactly one restart with the cached encryption key. If the restart succeeds, persistence resumes transparently. If the restart fails, the system MUST fall back to ephemeral mode for the remainder of the session.

### F040-R20: Message Ordering

> **Status: Partial.** Messages are ordered by `createdAt` timestamps assigned by the Rust helper on insertion. No explicit client-side sequence numbers are sent. Ordering is correct in practice (Rust assigns timestamps sequentially) but does not meet the "monotonic sequence numbers" requirement.

Messages MUST be stored with monotonic sequence numbers per thread, not solely timestamps. Sequence numbers MUST prevent ordering ambiguity from clock skew or rapid streaming. The timeline MUST render messages in sequence-number order.

### F040-R21: Full History with Capped UI Reads

All messages MUST be retained in the database until the auto-cleanup policy deletes the thread. The timeline view MUST display at most the latest 2,000 messages per thread — this cap is enforced on UI reads only. Full history MUST remain accessible for search (keyword and semantic) and export. When the cap is reached, the UI MUST display a visible banner at the top of the timeline indicating that older messages exist but are not shown (e.g., "Showing latest 2,000 messages. Older messages are available via search and export."). The banner MUST NOT be dismissible — it is informational and persists as long as the thread exceeds the cap. Activities and tool calls MUST also be capped on UI reads (500 activities, matching the message cap ratio).

### F040-R22: Security — Key Delivery and Zeroing

> **Status: Partial.** Key delivery via stdin pipe is correct. Rust helper zeros the key after extraction (`zeroize`). However, Swift-side `cachedKey: Data?` is retained in memory for the store's lifetime (needed for crash recovery restarts) and is never zeroed on shutdown.

The database encryption key MUST be delivered from Swift to the Rust helper via the stdin pipe (private to the parent-child process pair, not visible in `ps`). The Rust helper MUST zero out the key from the init message buffer immediately after extracting it. The init message containing the hex key MUST never be logged, even at debug level.

### F040-R23: Transport-Neutral Persistence

The persistence layer MUST attach to the shared `AgentSessionProtocol` abstraction, not to any specific transport. Thread metadata MUST include `agent_id` and `transport_kind` to distinguish conversations from different agent types. The Swift-side service MUST be `AgentConversationStore`.

### F040-R24: Async Queued Writes with ACK/Error

All writes to the persistence helper MUST use request/response pairs with unique request IDs. The Swift side MUST track ACK/error responses asynchronously. Persistent write failures MUST be detected via error responses and used for health monitoring (triggering ephemeral fallback if the helper is unhealthy). The UI MUST NOT block on write acknowledgments.

### F040-R25: libSQL Encryption Verification

Before committing to libSQL encryption, a spike MUST verify that `EncryptionConfig` works for local-only embedded databases via the `libsql` crate. If encryption does not work locally, the fallback path is `rusqlite` with `bundled-sqlcipher` feature + `sqlite-vec` extension for vectors.

### F040-R26: Extensible Thread Schema

The thread schema MUST support extensibility without requiring schema migrations for new thread types. The `threads` table MUST include:

- `thread_kind` TEXT with a default of `'conversation'` — extensible to future kinds such as `workflow_step`, `sub_conversation`, `review`, `template_instance`.
- `parent_thread_id` TEXT nullable foreign key referencing `threads(id)` — enabling hierarchical thread relationships (e.g., a workflow containing steps, a conversation spawning sub-conversations).
- `metadata` TEXT (JSON) with a default of `'{}'` — an open key-value bag for kind-specific data (e.g., workflow step index, PR reference, template ID) without schema changes.
- `tags` TEXT (JSON array) with a default of `'[]'` — user-defined or system-defined labels for filtering and grouping.

The core persistence layer MUST treat `thread_kind`, `parent_thread_id`, `metadata`, and `tags` as opaque storage — it MUST NOT interpret or validate the contents of `metadata` or `tags` beyond ensuring they are valid JSON. Future features MAY define kind-specific schemas for `metadata` validation.

### F040-R27: Metadata and Tags Integrity

The persistence layer MUST validate that `metadata` is well-formed JSON (object) and `tags` is a well-formed JSON array before storing. Malformed JSON MUST be rejected with an error response. The maximum size of the `metadata` field MUST be capped at 64 KB. The maximum number of entries in the `tags` array MUST be capped at 100. Individual tag strings MUST be capped at 256 characters.

### F040-R28: Tool Call Type Classification

Tool call activities MUST include an `itemType` field that classifies the tool call into one of the following categories: `command_execution`, `file_change`, `file_read`, `mcp_tool_call`, `web_search`, or `unknown`. The `itemType` MUST be derived from the tool call's `kind` field at persistence time. The timeline MUST render type-specific icons for each category (e.g., terminal icon for commands, pen icon for file changes, globe icon for web search). Activities without a recognized `itemType` MUST fall back to a generic tool icon.

### F040-R29: Work Log Collapsing

When rendering the timeline, adjacent tool call activities belonging to the same turn MUST be visually grouped into a collapsible work log section. Within a work log section, consecutive tool lifecycle events for the same tool call (identified by `toolCallId` in the activity payload) MUST be collapsed into a single row showing the final state. The collapsed row MUST show the tool title, a preview of the detail or command, and changed file paths if applicable. The work log section MUST be collapsed by default and expandable by the user. A maximum of 6 work log entries SHOULD be shown initially, with a "Show all" affordance for longer lists.

### F040-R30: VibeSpace-Relative File Paths

File paths displayed in tool call activities, file change summaries, and diff content MUST be shown relative to the project's vibespace root, not as absolute paths. The vibespace root MUST be resolved from the thread's `project_path` metadata. If the vibespace root cannot be determined, the full path MUST be shown as a fallback.

### F040-R31: Assistant Message Segmentation

When an approval request or user input request pauses a turn mid-stream, the assistant text before the pause and the assistant text after the pause MUST be persisted as separate messages with distinct message IDs but the same `turn_id`. This ensures that on restore, the timeline can render the pre-pause and post-pause text as separate blocks with the approval/input request visually between them. Each segment MUST be finalized (`is_streaming: false`) when the pause occurs, and a new segment MUST begin when the turn resumes.

### F040-R32: Codable Timeline Types

`ACPTurnEntry`, `ACPTimelineEntry`, `ACPToolCallState`, `ACPToolCallContent`, and `ACPPlan` MUST conform to `Codable`. This is required for transcript replay (R06) — the system must serialize the conversation timeline to replay it as context when reconnecting with `transcript_replay` strategy. It is also required for the Agent Board (F042) to serialize phase run summaries and artifact displays.

### F040-R33: Diff Spotlight Panel

When a turn produces file changes, the changed files summary MUST include a "View diff" button. Clicking it opens a full-screen sheet (`ACPDiffSpotlightPanel`) with a file sidebar listing all changed files with addition/deletion stats, and a diff content area showing syntax-highlighted unified diffs via `GitDiffPreview`. The panel MUST be dismissible via Escape key. File paths in the sidebar MUST be vibespace-relative.

### F040-R34: Unified Text Generation Service

Thread title generation MUST use `TextGenerationService` — a single service that works with all CLI providers (Kiro, Claude Code, Codex, Gemini, OpenCode). Each CLI has provider-specific print mode arguments and input mode (positional arg vs stdin). The service MUST strip ANSI escape sequences from CLI output and parse both standalone JSON responses and CLI result envelopes (with markdown code fences).

### F040-R35: Sidebar Agent Icons

Thread rows in the conversations sidebar MUST show the agent's branded icon (resolved via `ACPAgentRegistry.agentIconImage`) instead of raw agent ID text. The dock preview panel header MUST also show the agent-specific icon.

### F040-R36: Sidebar Time-Based Grouping

Within each project section, threads MUST be grouped into "Recent" (updated within 7 days) and "Older" time buckets. Bucket labels are shown only when both buckets have items.

### F040-R37: Sidebar VibeSpace Categorization

The conversations sidebar MUST show a "Current VibeSpace" section (default, expanded) and an "Other VibeSpaces" section (collapsed) containing threads from all other vibespaces. This follows the same pattern as the sessions pane.

### F040-R38: Inline Delete Confirmation

Deleting a conversation MUST show an inline confirmation in the thread row itself ("Delete this conversation? Cancel / Delete") instead of a modal alert popup.

### F040-R39: Cascading Delete Cleanup

Deleting a conversation MUST close any open tab for that thread, remove board tiles referencing the thread's ACP store (via `.acpStoreRemoved` notification), dismiss the dock preview if showing that thread, tear down the session store, and then delete from the database.

### F040-R40: Tab Titles Show Conversation Name

ACP pane tab titles MUST show the conversation title (from `persistenceContext.title`) instead of the provider name. Falls back to first user message prefix (40 chars), then agent title. Title updates reactively when the LLM generates it.

### F040-R41: Image Attachments in Compose Bar

Users MUST be able to paste (Cmd+V) or drag-and-drop images into the ACP compose bar. Images are shown as a thumbnail strip above the text input. Provider-specific encoding: Claude uses `source.base64`, Codex uses data URL format. Both file URL paste (Finder copy) and raw image data paste are supported.

### F040-R42: Interaction Mode Toggle

When an agent reports 2+ interaction modes, the compose bar footer MUST show pill-shaped toggle buttons for switching modes (e.g., Build/Plan). Mode changes are sent via provider-specific mechanisms: ACP uses `session/set_mode`, Codex uses `collaborationMode` in `turn/start`.

### F040-R43: Context Window Meter

When the agent reports token usage, a thin progress bar MUST appear above the compose bar showing used/max tokens. Color-coded: green (< 50%), orange (50-80%), red (> 80%).

### F040-R44: AcceptForSession Approval

Permission cards MUST include an "Accept for Session" button that sets `handler.allowAll = true`, auto-approving all subsequent similar requests for the session duration.

## Scenarios

### Scenario F040-S01: First Launch Creates Database Transparently

**Given** the user launches CrispyVibes for the first time (no existing database)
**When** `AppContainer.makeDefault()` initializes `AgentConversationStore`
**Then** a new 256-bit encryption key is generated and stored in the macOS Keychain
**And** the persistence helper is spawned and receives the key via stdin
**And** the helper creates the database file at `~/Library/Application Support/CrispyVibes/acp/conversations.db`
**And** schema migrations run to completion
**And** the helper reports ready within 500ms
**And** the user sees no indication of this process

### Scenario F040-S02: Send Message — Persisted with ACK

**Given** the user has an active agent conversation
**When** the user sends a message
**Then** the message appears in the chat timeline immediately
**And** the message is sent to the persistence helper as an async queued write with a request ID
**And** the helper responds with an ACK confirming the write succeeded
**And** the assistant's streamed response is persisted as it completes
**And** all tool calls and activities during the turn are persisted
**And** the Swift side tracks the ACK for health monitoring

### Scenario F040-S03: Close and Reopen App — Conversation Restored with Compose Bar

**Given** the user has an active conversation with multiple messages
**When** the user quits CrispyVibes and relaunches it
**Then** the conversation sidebar shows the previous thread with its title, agent, and timestamp
**And** clicking the thread loads the full message history including tool calls and file changes
**And** messages appear in the correct sequence-number order
**And** the compose bar is visible and ready for input immediately

### Scenario F040-S04: Switch Tabs — Conversation Preserved

**Given** the user has an active agent conversation in one tab
**When** the user switches to another tab and then switches back
**Then** the conversation is exactly as they left it — scroll position, message history, and streaming state preserved

### Scenario F040-S05: Open Thread with Live Session — Seamless Continue

**Given** the user has a thread whose agent session is still running
**When** the user selects that thread from the sidebar
**Then** the full conversation history loads from the database
**And** the compose bar is visible and ready
**And** the user can send a new message and continue the conversation immediately

### Scenario F040-S06: Type in Disconnected Thread — Silent Native Resume

**Given** the user has a thread whose agent session has ended
**And** the session's `resume_strategy` is `native_resume` (agent supports `session/load`)
**When** the user opens the thread and types a message
**Then** the compose bar accepts the input
**And** the system silently starts a new agent process and resumes using the stored provider session ID and resume cursor
**And** a brief connecting indicator MAY appear
**And** the user's message is sent once the connection is established
**And** the agent picks up where it left off with full internal state

### Scenario F040-S07: Type in Disconnected Thread — Silent Transcript Replay

**Given** the user has a thread whose agent session has ended
**And** the session's `resume_strategy` is `transcript_replay` (agent does not support native resume)
**When** the user opens the thread and types a message
**Then** the compose bar accepts the input
**And** the system silently starts a fresh agent session and replays the conversation transcript as context
**And** a brief connecting indicator MAY appear
**And** the user's message is sent once the connection is established
**And** the agent sees the history but does not have its internal state

### Scenario F040-S08: Keyword Search Finds Message

**Given** the user has multiple conversation threads with various messages
**When** the user types "pagination" in the sidebar search field
**Then** the system performs an FTS5 keyword search across all message content
**And** matching threads are displayed with the thread title, a message snippet containing the keyword, and a timestamp
**And** clicking a result navigates to that thread at the matched message

### Scenario F040-S09: Semantic Search Finds Related Message

**Given** the user has a conversation about fixing an authentication token refresh bug
**When** the user searches for "that thing where we fixed the login flow"
**Then** the system performs a vector similarity search using on-device embeddings
**And** the authentication-related conversation is returned as a result even though the exact words differ
**And** the result shows the thread title, a relevant message snippet, and a timestamp

### Scenario F040-S10: Delete Thread

**Given** the user has a conversation thread in the sidebar
**When** the user right-clicks the thread and selects "Delete conversation"
**Then** a confirmation dialog appears
**When** the user confirms deletion
**Then** the thread, all its messages, activities, session records, and embeddings are permanently removed from the database
**And** the thread disappears from the sidebar

### Scenario F040-S11: Auto-Cleanup Removes Old Threads

**Given** the user has set auto-cleanup to "30 days" in Settings → Privacy
**And** there are threads with last activity older than 30 days
**When** the user launches CrispyVibes
**Then** threads older than 30 days are permanently deleted during startup
**And** the sidebar reflects the updated thread list

### Scenario F040-S12: Export as Markdown — Full History

**Given** the user has a conversation thread with more than 2,000 messages
**When** the user right-clicks the thread and selects "Export as Markdown"
**Then** a standard file save dialog appears
**When** the user chooses a location and confirms
**Then** a Markdown file is saved containing ALL messages (full history, not capped at 2,000), tool calls, and file changes in a human-readable format

### Scenario F040-S13: Export as JSON — Full History

**Given** the user has a conversation thread
**When** the user right-clicks the thread and selects "Export as JSON"
**Then** a standard file save dialog appears
**When** the user chooses a location and confirms
**Then** a JSON file is saved containing all thread metadata, messages (full history), activities, and session records

### Scenario F040-S14: Persistence Helper Crashes — Ephemeral Fallback

**Given** the persistence helper is running and the user has active conversations
**When** the persistence helper process crashes unexpectedly
**Then** the Swift side detects the pipe closure
**And** one restart attempt is made with the cached encryption key
**If** the restart fails
**Then** agent sessions continue in ephemeral mode — new messages are not persisted
**And** the sidebar indicates that history is unavailable
**And** no blocking error dialog is shown to the user

### Scenario F040-S15: Persistence Helper Restarts After Crash

**Given** the persistence helper has crashed during the app session
**When** the Swift side attempts a restart with the cached encryption key
**And** the restart succeeds
**Then** the helper reconnects to the existing database
**And** persistence resumes transparently
**And** new messages are persisted normally

### Scenario F040-S16: Sidebar Shows VibeSpace-Scoped Threads

**Given** the user has conversations across multiple vibespaces
**When** the user views the conversation sidebar
**Then** only threads belonging to the current vibespace are shown by default
**And** threads are grouped by project
**And** within each project, threads are sorted by date (most recent first)

### Scenario F040-S17: Sidebar "Show All" Reveals Orphaned Threads

**Given** the user has conversations from projects that have been removed from the current vibespace
**And** the user has conversations from other vibespaces
**When** the user clicks "Show all conversations" in the sidebar
**Then** all threads across all vibespaces are displayed, including orphaned threads
**And** orphaned threads are visually distinguished from current-vibespace threads

### Scenario F040-S18: Thread Title Auto-Generated

**Given** the user starts a new agent conversation
**When** the user sends the first message "Fix the auth token refresh bug in the login service"
**Then** the thread title is auto-generated as a concise summary (e.g., "Fix auth token refresh")
**And** the title appears in the sidebar immediately

### Scenario F040-S19: Thread Title Renamed by User

**Given** the user has a conversation thread with an auto-generated title
**When** the user double-clicks the thread title in the sidebar
**Then** the title becomes editable inline
**When** the user types a new title and confirms (Enter or click away)
**Then** the new title is persisted immediately
**And** the sidebar reflects the updated title

### Scenario F040-S20: Full History Retained — UI Capped at 2,000

**Given** a conversation thread has more than 2,000 messages
**When** the user opens that thread
**Then** only the latest 2,000 messages are displayed in the timeline
**And** the UI indicates that older messages exist but are not shown
**And** older messages remain in the database and are accessible via search and export

### Scenario F040-S21: Embedding Generation Fails — Message Still Persisted

**Given** `NLContextualEmbedding` is unavailable or returns an error for a message
**When** the user sends a message
**Then** the message is persisted to the database without a vector embedding
**And** the message appears in the chat timeline normally
**And** keyword search (FTS5) can still find the message
**And** semantic search skips the message (no vector to compare)
**And** no error is shown to the user

### Scenario F040-S22: Write Error Detected via ACK — Health Monitoring

**Given** the persistence helper is running but returns an error response for a write
**When** multiple consecutive write errors are detected
**Then** the Swift side transitions to ephemeral mode
**And** the sidebar indicates that history is temporarily unavailable
**And** no blocking error dialog is shown to the user

### Scenario F040-S23: Transport-Neutral Persistence Across Agent Types

**Given** the user has conversations with different agent types (ACP, Claude Code direct, Codex direct)
**When** the user views the conversation sidebar
**Then** all conversations appear regardless of transport type
**And** each thread shows the correct agent name and transport indicator
**And** search works across all conversations regardless of transport

### Scenario F040-S24: Future Thread Kinds — Extensible Schema

**Given** a future feature creates a thread with `thread_kind: 'workflow_step'`, `parent_thread_id` referencing an existing thread, `metadata: '{"workflow_id": "wf-1", "step_index": 2}'`, and `tags: '["automated", "deploy-pipeline"]'`
**When** the persistence layer stores this thread
**Then** the thread is persisted with all extensibility fields intact
**And** the `metadata` JSON and `tags` JSON array are stored verbatim
**And** the thread can be queried by `thread_kind`, `parent_thread_id`, or tag values
**And** no schema migration is required to support this new thread kind

### Scenario F040-S25: Malformed Metadata Rejected

**Given** a caller attempts to create a thread with `metadata: 'not valid json'`
**When** the persistence helper processes the request
**Then** the write is rejected with an error response
**And** no thread is created
**And** the error response includes a descriptive message about invalid JSON

### Scenario F040-S26: Resume Cursor Read Back on Reconnect

**Given** the user has a thread whose agent session has ended
**And** the session stored a resume cursor after the last completed turn
**When** the user opens the thread and types a message
**Then** the system reads the stored session metadata via `session.get`
**And** the stored `resume_cursor_json` and `provider_session_id` are passed to the new agent session
**And** the agent resumes with full internal state from the cursor

### Scenario F040-S27: Resume Cursor Updated After Every Turn

**Given** the user has an active agent conversation
**When** the agent completes a turn and returns a resume cursor
**Then** the system calls `session.upsert` with the updated `resume_cursor_json`
**And** the cursor is stored before the next user message is accepted
**And** if the app crashes before the next turn, the stored cursor reflects the last completed turn

### Scenario F040-S28: Tool Calls Rendered with Type-Specific Icons

**Given** the user has a conversation with tool calls of different types (command execution, file change, web search)
**When** the user views the conversation timeline
**Then** each tool call shows an icon matching its `itemType` (terminal for commands, pen for file changes, globe for web search)
**And** tool calls without a recognized type show a generic tool icon

### Scenario F040-S29: Work Log Collapsed in Timeline

**Given** the user has a conversation where the agent made 8 tool calls in a single turn
**When** the user views the conversation timeline
**Then** the tool calls are grouped into a collapsible work log section
**And** the section shows at most 6 entries initially with a "Show all" affordance
**And** consecutive lifecycle events for the same tool call are collapsed into a single row

### Scenario F040-S30: Thread Title Replaced with Summary

**Given** the user starts a new conversation and sends "Fix the authentication token refresh bug in the login service so users don't get logged out every 15 minutes"
**When** the first assistant response completes
**Then** the thread title is updated from the initial seed to a concise summary like "Fix auth token refresh timeout"
**And** the sidebar reflects the updated title
**And** if the user had already renamed the thread, the summary does NOT overwrite the custom title

## Acceptance Criteria

- All threads, messages, and activities are persisted automatically with no user action required.
- Writes use async queued request/response pairs with IDs; Swift tracks ACK/error for health monitoring.
- Conversations survive app quit and relaunch with full fidelity (message order, tool calls, file changes).
- The compose bar is always visible on every thread — no "read-only" restored conversations, no "Start new turn" button.
- Opening a thread loads history from the database immediately with the compose bar ready for input.
- Typing in a disconnected thread silently triggers reconnection using the best available resume strategy (native resume → transcript replay → none).
- Session statuses (connecting, ready, running, interrupted, error, disconnected) are internal infrastructure — the user sees the conversation, not the session state.
- The conversation sidebar displays vibespace-scoped, project-grouped, date-sorted threads by default.
- "Show all conversations" reveals orphaned and cross-vibespace threads.
- Keyword search returns results within 50ms for up to 10,000 messages.
- Semantic search returns contextually relevant results within 200ms using runtime-adaptive embeddings (dimension not hardcoded).
- Messages persist even when embedding generation fails.
- Thread titles are auto-generated from the first message and user-renamable.
- Delete removes all associated data (thread, messages, activities, sessions, embeddings).
- Auto-cleanup respects the configured age threshold and runs on startup.
- Export produces valid Markdown and JSON files with full history (not capped) via standard file dialogs.
- The database is encrypted at rest with a Keychain-managed AES-256 key via `EncryptionConfig` (spike verified).
- The encryption key is delivered via stdin, zeroed after extraction, and never logged.
- `crispyvibes` and `crispyvibes-local` builds use isolated Keychain entries and database keys.
- The persistence helper is ready within 500ms of spawn and does not block app window appearance.
- Message writes complete within 10ms and never block the UI.
- Helper crash triggers one restart attempt; failure falls back to ephemeral mode silently.
- The 2,000 message cap is enforced on UI reads only; full history remains for search and export.
- Messages are ordered by monotonic sequence numbers, not timestamps.
- Persistence is transport-neutral — works with ACP, Claude Code direct, Codex direct, and any future `AgentSessionProtocol` implementation.
- The Swift-side service is `AgentConversationStore`, registered in `AppContainer`.
- Thread schema includes `vibespace_id`, `project_path`, `agent_id`, `transport_kind`, `thread_kind`, `parent_thread_id`, `metadata`, and `tags`.
- Session schema includes `transport_kind`, `resume_strategy`, `capabilities` JSON, and `provider_session_id`.
- Session status values are: `connecting`, `ready`, `running`, `interrupted`, `error`, `disconnected`.
- Extensibility fields (`thread_kind`, `parent_thread_id`, `metadata`, `tags`) are stored opaquely — the persistence layer does not interpret kind-specific metadata.
- `metadata` is validated as well-formed JSON object, capped at 64 KB. `tags` is validated as a JSON array, capped at 100 entries of 256 characters each.
- Tool call activities include an `itemType` classification and render with type-specific icons.
- Adjacent tool lifecycle events for the same tool call are collapsed into a single row in the work log.
- File paths in tool calls and file change summaries are displayed relative to the vibespace root.
- Assistant message segments are split on approval/input pauses and persisted as separate messages with the same `turn_id`.
- `ACPTurnEntry`, `ACPTimelineEntry`, `ACPToolCallState`, `ACPToolCallContent`, and `ACPPlan` conform to `Codable`.
- Thinking/reasoning content is persisted as `system` role messages and rendered in collapsible sections on restore.
- File change activities include file paths and additions/deletions counts in the payload.
- Resume cursor is updated via `session.upsert` after every completed turn, not only on connect/disconnect.
- On reconnect, stored session metadata (cursor, capabilities, provider session ID) is read from the database and passed to the new session.
- Thread title generation uses a two-phase approach: immediate seed + async summary replacement. Custom titles are never overwritten.
- The 2,000 message cap indicator is a visible banner at the top of the timeline.
- All 30 scenarios have corresponding test coverage.

## Change History

| Date | Author | Change |
|------|--------|--------|
| 2026-04-25 | Crispy Team | Initial draft based on ACP Conversation Persistence vision document |
| 2026-04-25 | Crispy Team | Revised: renamed to Agent Conversation Persistence, transport-neutral design, capability-based resume, runtime-adaptive embeddings, async queued writes with ACK/error, full history with capped reads, libSQL EncryptionConfig spike, schema additions |
| 2026-04-25 | Crispy Team | Unified thread model: compose bar always visible, no read-only state, silent reconnection on user input, session statuses as internal infrastructure. Extensible schema: thread_kind, parent_thread_id, metadata JSON, tags JSON array. Added F040-R05–R07, F040-R26–R27, F040-S24–S25. Renumbered requirements. |
| 2026-04-27 | Crispy Team | Strengthened R01 (diff content, thinking, system messages), R06 (cursor read-back, Codable for replay, connectAndSend for empty threads), R08 (cursor after every turn, capabilities storage), R12 (two-phase title generation with seed + async summary), R21 (visible cap banner, activity cap). Added R28 (tool type classification), R29 (work log collapsing), R30 (vibespace-relative paths), R31 (assistant segmentation on approval pause), R32 (Codable timeline types). Added S26–S30. |
| 2026-04-29 | Crispy Team | Added R33 (diff spotlight panel), R34 (unified text generation service), R35 (sidebar agent icons), R36 (time-based grouping), R37 (vibespace categorization), R38 (inline delete confirmation), R39 (cascading delete cleanup), R40 (tab titles show conversation name), R41 (image attachments), R42 (interaction mode toggle), R43 (context window meter), R44 (AcceptForSession approval). All conversation UI features complete. Removed external comparison docs. |
| 2026-04-30 | Crispy Team | Verification audit: marked R10 (semantic search) as deferred — backend ready, no Swift embedding generation. R15 (auto-cleanup) as not implemented. R20 (message ordering) as partial — uses timestamps not sequence numbers. R22 (key zeroing) as partial — Swift cachedKey not zeroed on shutdown. 40/44 requirements fully implemented. |
