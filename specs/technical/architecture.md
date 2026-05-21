# Architecture

Crispy uses a feature-based project structure with a UI + ViewModel + Service split.

## Project Structure

```text
crispyvibes/
  App/                          ← app entry, delegate, diagnostics, updates
  ContentView.swift             ← root app shell and vibespace layout bindings
  Protocols/                    ← shared protocols (project root level)
  Data/
    Persistence/                ← vibespace, layout, and app-state persistence
    Services/                   ← image scanning and raster persistence
    Repositories/               ← (reserved)
  Features/
    ACP/                        ← Agent Conversation Protocol: agent sessions, chat UI, transport, vibespace conversation management (14+ files)
    ContentViewer/              ← file preview/edit tab management
    Editor/                     ← markdown/code/html editing
    Home/                       ← dashboard, welcome, walkthrough, shelf
    Local/                      ← local project session implementation (split from ProjectSession)
    Remote/                     ← SSH connection, remote projects, SFTP-backed explorer and file services
    Settings/                   ← app and vibespace settings UI + auth
    Shared/                     ← cross-feature shared views
    Terminal/                   ← terminal sessions, board, presets
    VibeCast/                   ← VibeCast feature
    VibeSpace/                  ← explorer, canvas, settings, pane workers, file watchers
  Models/                       ← app data structures and state types
  Shared/                       ← shared components and support types
  Themes/                       ← theme palette, syntax themes, resolver
  Resources/                    ← runtime assets, icons, GhosttyRuntime, MarkdownRuntime
```

## App Layer

- `CrispyVibesApp.swift`: app entry point, app-level command wiring, and About link (`https://crispyvibe.com`)
- `AppDelegate.swift`: macOS service registration, window chrome, defaults observation
- `AppContainer.swift`: dependency injection container
- `RootView.swift`: root view wrapper
- `ContentView.swift`: root app shell, vibespace dashboard, and rail layout bindings
- `AppFirstRunExperience.swift`: first-run defaults and layout constants

## Composition Root

`AppContainer` is a struct that holds every shared service and provides factory methods for all major types. `makeDefault()` is the single construction site where all concrete implementations are wired:

- `AppPersistenceDataStore` — low-level persistence store
- `VibeSpacePersistenceStore` — vibespace-specific persistence, wraps `AppPersistenceDataStore`
- `VibeSpaceManagementService` — vibespace CRUD operations, wraps `VibeSpacePersistenceStore`
- `LayoutPersistenceService` — persisted layout dimensions and canvas modes
- `TerminalServices` — container for terminal subsystem services
- `TerminalViewModelDependencies` — preset diagnostics, shortcut store, and terminal services bundled for terminal view models
- `PaneWorkerFactory` — closure `(PaneWorkerKind) -> PaneWorkerExecuting`, defaults to creating `PaneWorkerClient` instances
- `VibeSpaceTerminalBoardStandaloneRegistry` — manages standalone terminal view models per vibespace
- `EditorDetachedWindowManager` — manages detached editor windows
- `ShelfStore` — pinned Shelf file state and persistence for the Files sidebar
- `CrispyVibesThemeManager` — application theme state
- `ExperimentalFeaturesService` — feature flag management
- `VibeSpaceInteractionService` — wraps `NSVibeSpace` for opening URLs and revealing files in Finder

Factory methods on `AppContainer` create all stateful objects: `makeAppShellStore()`, `makeVibeSpaceCatalogStore()`, `makeMarkdownViewModel()`, `makeFolderExplorerViewModel()`, `makeTerminalViewModel()`, `makeSplitViewStore()`, `makeContentViewerStore()`, `makeProjectSession(rootURL:vibespaceID:)`, `makeVibeSpaceState(id:name:projectURLs:)`, and others. Each factory injects the required dependencies from the container's stored services.

`makeContentViewDependencies()` is the top-level factory that assembles all objects needed by `ContentView` into a `ContentViewDependencies` struct, including the `ContentViewStableDependencies` object that holds coordinators.

## State Management

- `AppShellStore` — `@MainActor ObservableObject` that owns navigation state: `activeVibeSpaceID`, `isShowingHome`, `activeSurface` (vibespace settings or app settings), `activeModalSheet` (clone repository or vibe space creation), `vibespaceSidebarTab`, and `isVibeSpaceSidebarVisible`. Provides methods for vibespace selection, home/sidebar toggling, surface presentation, and modal sheet management.

