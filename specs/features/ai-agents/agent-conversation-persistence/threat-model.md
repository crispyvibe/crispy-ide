# Agent Conversation Persistence — Threat Model

## Overview

Agent Conversation Persistence stores all agent conversation history in an encrypted libSQL database managed by a Rust subprocess (`crispyvibes-persistence-helper`). The feature is transport-neutral — it persists conversations from any `AgentSessionProtocol` implementation (ACP, Claude Code direct, Codex direct). Every agent interaction is a thread; sessions are transient connections. The schema includes extensibility fields (`thread_kind`, `parent_thread_id`, `metadata` JSON, `tags` JSON array) for future thread types. The encryption key lives in the macOS Keychain and is delivered to the Rust process via stdin pipe at startup. This document identifies threats arising from the persistence layer, the inter-process communication channel, the on-disk database, the extensible metadata fields, and the export path.

## Trust Boundaries

```
┌──────────────────────────────────────────────────────┐
│  CrispyVibes Swift Process (trusted)                       │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ AgentConversation │  │ KeychainStore            │  │
│  │ Store             │  │ (macOS Keychain)         │  │
│  └────────┬──────────┘  └──────────┬───────────────┘  │
│           │ JSON-RPC               │ key load         │
│           │ stdin/stdout           │                  │
│           │ (req/resp with IDs)    │                  │
└───────────┼────────────────────────┼──────────────────┘
            │                        │
┌───────────┴────────────────────────┘
│
│  ┌──────────────────────────────────────────────────┐
│  │  macOS Keychain                                  │
│  │  Service: com.crispyvibe.app.agent-persist               │
│  │  Backend: standard macOS Keychain                │
│  └──────────────────────────────────────────────────┘
│
┌───────────┴──────────────────────────────────────────┐
│  Rust Persistence Helper (subprocess)                │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ JSON-RPC Server  │  │ libSQL (encrypted via     │  │
│  │ (stdin/stdout)   │  │ EncryptionConfig)         │  │
│  │ (req/resp pairs) │  │ AES-256 at rest           │  │
│  └──────────────────┘  └──────────┬───────────────┘  │
└───────────────────────────────────┼───────────────────┘
                                    │
                        ┌───────────┴───────────┐
                        │  Database File        │
                        │  ~/Library/App Sup/   │
                        │  CrispyVibes/acp/           │
                        │  conversations.db     │
                        └───────────────────────┘

                        ┌───────────────────────┐
                        │  Exported Files       │
                        │  (user-chosen path,   │
                        │   decrypted plaintext)│
                        └───────────────────────┘
```

**Boundary 1: Swift app ↔ Rust subprocess.** Communication over stdin/stdout pipe using request/response pairs with IDs. The pipe is private to the parent-child process pair. The encryption key crosses this boundary exactly once at startup.

**Boundary 2: Rust process ↔ libSQL database file.** The Rust process holds the decrypted connection. The file on disk is AES-256 encrypted via `EncryptionConfig`. An attacker with file access but no key sees ciphertext.

**Boundary 3: macOS Keychain ↔ Swift app.** The standard macOS Keychain stores the encryption key under an app-specific service name. The app does not request Data Protection keychain attributes.

**Boundary 4: User ↔ exported files.** Export produces decrypted plaintext (Markdown or JSON) at a user-chosen path. Once written, the file is outside the encryption boundary.

## Attack Surfaces

| Surface | Entry Point | Exposure |
|---------|-------------|----------|
| Stdin pipe (init message) | `AgentConversationStore` → Rust helper | Encryption key in transit |
| Database file on disk | `~/Library/Application Support/CrispyVibes/acp/conversations.db` | Encrypted conversation data |
| macOS Keychain entry | `com.crispyvibe.app.agent-persist` / `db-encryption-key` | 256-bit AES key |
| JSON-RPC message stream | stdin/stdout between Swift and Rust (req/resp pairs) | SQL parameters, message content |
| Export file output | User-chosen file path | Decrypted conversation plaintext (full history) |
| Rust process memory | `crispyvibes-persistence-helper` address space | Encryption key, decrypted data |
| Debug/log output | Console, log files, Xcode output | Potential key or content leakage |
| Database schema (migrations) | Startup migration path | Schema corruption, injection |
| ACK/error response stream | stdout from Rust to Swift | Health state, error details |
| Extensible metadata fields | `metadata` JSON, `tags` JSON array on threads | Injection, oversized payloads, malformed JSON |

