# Agent Conversation Persistence — Technical Design

## Overview

F040 adds durable conversation persistence to agent sessions. Today, all agent conversations are ephemeral — closing CrispyVibes or switching vibespaces loses all history. This feature stores every message, tool activity, and session state in an encrypted local database so conversations survive app restarts, support full-text and semantic search, and enable session resume.

The persistence layer is transport-neutral — it attaches to the shared `AgentSessionProtocol` abstraction, not to any specific transport. Conversations from ACP, Claude Code direct, Codex direct, and any future agent transport are all persisted through the same `AgentConversationStore` service.

Every agent interaction is a **thread**. A thread is permanent. An agent session is a transient connection attached to a thread. There is no "standalone pane" vs "project session" distinction. The compose bar is always visible on any thread. When the user types in a disconnected thread, the system silently reconnects using the best available resume strategy. No session ever "expires" from the user's perspective.

The schema is extensible by design — `thread_kind`, `parent_thread_id`, `metadata` JSON, and `tags` JSON array enable future thread types (workflow steps, sub-conversations, reviews, template instances) without schema migrations.

The persistence layer runs as a Rust subprocess (`crispyvibes-persistence-helper`) communicating with Swift over JSON-RPC on stdin/stdout — the same pattern used by `crispyvibes-path-search-helper`. The database engine is libSQL (SQLite fork by Turso) with native encryption, FTS5, and vector search. Embedding generation uses Apple's on-device `NLContextualEmbedding` framework on the Swift side.

The design prioritizes:

- **Zero-friction persistence** — no save button, no export warnings. Messages are persisted as they arrive.
- **Always-ready compose bar** — the user opens a thread, sees history, types. The system handles connection state transparently.
- **Graceful degradation** — if the helper crashes or the DB is corrupt, agent sessions run in ephemeral mode. Helper restarts with exponential backoff (3 attempts: 1s, 2s, 4s).
- **Security** — AES-256 encryption at rest, key in macOS Keychain, key delivered via stdin pipe (never on disk, never logged).
- **Search** — FTS5 for keyword search, runtime-adaptive dimensional vectors for semantic search, both under 200ms.
- **Serialized persistence** — all writes go through `SerialTaskQueue` (FIFO async queue). No fire-and-forget `Task {}`. Message ordering guaranteed. Session status updates serialized to prevent races.
- **Protocol-based session identity** — `AgentSessionProtocol` exposes `transportKind`, `providerSessionID`, `resumeStrategy`, `agentID`, and `installPermissionHandler`. No type-checking of session implementations anywhere in the persistence or session management code.
- **Dependency injection** — `AppContainer` owns all ACP object construction via a shared `makeACPStandaloneStore` factory closure. `ACPChatViewModel` is injected into `ACPStandaloneSessionStore`. `AgentConversationStore` accepts an explicit `AgentConversationStoreConfig` for testability.
- **Error propagation** — transport errors include exit code and stderr. `ACPUpdate.error(String)` propagates errors to the timeline. Unexpected disconnects surface via `ProviderStatusBanner` with the actual reason.

Reference: Vision document at `specs/planning/agent-conversation-persistence-vision.md`. Implements F011-R14.

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     Swift (Main App)                     │
│                                                          │
│  AppContainer                                            │
│  ├── makeACPStandaloneStore (factory closure)            │
│  │   ├── creates ACPChatViewModel                        │
│  │   └── creates ACPStandaloneSessionStore               │
│  │       ├── SessionMetadata (value type)                │
│  │       ├── SerialTaskQueue (ordered persistence)       │
│  │       └── onTurnCompleted → persistSessionMetadata    │
│  │                                                       │
│  ├── AgentConversationStore(config:)                     │
│  │   ├── AgentConversationStoreConfig (explicit deps)    │
│  │   ├── KeychainStore (reused)     → loads/creates key  │
│  │   ├── Process + Pipe             → spawns helper      │
│  │   └── NLContextualEmbedding      → generates vectors  │
│  │                                                       │
│  ├── AgentSessionProtocol (transport-neutral)            │
│  │   ├── transportKind, providerSessionID, resumeStrategy│
│  │   ├── agentID, installPermissionHandler               │
│  │   ├── ACPSession (session/resume + session/load)      │
│  │   ├── ClaudeCodeSession (--resume flag)               │
│  │   └── CodexSession (thread/start with threadID)       │
│  │                                                       │
│  ├── ACPSessionManager                                   │
│  │   └── standaloneSessions: [UUID: any AgentSession...] │
│  │       (tracks ALL session types, not just ACP)        │
│  │                                                       │
│  ├── ContentViewerStore                                  │
│  │   └── acpStoreFactory (from AppContainer)             │
│  │                                                       │
│  └── DockedAgentPreviewCoordinator                       │
│      └── acpStoreFactory (from AppContainer)             │
│                                                          │
│              stdin/stdout (JSON-RPC, newline-delimited)   │
│                          │                                │
└──────────────────────────┼────────────────────────────────┘
                           │
┌──────────────────────────┼────────────────────────────────┐
│              Rust (crispyvibes-persistence-helper)               │
│                          │                                 │
│  main.rs ── JSON-RPC server (stdin/stdout, tokio)          │
│  ├── schema.rs ── migrations, DDL                          │
│  ├── handlers.rs ── method dispatch                        │
│  └── models.rs ── thread, message, activity, session types │
│                          │                                 │
│  libSQL (encrypted via EncryptionConfig, WAL mode)         │
│  ├── threads, messages, activities, sessions               │
│  ├── message_fts (FTS5 virtual table)                      │
│  └── message_embeddings (runtime-adaptive vector column)   │
│                          │                                 │
│  ~/Library/Application Support/CrispyVibes/acp/conversations.db  │
└────────────────────────────────────────────────────────────┘
```

### Rust Persistence Helper Binary

New binary `crispyvibes-persistence-helper` in the shared Cargo vibespace alongside `crispyvibes-path-search`:

```
projects/crispyvibes/rust/
├── crispyvibes-path-search/            ← existing, unchanged
│   ├── Cargo.toml
│   └── src/
└── crispyvibes-persistence/            ← new
    ├── Cargo.toml                ← depends on libsql, serde, serde_json, tokio
    └── src/
        ├── main.rs               ← JSON-RPC stdin/stdout server loop
        ├── schema.rs             ← migrations, table DDL
        ├── handlers.rs           ← method routing and execution
        └── models.rs             ← Rust structs for thread, message, activity, session