- `VibeSpaceCatalogStore` — `@MainActor ObservableObject` that holds the array of open `VibeSpaceState` objects. Provides indexed and ID-based lookup, mutation helpers (`mutateActiveVibeSpace`, `mutateVibeSpace`), and lifecycle methods for replacing, removing, clearing, and shutting down vibespaces. On removal, it shuts down project sessions and releases terminal board standalone entries.

- Feature-level state is managed by individual `ObservableObject` classes: `VibeSpaceSourceControlViewModel`, `ContentViewerStore`, `SplitViewStore`, `ShelfStore`, `ProjectActivityTracker`, `FeatureWalkthroughController`, `StackedRailTerminalStore`, and `CrispyVibesThemeManager`.

## ViewModel Layer

Feature-scoped ViewModels live under each `Features/<name>/ViewModels/`:

- `FolderExplorerViewModel` (`Features/VibeSpace/ViewModels/Explorer/`): folder tree, selection state, file operations, project session orchestration
- `ProjectSession` (`Features/VibeSpace/ViewModels/Explorer/`): runtime state for one opened project. `ProjectSession` is behind a `ProjectProviding` protocol abstraction with `LocalProjectSession` and `RemoteProjectSession` implementations. The vibespace state stores `[AnyProjectSession]` (type-erased wrappers) instead of concrete `[ProjectSession]`.
- `VibeSpaceSourceControlViewModel` (`Features/VibeSpace/ViewModels/`): vibespace-level source control
- `MarkdownViewModel` (`Features/Editor/ViewModels/`): document type detection, load/save, markdown autosave
- `TerminalViewModel` (`Features/Terminal/ViewModels/`): terminal tab model, session ownership, presets, shortcuts, startup
- `ContentViewerStore` (`Features/ContentViewer/ViewModels/`): content viewer tab management
- `EditorGroupStore` (`Features/ContentViewer/ViewModels/`): editor group/split coordination
- `SplitViewStore` (`Features/ContentViewer/ViewModels/`): split view state
- `VibeCastStore` (`Features/VibeCast/ViewModels/`): VibeCast feature state

## Service Layer

### Data / Persistence (`Data/Persistence/`)

- `VibeSpaceManagementService`: vibespace CRUD, project management, per-project config, session state, app-state persistence
- `VibeSpacePersistenceStore`: low-level file I/O for vibespace/project JSON files, HMAC signing, Keychain integration
- `LayoutPersistenceService`: per-vibespace rail position/sizes, canvas mode, terminal board layout, editor session state (stored in per-vibespace `layout.json`)
- `AppPersistenceDataStore`: app-level file persistence (app directory, signed file wrappers)
- `VibeSpaceSessionStateService`: vibespace session state coordination

### Data / Services (`Data/Services/`)

- `RasterImagePersistenceService`: raster image save/export
- `MarkdownImageCandidateScannerService`: image candidate discovery for markdown

### Terminal (`Features/Terminal/Services/`)

- `GhosttyTerminalEngine`: primary terminal rendering engine via GhosttyKit
- `TerminalSession`: terminal process lifecycle, engine selection (Ghostty primary, SwiftTerm fallback)
- `TmuxService`: tmux availability detection, session lifecycle (create/kill/list), server option management
- `TerminalFocusCoordinator`: terminal focus management across views
- `TerminalPresetServices`: installed CLI tool detection and preset management
- `TerminalSessionOwnershipCoordinator`: terminal view ownership transfer between containers

### Editor (`Features/Editor/Services/`)

- `TextProcessorService`: command execution for rephrase/research text services
- `PaneWorkerExecutorEditor`: editor pane worker operations

### VibeSpace (`Features/VibeSpace/Services/`)

- `DirectoryWatcher` (`FileSystem/`): filesystem change monitoring
- `GitHeadWatcher` (`FileSystem/`): git HEAD ref monitoring
- `PaneWorkerExecutor` (`PaneWorker/`): pane worker execution infrastructure
- `PaneWorkerExecutorExplorer` (`PaneWorker/`): explorer-specific worker operations
- `PaneWorkerExecutorGit` (`PaneWorker/`): git-specific worker operations

### Remote (`Features/Remote/`)

- `SSHConnection`: app-managed SSH and SFTP lifecycle
- `SSHConnectionManager`: shared remote-connection coordination
- `SSHPortForwardService`: SSH local port-forward lifecycle
- `RemoteProjectSession`: SSH-backed project session wiring
- `RemoteFolderExplorer`: lazy SFTP-backed folder explorer
- `SFTPFileSystemProvider`: remote file-system operations
- `SFTPFileContentProvider`: remote file content reads, writes, and preview materialization contract support
- `RemoteConnectionStatusPopover`: vibespace-scoped remote status and retry UI
- `VibeSpaceSidebarSessionBrowser`: vibespace-scoped local/remote tmux discovery and grouping

