# Whiteboards, Quick Todos & Mind Maps — Design

Status: proposal · rev. 2026-06-03

Three features, each file/record-backed with a CLI surface and visual presence:
- **F053 Quick Todos & Sticky Notes** — project-scoped todos with reminders. **(starting now — see `specs/features/vibespace/todos/`)**
- **F052 Whiteboarding** — Excalidraw `.excalidraw` editor. (next)
- **F054 Mind Maps** — interactive **Mind Elixir** `.mindmap` editor, not mermaid. (parked / deprioritized)

All slot into existing patterns; no parallel infrastructure. Next free prefix: F052 → F055.

---

## Decisions

| Feature | Renderer / store | On-disk format | Persistence | Effort |
|---------|------------------|----------------|-------------|--------|
| F052 Whiteboard | Excalidraw (MIT) in WKWebView | `.excalidraw` JSON | real files (Shelf draft → project) | HIGH (offline bundle) |
| F053 Todos | `VibeSpaceTodoStore` | — | SQLite via `crispyvibes-persistence` (comments pattern) | MED + HIGH reminders |
| F054 Mind Map | Mind Elixir (`mind-elixir-core`, MIT) in WKWebView | `.mindmap` JSON node tree | real files (Shelf draft → project) | LOW–MED |

- Mind maps require draggable nodes → mermaid rejected (static); tldraw rejected (paid production license). Mermaid stays only as a static Markdown preview.
- Whiteboards + mind maps share one lifecycle: **new file from template → app-global Shelf → move into project**. Build once, parameterize by extension.

---

## Reusable patterns (already in the codebase)

- **New file-backed editor (6 steps):** add `DocumentType` case → extension detection (`MarkdownViewModelDetection`) → handle in `MarkdownViewModelFileLifecycle.openFile` → `EditorContentPlugin.makeView` (WKWebView host) → register in `EditorPluginRegistry.plugins` → mark editable for autosave.
- **WKWebView bridge (`MarkupRenderedEditor`):** JS→Swift via `WKScriptMessageHandler`; Swift→JS via `evaluateJavaScript`; edits → `userDidEdit` → `DocumentBuffer` → `AutosaveScheduler`. `NotebookWebViewArbiter` = persistent re-parented web view + locked navigation. CSP is offline (`connect-src 'none'`).
- **Shelf + move-to-project:** `ShelfStore.addFiles` / `retargetFile` + `ContentViewerStore.retargetFileSystemLocation` + `FileSystemProviding.moveItem` (already used by `ContentViewShelfActions.renameShelfFile`). Project = longest-prefix path match.
- **CLI:** add `CLICommandRouter{X}Handlers.swift` + `CommandRegistration` entries + `DomainInfo`; add `clap` subcommand → method mapping in `crispyvibes-cli`. `comments.*` is the precedent for scoped/persisted commands.
- **Quick-create:** post a `Notification.Name` from toolbar pill / `OptionsMenuCommands` / `AppShortcutAction` / welcome dock; `ContentView` listens. Strings in `AppStrings`.

**Gaps (must build):** no `UserNotifications` (reminders); no `NSStatusItem`/menu-bar and app quits on last window close (always-on capture); no freeform zoom/pan canvas (native canvas only).

---

## F052 — Whiteboarding

- **Create:** "New Whiteboard" (toolbar/menu/shortcut) writes an empty `.excalidraw` into a shelf-staging dir, adds to `ShelfStore`, opens it.
- **Edit:** `ExcalidrawEditorPlugin` hosts an offline Excalidraw build (`Resources/ExcalidrawRuntime/`); scene JSON ↔ `DocumentBuffer`/autosave via bridge messages.
- **Move to project:** drag Shelf row → `moveItem` + `retargetFile` + `retargetFileSystemLocation`.
- **CLI (optional v1):** `whiteboard.new|list|open|move`.
- **Risks:** offline bundle (~2–5 MB, disable CDN fonts/collab; own CSP page); narrow `allowingReadAccessTo` + add `decidePolicyFor`; offline-only (no multiplayer).

## F053 — Quick Todos & Sticky Notes

- **Model:** `Todo { id, vibespaceID, projectPath?, title, body?, colorTag, createdAt, updatedAt, dueAt?, reminderAt?, completedAt? }`.
- **Store/persistence:** `VibeSpaceTodoStore` → new `todos` table in `crispyvibes-persistence` (comments pattern). JSON fallback possible for v1.
- **UI:** sidebar panel of sticky cards scoped to focused project (+ "all in vibespace"); quick-capture popover.
- **Reminders (net-new):** `ReminderScheduling` protocol wrapping `UNUserNotificationCenter` + delegate in `AppDelegate`; persist notification IDs per todo.
- **CLI:** `todo.add|list|complete|reopen|update|remove|remind`; project from `_env.project_path`.
- **Risks:** reminders need permission flow + app-lifecycle decision (`.accessory` to stay resident); menu-bar capture is optional, not v1.

## F054 — Mind Maps