```

The binary follows the same process lifecycle as `crispyvibes-path-search-helper`:

- Spawned by Swift as a child process via `Process` + `Pipe`.
- Reads newline-delimited JSON requests from stdin.
- Writes newline-delimited JSON responses to stdout.
- Process name set to `"CrispyVibes (persistence helper)"` via `setprogname`.
- Terminates when stdin closes (parent exits).

Unlike the path-search helper (which is stateless and session-based), the persistence helper is stateful — it holds an open libSQL connection for the app's lifetime.

### JSON-RPC Protocol

Same framing as `crispyvibes-path-search-helper`: one JSON object per line on stdin/stdout. Unlike the path-search helper (fire-and-forget notifications), the persistence helper uses **request/response pairs** so the Swift side knows whether a write succeeded or failed.

Request format:
```json
{ "id": "req-1", "method": "message.append", "params": { ... } }
```

Response format:
```json
{ "id": "req-1", "result": { "ok": true } }
```

Error format:
```json
{ "id": "req-1", "error": { "code": -32000, "message": "thread not found" } }
```

Every request includes a unique `id`. Every response echoes the `id` so Swift can correlate ACK/error with the original request. Writes are async queued on the Swift side — the UI never blocks — but the ACK/error response lets Swift detect failures and fall back to ephemeral mode if the helper is unhealthy.

The `init` method is special — it must be the first message sent and carries the encryption key. All other methods fail with an error if called before `init` completes.

### libSQL with EncryptionConfig, FTS5, and Vector Search

**Why libSQL over plain SQLite:**

- Native AES-256 encryption at rest via `EncryptionConfig` — no separate SQLCipher dependency.
- Native vector search (`libsql_vector_idx`) — no sqlite-vec extension to bundle.
- FTS5 inherited from SQLite — full-text search on message content.
- First-class Rust support via the `libsql` crate (Turso is a Rust shop).

**Spike required:** Verify that `EncryptionConfig` works for local-only embedded databases via the `libsql` crate before committing. If encryption doesn't work locally, fall back to `rusqlite` with `bundled-sqlcipher` feature + `sqlite-vec` extension for vectors.

Database configuration:
- WAL journal mode for concurrent reads during writes.
- `PRAGMA foreign_keys = ON` for referential integrity.
- Single file: `~/Library/Application Support/CrispyVibes/acp/conversations.db`.

### Swift `AgentConversationStore`

New `@MainActor` service registered in `AppContainer`:

```swift
@MainActor
final class AgentConversationStore: ObservableObject {
    @Published private(set) var state: PersistenceState = .starting

    enum PersistenceState {
        case starting
        case ready(schemaVersion: Int)
        case ephemeral(reason: String)
    }

    private let keychainStore: KeychainStore
    private var process: Process?
    private var jsonRPCClient: PersistenceHelperRPCClient?
    private var cachedKey: Data?
    private var pendingRequests: [String: PendingWrite] = [:]
    private var consecutiveErrors: Int = 0

    init(keychainStore: KeychainStore) { ... }
    func start() async { ... }
    func shutdown() { ... }
}
```

Conforms to the project's patterns:
- `@MainActor` at the type level.
- `ObservableObject` with `@Published` state.
- Initializer injection via `AppContainer`.
- Explicit `shutdown()` for process teardown.
- `[weak self]` in all `Task` closures.
- Tracks pending requests by ID for ACK/error correlation.
- Monitors consecutive errors to trigger ephemeral fallback.

The service attaches to `AgentSessionProtocol` — any session implementation (ACP, Claude Code direct, Codex direct) calls `AgentConversationStore` on message events. The store is transport-agnostic.

### `KeychainStore` for Encryption Key

Reuses the existing `KeychainStore` struct from `CognitoAuthSecurity.swift` with a new service name:

| Property | Value |
|----------|-------|
| Keychain service | `com.crispyvibe.app.agent-persist` (resolved from Info.plist) |
| Account | `db-encryption-key` |
| Key size | 256-bit AES (32 bytes) |
| Backend | Standard macOS Keychain, no Data Protection keychain attributes |

Follows the same pattern as `VibeSpacePersistenceStore.loadOrCreateSigningKey()`:
1. Try to read existing key from keychain.
2. If not found, generate 32 random bytes via `SecRandomCopyBytes`.
3. Store in keychain.
4. Cache in memory for the app session.

Build isolation: keychain service name resolved from Info.plist key `CrispyVibesAgentPersistKeychainService`, so `crispyvibes` and `crispyvibes-local` builds use separate keys and databases.

### `NLContextualEmbedding` for Vector Generation — Runtime-Adaptive

Embedding generation happens on the Swift side before sending messages to the Rust helper. Dimensions are **not hardcoded** — the system queries the runtime:

```swift
import NaturalLanguage