### Settings (`Features/Settings/Services/`)

- `CognitoAuthService`: Cognito-based authentication
- `CognitoAuthSecurity`: auth security utilities

### Pane Worker Internals

`PaneWorkerExecuting` is the protocol defining `restart()` and `execute(_:arguments:timeout:)` for all subprocess operations (git, file system, editor). `PaneWorkerClient` is the concrete implementation, an `actor` that supports two execution modes: in-process (direct call to `PaneWorkerExecutor`) and subprocess (spawns the app binary with `--pane-task` flag, communicates via stdin/stdout JSON). Execution mode is resolved from the `CRISPYVIBES_PANE_WORKER_EXECUTION_MODE` environment variable, defaulting to subprocess in the app process. `PaneWorkerKind` has three cases: `.explorer`, `.editor`, `.terminal`. `PaneWorkerMethod` enumerates all supported operations (file CRUD, git status/diff/branch/commit/clone/history, ping).

### Terminal Services Internals

`TerminalServices` is a `@MainActor` class that groups terminal subsystem dependencies: `TerminalFocusCoordinator` (tracks which terminal session has focus), `TerminalDiagnosticsSnapshot` (captures terminal diagnostic state), `TerminalHostOwnershipCoordinator` (manages terminal host ownership), `VibeSpaceInteractionService` (for opening URLs from terminals), and a lazy `GhosttyTerminalRuntime`.

### Experimental Features (`Data/Services/`)

- `ExperimentalFeaturesService`: observable feature flag provider backed by UserDefaults KVO; protocol `ExperimentalFeaturesProviding` for injection/testing. Registered in `AppContainer`.

Current flags include tmux integration behavior, ACP diagnostics, and Terminal Insight. Remote SSH is a regular app feature and is no longer hidden behind an experimental feature flag.

## ContentView Decomposition Status

`ContentView.swift` is the root app shell. It is extended by files in `Features/Home/Views/` and `Features/VibeSpace/Views/Canvas/`:

| File | Location | Responsibility |
|------|----------|---------------|
| `ContentView.swift` | Root | Main body, state declarations, lifecycle, notification wiring |
| `ContentViewCatalog.swift` | Home/Views | VibeSpace catalog load/persist/shutdown |
| `ContentViewCatalogVibeSpaceActions.swift` | Home/Views | External open, shelf, vibespace CRUD, project add/remove |
| `ContentViewCatalogRecentSnapshots.swift` | Home/Views | Recent vibespace snapshot display |
| `ContentViewComputed.swift` | Home/Views | Layout constants |
| `ContentViewShelf.swift` | Home/Views | Shelf sidebar section UI |
| `ContentViewToolbar.swift` | Home/Views | Toolbar items, window title sync |
| `ContentViewWelcomeActions.swift` | Home/Views | Welcome screen action cards |
| `ContentViewWelcomeRecents.swift` | Home/Views | Recent vibespaces list on welcome screen |
| `ContentViewWelcomeSurface.swift` | Home/Views | Welcome/empty state layout, creation sheet |
| `ContentViewProjectCanvas.swift` | VibeSpace/Views/Canvas | Project rail, split view, unified terminal/VibeCast spotlight with swipe-to-switch |
| `ContentViewVibeSpaceHydration.swift` | VibeSpace/Views/Canvas | Terminal hydration, startup config |
| `ContentViewVibeSpaceActions.swift` | VibeSpace/Views/Canvas | Project focus, terminal navigation, diagnostics |
| `ContentViewVibeSpaceSettingsActions.swift` | VibeSpace/Views/Canvas | VibeSpace/app settings sheets |
| `ContentViewVibeSpaceCloneActions.swift` | VibeSpace/Views/Canvas | Clone repository actions |
| `ContentViewVibeSpaceSidebar.swift` | VibeSpace/Views/Canvas | VibeSpace sidebar navigation |
| `ContentViewTerminalLinkPreview.swift` | VibeSpace/Views/Canvas | Terminal link preview handling |

### Known Coupling

> **Update:** ContentView has been further decomposed into coordinators: `HomeCatalogCoordinator` under `Features/Home/`, and `VibeSpaceCanvasActionsCoordinator`, `VibeSpaceCanvasFileOpenUseCase`, etc. under `Features/VibeSpace/Canvas/`.

ContentView still owns too many concerns: navigation state, vibespace lifecycle, shelf/file open, terminal orchestration, settings, welcome flow, recent snapshots, external open handling, and 15+ `onReceive` notification handlers.