## Threats

### F040-T01: Encryption Key Exposure via Process Inspection

- **Vector:** An attacker with local access attaches a debugger (`lldb`), `dtrace` probe, or `Instruments` to the Rust subprocess and reads the encryption key from memory or the init message being parsed.
- **Impact:** Full decryption of the conversation database. All stored messages, tool calls, and embeddings exposed.
- **Likelihood:** Low — requires local access with the same user account or root. macOS SIP and TCC restrict debugger attachment to processes the user owns.
- **Mitigation:**
  - The key is zeroed from the init message buffer immediately after extraction (vision NFR: key zeroing).
  - After init, the key exists only inside the libSQL connection state, not in application-accessible variables.
  - macOS System Integrity Protection prevents unauthorized debugger attachment in production builds.
  - Hardened runtime entitlement on signed builds disables `DYLD_INSERT_LIBRARIES` and debugger attachment by default.

### F040-T02: Database File Theft Without Keychain Access

- **Vector:** An attacker copies `conversations.db` from a backup, disk image, or file share. Without the Keychain entry, they attempt offline decryption.
- **Impact:** Without the key, the file is AES-256 ciphertext. No conversation content is recoverable.
- **Likelihood:** Medium — database file is a regular file in Application Support, accessible to any process running as the user.
- **Mitigation:**
  - libSQL encrypts the entire database with AES-256 via `EncryptionConfig`.
  - The encryption key is stored in the standard macOS Keychain under an app-specific service name. The app does not use Data Protection keychain attributes, so Developer ID releases do not require restricted keychain entitlements or an embedded provisioning profile.
  - Without the key, brute-forcing AES-256 is computationally infeasible.

### F040-T03: Encryption Key Logged in Debug Output

- **Vector:** A developer or CI build inadvertently logs the JSON-RPC init message (which contains the hex key) to console, Xcode output, or a log file.
- **Impact:** Key exposed in plaintext in logs. Anyone with log access can decrypt the database.
- **Likelihood:** Medium — logging stdin/stdout for debugging is a common development practice.
- **Mitigation:**
  - The init message containing the hex key must never be logged, even at debug level (vision NFR: no logging of secrets).
  - The Rust helper's JSON-RPC logging must explicitly exclude the `init` method payload.
  - The Swift side must not log outgoing pipe writes for the init call.
  - Code review checklist item: no `print`/`os_log`/`NSLog` of the init message or key material.

### F040-T04: Pipe Interception Between Swift and Rust

- **Vector:** A malicious process on the same machine intercepts the stdin/stdout pipe between the Swift app and the Rust helper to read the encryption key or conversation data in transit.
- **Impact:** Key exposure (from init message) or conversation content exposure (from subsequent messages).
- **Likelihood:** Low — Unix pipes between a parent and child process are private file descriptors. They are not visible in the filesystem and cannot be opened by other processes without `ptrace` or root access.
- **Mitigation:**
  - Pipes are created by `Process()` / `posix_spawn` and are private to the parent-child pair. No filesystem path exists for the pipe.
  - The key is sent exactly once at startup, minimizing the interception window.
  - macOS SIP prevents `ptrace` attachment from unauthorized processes.
  - An attacker who can `ptrace` the process already has equivalent access to the Keychain (same user context), making pipe interception redundant.

### F040-T05: SQL Injection via JSON-RPC Parameters

- **Vector:** A crafted message text, thread title, or activity payload containing SQL metacharacters is passed through JSON-RPC and interpolated into a SQL query in the Rust helper.
- **Impact:** Arbitrary SQL execution — data exfiltration, schema modification, or data destruction within the database.
- **Likelihood:** Low — the Rust helper controls all SQL. The attack requires a compromised agent or malicious message content that flows through the Swift layer unmodified.
- **Mitigation:**
  - All SQL queries in the Rust helper must use parameterized statements (`?` placeholders). No string interpolation of user-supplied values into SQL.
  - The `libsql` Rust crate's `execute()` and `query()` methods accept parameter arrays, enforcing parameterization at the API level.
  - Input validation on the Swift side: thread titles truncated to a maximum length, message text validated as valid UTF-8.