func generateEmbedding(for text: String) -> EmbeddingResult? {
    guard let embedding = NLContextualEmbedding(modelIdentifier: "...", revision: ..., language: .english) else { return nil }
    guard embedding.hasAvailableAssets else { return nil }
    try? embedding.load()
    guard let vector = embedding.processString(text) else { return nil }
    return EmbeddingResult(
        vector: vector.map { Float($0) },
        modelId: embedding.modelIdentifier,
        revision: embedding.revision,
        dimension: embedding.dimension,
        language: "en"
    )
}
```

- On-device model, no network required.
- macOS 26+ (Tahoe) — matches the app's deployment target.
- `dimension`, `modelIdentifier`, `revision` queried from the runtime, not assumed.
- Each embedding batch stores `model_id`, `revision`, `dimension`, `language` alongside vectors.
- If embedding generation fails (model unavailable, assets not downloaded, text too short), the message is persisted without a vector. Search falls back to FTS5 only.
- Vectors are sent alongside message text and embedding metadata in the `message.append` RPC call.

## Data Flow

### Startup Sequence

```
App Launch
  └── AppContainer.makeDefault()
        ├── existing services...
        └── AgentConversationStore(keychainStore:)
              │
              ├─ 1. KeychainStore.read(account: "db-encryption-key")
              │     ├── found → use existing key
              │     └── not found → SecRandomCopyBytes(32) → KeychainStore.write() → use new key
              │
              ├─ 2. Ensure directory exists:
              │     ~/Library/Application Support/CrispyVibes/acp/
              │
              ├─ 3. Spawn crispyvibes-persistence-helper via Process + Pipe
              │     ├── executable: Bundle.main.url(forAuxiliaryExecutable:)
              │     ├── stdin: Pipe (write end held by Swift)
              │     ├── stdout: Pipe (read end held by Swift)
              │     └── stderr: Pipe (captured for diagnostics)
              │
              ├─ 4. Send init RPC:
              │     → { "id": "init", "method": "init", "params": {
              │           "dbPath": "~/Library/.../conversations.db",
              │           "hexKey": "a1b2c3..." } }
              │
              │     Rust side:
              │     ├── libsql::Builder::new_local(dbPath)
              │     │     .encryption_config(EncryptionConfig::new(
              │     │         Cipher::Aes256Cbc, hexKey))
              │     │     .build()
              │     ├── PRAGMA journal_mode = WAL
              │     ├── PRAGMA foreign_keys = ON
              │     ├── Run forward-only migrations (schema.rs)
              │     ├── Zero out hexKey from init message buffer
              │     └── Return { "id": "init", "result": { "ready": true, "schemaVersion": 1 } }
              │
              ├─ 5. state = .ready(schemaVersion: 1)
              └─ 6. If any step fails → state = .ephemeral(reason: "...")
                    Agent sessions run without persistence (today's behavior)
```

Startup target: helper ready within 500ms of spawn. The helper starts eagerly at app launch, not lazily on first agent use.

### Message Persistence Flow

```
User sends message or agent streams response
  │
  ├── AgentSessionProtocol implementation receives update
  │   ├── Updates in-memory timeline (existing behavior, unchanged)
  │   └── Calls AgentConversationStore.persistMessage(...)
  │
  └── AgentConversationStore
        ├── Guard: state == .ready, else return (skip silently)
        ├── Generate embedding: NLContextualEmbedding → EmbeddingResult?
        ├── Assign unique request ID
        └── Send RPC (async queued, non-blocking):
            → { "id": "req-42", "method": "message.append", "params": {
                  "id": "<uuid>",
                  "threadId": "<thread-uuid>",
                  "turnId": "<turn-uuid>",
                  "role": "user|assistant",
                  "text": "...",
                  "isStreaming": false,
                  "embedding": [0.123, -0.456, ...],
                  "embeddingMeta": {
                    "modelId": "...", "revision": 1,
                    "dimension": 512, "language": "en"
                  } } }

            Rust side:
            ├── INSERT INTO messages (...)
            ├── INSERT INTO message_fts (rowid, text) — FTS5 content sync
            ├── If embedding present:
            │   INSERT INTO message_embeddings (message_id, model_id, revision,
            │     dimension, language, embedding)
            └── Return { "id": "req-42", "result": { "ok": true } }

        Swift side (async response handler):
        ├── Match response ID to pending request
        ├── On ACK: clear pending, reset error counter
        └── On error: increment consecutiveErrors, log warning
            If consecutiveErrors > threshold → transition to .ephemeral
```

### Turn Completion Persistence Flow

When a turn completes (assistant finishes responding), `persistCompletedTurn()` persists all content from the turn in a single batch:

```
Agent turn completes
  │
  ├── 1. Persist thinking content (if non-empty):
  │   → message.append with role: "system", text: turn.thinking
  │
  ├── 2. Persist assistant response (if non-empty):
  │   → message.append with role: "assistant", text: turn.responseText
  │
  ├── 3. Persist tool calls as activities:
  │   For each toolCall in turn.toolCalls:
  │   → activity.append with:
  │     kind: "tool_call"
  │     summary: toolCall.title
  │     payload: { toolCallId, kind, status, itemType,
  │                filePaths: [extracted from diff content] }
  │
  ├── 4. Persist file change summary (if files changed):
  │   → activity.append with:
  │     kind: "file_change"
  │     summary: "N file(s) changed"
  │     payload: { files: ["path (+A/-D)", ...] }
  │
  ├── 5. Update resume cursor:
  │   → session.upsert with updated resume_cursor_json
  │     from the agent's turn completion response
  │
  └── 6. Auto-generate title (if first turn):
      → Phase 1: thread.update with title = prefix(60) of user message
      → Phase 2 (async, after response): thread.update with
        concise summary derived from message content
        (only if title still matches the seed)
```

### Assistant Message Segmentation

When an approval request or user input request pauses a turn mid-stream:

```
Agent streaming response → approval request arrives
  │
  ├── 1. Finalize current assistant segment:
  │   → message.append with is_streaming: false for current messageId
  │
  ├── 2. Persist approval activity:
  │   → activity.append with kind: "approval", payload: { requestId, requestKind }
  │
  ├── 3. User responds to approval → agent resumes
  │
  ├── 4. Start new assistant segment:
  │   → message.append with NEW messageId, same turnId, is_streaming: true
  │
  └── On restore: timeline renders segment 1 → approval card → segment 2
```

Writes are async queued — the UI never blocks on persistence. But unlike fire-and-forget, the ACK/error response lets Swift detect an unhealthy helper and fall back gracefully.

### Search Flow

```
User types in search bar
  │
  ├── Keyword search (immediate, on every keystroke after debounce):
  │   └── AgentConversationStore.searchKeyword(query:)
  │       → { "id": "req-50", "method": "search.keyword", "params": {
  │             "query": "pagination",
  │             "vibespaceId": "<optional>",
  │             "limit": 50 } }
  │
  │       Rust: SELECT ... FROM message_fts WHERE message_fts MATCH ?
  │       → { "id": "req-50", "result": { "matches": [...] } }
  │
  └── Semantic search (triggered by explicit action or after keyword returns few results):
      ├── Swift: NLContextualEmbedding → vector + metadata
      └── AgentConversationStore.searchVector(embedding:)
          → { "id": "req-51", "method": "search.vector", "params": {
                "embedding": [0.123, -0.456, ...],
                "dimension": 512,
                "vibespaceId": "<optional>",
                "limit": 20 } }

          Rust: SELECT ... FROM message_embeddings
                WHERE dimension = ?
                ORDER BY libsql_vector_distance(embedding, ?) ASC
                LIMIT 20
          → { "id": "req-51", "result": { "matches": [...] } }
```

### Session Resume Flow — Silent Reconnection

The unified thread model means the user never explicitly triggers resume. They open a thread, see history, and type. The system handles reconnection transparently. The restore and connect sequence is coordinated by `ACPStandaloneSessionStore` — the view simply calls `ensureConnected` and the store awaits any in-flight restore before connecting.

```
App restores a tab with a persisted thread
  │
  ├── ACPStandaloneSessionStore.restore(from: snapshot)
  │   ├── Set selectedAgentID, project, model from snapshot (synchronous)
  │   └── restoreTask = Task {
  │       ├── Parallel DB loads:
  │       │   ├── conversationStore.listMessages(threadId:)
  │       │   ├── conversationStore.getSession(threadId:)
  │       │   └── conversationStore.getThread(id:)
  │       ├── Set storedProviderSessionId, storedTransportKind from session data
  │       └── chatViewModel.applyRestoredData(threadId:messages:threadData:)
  │           (PersistenceContext populated with real metadata from DB)
  │   }
  │
  ├── View .onAppear → prepareDefaults() → store.ensureConnected(projects:)
  │   └── ensureConnected:
  │       ├── await restoreTask?.value  (waits for DB load to complete)
  │       └── connect(projects:)
  │
  ├── connect() reads session metadata:
  │   ├── storedProviderSessionId loaded from DB (not nil)
  │   ├── storedTransportKind loaded from DB
  │   └── Agent capabilities from initialize response
  │
  ├── ACP agents — resume strategy selection:
  │   ├── Agent has sessionCapabilities.resume?
  │   │   → session/resume(sessionId, cwd, mcpServers) — lightweight, no replay
  │   ├── Agent has loadSession?
  │   │   → session/load(sessionId, cwd, mcpServers) — replays full history
  │   └── Neither → connect as fresh session
  │
  ├── Direct integrations — resume via CLI flags:
  │   ├── Claude Code → --resume <sessionId>
  │   └── Codex → thread/start with stored threadID
  │
  ├── On resume success:
  │   ├── bindACPSession / bindDirectSession
  │   ├── SessionMetadata.from(session:agentID:) captures identity
  │   ├── persistSessionMetadata(status: "ready") via SerialTaskQueue
  │   └── Observe isConnected for unexpected disconnect
  │
  └── On resume failure:
      ├── Disconnect the session
      ├── Set pendingResumeFailure with error detail
      ├── Show alert: "Session Resume Failed" with reason
      └── User chooses: "Start Fresh" (connects without resume) or "Cancel"
```

**Session identity is protocol-based.** `SessionMetadata.from(session:agentID:)` reads `transportKind`, `providerSessionID`, and `resumeStrategy` directly from `AgentSessionProtocol` properties. No type-checking of `ACPSession`, `ClaudeCodeSession`, or `CodexSession` anywhere in the persistence or session management code.

**Persistence is serialized.** All writes (`persistUserMessage`, `persistCompletedTurn`, `ensureThread`, `persistSessionMetadata`) go through `SerialTaskQueue`. This guarantees message ordering (user message before assistant response before tool calls) and prevents races between turn-complete and disconnect status updates. The `onTurnCompleted` callback from `ACPChatViewModel` triggers `persistSessionMetadata(status: "ready")` on the store — single owner for session status.

**Error propagation.** When `session/prompt` fails, the error is yielded as `ACPUpdate.error(message)` to the stream. `ACPTurnEntry.errorText` stores it. The timeline view renders it in red. Transport errors include the process exit code and last 300 chars of stderr. When the agent process dies unexpectedly after a successful connect, the store observes `isConnected` flipping to false and sets `connectionError` with `lastDisconnectReason` from the session — which includes the exit code and stderr from the transport's termination handler.

### Sidebar Hydration

```
VibeSpace opens (or vibespace focus changes)
  │
  ├── ACPVibeSpaceSessionService.sync(focusedProject:...)
  │   └── AgentConversationStore.listThreads(vibespaceId:)
  │       → { "method": "thread.list", "params": {
  │             "vibespaceId": "<vibespace-uuid>",
  │             "includeArchived": false } }
  │       ← { "result": { "threads": [
  │             { "id", "title", "agentId", "transportKind",
  │               "model", "projectPath", "threadKind",
  │               "updatedAt", "messageCount", "hasActiveSession" },
  │             ... ] } }
  │
  └── Sidebar view model populates thread list
      ├── Grouped by project path
      ├── Sorted by updatedAt descending within each group
      ├── Active sessions show live indicator
      └── No thread shows "expired" or "session ended" — just the conversation
```

## API / Command Contracts

All methods use JSON-RPC 2.0 framing over stdin/stdout. Requests include `id`, `method`, and `params`. Responses include `id` and either `result` or `error`. Every request gets a response — no fire-and-forget.

### `init`

Initializes the database connection. Must be the first message. The hex key is zeroed from memory immediately after extraction. Uses `EncryptionConfig` (not `PRAGMA hexkey`) — spike required to verify this works for local-only embedded databases.

```json
// Request
{ "id": "init", "method": "init", "params": {
    "dbPath": "/Users/x/Library/Application Support/CrispyVibes/acp/conversations.db",
    "hexKey": "a1b2c3d4e5f6..."
}}

// Response
{ "id": "init", "result": { "ready": true, "schemaVersion": 1 } }
```

### `thread.create`

```json
// Request
{ "id": "req-1", "method": "thread.create", "params": {
    "id": "uuid-1",
    "vibespaceId": "ws-uuid",
    "projectPath": "/Users/x/projects/crispyvibes-ide",
    "title": "Fix auth token refresh",
    "agentId": "claude-code",
    "transportKind": "acp",
    "model": "claude-sonnet-4-20250514",
    "threadKind": "conversation",
    "parentThreadId": null,
    "metadata": "{}",
    "tags": "[]"
}}

// Response
{ "id": "req-1", "result": { "id": "uuid-1", "createdAt": "2026-04-25T17:00:00Z" } }
```

`threadKind` defaults to `"conversation"` if omitted. `parentThreadId`, `metadata`, and `tags` are optional — they default to `null`, `"{}"`, and `"[]"` respectively. `metadata` must be a valid JSON object string; `tags` must be a valid JSON array of strings. The helper validates JSON well-formedness and rejects malformed values with an error response.

### `thread.update`

```json
{ "id": "req-2", "method": "thread.update", "params": {
    "id": "uuid-1",
    "title": "Fix auth token refresh bug",
    "metadata": "{\"priority\": \"high\"}",
    "tags": "[\"bug-fix\", \"auth\"]",
    "archivedAt": null
}}
```

### `thread.delete`

```json
{ "id": "req-3", "method": "thread.delete", "params": { "id": "uuid-1" } }
```

Cascades: deletes all messages, activities, sessions, embeddings, and FTS entries for the thread. Also cascades to child threads (via `parent_thread_id` FK).

### `thread.list`

```json
// Request
{ "id": "req-4", "method": "thread.list", "params": {
    "vibespaceId": "ws-uuid",
    "includeArchived": false,
    "threadKind": "conversation",
    "limit": 100,
    "offset": 0
}}

// Response
{ "id": "req-4", "result": { "threads": [
    { "id": "uuid-1", "vibespaceId": "ws-uuid", "projectPath": "/...",
      "title": "Fix auth token refresh", "agentId": "claude-code",
      "transportKind": "acp", "model": "claude-sonnet-4-20250514",
      "threadKind": "conversation", "parentThreadId": null,
      "metadata": "{}", "tags": "[]",
      "createdAt": "...", "updatedAt": "...", "archivedAt": null }
] } }
```

`threadKind` filter is optional — omit to list all kinds.

### `message.append`

```json
{ "id": "req-5", "method": "message.append", "params": {
    "id": "msg-uuid",
    "threadId": "uuid-1",
    "turnId": "turn-uuid",
    "role": "assistant",
    "text": "I'll fix the token refresh logic...",
    "isStreaming": false,
    "embedding": [0.123, -0.456, 0.789, ...],
    "embeddingMeta": {
        "modelId": "NLContextualEmbedding-v2",
        "revision": 1,
        "dimension": 512,
        "language": "en"
    }
}}
```

If `embedding` is `null` or omitted, the message is stored without a vector (FTS-only search). The `embedding` array length must match `embeddingMeta.dimension` when present. Embedding dimensions are not hardcoded — they adapt to the runtime model.

For streaming messages, the caller sends `message.append` with `isStreaming: true` initially, then sends again with the same `id`, `isStreaming: false`, and the final `text` when streaming completes. The Rust side upserts by message ID.

### `message.list`

```json
// Request
{ "id": "req-6", "method": "message.list", "params": {
    "threadId": "uuid-1",
    "limit": 2000,
    "afterSequence": 0
}}

// Response — ordered by sequence ASC
{ "id": "req-6", "result": { "messages": [
    { "id": "msg-uuid", "threadId": "uuid-1", "turnId": "turn-uuid",
      "role": "user", "text": "...", "isStreaming": false,
      "sequence": 1, "createdAt": "...", "updatedAt": "..." },
    ...
] } }
```

The 2,000 message cap is enforced on UI reads only (returns latest 2,000 by sequence). Full history stays in the DB for search and export.

### `activity.append`

```json
{ "id": "req-7", "method": "activity.append", "params": {
    "id": "act-uuid",
    "threadId": "uuid-1",
    "turnId": "turn-uuid",
    "kind": "tool_call",
    "itemType": "command_execution",
    "summary": "Read file: src/auth.swift",
    "payloadJson": "{\"toolCallId\":\"tc-1\",\"tool\":\"fs/read_text_file\",\"path\":\"src/auth.swift\",\"status\":\"success\",\"filePaths\":[\"src/auth.swift\"]}"
}}
```

`itemType` is optional. When present, it classifies the tool call for type-specific icon rendering: `command_execution`, `file_change`, `file_read`, `mcp_tool_call`, `web_search`. When absent or unrecognized, the timeline renders a generic tool icon. The `payloadJson` SHOULD include `filePaths` for tool calls that affect files, and `toolCallId` for lifecycle collapsing.

### `activity.list`

```json
{ "id": "req-8", "method": "activity.list", "params": {
    "threadId": "uuid-1",
    "turnId": "turn-uuid"
}}
```

### `session.upsert`

```json
{ "id": "req-9", "method": "session.upsert", "params": {
    "threadId": "uuid-1",
    "provider": "claude-code",
    "transportKind": "acp",
    "status": "ready",
    "resumeStrategy": "native_resume",
    "capabilities": "{\"loadSession\":true,\"mcp\":true}",
    "providerSessionId": "provider-session-abc",
    "resumeCursorJson": "{\"sessionId\":\"abc\",\"lastEventId\":\"xyz\"}",
    "runtimeMode": "direct"
}}
```

`status` values: `connecting`, `ready`, `running`, `interrupted`, `error`, `disconnected`. These are internal infrastructure states — the UI does not expose them directly to the user.

`resumeCursorJson` is an opaque JSON string — stored and returned verbatim, never interpreted by the persistence layer. `capabilities` records what the agent reported at session start. `resumeStrategy` is determined by the Swift side based on capabilities.

**Cursor update timing:** `session.upsert` MUST be called:
1. On session connect — stores initial capabilities, provider session ID, and resume strategy.
2. After every completed turn — updates `resumeCursorJson` with the cursor returned by the agent.
3. On session disconnect — updates status to `disconnected`.

This ensures the cursor always reflects the last completed turn, not just the session start. If the app crashes between turns, the stored cursor enables resume from the correct point.

### `session.get`

```json
// Request
{ "id": "req-10", "method": "session.get", "params": { "threadId": "uuid-1" } }

// Response
{ "id": "req-10", "result": {
    "threadId": "uuid-1", "provider": "claude-code",
    "transportKind": "acp",
    "status": "disconnected",
    "resumeStrategy": "native_resume",
    "capabilities": "{\"loadSession\":true,\"mcp\":true}",
    "providerSessionId": "provider-session-abc",
    "resumeCursorJson": "{...}",
    "runtimeMode": "direct", "updatedAt": "..."
} }
```

### `search.keyword`

```json
// Request
{ "id": "req-11", "method": "search.keyword", "params": {
    "query": "pagination",
    "vibespaceId": "ws-uuid",
    "limit": 50
}}

// Response
{ "id": "req-11", "result": { "matches": [
    { "threadId": "uuid-1", "messageId": "msg-uuid",
      "snippet": "...add <b>pagination</b> to the API...",
      "threadTitle": "Add pagination to API",
      "rank": -12.5 }
] } }
```

### `search.vector`

```json
// Request
{ "id": "req-12", "method": "search.vector", "params": {
    "embedding": [0.123, -0.456, ...],
    "dimension": 512,
    "vibespaceId": "ws-uuid",
    "limit": 20
}}

// Response
{ "id": "req-12", "result": { "matches": [
    { "threadId": "uuid-1", "messageId": "msg-uuid",
      "snippet": "Fixed the authentication flow by...",
      "threadTitle": "Fix auth token refresh",
      "distance": 0.234 }
] } }
```

### `export.markdown`

Exports full history (not capped at 2,000).

```json
// Request
{ "id": "req-13", "method": "export.markdown", "params": { "threadId": "uuid-1" } }

// Response
{ "id": "req-13", "result": { "markdown": "# Fix auth token refresh\n\n**User** (2026-04-25 17:00):\n..." } }
```

### `export.json`

Exports full history (not capped at 2,000).

```json
// Request
{ "id": "req-14", "method": "export.json", "params": { "threadId": "uuid-1" } }

// Response
{ "id": "req-14", "result": { "thread": { ... }, "messages": [...], "activities": [...] } }
```

### `maintenance.cleanup`

Called on app startup. Deletes threads older than the user's configured retention period.

```json
// Request
{ "id": "req-15", "method": "maintenance.cleanup", "params": {
    "retentionDays": 90
}}

// Response — null retentionDays means "never delete"
{ "id": "req-15", "result": { "deletedThreads": 3, "deletedMessages": 142 } }
```

## Data Schema

### DDL

All tables created in the initial migration (`V1`). Forward-only migrations managed by `schema_version` table.

```sql
-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER NOT NULL
);
INSERT INTO schema_version (version) VALUES (1);