### Remaining Refactor Steps

1. **Extract `AppCommandRouter`** — replace `onReceive` handlers with a typed command enum and central dispatcher.
2. **Extract `VibeSpaceCatalogStore`** — move `vibespaces`, `activeVibeSpaceID`, catalog load/persist into an `ObservableObject`. ~~Partially done~~ **Done** — now exists at `App/VibeSpaceCatalogStore.swift`. `VibeSpaceManagementService` owns persistence; `VibeSpaceCatalogStore` owns the in-memory catalog state.
3. **Relocate Shelf UI next to explorer code** — Shelf now renders inside the Files sidebar, but its section view still lives under `Features/Home`.
4. **Extract `AppCoordinator`** — own the top-level navigation enum and wire child stores.

## Brand Icons and Tool Presentation

CLI tool presets (Kiro, Claude, Codex, Gemini, OpenCode, Copilot) use brand SVG icons stored in `Resources/Assets.xcassets/ToolIcons/`. Icons are rendered in:
- Terminal `Tools` dropdown menu
- VibeSpace creation agent grid

Monochrome icons (Kiro, Codex, OpenCode, Copilot) use `template` rendering intent for automatic light/dark theme adaptation. Brand-colored icons (Claude, Gemini) use `original` rendering intent.

`CLITerminalPresentation.isCustomIcon` flag controls whether `Image(name)` (asset catalog) or `Image(systemName:)` (SF Symbol) is used. `TextServiceCLIProfile.iconName` and `.isCustomIcon` provide convenience access.

## VibeSpace Creation Trust Mode

The VibeSpace creation flow (screen 3, agent step) includes trust mode selection:
- VibeSpace-level `Full Trust` toggle appears below the agent grid when the selected profile supports it
- Per-project inline trust toggle appears next to each project's CLI override picker
- Trust mode flows through `VibeSpaceCLISelection.trustMode` into `VibeSpaceCreationResult`
- Trust mode resets to `.standard` when the selected profile changes

## Unified Terminal Spotlight

`TerminalSpotlightState` (on `ContentView`) is the single spotlight system for both terminals and VibeCast. Source enum:
- `.persistent(terminalViewModel:tabID:)` — project terminal tab
- `.transient(session:)` — temporary terminal
- `.vibeCast` — VibeCast view

Swipe-to-switch uses `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` to capture two-finger trackpad gestures at app level when spotlight is active. The flat swipe sequence is built from all terminal tabs across all projects plus VibeCast. The monitor is installed on spotlight appear and removed on dismiss.

The duplicate VibeCast spotlight overlay that was in `VibeSpaceTerminalOnlyView` has been removed. VibeCast tile double-click now routes through `onVibeCastSpotlightRequested` to the unified system.

## Dependency Injection Mechanics

All dependencies are injected via initializer parameters or factory closures. `AppContainer.makeDefault()` constructs every concrete service and passes them into the `AppContainer` struct. Factory methods on `AppContainer` capture `self` to inject stored services into the objects they create. `VibeSpaceState` receives a `projectSessionFactory` closure so it can create `AnyProjectSession` instances without knowing about `AppContainer`. `VibeSpaceSourceControlViewModel` receives a `PaneWorkerFactory` closure. `EditorDetachedWindowManager` and `VibeSpaceTerminalBoardStandaloneRegistry` receive view model factory closures.

No global singletons are used in production dependency flow. `TerminalFocusCoordinator`, `TerminalDiagnosticsSnapshot`, and `GhosttyTerminalRuntime` are instantiated as regular objects owned by `TerminalServices`, which is owned by `AppContainer`.

## View Composition

`RootView` is a thin wrapper that passes `AppContainer` to `ContentView`. `ContentView` is the root view that owns all top-level `@StateObject` properties. Its `init` calls `appContainer.makeContentViewDependencies()` and unpacks the returned `ContentViewDependencies` struct into individual `@StateObject` wrappers.

`ContentView.body` gates on a disclaimer acceptance check. Once accepted, it renders `notificationAwareContent`, which layers notification observers (for menu commands and external open requests) on top of `lifecycleAwareContent`, which layers `onAppear`/`onDisappear`/`onChange` handlers on top of `styledContent`, which applies theming, color scheme, and file drop handling around `shellContent` → `mainContent`. `mainContent` switches between vibespace settings, app settings, home empty state, or the project canvas based on `AppShellStore` state. Shelf content renders inside the Files sidebar rather than as its own canvas.

## Coordinator Pattern

Coordinators encapsulate multi-step operations that span multiple stores and services:

- `VibeSpaceHydrationCoordinator` (`ObservableObject`) — manages vibespace loading, hydration from persistence, active vibespace transitions, and editor session state persistence. Receives `AppShellStore`, `VibeSpaceCatalogStore`, `LayoutPersistenceService`, `SplitViewStore`, and `ContentViewerStore`.

- `HomeCatalogCoordinator` — manages home screen catalog loading, external open request draining, and vibespace creation flows. Receives `AppContainer`, `AppShellStore`, `VibeSpaceCatalogStore`, `VibeSpaceManagementService`, `LayoutPersistenceService`, `ShelfStore`, `FeatureWalkthroughController`, `TerminalSpotlightCoordinator`, `TerminalLinkPreviewCoordinator`, and `VibeSpaceHydrationCoordinator`.

- `VibeSpaceCanvasActionsCoordinator` — handles vibespace canvas operations: project focus/navigation, terminal focus cycling, view mode switching (detailed/terminal-only), VibeCast toggling. Receives `AppShellStore`, `VibeSpaceCatalogStore`, `VibeSpaceManagementService`, `VibeSpaceHydrationCoordinator`, `TerminalLinkPreviewCoordinator`, `VibeSpaceInteractionService`, `ShelfStore`, `SplitViewStore`, `ContentViewerStore`, and `LayoutPersistenceService`.

- `TerminalSpotlightCoordinator` (`ObservableObject`) — manages terminal spotlight search presentation and dismissal. Receives `TerminalDiagnosticsSnapshot`.

- `TerminalLinkPreviewCoordinator` (`ObservableObject`) — manages terminal link preview presentation and dismissal. Receives an `openExternalURL` closure from `VibeSpaceInteractionService`.

- `VibeSpaceCloneRepositoryCoordinator` (`ObservableObject`) — manages the clone repository sheet flow.

All coordinators are created inside `ContentViewStableDependencies`, which is itself created by `AppContainer.makeContentViewDependencies()`. `ContentViewStableDependencies` is an `ObservableObject` held as a `@StateObject` in `ContentView`, ensuring coordinators survive view re-renders.

## Context Structs

Context structs provide scoped, read-oriented access to `AppShellStore` and related state for specific view regions, avoiding direct store exposure:

- `HomeShellContext` — wraps `AppShellStore` for home screen views. Exposes navigation queries (`hasActiveVibeSpace`, `canReturnToVibeSpace`, `vibespaceSidebarTab`), active side menu item resolution, and delegated mutation methods (show/dismiss home, select vibespaces, present settings, show/hide sidebar). Accessed via `ContentView.homeShell`.

- `VibeSpaceShellContext` — wraps `AppShellStore` for vibespace-level views. Exposes `activeVibeSpaceID`, `sidebarTab`, clone repository sheet binding, app settings presentation state, and delegated mutation methods. Accessed via `ContentView.vibespaceShell`.

- `VibeSpaceViewContext` — aggregates active vibespace session data (vibespace, focused project, project lists, unresolved project count, source control selection, canvas mode, rail position) with `LayoutPersistenceService` for rail size bindings. Accessed via `ContentView.vibespaceView`.

## Engineering Guardrails

### File Splitting Rules
- File over 400 LOC: must be considered for split
- Primary type over 200 LOC: split by responsibility
- One primary type per file (exceptions: small helpers)
- SwiftUI view files: keep heavy logic out of `body`

### Design Pattern Rules
- Use vertical feature slices under `Features/*`
- Use `Repository` at persistence boundaries
- Use `UseCase` for domain actions with non-trivial orchestration
- Use `Coordinator/Router` for navigation/workflow state
- Use `Adapter` for legacy APIs or external tool interfaces

### Dependency Injection Rules
- Single composition root: `App/AppContainer.swift`
- Protocols in `Protocols/`
- Concrete implementations in `Data/*`
- Feature view models depend on interfaces/use-cases, not concrete services
- Initializer injection first; environment injection only for app-wide shared dependencies

### Storage and Data Layer Rules
- One canonical vibespace/session metadata write location under app support
- No vibespace/session metadata reads or writes from per-project paths
- File I/O goes through persistence services/repositories, not SwiftUI views

### Performance Safety Rules
- Measure before and after each major split for affected flows
- Keep terminal/session/render hot paths concrete (`final`/`struct`) where practical
- Avoid dynamic indirection in tight loops
- Avoid heavy sync work in SwiftUI render path
- Regression thresholds: no regression > 5% for app startup, vibespace hydration, terminal tab switch, or steady-state memory