- **Edit:** `MindmapEditorPlugin` hosts Mind Elixir (`Resources/MindmapRuntime/`). `window.crispyvibesSetMindmap(json)` on load; `operation` event → `mindmapChanged` → `userDidEdit` → autosave. Drag/rename/add/collapse handled by the library. Theme-map Crispy tokens.
- **Format:** `.mindmap` = JSON node tree. **Own + version the schema** (don't pass Mind Elixir's native format straight through) so a library upgrade can't break old files.
- **Lifecycle:** same Shelf → move-to-project as F052.
- **CLI:** `mindmap.new` (title/outline), `mindmap.add-node --parent <id>`, `mindmap.list`, `mindmap.render` (base64 PNG/SVG). Accept outline/raw-JSON, not many flags.
- **Risks:** verify no runtime CDN/font fetch under `connect-src 'none'`; pin version; same web-view hardening as F052.
- **Future (optional, HIGH):** native SwiftUI canvas as a 3rd `VibeSpaceCanvasMode` — unifies mind maps + whiteboard + free-floating notes. Reuse `BoardInteractionController` FSM pattern only (not its grid metrics/hit-testing).

---

## Cross-cutting

- **Persistence scope:** board/mindmap content = real files; open-tab session = per-vibespace `editor-session.json`; todos + reminder IDs = SQLite helper.
- **CLI contract:** validate params (`invalidParams`) → resolve `_env`/focused context → service call → `.ok`/`.error`; project ops validate path containment; `_env` ≠ authorization. New error codes go in `CLIErrorCode` + spec table. Doc each as `commands-{whiteboard,todo,mindmap}.md`.
- **Security:** offline bundles only; each web app in its own CSP page with local fonts; narrow file access + navigation policy; lazy notification permission.
- **Registry/docs:** allocate F052/F053/F054 in `INDEX.md` (next prefix → F055); domains D4 (whiteboard, mind-maps), D2/D9 (todos); full 4-doc set per `CONVENTION.md`; gate behind `ExperimentalFeaturesService`.
- **UI:** consider one "New" menu (Terminal / Whiteboard / Mind Map / Sticky Note) instead of separate toolbar buttons.

---

## Phasing

**Priority: F053 Todos first. F052 Whiteboarding follows. F054 Mind Maps parked.**

1. **F053 Todos** — `VibeSpaceTodoStore` + sticky-note panel + `todo.*` CLI (core CRUD, no reminders). **Shipped (implemented):** dockable surface (VibeCast model) + per-todo rich-text notes & flat threads + instant-capture HUD (⌃⌘T) with project picker & success feedback + palette theming & `crispyvibesUIScale`. Docs: `specs/features/vibespace/todos/`.
2. **F053 Reminders** — `UserNotifications` + app-lifecycle decision; optional menu-bar capture.
3. **F052 Whiteboarding** — offline Excalidraw + plugin + Shelf/move-to-project.
4. **Parked: F054 Mind Maps** — Mind Elixir `.mindmap` editor + `mindmap.*` CLI (deprioritized).
5. **Optional** — native unified canvas (§F054 future).

---

## Open questions

1. Reminders: keep Crispy resident in the menu bar, or best-effort while running?
2. Whiteboard: offline-only (no multiplayer) acceptable for v1?
3. Mind maps: web editor sufficient long-term, or native canvas eventually for whiteboard parity?
4. Todos: sidebar cards for v1, or canvas-pinned sticky notes up front (forces native canvas earlier)?
5. Whiteboard: cross-project references allowed, or single-project ownership after move?
6. Bundle budget: ~5–8 MB (Excalidraw; Mind Elixir adds ~tens of KB) acceptable?
7. Todo storage: SQLite helper vs. per-vibespace JSON for v1?

---

## Code anchors

| Concern | Location |
|---------|----------|
| Plugin registry / file-type | `Features/Editor/Views/MarkdownEditorPlugins.swift`; `…/ViewModels/MarkdownViewModelDetection.swift` |
| WKWebView bridge | `Features/Editor/Views/MarkupRenderedEditor.swift`; Notebook arbiter (locked nav) |
| Autosave / buffer | `Features/Editor/Services/AutosaveScheduler.swift`, `DocumentBuffer` |
| Shelf / move / retarget | `Features/Home/Models/ShelfStore.swift`; `Features/Home/Actions/ContentViewShelfActions.swift`; `Protocols/FileSystemProviding.swift`; `ContentViewerStore.retargetFileSystemLocation` |
| Project association | `ExplorerItemDropPlanner` (longest-prefix) |
| Canvas modes | `Models/VibeSpaceDisplayTypes.swift`; `ContentViewProjectCanvas.swift`; `Models/BoardInteractionController.swift` |
| Persistence | JSON: `Data/Persistence/AppPersistenceDataStore.swift`, `VibeSpacePersistenceStore.swift`, `LayoutPersistenceService.swift` · SQLite: `rust/crispyvibes-persistence`, `VibeSpaceCommentStore` (F049) |
| CLI | `Features/AgentCLI/CLICommandRouter*.swift`; `rust/crispyvibes-cli/src/main.rs` |
| Quick-create | `Features/Home/Views/ContentViewToolbar.swift`; `App/CrispyVibesApp.swift`; `AppShortcutAction` + `App/AppDelegate.swift` |
| New runtimes to bundle | `Resources/ExcalidrawRuntime/` (Excalidraw, MIT); `Resources/MindmapRuntime/` (Mind Elixir, MIT) |