### F040-T06: Path Traversal in Export File Paths

- **Vector:** A crafted or manipulated export file path (e.g., containing `../` or symlinks) causes the export to write decrypted conversation data to an unintended location — overwriting system files or writing to a shared/public directory.
- **Impact:** Decrypted conversation data (full history, not capped) written to an attacker-controlled or publicly accessible location.
- **Likelihood:** Low — export uses `NSSavePanel`, which returns a user-selected, sandboxed-scoped URL.
- **Mitigation:**
  - Export file paths are obtained exclusively through `NSSavePanel`, which enforces macOS sandbox and permission scoping.
  - The app must not accept export paths from agent processes or JSON-RPC messages — only from direct user interaction.
  - Resolve symlinks on the export path before writing and verify the resolved path is within a user-writable directory.

### F040-T07: Denial of Service via Unbounded Message Storage

- **Vector:** A runaway agent session or malicious agent floods the persistence layer with messages, consuming disk space and degrading database performance.
- **Impact:** Disk exhaustion, degraded search performance, potential app instability.
- **Likelihood:** Medium — a long-running agent session with verbose output could produce tens of thousands of messages.
- **Mitigation:**
  - Full history is retained in the DB (no pruning on write), but the 2,000 message cap on UI reads bounds timeline rendering cost.
  - Auto-cleanup setting (7/30/90 days) prunes old threads on app startup.
  - The Rust helper should enforce a maximum single-message payload size (e.g., 1 MB) and reject oversized writes with an error response.
  - Monitor database file size; log a warning if it exceeds a configurable threshold (e.g., 500 MB).
  - ACK/error tracking on the Swift side detects if the helper becomes unresponsive under load.

### F040-T08: Stale Resume Cursor Replay

- **Vector:** An attacker or bug replays a previously used resume cursor to an agent provider, potentially causing the agent to re-execute actions from a prior session or enter an inconsistent state.
- **Impact:** Duplicate tool calls, repeated file modifications, or agent confusion leading to incorrect behavior.
- **Likelihood:** Low — resume cursors are opaque blobs returned by the agent provider. Replay requires access to the database or the pipe.
- **Mitigation:**
  - Resume cursors are stored as opaque JSON blobs — CrispyVibes does not interpret or validate them.
  - The agent provider is responsible for cursor validity. Providers like Claude and Codex reject stale or replayed cursors with an error.
  - On cursor rejection, the system disconnects and presents the failure reason to the user with the option to start a fresh session. It does NOT silently fall back to a fresh session — the user must confirm.
  - `session/resume` (lightweight) is preferred over `session/load` (full replay) when the agent supports it, reducing the window for stale cursor issues.
  - Both `session/resume` and `session/load` include `cwd` and `mcpServers` per the ACP spec, ensuring the agent has the correct working context.
  - Cursors are scoped to a specific `provider_session_id`; using a cursor from session A in session B is a protocol error handled by the provider.
  - The `capabilities` JSON (including `sessionCapabilities.resume` and `loadSession`) records what the agent supports, preventing mismatched resume attempts.

### F040-T09: Cross-Build Data Leakage (crispyvibes vs crispyvibes-local)

- **Vector:** The production build (`com.crispyvibe.app`) and the local development build (`com.crispyvibe.app.local`) share the same database or encryption key, allowing a developer's test conversations to leak into production or vice versa.
- **Impact:** Test data visible in production, or production conversation data accessible to debug builds with relaxed security.
- **Likelihood:** Medium — developers routinely run both builds on the same machine.
- **Mitigation:**
  - Keychain service name is resolved from `Info.plist` — each build variant uses a distinct service name (vision NFR: build isolation).
  - Database path includes the app support directory: `~/Library/Application Support/Crispy/acp/` vs `~/Library/Application Support/CrispyLocal/acp/`.
  - Separate keys + separate database files = complete isolation. Neither build can decrypt the other's database.

### F040-T10: Memory Disclosure of Encryption Key in Rust Process

