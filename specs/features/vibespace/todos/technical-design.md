# Quick Todos & Sticky Notes — Technical Design

## Overview

Todos are vibespace/project-scoped records with per-todo markdown notes and a flat message thread, stored in the encrypted libSQL database owned by the `crispyvibes-persistence` helper (the same store as File Comments, F049). A `VibeSpaceTodoStore` (`@MainActor ObservableObject`) drives both the dockable surface and the agent CLI. The surface docks exactly like VibeCast (a `ContentViewerTabKind` case). Instant capture is a hotkey-invoked SwiftUI overlay. No new persistence process; reminders deferred (columns reserved).

## Architecture

```
TodoQuickCaptureOverlay (⌃⌘T HUD) ─┐
TodosSurfaceView (master/detail) ──┼─► VibeSpaceTodoStore ──► AgentConversationStore.send("todo.*")
todo.* CLI (CLICommandRouterTodoHandlers) ┘        │                     (stdio JSON-RPC, AES-256)
                                          @Published todos / messagesByTodo        │
                                                                                   ▼
                                                              crispyvibes-persistence (libSQL: todos, todo_messages)
```

- **`VibeSpaceTodoStore`** — wraps `AgentConversationStore`; `@Published private(set) todos` + `messagesByTodo`; late-binds the active vibespace via `bindActiveVibeSpace(provider:resolver:)`; async CRUD (`add/update/setCompleted/delete`), thread (`addMessage/refreshMessages/messages(forTodo:)`), `refresh`; `changes` subject + `lastErrorMessage`.
- **Surface views** (`Features/Todos/Views/`): `TodosSurfaceView` (`HSplitView` master↔detail), `TodosPanelView` (list: scope toggle, quick-add, selectable cards), `TodoDetailView` (title, markdown notes edit/preview, author-grouped thread, composer), `MarkdownText` (inline-markdown renderer), `TodoQuickCaptureOverlay` (capture HUD).
- **Store exposure** — `TodoStoreEnvironment` adds a `vibespaceTodoStoreEnvironment` `EnvironmentKey`; `RootView` injects `appContainer.vibespaceTodoStore` app-wide so the content viewer builds the surface without threading the store through canvas layers.
- **Rust** — `handlers_todos.rs` over `todos`/`todo_messages`; registered in `main.rs` `dispatch`.

## Data Flow

UI/CLI → `VibeSpaceTodoStore` method → resolve active vibespace ID → `conversationStore.send(method:params:)` → helper validates + writes → store refreshes its cache and emits `changes`. Because mutations route through one store, CLI writes surface live in the UI.

## API / Command Contracts

### Persistence RPC (`main.rs` dispatch)
| Method | Params | Result |
|--------|--------|--------|
| `todo.add` | `id, vibespaceId, projectPath?, title, body?, colorTag?, filePath?` | created row |
| `todo.list` | `vibespaceId, projectPath?, status(active\|completed\|all)` | `{ todos: [...] }` |
| `todo.update` | `id, title?, body?, colorTag?, filePath?` (partial) | `{ id, updatedAt }` |
| `todo.complete` | `id, completed: bool` | `{ id, status, completedAt, updatedAt }` |
| `todo.delete` | `id` | `{ id, deletedCount }` |
| `todo.show` | `id` | todo row + `messages: [...]` |
| `todo.message.add` | `id (msg), todoId, body, authorKind(user\|agent)` | created message |
| `todo.message.list` | `todoId` | `{ messages: [...] }` |

JSON keys are camelCase. Limits: `MAX_TITLE_CHARS=500`, `MAX_BODY_CHARS=10_000`. Bodies/titles validated (non-empty, length); `authorKind`/`status` enum-checked.

### Agent CLI (`crispyvibes-cli` → Swift handlers)
`todo add --text [--project --body --color --file]`, `todo list [--project --status]`, `todo complete|reopen|remove <id>`, `todo update <id> [--text --body --color]`, `todo show <id>`, `todo message add <id> --text`. Project context resolves from the explicit `--project`/`project` param else `_env.project_path` (trimmed); vibespace from the attached store. Swift handlers in `CLICommandRouterTodoHandlers.swift`; registered in `CLICommandRouter.commandRegistry`; `todo` domain in `CLICommandRouterSystemHandlers`.

## State Management

### Schema (`migrate_v4`, `CURRENT_VERSION = 4`)
```sql
CREATE TABLE todos (
  id TEXT PRIMARY KEY, vibespace_id TEXT NOT NULL, project_path TEXT,           -- NULL = vibespace-level
  title TEXT NOT NULL, body TEXT, color_tag TEXT, file_path TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed')),
  due_at TEXT, reminder_at TEXT,                                                -- reserved (reminders phase)
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, completed_at TEXT);
CREATE INDEX idx_todos_vs ON todos(vibespace_id, status, updated_at DESC);
CREATE INDEX idx_todos_vs_project ON todos(vibespace_id, project_path, status, updated_at DESC);
CREATE TABLE todo_messages (
  id TEXT PRIMARY KEY, todo_id TEXT NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
  body TEXT NOT NULL, author_kind TEXT NOT NULL DEFAULT 'user' CHECK (author_kind IN ('user','agent')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE INDEX idx_todo_messages_todo ON todo_messages(todo_id, created_at);
```
`PRAGMA foreign_keys = ON` is set by the helper, so message inserts for a missing todo are rejected and todo deletes cascade.

