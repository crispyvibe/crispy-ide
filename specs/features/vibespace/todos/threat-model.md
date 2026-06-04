# Quick Todos & Sticky Notes — Threat Model

## Overview

F053 stores todo records and markdown thread messages in the encrypted libSQL store owned by the `crispyvibes-persistence` helper (shared with F049 Comments), reachable from the UI and from the agent CLI (Unix-domain socket → `CLICommandRouter`). This model covers the data path, the CLI surface, and markdown rendering. Reminders/notifications are out of scope (deferred).

## Trust Boundaries

- **UI ↔ store ↔ helper:** SwiftUI views → `VibeSpaceTodoStore` → `AgentConversationStore` → persistence-helper subprocess over stdio JSON-RPC. The DB is AES-256 encrypted at rest with a key from the macOS Keychain (per F049/Agent-Conversation-Persistence).
- **Agent ↔ CLI ↔ router:** agents inside Crispy terminals invoke `crispy todo …` → Unix socket (`CLISocketServer`, process-ancestry checked per F044) → `CLICommandRouter` → `VibeSpaceTodoStore`. Agents are semi-trusted automation; CLI input is untrusted data.
- **Markdown content:** todo `body` and `todo_messages.body` are user/agent-authored markdown rendered in SwiftUI.

## Attack Surfaces

- `todo.*` / `todo.message.*` CLI methods (params: title/body/project/id).
- Persistence RPC params written to SQL.
- Markdown bodies rendered in the detail pane and previews.

## Threats

### F053-T01: Markdown/link injection in body or thread messages
- **Vector:** A malicious agent (or pasted content) puts `<script>`, `<iframe>`, or `[x](javascript:…)` into a todo body or message.
- **Impact:** Low. Bodies are rendered with `AttributedString(markdown: .inlineOnlyPreservingWhitespace)` inside SwiftUI `Text` — no HTML/JS execution, no web context. Raw HTML tags render inert (or are dropped); there is no script execution path.
- **Likelihood:** Medium (agent-authored content is common).
- **Mitigation:** Inline-only markdown rendering (no HTML, no WKWebView). **Residual:** unlike F049 comments, the helper does not strip `javascript:`/dangerous schemes from todo bodies; a rendered link could carry a `javascript:`/`file:` scheme. macOS `Text` link activation routes through `openURL`, which would no-op/refuse such schemes, but parity hardening (server-side `sanitize_body` like comments) is recommended as a follow-up.

### F053-T02: Path / scope abuse via CLI
- **Vector:** CLI caller supplies an arbitrary `--project` path or spoofs `_env.project_path` to scope todos outside the active vibespace.
- **Impact:** Low. `project_path` is an opaque scoping label stored verbatim; todos are always keyed by the server-resolved active `vibespace_id`. `_env` is a convenience default, never authorization (F044-T03). No filesystem access is performed from the project path.
- **Mitigation:** Vibespace resolved server-side from app state; project path trimmed and used only as a scoping string; `todo.add`/`list` guard for an active vibespace.

### F053-T03: SQL injection
- **Vector:** Crafted title/body/id reaching SQL.
- **Impact:** None observed. All values bind via libsql `?N` parameters; the only dynamic SQL is the `WHERE`/`SET` clause assembly in `do_todo_list`/`do_todo_update`, which interpolates **column names/placeholders only** (from controlled enums), never user data.
- **Mitigation:** Parameterized queries throughout; no string interpolation of user values.

### F053-T04: Resource exhaustion / oversized input
- **Vector:** Very long titles/bodies or unbounded message counts.
- **Impact:** Low. `MAX_TITLE_CHARS=500` and `MAX_BODY_CHARS=10_000` reject oversized content; empty titles/bodies rejected. No per-todo message cap yet.
- **Mitigation:** Length validation at the handler. **Residual:** consider a per-todo message-count cap (as comments cap per file) in a follow-up.

### F053-T05: Orphaned / inconsistent thread data
- **Vector:** Messages for a deleted todo; messages for a non-existent todo.
- **Impact:** None. `todo_messages.todo_id` is a foreign key `ON DELETE CASCADE` with `PRAGMA foreign_keys = ON`; inserts for a missing todo are rejected, deletes cascade. Covered by a test.

### F053-T06: Cross-process socket exposure
- **Vector:** A non-descendant process connects to the CLI socket to write todos.
- **Impact:** Inherited from F044; the socket enforces a process-ancestry check and is bundle-scoped. No F053-specific exposure.

## Residual Risks

- No server-side sanitization of dangerous URL schemes in markdown bodies (T01) — low impact given inline-only rendering; parity with comments recommended.
- No per-todo message cap (T04).
- The capture HUD is app-local only (no global hotkey), so no background-input attack surface.

## NFR Compliance

- **SEC** — Encryption at rest (Keychain-derived key), parameterized SQL, process-ancestry-gated socket, no untrusted code execution (inline-only markdown). Follow-up: markdown URL-scheme sanitization parity.
- **REL** — FK cascade + validation prevent orphan/oversized rows; mutations route through one store; covered by Rust tests.
- **A11Y** — All sizes scale via `crispyvibesUIScale` (cmd+/-); colors from the theme palette honor contrast presets. Follow-up: VoiceOver labels on cards/composer.
- **PERF** — Indexed list queries (<20 ms target); shared date formatters.
- **TEST** — Persistence covered by `cargo test` (CRUD + thread cascade + validation); Swift verified via `xcodebuild` compile + manual run.