-- Conversation threads (extensible via thread_kind, metadata, tags)
CREATE TABLE IF NOT EXISTS threads (
    id                TEXT PRIMARY KEY,
    vibespace_id      TEXT NOT NULL,
    project_path      TEXT NOT NULL,
    title             TEXT NOT NULL,
    agent_id          TEXT NOT NULL,       -- e.g., 'claude-code', 'codex', 'acp-agent-x'
    transport_kind    TEXT NOT NULL,       -- 'acp', 'claude_code_direct', 'codex_direct', etc.
    model             TEXT NOT NULL,
    thread_kind       TEXT NOT NULL DEFAULT 'conversation',  -- extensible: workflow_step, sub_conversation, review, template_instance
    parent_thread_id  TEXT REFERENCES threads(id) ON DELETE SET NULL,  -- nullable FK for hierarchical relationships
    metadata          TEXT NOT NULL DEFAULT '{}',   -- JSON object, kind-specific data
    tags              TEXT NOT NULL DEFAULT '[]',   -- JSON array of strings, user/system labels
    created_at        TEXT NOT NULL,       -- ISO 8601
    updated_at        TEXT NOT NULL,       -- ISO 8601
    archived_at       TEXT                 -- ISO 8601, NULL if not archived
);

CREATE INDEX idx_threads_vibespace ON threads(vibespace_id, updated_at DESC);
CREATE INDEX idx_threads_project ON threads(vibespace_id, project_path, updated_at DESC);
CREATE INDEX idx_threads_kind ON threads(thread_kind);
CREATE INDEX idx_threads_parent ON threads(parent_thread_id);