- **Vector:** A memory safety bug in the Rust helper (unsafe block, FFI boundary, or dependency vulnerability) leaks the encryption key from process memory — via a crash dump, core file, or memory disclosure vulnerability.
- **Impact:** Encryption key exposed, enabling database decryption.
- **Likelihood:** Low — Rust's memory safety guarantees reduce this risk significantly. The key is held inside libSQL's C layer after init.
- **Mitigation:**
  - The Rust helper zeroes the key from its own buffers immediately after passing it to `libsql` (vision NFR: key zeroing).
  - Minimize `unsafe` blocks in the persistence helper. Audit all `unsafe` usage in code review.
  - Disable core dumps for the helper process (`setrlimit(RLIMIT_CORE, 0)`).
  - Pin dependency versions and audit `libsql` crate updates for security advisories.

### F040-T11: Corrupt Database from Crash During Write

- **Vector:** The Rust helper or the host app crashes (kill -9, power loss, OOM) while a write transaction is in progress, leaving the database in a corrupt state.
- **Impact:** Partial or total loss of conversation history. App may fail to start the persistence layer on next launch.
- **Mitigation:**
  - libSQL uses WAL (Write-Ahead Logging) mode with ACID transactions (vision NFR: crash recovery). A crash mid-write loses at most the in-flight message, not the database.
  - On startup, libSQL automatically replays or discards incomplete WAL entries.
  - If the database fails integrity checks on open, the Rust helper reports an error and the Swift layer falls back to ephemeral mode (vision NFR: graceful degradation).
  - Periodic `PRAGMA integrity_check` can be run as a background maintenance task.
  - ACK/error tracking means the Swift side knows which writes were not acknowledged and can log them.

### F040-T12: Export File Contains Sensitive Data Left on Disk

- **Vector:** A user exports a conversation to Markdown or JSON. The exported file is decrypted plaintext sitting on disk — potentially in a shared folder, cloud-synced directory, or unencrypted volume. The user forgets about it. Export includes full history (not capped at 2,000).
- **Impact:** Conversation content (including tool calls, file changes, and potentially sensitive code snippets) exposed to anyone with access to the export location.
- **Likelihood:** Medium — export is an explicit user action, but users may not consider the security implications of the export location.
- **Mitigation:**
  - Export is the only path for data to leave the encrypted database — this is by design and clearly communicated.
  - `NSSavePanel` defaults to the user's Documents folder, not a shared or cloud-synced location.
  - The export confirmation dialog should remind the user that the exported file is unencrypted.
  - The app does not track or manage exported files after creation — the user is responsible for their lifecycle.
  - Consider adding a "Sensitive content" warning header in exported Markdown files.

### F040-T13: Health Monitoring Bypass via Spoofed ACK

- **Vector:** A compromised or buggy Rust helper sends ACK responses for writes that actually failed, causing the Swift side to believe persistence is healthy when data is being lost.
- **Impact:** Silent data loss — the user believes conversations are persisted but they are not.
- **Likelihood:** Very low — requires compromise of the helper binary itself.
- **Mitigation:**
  - The helper binary is bundled in the signed app bundle — tampering is detected by macOS code signing.
  - Periodic read-back verification (e.g., on thread open, verify the last few messages exist) provides a secondary health check.
  - The Rust helper is built from source in the same CI pipeline — no third-party binary trust.

### F040-T14: Metadata Injection via Malformed JSON in Extensibility Fields

- **Vector:** A compromised agent, malicious plugin, or crafted input supplies a `metadata` JSON object or `tags` JSON array containing excessively large payloads, deeply nested structures, or values designed to exploit JSON parsing vulnerabilities in downstream consumers. Since `metadata` and `tags` are opaque to the persistence layer, malicious content could propagate to any future feature that reads these fields.
- **Impact:** Denial of service via oversized metadata consuming disk space or memory during parsing. Potential for injection if a future consumer interpolates metadata values into queries, commands, or UI without sanitization. Deeply nested JSON could cause stack overflow in recursive parsers.
- **Likelihood:** Medium — `metadata` and `tags` are open-ended by design, and agent-supplied content flows through them. The attack surface grows as more features consume these fields.
- **Mitigation:**
  - The Rust helper MUST validate that `metadata` is a well-formed JSON object and `tags` is a well-formed JSON array of strings before storing. Malformed JSON is rejected with an error response.
  - `metadata` is capped at 64 KB. `tags` is capped at 100 entries with individual tags capped at 256 characters. Oversized payloads are rejected.
  - JSON parsing depth MUST be limited (e.g., max 32 levels of nesting) to prevent stack overflow from deeply nested structures.
  - The persistence layer stores `metadata` and `tags` as opaque TEXT — it does not interpret or execute the contents. Future consumers MUST treat these fields as untrusted input and apply their own validation.
  - `metadata` and `tags` are stored via parameterized SQL — no risk of SQL injection from their contents.
  - Exported JSON includes `metadata` and `tags` verbatim — the export warning (F040-T12) covers this data leaving the encrypted boundary.

