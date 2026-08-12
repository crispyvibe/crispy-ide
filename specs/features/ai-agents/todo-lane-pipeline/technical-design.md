# Todo Lane Pipeline — Technical Design

## Overview

F060 is glue, deliberately thin: a bridge service above Todos (F053) and Vibe
Lanes (F059) plus small extensions to each side. Todos gains file links and
three pipeline fields; Vibe Lanes gains seeded carry-forward at task creation
and a state-change callback; the bridge owns triage orchestration, dispatch
mapping, and lifecycle fan-in. No new persistence process; todo-side data rides
the existing `crispyvibes-persistence` libSQL store (schema bump), lane-side
data is untouched.

## Architecture

```
                      ┌──────────────────────────────────────────────┐
                      │        TodoLanePipelineBridge (AppContainer) │
                      │  • dispatch(todo → lane task)                │
                      │  • task-state fan-in → thread messages       │
                      │  • TriageCoordinator (debounce, queue, guard)│
                      └──────┬──────────────────────┬────────────────┘
                             │                      │
        VibeSpaceTodoStore ◄─┘                      └─► VibeLaneTaskManager
        (F053, + links/triage/laneTaskID)               (F059, + initialCarryForward,
                             │                              + onTaskStateChanged)
                             │                      headless triage / refine sessions
                             └──────────────► ACPSessionRegistry (F011/F047)
                                              ContentViewerStore.openACPPane (refine UI)
```

- **`TodoLanePipelineBridge`** (new, `Features/AIAgents/` or `Shared/`): owns a
  weak-side reference to both stores; neither store references the bridge. All
  cross-feature behavior lives here so either feature builds and runs without it
  (F060-R10).