-- Messages (user and assistant)
CREATE TABLE IF NOT EXISTS messages (
    id           TEXT PRIMARY KEY,
    thread_id    TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    turn_id      TEXT,
    role         TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    text         TEXT NOT NULL,
    is_streaming INTEGER NOT NULL DEFAULT 0,  -- 0 = complete, 1 = still streaming
    sequence     INTEGER NOT NULL,            -- monotonic per thread
    created_at   TEXT NOT NULL,               -- ISO 8601
    updated_at   TEXT NOT NULL                -- ISO 8601
);

CREATE INDEX idx_messages_thread_seq ON messages(thread_id, sequence ASC);
CREATE INDEX idx_messages_thread_turn ON messages(thread_id, turn_id);

-- Full-text search over message content
CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
    text,
    content='messages',
    content_rowid='rowid'
);

-- FTS sync triggers
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
END;

CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
END;

CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE OF text ON messages BEGIN
    INSERT INTO message_fts(message_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
    INSERT INTO message_fts(rowid, text) VALUES (new.rowid, new.text);
END;

-- Vector embeddings for semantic search (runtime-adaptive dimensions)
CREATE TABLE IF NOT EXISTS message_embeddings (
    message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    model_id   TEXT NOT NULL,            -- NLContextualEmbedding model identifier
    revision   INTEGER NOT NULL,         -- model revision number
    dimension  INTEGER NOT NULL,         -- actual vector dimension from runtime
    language   TEXT NOT NULL,            -- e.g., 'en'
    embedding  F32_BLOB(512)            -- vector column; dimension adapts at runtime
);

-- Tool call and file change activity log
CREATE TABLE IF NOT EXISTS activities (
    id           TEXT PRIMARY KEY,
    thread_id    TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    turn_id      TEXT,
    kind         TEXT NOT NULL,   -- 'tool_call', 'file_change', 'approval', 'plan', etc.
    item_type    TEXT,            -- 'command_execution', 'file_change', 'file_read', 'mcp_tool_call', 'web_search', NULL for non-tool activities
    summary      TEXT NOT NULL,   -- human-readable one-liner
    payload_json TEXT,            -- full structured payload as JSON string
    sequence     INTEGER NOT NULL, -- monotonic per thread
    created_at   TEXT NOT NULL     -- ISO 8601
);

CREATE INDEX idx_activities_thread_seq ON activities(thread_id, sequence ASC);
CREATE INDEX idx_activities_thread_turn ON activities(thread_id, turn_id);

-- Agent session state (transient connection attached to a thread)
CREATE TABLE IF NOT EXISTS sessions (
    thread_id           TEXT PRIMARY KEY REFERENCES threads(id) ON DELETE CASCADE,
    provider            TEXT NOT NULL,
    transport_kind      TEXT NOT NULL,       -- 'acp', 'claude_code_direct', 'codex_direct'
    status              TEXT NOT NULL CHECK (status IN ('connecting', 'ready', 'running', 'interrupted', 'error', 'disconnected')),
    resume_strategy     TEXT NOT NULL CHECK (resume_strategy IN ('native_resume', 'transcript_replay', 'none')),
    capabilities        TEXT,               -- JSON blob of agent-reported capabilities
    provider_session_id TEXT,               -- agent's own session ID (for native resume)
    resume_cursor_json  TEXT,               -- opaque JSON blob from agent, stored verbatim
    runtime_mode        TEXT NOT NULL,      -- 'acp', 'direct', 'background'
    updated_at          TEXT NOT NULL       -- ISO 8601
);
```

### Schema Notes

- **`thread_kind`**: Defaults to `'conversation'` for standard agent interactions. Extensible to `workflow_step`, `sub_conversation`, `review`, `template_instance`, and future kinds without schema migrations. The persistence layer stores this value opaquely — kind-specific behavior is implemented in the Swift layer.

- **`parent_thread_id`**: Nullable FK to `threads(id)` with `ON DELETE SET NULL`. Enables hierarchical thread relationships: a workflow thread can have step threads as children, a conversation can spawn sub-conversations. Setting NULL on parent deletion preserves child threads as orphans rather than cascading deletion.

- **`metadata`**: JSON object stored as TEXT. Open key-value bag for kind-specific data. Examples:
  - Workflow step: `{"workflow_id": "...", "step_index": 2, "step_name": "implement"}`
  - Review thread: `{"pr_url": "...", "pr_number": 42}`
  - Template instance: `{"template_id": "...", "template_name": "Bug fix"}`
  - The persistence layer validates well-formedness (must be a JSON object) and enforces a 64 KB size cap. It does not validate kind-specific schemas.

- **`tags`**: JSON array of strings stored as TEXT. User-defined or system-defined labels for filtering and grouping. Examples: `["bug-fix", "auth", "high-priority"]`. The persistence layer validates well-formedness (must be a JSON array of strings), caps at 100 entries, and caps individual tags at 256 characters.

- **`sequence` columns**: Monotonically increasing integers per thread, assigned by the Rust helper (not by Swift). Prevents ordering ambiguity from clock skew or rapid streaming. The helper maintains a per-thread counter in memory, seeded from `MAX(sequence)` on thread load.

- **`message_fts`**: Content-sync FTS5 table backed by `messages`. Triggers keep FTS in sync on insert, update, and delete. Keyword search uses `MATCH` with BM25 ranking.

- **`message_embeddings`**: Runtime-adaptive vector storage. The `dimension` column records the actual dimension from the runtime model. The `F32_BLOB(512)` declaration is the initial size — if the runtime reports a different dimension, the column adapts. `model_id`, `revision`, and `language` are stored per-row so vectors remain interpretable if the OS model changes across macOS versions.

- **`threads.agent_id` and `threads.transport_kind`**: Distinguish conversations from different agent types. `agent_id` identifies the specific agent (e.g., `claude-code`), while `transport_kind` identifies the protocol used (e.g., `acp`, `claude_code_direct`).

- **`sessions.status`**: Tracks the transient connection state: `connecting`, `ready`, `running`, `interrupted`, `error`, `disconnected`. These are internal infrastructure states — the user mostly just sees the conversation. The sidebar may show a subtle live indicator for active sessions but does not expose raw status values.

- **`sessions.resume_strategy`**: Determined by the Swift side based on `capabilities`. `native_resume` means the agent supports `session/load`; `transcript_replay` means the agent doesn't support native resume but can accept replayed context; `none` means one-shot.

- **`sessions.capabilities`**: JSON blob recording what the agent reported at session start (e.g., `{"loadSession": true, "mcp": true}`). Used to determine `resume_strategy`.

- **`sessions.provider_session_id`**: The agent's own session identifier, used for native resume. Distinct from the thread ID.

- **`resume_cursor_json`**: Opaque blob. Each agent type returns its own resume token. We store it as-is and hand it back on reconnect. The persistence layer never parses or validates this field.

- **Cascade deletes**: `ON DELETE CASCADE` on messages, activities, sessions, embeddings. `ON DELETE SET NULL` on `parent_thread_id` — deleting a parent thread orphans children rather than cascading. Deleting a thread removes all its messages, activities, sessions, embeddings, and FTS entries in a single transaction.

- **No `attachments` column on messages**: File attachments are handled by the agent's own file I/O. The persistence layer stores the text content and tool call activity, not binary file data.

- **Full history retained**: All messages stay in the DB until the auto-cleanup policy deletes the thread. The 2,000 message cap is on UI reads only — search and export access the full history.

## State Management

### `AgentConversationStore` State Machine

```
                  ┌──────────┐
     app launch → │ starting │
                  └────┬─────┘
                       │
            ┌──────────┴──────────┐
            │ spawn helper,       │
            │ send init RPC       │
            ▼                     ▼
     ┌──────────┐         ┌────────────┐
     │  ready   │         │ ephemeral  │ ← helper crash / init failure
     └────┬─────┘         └────────────┘
          │                      ▲
          │ helper pipe closed   │ restart fails
          │ or consecutive       │ or consecutive
          │ write errors         │ errors exceed threshold
          ├──────────────────────┘
          │ restart succeeds
          └──→ ready
```

States:
- **`.starting`** — helper is being spawned and initialized. RPC calls are queued.
- **`.ready(schemaVersion:)`** — helper is running, DB is open. All RPC methods available.
- **`.ephemeral(reason:)`** — persistence unavailable. Agent sessions run without history (today's behavior). No user-facing error unless they explicitly look for history.

### Health Monitoring via ACK/Error

`AgentConversationStore` tracks write health through ACK/error responses:
- Each write request has a unique ID tracked in `pendingRequests`.
- ACK responses clear the pending entry and reset the error counter.
- Error responses increment `consecutiveErrors`.
- If `consecutiveErrors` exceeds a threshold (e.g., 5), the store transitions to `.ephemeral`.
- This replaces fire-and-forget — the UI still never blocks, but the system detects an unhealthy helper.

### Helper Crash Recovery

If the Rust process dies during the app session (pipe closed, SIGTERM, etc.):

1. `AgentConversationStore` detects pipe closure via `Process.terminationHandler`.
2. Transitions to `.starting`.
3. Attempts one restart with the cached in-memory key.
4. If restart succeeds → `.ready`. Queued writes during restart are replayed.
5. If restart fails → `.ephemeral(reason: "helper restart failed")`. No further attempts.

### Integration with Existing Session State

`AgentConversationStore` is a passive observer — it does not own or modify agent session state. The existing session managers and chat view models remain the source of truth for live session state.

Persistence hooks are added at the `AgentSessionProtocol` level:

1. **Session implementations** (ACP, Claude Code direct, Codex direct) — after processing each update, call `AgentConversationStore` to persist the message or activity. Async queued with ACK tracking.
2. **`ACPVibeSpaceSessionService`** — on vibespace open, calls `AgentConversationStore.listThreads()` to populate the sidebar. On session connect/disconnect, calls `session.upsert` to update session state with the appropriate status (`connecting`, `ready`, `running`, `interrupted`, `error`, `disconnected`).

No new `@Published` properties are added to existing types. The sidebar thread list is a new `@Published` property on `AgentConversationStore` itself, consumed by a new sidebar view.

### Silent Reconnection State

When the user types in a disconnected thread, the reconnection flow is managed by the session layer, not the persistence layer. The persistence layer's role is to provide the stored session metadata (resume strategy, cursor, capabilities) so the session layer can reconnect. The compose bar remains visible throughout — the user's message is queued and sent once the connection is established.

## Timeline Rendering Design

#### Tool Call Type Classification

Activities with `kind: "tool_call"` include an `item_type` column that classifies the tool for rendering:

| `item_type` | Icon | Description |
|-------------|------|-------------|
| `command_execution` | Terminal | Shell commands, script execution |
| `file_change` | Pen/Edit | File writes, patches, edits |
| `file_read` | Eye | File reads, directory listings |
| `mcp_tool_call` | Wrench | MCP server tool invocations |
| `web_search` | Globe | Web search queries |
| `NULL` / unknown | Generic tool | Unclassified tool calls |

Classification is performed in `ACPPersistenceEncoder` at persistence time by mapping `ACPToolCallState.kind` to the `item_type` enum. The mapping is centralized — not scattered across views.

#### Work Log Collapsing

On restore, the timeline groups adjacent tool call activities into a collapsible "Work log" section:

1. Activities for the same `turn_id` with `kind: "tool_call"` are grouped.
2. Within a group, consecutive activities with the same `toolCallId` (from `payload_json`) are collapsed into a single row showing the final state.
3. The collapsed row shows: tool title, detail/command preview, changed file paths (vibespace-relative).
4. Default display: collapsed, showing at most 6 entries. "Show all" expands the full list.

This is a **view-layer concern** — the database stores every activity individually. Collapsing happens in the SwiftUI view model when building the timeline from persisted activities.

#### VibeSpace-Relative File Paths

File paths in tool call activities and file change summaries are stored as absolute paths in the database but displayed relative to the vibespace root in the UI:

```
Stored:   /path/to/project/projects/crispyvibes/crispyvibes/Features/ACP/ACPChatViewModel.swift
Displayed: projects/crispyvibes/crispyvibes/Features/ACP/ACPChatViewModel.swift
```

The vibespace root is resolved from the thread's `project_path` field. Path stripping is performed at render time in the view, not at persistence time — the database always stores absolute paths for portability.

#### Assistant Message Segmentation on Approval Pause

When an approval request pauses a turn mid-stream, the assistant text is split into segments:

```
messages table:
  msg-1: { turnId: "turn-1", role: "assistant", text: "I'll read the file first...", is_streaming: 0 }
  msg-2: { turnId: "turn-1", role: "assistant", text: "Now I'll apply the fix...", is_streaming: 0 }

activities table:
  act-1: { turnId: "turn-1", kind: "approval", summary: "Command approval requested", payload: { requestId: "req-1" } }
```

On restore, the timeline interleaves messages and activities by sequence number, producing:
1. Assistant segment 1: "I'll read the file first..."
2. Approval card: "Command approval requested"
3. Assistant segment 2: "Now I'll apply the fix..."

This requires multiple assistant messages per turn — the `turn_id` groups them, and `sequence` orders them.

#### Thread Title Generation Flow

```
First user message sent
  │
  ├── Phase 1 (immediate): title = userMessage.prefix(60)
  │   → thread.update(title: "Fix the auth token refresh bug in the login ser…")
  │   → Sidebar shows seed title immediately
  │
  └── Phase 2 (async, after first assistant response):
      ├── Extract concise summary from user message
      │   Option A: First sentence/clause extraction (local, no network)
      │   Option B: Ask the connected agent to summarize (piggyback on response)
      │
      ├── Check: has user already renamed? (title != seed)
      │   ├── Yes → skip, preserve custom title
      │   └── No → thread.update(title: "Fix auth token refresh timeout")
      │
      └── Sidebar updates with concise title
```

## Dependencies (frameworks, libraries)

### Rust (`crispyvibes-persistence/Cargo.toml`)

| Crate | Version | Purpose |
|-------|---------|---------|
| `libsql` | `0.6` | Encrypted SQLite fork with vector search |
| `serde` | `1` (with `derive`) | JSON serialization for RPC types |
| `serde_json` | `1` | JSON parsing for stdin/stdout protocol |
| `tokio` | `1` (features: `rt`, `io-std`, `macros`) | Async runtime for stdin reader loop |
| `anyhow` | `1` | Error handling (same as path-search helper) |
| `libc` | `0.2` | `setprogname` for process naming |
| `zeroize` | `1` | Secure zeroing of encryption key from memory after extraction |

### Swift

| Framework / Type | Source | Purpose |
|------------------|--------|---------|
| `NaturalLanguage` (`NLContextualEmbedding`) | Apple SDK | On-device runtime-adaptive sentence embeddings |
| `KeychainStore` | Existing (`CognitoAuthSecurity.swift`) | Keychain read/write for encryption key |
| `AppContainer` | Existing (`App/AppContainer.swift`) | Composition root — registers `AgentConversationStore` |
| `Process` + `Pipe` | Foundation | Spawn and communicate with Rust helper |
| `CryptoKit` | Apple SDK | `SecRandomCopyBytes` for key generation |

No new third-party Swift dependencies. No new Xcode frameworks beyond `NaturalLanguage` (already available in macOS 26+ SDK).

## Platform Considerations

- **macOS 26+ (Tahoe)**: Required for `NLContextualEmbedding`. Matches the app's existing deployment target.
- **ARM64 primary, Intel supported**: libSQL and the Rust helper compile for both architectures. The Xcode build phase compiles the Rust binary for the active architecture (same as `crispyvibes-path-search-helper`).
- **Sandbox compatibility**: The DB path (`~/Library/Application Support/CrispyVibes/acp/`) is within the app's container for sandboxed builds. Keychain access uses the standard macOS Keychain without restricted Data Protection entitlements.
- **Build isolation**: `crispyvibes` and `crispyvibes-local` schemes use separate keychain service names (resolved from Info.plist) and separate database directories. No cross-contamination between production and development builds.
- **Xcode build integration**: The Rust binary is compiled via a Run Script build phase (same pattern as `crispyvibes-path-search-helper`). Requires Rust/Cargo installed on the build machine.

## Performance Constraints

All targets from the vision document NFR section:

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Startup latency** | < 500ms | Time from helper spawn to `init` response. Must not block app window appearance. |
| **Write latency** | < 10ms | Single `message.append` round-trip. Async queued from Swift — UI never waits. ACK tracked for health. |
| **FTS5 keyword search** | < 50ms | For 10K messages across all threads. |
| **Vector similarity search** | < 200ms | Cosine distance over 10K embeddings (runtime-adaptive dimensions). |
| **Helper memory (RSS)** | < 50MB | Typical usage: < 20 active threads, < 2K messages per thread. |
| **Embedding generation** | < 100ms | Per message, on-device `NLContextualEmbedding`. Non-blocking (async). |

### Write Path Optimization

- Writes are async queued: Swift sends the RPC and processes the ACK/error response asynchronously. The UI never blocks.
- The Rust helper batches FTS5 and embedding inserts in the same transaction as the message insert.
- WAL mode allows concurrent reads during writes — sidebar queries don't block on message persistence.

### Read Path Optimization

- `thread.list` returns lightweight thread metadata (no message bodies). Sidebar hydration is a single indexed query.
- `message.list` uses the `sequence` index for efficient cursor-based pagination. The 2,000 cap is on reads only.
- FTS5 uses BM25 ranking — no post-processing needed on the Rust side.
- Vector search uses libSQL's native `libsql_vector_idx` for approximate nearest neighbor, avoiding full table scan.

## Migration / Rollout Notes

### Schema Migrations

- Forward-only. Each migration is idempotent (uses `IF NOT EXISTS`).
- Migrations run at startup inside the `init` handler, before the `ready` response.
- `schema_version` table tracks the current version. The helper checks the version and runs any pending migrations in order.
- No downgrade path. If a user downgrades the app, the newer schema is left as-is and the older app runs in ephemeral mode (it won't recognize the helper binary or the schema version).

### Pre-Implementation Spike

Before building, verify:
1. **libSQL local encryption from Rust** — confirm `EncryptionConfig` works for local-only embedded databases via the `libsql` crate. If not, document the fallback path (`rusqlite` + `bundled-sqlcipher` + `sqlite-vec`).
2. **NLContextualEmbedding availability** — confirm `hasAvailableAssets` behavior on macOS 26+, and what happens when assets aren't downloaded. Record actual `dimension`, `modelIdentifier`, and `revision` values.

### Fresh Start

- No migration of existing ephemeral sessions. Conversations started before F040 are not retroactively persisted.
- The database is created on first launch after the feature ships. Existing users get an empty conversation history.

### Feature Flag

- `AgentConversationStore` checks `ExperimentalFeaturesService` for an `agentConversationPersistence` flag during the initial rollout.
- When disabled, the service stays in `.ephemeral` mode without spawning the helper.
- Once stable, the flag is removed and persistence is always-on.

### Rollback Safety

- If the feature is disabled (flag off or helper missing), agent sessions revert to ephemeral mode — identical to today's behavior.
- The database file remains on disk but is not accessed. No data loss — re-enabling the feature picks up where it left off.
- The keychain entry persists independently of the feature flag. No key rotation needed on re-enable.

## Conversation UI Components (shipped 2026-04-29)

### Diff Spotlight Panel

`ACPDiffSpotlightPanel` — full-screen sheet presented from `ACPChatView` via `.sheet(isPresented:)`.

- **File sidebar** (180-280px HSplitView): Lists all changed files for a turn with vibespace-relative paths, per-file +/- stats, click to select.
- **Diff content**: `GitDiffPreview` rendering unified diffs built by `ACPUnifiedDiffBuilder.render()`.
- **Entry point**: "View diff" button on `ACPChangedFilesSummaryView` header. Passes `[ACPDiffSummaryRow]` and turn label to the panel.
- **Dismiss**: Escape key via `.keyboardShortcut(.escape)`.

### Unified Text Generation Service

`TextGenerationService` at `Features/Editor/Services/TextGenerationService.swift`.

- Single `generate(prompt:) -> String?` method that reads active CLI profile from `AppPreferences`, gets print mode invocation from `CLIToolCatalog.definition(for:)`, and executes.
- Per-CLI print mode arguments stored in `CLIInvocationDefinition.printModeArguments` and `printModeInputMode` (.positionalArg or .stdin).
- Output processing: strips ANSI escape sequences, parses CLI result envelopes (`{"type":"result","result":"..."}` with markdown code fences), extracts JSON title objects.
- `generateThreadTitle(from:)` wraps `generate()` with title-specific prompt, JSON extraction (`extractJSONTitle`), and sanitization.

### Sidebar Polish

All in `VibeSpaceSidebarConversationsPane.swift`:

- **Agent icons**: `ACPAgentRegistry.agentIconImage(for:size:)` resolves agent ID to branded icon (14×14). Falls back to orange dot.
- **Time grouping**: `timeGrouped()` splits threads into "Recent" (< 7 days) and "Older" buckets. Labels shown when both buckets exist.
- **VibeSpace categorization**: Two loads — vibespace-scoped (`thread.list` with `vibespaceId`) and all threads. Diff produces "Other VibeSpaces" section.
- **Inline delete**: `pendingDeleteId` state replaces modal alert. Row shows "Delete this conversation? Cancel / Delete" inline.

### Cascading Delete

On delete from sidebar (`ContentView` extension → `onDeleteConversationThread`):

1. `ContentViewerStore.removeACPStore(id:)` — closes tabs, tears down store
2. `NotificationCenter.post(.acpStoreRemoved, userInfo: ["storeID": id])` — board store observes and calls `removeACPTiles(storeID:)`
3. `DockedAgentPreviewCoordinator.dismissPreview()` — if showing deleted thread
4. `AgentConversationStore.deleteThread(id:)` — removes from DB

### Tab Titles

`ACPStandaloneSessionStore.tabTitle` priority:
1. `persistenceContext.title` (from DB, updated by LLM title generation)
2. First user message prefix (40 chars)
3. `agentTitle` (provider name — last resort)

`PersistenceContext.title` is set on restore from DB and updated in-place when `persistCompletedTurn` generates a title.

### Compose Bar Features

- **Image attachments** (`composeImages: [NSImage]`): Thumbnail strip, drag-and-drop + Cmd+V paste. `ComposeTextView.mouseDown` override ensures first responder in board tiles.
- **Interaction mode toggle**: Pill buttons from `availableModes`, `setMode()` dispatches to provider.
- **Context window meter**: `ContextWindowMeterView` thin bar, color-coded by usage percentage.
- **AcceptForSession**: Button on permission cards sets `handler.allowAll = true`.

### Board View Integration

- `ACPBoardTileCard` has `.contentShape(Rectangle()).simultaneousGesture(TapGesture())` for selection highlight (same as terminal tiles).
- `ComposeTextView.mouseDown` override claims first responder explicitly, preventing `simultaneousGesture` from blocking text input.
- Board store observes `.acpStoreRemoved` notification via `acpStoreRemovedSubscription` for auto-cleanup on delete.