## Residual Risks

| Risk | Rationale |
|------|-----------|
| **Local privileged attacker** | An attacker with root access or the same user account can read Keychain entries, attach debuggers, and access process memory. No application-level mitigation can fully defend against a compromised local account. macOS account security is the primary control. |
| **libSQL encryption implementation** | The encryption correctness depends on libSQL's `EncryptionConfig` implementation of AES-256. A vulnerability in libSQL's crypto layer would affect all stored data. Mitigated by tracking libSQL security advisories and pinning to audited versions. **Spike required** to verify `EncryptionConfig` works for local-only embedded databases before committing. |
| **Export file lifecycle** | Once exported, conversation data (full history) is outside the app's control. Users may store exports in insecure locations. The app can warn but cannot enforce post-export security. |
| **Memory-resident key** | The encryption key must exist in process memory while the database is open. A sophisticated memory-scraping attack on the Rust process could theoretically extract it. Mitigated by minimizing key copies and disabling core dumps. |
| **Agent-supplied content** | Messages and tool call payloads originate from agent processes of various transport types. While SQL injection is mitigated by parameterized queries, the stored content itself may contain sensitive data (API keys, credentials) that the user discussed with the agent. This data is encrypted at rest but visible in search results and exports. |
| **Extensible metadata propagation** | The `metadata` and `tags` fields are opaque to the persistence layer. While size and well-formedness are validated at write time, the semantic content is not inspected. A future consumer that trusts metadata values without sanitization could introduce vulnerabilities. Mitigated by documenting that all consumers must treat these fields as untrusted input. |

## NFR Compliance

| Vision NFR | Threat Coverage | Status |
|------------|-----------------|--------|
| **Encryption key delivery via stdin pipe** | F040-T01, F040-T04 | Key delivered over private parent-child pipe; not visible in `ps`; sent exactly once |
| **Key zeroing after extraction** | F040-T01, F040-T10 | Rust helper zeros init buffer immediately; key lives only in libSQL connection state |
| **No logging of secrets** | F040-T03 | Init message excluded from all log levels; code review enforced |
| **Standard macOS Keychain service isolation** | F040-T02 | Key stored under an app-specific service without restricted Data Protection entitlements |
| **Build isolation (Info.plist service name)** | F040-T09 | Separate Keychain entries and database paths per build variant |
| **Graceful degradation** | F040-T11 | Persistence failure → ephemeral mode; no user-blocking errors |
| **Crash recovery (WAL mode)** | F040-T11 | ACID transactions; at most one in-flight message lost on crash |
| **Message ordering (monotonic sequence)** | F040-T08 | Sequence numbers prevent ordering ambiguity; resume cursors scoped to sessions |
| **Full history, capped UI reads** | F040-T07 | All messages retained for search/export; timeline bounded at 2,000 on read |
| **Async queued writes with ACK/error** | F040-T13 | Request/response pairs with IDs; health monitoring detects unhealthy helper |
| **EncryptionConfig (spike required)** | F040-T02 | Uses `EncryptionConfig` not `PRAGMA hexkey`; needs verification for local-only DBs |
| **Transport-neutral persistence** | F040-T05 | All agent types persisted through same parameterized SQL path |
| **Capability-based resume** | F040-T08 | Resume strategy determined by capabilities; prevents mismatched resume attempts |
| **Unified thread model** | F040-T08 | Sessions are transient connections; no "expired" state exposed to user; silent reconnection reduces user-initiated replay errors |
| **Extensible schema validation** | F040-T14 | `metadata` and `tags` validated for well-formedness, size-capped, stored via parameterized SQL; consumers must treat as untrusted |