- **`TriageCoordinator`** (owned by the bridge): per-todo debounce timers,
  bounded FIFO queue, ≤2 concurrent headless runs via
  `ACPSessionRegistry`/`connectHeadless` (same substrate as
  `VibeLaneACPAgentRunner`, but its own capacity — never counted against the
  lane scheduler's cap).
- **Refine**: `ContentViewerStore.openACPPane(...)` (existing, lines ~133–145)
  creates + shows the session; seed prompt via
  `chatViewModel.sendProgrammatic(_:)` (ACPChatViewModel.swift:226). The bridge
  records the returned store/session ID on the todo (`refinementSessionID`) and
  on reopen resolves it through the registry, falling back to a fresh session.
- **Inline file search in todo composers**: embed
  `TerminalInlineTriggerController` (Features/Terminal/Support/…:14–485) as a
  `@StateObject` in `TodoDetailView` body editor and thread composer — the
  identical pattern already used by VibeCastView (line 28) and ACPChatView.
  `searchRoots`: the todo's project root, else all vibespace project roots.
  Insertion handler appends a file link (and inserts the path text where
  appropriate).
- **Opening links**: `ContentViewerStore.openFileInTab(at:line:column:projectIdentifier:)`
  (lines ~67–81); works for non-project paths (standalone `FileDocumentReference`).

## Data Flow

**Triage:** todo write → store emits change → bridge debounce (≥10 s) → skip
heuristics → snapshot `updatedAt` → enqueue → headless session with triage
prompt (todo content + links + lane catalog summary + time box) → structured
JSON reply parsed → generation check (`updatedAt` unchanged?) → persist
`triage` field + one `todo.message.add` (authorKind `agent`) → UI chips render
from the field. Discard on mismatch; requeue on subsequent settle.

**Refine:** user taps Refine → bridge builds seed prompt (todo + links + triage
JSON + interview instructions + the todo's ID and CLI usage guidance) →
`openACPPane` + `sendProgrammatic` → agent converses, writes back via
`crispy todo update / message add / file add` (socket → `CLICommandRouter` →
same store → live UI). Session ID persisted; content durability comes from the
todo, not the session.

**Dispatch (UI or CLI):** caller picks lane → bridge rejects if a non-terminal
`laneTaskID` exists → resolves the lane's first-checkpoint `requires` keys →
maps explicit overrides (CLI `--input`), dispatch-block sections (parsed from
body markdown headings), `triage.prefill`, and link paths onto keys →
surfaces unresolved keys (UI sheet / CLI error unless `--allow-unresolved`) →
`createTask(laneID:title:projectPath:agentID:initialCarryForward:)` → store
`laneTaskID` on the todo → thread message "dispatched". One bridge method,
two callers.

**Fan-in:** `VibeLaneTaskManager.onTaskStateChanged(taskID, old, new)` fires →
bridge looks up the todo by `laneTaskID` → posts one thread message per
transition (dedupe by `(taskID, newState, requestID?)`) → on `done`, apply the
completion setting.

## API / Command Contracts

### Vibe Lanes side (F059 extensions)

| API | Change |
|-----|--------|
| `VibeLaneTaskManager.createTask` | new `initialCarryForward: [String: String]? = nil`; stored on the task before engine start. Engine change: none — `VibeLaneEngine` already reads first-checkpoint requires from `task.carryForward ?? [:]` (VibeLaneEngine.swift:418–426). |
| `VibeLaneTaskManager.onTaskStateChanged` | new callback `(UUID, VibeLaneTaskState, VibeLaneTaskState) -> Void`, invoked after each persisted transition (same choke point as persistence writes). Multiple subscribers not needed; the bridge is the sole consumer for now. |
| Lane catalog summary | small pure helper exposing `[(laneID, name, description, firstCheckpointRequires: [key: askUser])]` for triage prompts and dispatch mapping. |

### Todos side (F053 extensions)

Persistence RPC (schema v5):

| Method | Params | Result |
|--------|--------|--------|
| `todo.file.add` | `id, todoId, path, line?` | created row |
| `todo.file.remove` | `todoId, path` | `{ deletedCount }` |
| `todo.file.list` | `todoId` | `{ files: [...] }` |
| `todo.pipeline.set` | `id, laneTaskID?, refinementSessionID?, triage?` (partial; JSON blob for triage) | `{ id, updatedAt }` |

`todo.show` includes `files` and pipeline fields. Limits: `MAX_LINK_PATH_CHARS
= 1_024`, `MAX_LINKS_PER_TODO = 32`, `MAX_TRIAGE_CHARS = 20_000` (structured
JSON, validated shape before store).

Agent CLI additions (`CLICommandRouterTodoHandlers`): `todo file add <id>
--path <path[:line]>`, `todo file remove <id> --path`, `todo file list <id>`,
`todo triage show <id>`, and `todo dispatch <id> --lane <name-or-id>
[--input key=value …] [--allow-unresolved]`. Path parsing splits a trailing
`:NN` into the line anchor; paths standardized like `--project` today.

`todo dispatch` is a thin passthrough: the router calls
`TodoLanePipelineBridge.dispatch(todoID:laneRef:overrides:allowUnresolved:)` —
the identical method the dispatch UI calls — so mapping priority (`--input` >
dispatch block > triage prefill > links), the one-active-task rule, and thread
fan-in are one code path with two callers. The router gains an
`attachTodoLanePipelineBridge(_:)` hook (mirroring
`attachVibeSpaceTodoStore`); when no bridge is attached the command reports
the feature as unavailable. Lane resolution accepts a lane UUID or a unique
case-insensitive name match; ambiguous names fail listing candidates. Without
`--allow-unresolved`, unresolved keys fail the command and are listed in the
JSON reply (`{ unresolved: ["repro", …] }`) so a refine agent can supply them
via `--input` and retry.

### Triage result shape (stored JSON)

```json
{
  "status": "done",
  "startedAt": "…", "finishedAt": "…", "todoUpdatedAtSnapshot": "…",
  "context": [{ "path": "…", "line": 42, "note": "…" }],
  "questions": [{ "text": "…", "carryForwardKey": "repro" }],
  "lanes": [{ "laneID": "…", "name": "…", "reason": "…", "score": 0.8 }],
  "laneShaped": true,
  "prefill": { "goal": "…" }
}
```

## State Management

### Schema (migrate_v5)

```sql
ALTER TABLE todos ADD COLUMN lane_task_id TEXT;            -- UUID of linked F059 task
ALTER TABLE todos ADD COLUMN refinement_session_id TEXT;
ALTER TABLE todos ADD COLUMN triage_json TEXT;             -- validated shape above
CREATE TABLE todo_files (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
  path TEXT NOT NULL, line INTEGER,
  created_at TEXT NOT NULL);
CREATE INDEX idx_todo_files_todo ON todo_files(todo_id, created_at);
```

Existing `file_path` column stays; on first link-write for a todo with a legacy
`file_path`, the store surfaces it as link index 0 (read-side merge — no
destructive migration).

### Swift models

`TodoFileLink { id, todoID, path, line?, createdAt }`;
`TodoTriage` (Codable mirror of the JSON above); `Todo` gains `laneTaskID?`,
`refinementSessionID?`, `triage?`, `fileLinks: [TodoFileLink]` (loaded with
`todo.show`, cached in `messagesByTodo`-style keyed storage on the store).
Missing-path state is computed at render (`FileManager.fileExists`), never
stored.

### Bridge state

In-memory only: debounce timers keyed by todo ID, triage queue, in-flight
generation snapshots, fan-in dedupe set `(taskID, state, requestID?)`. All
reconstructible from persisted todo/task state on relaunch; on bootstrap the
bridge reconciles: for each todo with a non-terminal `laneTaskID`, re-arm
fan-in; orphaned `laneTaskID`s (task deleted) are left in place and rendered as
"task no longer exists" in the detail pane.

## Dependencies (frameworks, libraries)

- Swift only: SwiftUI/AppKit, existing ACP session layer, existing conversation
  store RPC. No new SwiftPM packages.
- Rust (`crispyvibes-persistence`): reuse `libsql`, `serde_json`; v5 migration.
- Reused components: `TerminalInlineTriggerController` +
  `SpotlightComposePathSearchController` (F038), `openFileInTab` (F006),
  `openACPPane`/`sendProgrammatic` (F011), `connectHeadless` (F047).

## Platform Considerations

- Bridge is `@MainActor`; headless sessions and RPC I/O off-main as today.
- Wiring in AppContainer: construct bridge with `(todoStore, laneTaskManager,
  sessionRegistry, contentViewerStore)`; register the lane callback; attach the
  triage setting from vibespace settings.
- Headless triage/refine sessions must receive `CRISPY_SOCKET` in their
  environment so `crispy todo …` works — note `connectHeadless` currently
  passes `environment: nil` (VibeLaneACPAgentRunner.swift:105); triage/refine
  connect calls must set it (and F059 workers may adopt the same fix
  separately).

## Performance Constraints

- Triage adds zero latency to capture (fires ≥10 s post-settle, off the
  capture path entirely).
- Link chips: existence check is one `stat` per visible chip per render pass;
  memoize per (path, render tick) if list profiling demands.
- `todo_files` reads ride the indexed `todo_id` lookup; well under the F053
  20 ms list budget.
- Triage prompt stays small: lane catalog summary is names + descriptions +
  requires keys, never full lane definitions.

## Migration / Rollout Notes

- Schema v5 is additive; older builds ignore the new table/columns.
- Ship order (each independently releasable):
  1. **Dispatch bridge** — `initialCarryForward`, state callback, dispatch UI
     + `todo dispatch` CLI (same bridge method), fan-in, `laneTaskID`.
  2. **Triage** — coordinator, `triage_json`, chips, thread summary, settings.
  3. **Refine** — seeded pane, `refinementSessionID`, reattach.
  4. **File links** — `todo_files`, chips, drag-and-drop, F038 trigger in
     composers, CLI `todo file …`. (Trigger wiring may land alongside stage 1;
     it has no dependency on the others.)
- Gate stages 2–3 behind `ExperimentalFeaturesService` while tuning triage
  prompt quality and skip heuristics.
- Test plan: bridge unit tests with deterministic fakes for both stores
  (dispatch mapping, dedupe, generation guard, debounce via injected clock);
  Rust `cargo test` for v5 CRUD + cascade; existing F059 engine tests extended
  for seeded carry-forward.

## Known Gaps / Future

- Triage-discovered file links (currently candidates live in `triage.context`
  only; refine promotes them).
- Lane suggestion ranking from dispatch history.
- Rename/move tracking for links (accepted gap: missing-state chip).
- Multiple concurrent tasks per todo.