### Swift models
`Todo { id, vibespaceID, projectPath?, title, body?, colorTag?, filePath?, status, dueAt?, reminderAt?, createdAt, updatedAt, completedAt? }` and `TodoMessage { id, todoID, body, authorKind, createdAt, updatedAt }`, each with an `init?(json:)` decoder. Store holds `@Published private(set) todos` and `messagesByTodo: [String: [TodoMessage]]`; thread grouping (same author within 5 min) and relative timestamps are computed in `TodoDetailView`.

## Dockable surface integration (VibeCast model)

`ContentViewerTabKind.todos` added and handled in every exhaustive switch (`ContentViewerTab` title/icon/drag-payload, `EditorGroupStore`, `ContentViewerView`, `SplitPaneContentView`, `ContentView.resolveOwningProjectPath`). `ContentViewerStore.openTodos()` opens the tab; `ContentViewerView` builds `TodosSurfaceView` from the env store + `focusedProjectRootPath` (single-pane `todosContent` and split-pane `todosViewFactory`). The toolbar checklist button posts `.toggleTodos`; `ContentView`'s handler consults `ContentSurfacePolicy.surface(for: .todos, mode:)` (see ADR-003) and routes by surface: in board mode (`.spotlight`) it calls `presentTodosSpotlight()` — a `TerminalSpotlightState.Source.todos` overlay rendering `TodosSurfaceView` in the spotlight card; otherwise (`.detailTab`) it calls `VibeSpaceCanvasActionsCoordinator.toggleTodos()` → `present(.todos)`, which switches to detailed and activates-existing-or-opens the tab. Capture: `quickCaptureTodo` `AppShortcutAction` (default ⌃⌘T, editable) → `AppDelegate` posts `.quickCaptureTodo` → `ContentView` shows `TodoQuickCaptureOverlay` (hosted on `body`, not the deep `notificationAwareContent` chain, to avoid type-checker blow-up).

## Theming & scaling

Views read `@Environment(\.appThemePalette)` (`accentColor`, `canvasBackgroundColor`, `canvasSecondaryBackgroundColor`, `borderColorValue`, `successColor`, `primary/secondary/tertiaryTextColor`), `@Environment(\.crispyvibesTheme)` (`radius(_:)`), and `@Environment(\.crispyvibesUIScale)` (`textSize/iconSize/spacing/chromeSize`). Selection = accent-tint fill + leading bar; agent messages get a subtle accent rule; capture HUD uses `.ultraThinMaterial`. No hardcoded colors; all sizes scaled.

## Dependencies (frameworks, libraries)

- Swift: SwiftUI/AppKit; existing `AgentConversationStore` RPC; no new SwiftPM packages.
- Rust (`crispyvibes-persistence`): `libsql`, `serde_json`, `anyhow` (reused). `crispyvibes-cli`: `clap`, `serde_json` (reused).

## Platform Considerations

- Store calls `@MainActor`; helper I/O off-main via the conversation-store transport.
- AppContainer wiring: construct `VibeSpaceTodoStore(conversationStore:)`, `attachVibeSpaceTodoStore` on the router, `bindActiveVibeSpace` from `makeContentViewDependencies`; `RootView` env injection.
- Capture hotkey is app-local (`NSEvent.addLocalMonitorForEvents`) — fires only when the app is active (a global hotkey would need Accessibility permission; out of scope).

## Performance Constraints

- List a project's todos < 20 ms (indexed by `vibespace_id, project_path, status`).
- Reuse one `ISO8601DateFormatter`/`RelativeDateTimeFormatter` for thread timestamps.

## Migration / Rollout Notes

- Schema bump to v4 (todos + todo_messages) runs automatically on `init`; additive, older builds ignore the tables.
- Gate behind `ExperimentalFeaturesService` while stabilizing.
- Verified: `cargo test` (persistence, 9 passing incl. thread cascade), `cargo build` (CLI), full `xcodebuild -scheme crispyvibes-local` succeeds.

## Known Gaps / Future

- Vibespace-switch auto-refresh of the open surface (hook parity with comments).
- Board-tile presentation (a dedicated `TileContentKind` alongside ACP/Browser); the spotlight presentation now ships (board mode floats Todos as `TerminalSpotlightState.Source.todos`, chosen by `ContentSurfacePolicy`).
- Session restore of the `.todos` tab (parity with VibeCast — not persisted).
- Reminders (`due_at`/`reminder_at` + `UserNotifications`).
- Server-side markdown sanitization parity with comments (see threat-model F053-T01).
