# Architectural Rules & Conventions

This document captures the verified patterns and rules used in the CrispyVibes codebase. All examples are drawn from production code. Follow these conventions when writing new code.

---

## Dependency Injection

**No singletons in production code.** All dependencies flow through initializers or factory closures.

`AppContainer` is the composition root. It is a plain `struct` that holds every shared service and exposes `make*()` factory methods for creating view models, stores, and coordinators. The single entry point is `AppContainer.makeDefault()`, called once in `CrispyVibesApp`.

```swift
// AppContainer.swift
struct AppContainer {
    let appPersistenceStore: AppPersistenceDataStore
    let vibespacePersistenceStore: VibeSpacePersistenceStore
    let terminalServices: TerminalServices
    let paneWorkerFactory: PaneWorkerFactory
    // ... every shared service listed as a stored property

    @MainActor
    func makeTerminalViewModel() -> TerminalViewModel {
        TerminalViewModel(
            dependencies: terminalViewModelDependencies,
            worker: makePaneWorker(pane: .terminal)
        )
    }

    @MainActor
    static func makeDefault() -> AppContainer { ... }
}
```

Rules:
- Never call `SomeService.shared` from production code. Some types retain a `static let shared` for legacy or convenience, but `AppContainer.makeDefault()` creates fresh instances and injects them explicitly.
- Every dependency a type needs is received through its `init`. No type reaches out to a global to get a collaborator.
- `AppContainer` itself is passed into coordinators that need to create further objects (e.g., `HomeCatalogCoordinator`, `ContentViewStableDependencies`).

### Service Containers

Group related services into a container struct when they travel together:

```swift
// TerminalServices — bundles terminal-specific collaborators
@MainActor
final class TerminalServices {
    let focusCoordinator: TerminalFocusCoordinator
    let diagnosticsSnapshot: TerminalDiagnosticsSnapshot
    let hostOwnershipCoordinator: TerminalHostOwnershipCoordinator
    let vibespaceInteraction: VibeSpaceInteractionService
    lazy var ghosttyRuntime = GhosttyTerminalRuntime()

    init(
        focusCoordinator: TerminalFocusCoordinator,
        diagnosticsSnapshot: TerminalDiagnosticsSnapshot,
        hostOwnershipCoordinator: TerminalHostOwnershipCoordinator,
        vibespaceInteraction: VibeSpaceInteractionService
    ) { ... }
}
```

```swift
// TerminalViewModelDependencies — flat struct for TerminalViewModel init
struct TerminalViewModelDependencies {
    var presetDiagnostics: TerminalPresetAvailabilityDiagnostics
    var shortcutStore: TerminalShortcutStore
    var terminalServices: TerminalServices
}
```

```swift
// ProjectSessionDependencies — flat struct for ProjectSession init
struct ProjectSessionDependencies {
    var layoutPersistence: LayoutPersistenceService
    var vibespaceManagement: VibeSpaceManagementService
    var vibespaceID: UUID?
    var folderExplorerViewModelFactory: @MainActor () -> FolderExplorerViewModel
    var terminalViewModelFactory: @MainActor () -> TerminalViewModel
    var detachedWindowManager: EditorDetachedWindowManaging
}
```

---

## State Management

### Enum-Based State Machines for Navigation

Navigation state is modeled with enums. `AppShellStore` uses `ActiveSurface` and `ActiveModalSheet` to represent mutually exclusive UI states:

```swift
@MainActor
final class AppShellStore: ObservableObject {
    enum ActiveSurface: Equatable {
        case vibespaceSettings(UUID)
        case appSettings(AppSettingsCategory)
    }

    enum ActiveModalSheet: Equatable {
        case cloneRepository
        case vibeSpaceCreation
    }

    @Published var activeSurface: ActiveSurface?
    @Published var activeModalSheet: ActiveModalSheet?
}
```

State transitions happen through named methods, never by setting properties directly from views:

```swift
func showHome() {
    activeSurface = nil
    isShowingHome = true
}

func presentVibeSpaceSettingsForActiveVibeSpace() {
    guard let activeVibeSpaceID else { return }
    activeSurface = .vibespaceSettings(activeVibeSpaceID)
    isShowingHome = false
}
```

### `private(set)` with Mutation-Through-Methods

Collection state uses `@Published private(set)` and exposes mutation through named methods. External code cannot assign to the collection directly:

```swift
@MainActor
final class VibeSpaceCatalogStore: ObservableObject {
    @Published private(set) var vibespaces: [VibeSpaceState] = []

    func replaceDisplayedVibeSpace(with vibespace: VibeSpaceState) {
        shutdownDisplayedVibeSpaces()
        vibespaces = [vibespace]
    }

    func mutateVibeSpace(id vibespaceID: UUID, _ update: (inout VibeSpaceState) -> Void) {
        guard let vibespaceIndex = vibespaces.firstIndex(where: { $0.id == vibespaceID }) else { return }
        update(&vibespaces[vibespaceIndex])
    }

    func removeDisplayedVibeSpace(at index: Int) -> VibeSpaceCatalogRemovalResult {
        let removedVibeSpace = vibespaces.remove(at: index)
        removedVibeSpace.shutdownProjects()
        terminalBoardStandaloneRegistry.release(vibespaceID: removedVibeSpace.id)
        return VibeSpaceCatalogRemovalResult(
            removedVibeSpaceID: removedVibeSpace.id,
            fallbackVibeSpaceID: vibespaces.first?.id
        )
    }
}
```

The `mutateVibeSpace(id:_:)` / `mutateActiveVibeSpace(for:_:)` pattern gives callers `inout` access to a single vibespace without exposing the array.

---

## Context Structs

Context structs provide scoped, read-only access to stores for specific view layers. They wrap a store and expose only the subset of state and actions that a particular view needs.

```swift
@MainActor
struct HomeShellContext {
    private let store: AppShellStore

    init(store: AppShellStore) {
        self.store = store
    }

    var hasActiveVibeSpace: Bool { store.activeVibeSpaceID != nil }
    var vibespaceSidebarTab: FolderExplorerViewModel.SidebarTab { store.vibespaceSidebarTab }

    func showHome() { store.showHome() }
    func dismissHome() { store.dismissHome() }
    // ... only the actions Home needs
}
```

```swift
@MainActor
struct VibeSpaceShellContext {
    private let store: AppShellStore

    init(store: AppShellStore) {
        self.store = store
    }

    var activeVibeSpaceID: UUID? { store.activeVibeSpaceID }
    var sidebarTab: FolderExplorerViewModel.SidebarTab { store.vibespaceSidebarTab }

    func showVibeSpace(_ vibespaceID: UUID) { store.showVibeSpace(vibespaceID) }
    func dismissSurface() { store.dismissSurface() }
    // ... only the actions VibeSpace canvas needs
}
```

Context structs are created as computed properties on `ContentView`:

```swift
extension ContentView {
    var homeShell: HomeShellContext {
        HomeShellContext(store: appShellStore)
    }
    var vibespaceShell: VibeSpaceShellContext {
        VibeSpaceShellContext(store: appShellStore)
    }
}
```

Rules:
- Context structs are `@MainActor` value types (structs).
- They hold a `private let store` reference and expose computed properties and forwarding methods.
- They may provide SwiftUI `Binding` values derived from the store.
- They hide store properties and methods that the consuming view should not access.

---

## Coordinator Pattern

Coordinators are `@MainActor final class` types conforming to `ObservableObject`. They orchestrate complex multi-step workflows that span multiple stores and services.

```swift
@MainActor
final class VibeSpaceHydrationCoordinator: ObservableObject {
    private let appShellStore: AppShellStore
    private let vibespaceCatalogStore: VibeSpaceCatalogStore
    private let layoutPersistence: LayoutPersistenceService
    private let splitViewStore: SplitViewStore
    private let contentViewerStore: ContentViewerStore

    private var vibespaceHydrationTask: Task<Void, Never>?
    private var editorSessionSaveWorkItem: DispatchWorkItem?

    init(
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        layoutPersistence: LayoutPersistenceService,
        splitViewStore: SplitViewStore,
        contentViewerStore: ContentViewerStore
    ) { ... }

    func cancelVibeSpaceHydration() {
        vibespaceHydrationTask?.cancel()
        vibespaceHydrationTask = nil
    }

    func scheduleVibeSpaceTerminalHydration(for vibespaceID: UUID) {
        cancelVibeSpaceHydration()
        // ...
        vibespaceHydrationTask = Task { [weak self] in
            await self?.hydrateVibeSpaceTerminals(for: vibespaceID, targets: preparation.targets)
        }
    }
}
```

Other coordinators: `HomeCatalogCoordinator`, `VibeSpaceCanvasActionsCoordinator`, `TerminalSpotlightCoordinator`, `TerminalLinkPreviewCoordinator`, `VibeSpaceCloneRepositoryCoordinator`.

Rules:
- All dependencies injected through `init`.
- `Task` closures always capture `[weak self]`.
- Tracked tasks are stored in properties (e.g., `vibespaceHydrationTask`) and cancelled explicitly before starting new ones.
- `DispatchWorkItem` references are stored and cancelled before scheduling replacements.

---

## Use Case Pattern

Use cases are `@MainActor struct` types that contain pure business logic with no stored state. They take all dependencies as method parameters.

```swift
@MainActor
struct VibeSpaceCanvasFileOpenUseCase {
    private let projectRoutingUseCase = VibeSpaceProjectRoutingUseCase()

    func wireProjectFileOpenHandler(
        _ project: ProjectSession,
        contentViewerStore: ContentViewerStore,
        splitViewStore: SplitViewStore,
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore
    ) { ... }
}
```

```swift
@MainActor
struct VibeSpaceProjectRoutingUseCase {
    func projectForShortcut(index: Int, in vibespace: VibeSpaceState) -> ProjectSession? { ... }
    func terminalProjectMatch(
        for fileURL: URL,
        preferredProjectRootURL: URL?,
        candidates: [(vibespaceID: UUID, project: ProjectSession)]
    ) -> (vibespaceID: UUID, project: ProjectSession)? { ... }
}
```

```swift
@MainActor
struct VibeSpaceHydrationUseCase {
    func prepareHydration(
        for vibespaceID: UUID,
        vibespace: VibeSpaceState,
        layoutPersistence: LayoutPersistenceService
    ) -> VibeSpaceHydrationPreparation { ... }
}
```

Rules:
- Use cases are structs, not classes. They hold no mutable state.
- They may compose other use cases as stored properties (e.g., `VibeSpaceCanvasFileOpenUseCase` holds a `VibeSpaceProjectRoutingUseCase`).
- All external state is passed as method parameters.
- They are `@MainActor` when they operate on UI-bound types.

---

## Concurrency Rules

### `@MainActor` on All UI Types

Every `ObservableObject`, store, coordinator, view model, and context struct is annotated `@MainActor`. This is applied at the type level, not per-method:

```swift
@MainActor
final class AppShellStore: ObservableObject { ... }

@MainActor
final class VibeSpaceCatalogStore: ObservableObject { ... }

@MainActor
struct HomeShellContext { ... }

@MainActor
struct VibeSpaceCanvasFileOpenUseCase { ... }
```

### `[weak self]` in Task Closures and DispatchWorkItems

Every `Task` closure and `DispatchWorkItem` that captures `self` uses `[weak self]` with an early `guard let self` return:

```swift
vibespaceHydrationTask = Task { [weak self] in
    await self?.hydrateVibeSpaceTerminals(for: vibespaceID, targets: preparation.targets)
}

let workItem = DispatchWorkItem { [weak self] in
    self?.persistEditorSessionStateNow()
}
```

This pattern is used consistently across 43+ files with 123+ occurrences.

### Task Cancellation Tracking

Long-running tasks are stored in typed properties and cancelled before replacement:

```swift
private var vibespaceHydrationTask: Task<Void, Never>?

func scheduleVibeSpaceTerminalHydration(for vibespaceID: UUID) {
    cancelVibeSpaceHydration()  // cancel previous
    // ... setup ...
    vibespaceHydrationTask = Task { [weak self] in ... }
}

func cancelVibeSpaceHydration() {
    vibespaceHydrationTask?.cancel()
    vibespaceHydrationTask = nil
}
```

### `Sendable` Conformance

Value types that cross concurrency boundaries conform to `Sendable`:

```swift
enum TerminalDisplayDensity: Equatable, Sendable { ... }
enum TerminalTextDeliveryMode: Sendable { ... }
struct TerminalShellResolutionContext: Equatable, Sendable { ... }
struct CLIResolvedCommand: Equatable, Sendable { ... }
```

Protocols that must be safe across isolation boundaries are marked `Sendable`:

```swift
protocol PaneWorkerExecuting: Sendable { ... }
```

Factory typealiases that cross boundaries are `@Sendable`:

```swift
typealias PaneWorkerFactory = @Sendable (PaneWorkerKind) -> any PaneWorkerExecuting
```

Types that need `Sendable` but manage internal mutable state use `@unchecked Sendable` with explicit locking:

```swift
final class TerminalShellResolutionProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var context: TerminalShellResolutionContext
    // ...
}
```

---

## Memory Management

### Shutdown Methods

Types with long-lived resources implement explicit `shutdown()` methods that nil closures, cancel subscriptions, and terminate child processes:

```swift
// ProjectSession.shutdown()
func shutdown() {
    guard !hasShutdown else { return }
    hasShutdown = true
    onFileOpenRequested = nil
    onFileRenamed = nil
    cancellables.removeAll()
    terminalViewModel.shutdown()
}

// TerminalViewModel.shutdown()
func shutdown() {
    terminateAllSessions()
    withStateUpdates {
        tabs.removeAll()
        activeTabID = nil
        errorMessage = nil
    }
    clearTabActivityStates()
}
```

`VibeSpaceCatalogStore` calls `shutdownProjects()` on every vibespace before removing it:

```swift
func shutdownDisplayedVibeSpaces() {
    for vibespace in vibespaces {
        vibespace.shutdownProjects()
        terminalBoardStandaloneRegistry.release(vibespaceID: vibespace.id)
    }
}
```

### Registry Release

`VibeSpaceTerminalBoardStandaloneRegistry` tracks view models by vibespace key and releases them explicitly:

```swift
func release(vibespaceID: UUID?) {
    let key = vibespaceID?.uuidString ?? "__default__"
    guard let viewModel = viewModelsByVibeSpaceKey.removeValue(forKey: key) else { return }
    viewModel.shutdown()
}
```

### `deinit` for NSEvent Monitors and Notification Observers

Types that install `NSEvent.addLocalMonitorForEvents` or `NotificationCenter` observers remove them in `deinit`:

```swift
// MonitoredTerminalView
deinit {
    teardownInteractiveTargetRecognition()
}

// TerminalViewModel
deinit {
    if let shortcutStoreObserver {
        NotificationCenter.default.removeObserver(shortcutStoreObserver)
    }
    MainActor.assumeIsolated {
        terminateAllSessions()
    }
}

// AppDelegate
deinit {
    for observer in windowObservers {
        NotificationCenter.default.removeObserver(observer)
    }
    if let distributedThemeObserver {
        DistributedNotificationCenter.default().removeObserver(distributedThemeObserver)
    }
}
```

### `SwiftTermTerminalEngine.terminate()` Nils All Callbacks

```swift
func terminate() {
    terminalView.terminate()
    terminalView.onRenderableOutputReceived = nil
    terminalView.onSignificantOutputReceived = nil
    terminalView.onSplitTerminalRequested = nil
    terminalView.onTemporaryTerminalRequested = nil
    terminalView.onLinkTargetActivated = nil
    terminalView.onFileSystemTargetActivated = nil
    terminalView.currentDirectoryProvider = nil
}
```

---

## String Localization

All user-facing strings are centralized in `AppStrings` (an enum namespace) using `String(localized:)` backed by `Localizable.xcstrings`.

```swift
enum AppStrings {
    enum Common {
        static let done = String(localized: "common.done")
        static let cancel = String(localized: "common.cancel")
    }

    enum Terminal {
        static let newTerminal = String(localized: "terminal.newTerminal")
        static let closeTerminal = String(localized: "terminal.closeTerminal")
    }

    enum Explorer {
        static let searchFiles = String(localized: "explorer.searchFiles")
        static let newFile = String(localized: "explorer.newFile")
    }
}
```

Rules:
- Naming convention: `{feature}.{context}.{element}` (e.g., `"explorer.deleteItem.title"`).
- Parameterized strings use `String(format:locale:_:)` with a format stored as a localized string.
- Non-localized brand constants live in `AppStrings.Brand` (e.g., `Brand.crispyvibes = "CRISPYVIBES"`).
- To change UI text, edit `Localizable.xcstrings` — no code changes needed.
- Nested enums group strings by feature: `Common`, `Home`, `Terminal`, `Explorer`, `SourceControl`, `Settings`, etc.

---

## Factory Closures

Factory closures are used to defer creation of child objects and break circular dependencies. They are stored as properties and invoked lazily.

### `projectSessionFactory` on `VibeSpaceState`

```swift
@MainActor
struct VibeSpaceState: Identifiable {
    private let projectSessionFactory: @MainActor (URL) -> ProjectSession

    init(
        id: UUID = UUID(),
        name: String,
        projectURLs: [URL],
        projectSessionFactory: @escaping @MainActor (URL) -> ProjectSession
    ) { ... }

    func makeProjectSession(rootURL: URL) -> ProjectSession {
        projectSessionFactory(rootURL)
    }
}
```

`AppContainer` captures `[self]` to close over its own `make*` methods:

```swift
func makeVibeSpaceState(id: UUID = UUID(), name: String, projectURLs: [URL]) -> VibeSpaceState {
    VibeSpaceState(
        id: id,
        name: name,
        projectURLs: projectURLs,
        projectSessionFactory: { [self] rootURL in
            makeProjectSession(rootURL: rootURL, vibespaceID: id)
        }
    )
}
```

### `editorGroupFactory` on `SplitViewStore` / `ContentViewerStore`

```swift
final class SplitViewStore: ObservableObject {
    private let editorGroupFactory: @MainActor (UUID) -> EditorGroupStore

    init(editorGroupFactory: @escaping @MainActor (UUID) -> EditorGroupStore) {
        self.editorGroupFactory = editorGroupFactory
    }
}
```

Wired in `AppContainer`:

```swift
func makeSplitViewStore() -> SplitViewStore {
    SplitViewStore(editorGroupFactory: makeEditorGroupStore)
}
```

### `terminalViewModelFactory` / `folderExplorerViewModelFactory` on `ProjectSessionDependencies`

```swift
struct ProjectSessionDependencies {
    var folderExplorerViewModelFactory: @MainActor () -> FolderExplorerViewModel
    var terminalViewModelFactory: @MainActor () -> TerminalViewModel
}
```

### `PaneWorkerFactory`

```swift
typealias PaneWorkerFactory = @Sendable (PaneWorkerKind) -> any PaneWorkerExecuting
```

---

## Protocol Abstractions

Protocols define boundaries for subsystem operations, enabling testability and alternative implementations.

### `PaneWorkerExecuting`

Abstracts subprocess/in-process pane operations:

```swift
protocol PaneWorkerExecuting: Sendable {
    func restart() async
    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String?
}
```

`PaneWorkerClient` (an `actor`) is the production implementation. `PaneWorkerExecutionMode` resolves at runtime between `.inProcess` and `.subprocess` based on environment variables.

### `TerminalSessionEngine`

Abstracts terminal rendering backends (SwiftTerm, Ghostty):

```swift
@MainActor
protocol TerminalSessionEngine: AnyObject {
    var hostedView: NSView { get }
    var processIsRunning: Bool { get }
    func configure(delegate: any TerminalSessionEngineDelegate, ...)
    func startProcess(executable: String, args: [String], ...)
    func terminate()
    func send(text: String)
    // ...
}
```

Default implementations are provided via protocol extensions for optional capabilities:

```swift
extension TerminalSessionEngine {
    var canDispatchStandardCommandsBeforeFirstOutput: Bool { false }
    var requiresInteractivePromptForStartupCommands: Bool { false }
    func setSurfaceFocus(_ focused: Bool) {}
}
```

### `EditorDetachedWindowManaging`

```swift
@MainActor
protocol EditorDetachedWindowManaging: AnyObject {
    func openWindow(for fileURL: URL)
}
```

`EditorDetachedWindowManager` is the production conformance. `ProjectSessionDependencies` holds it as the protocol type, enabling test substitution.

---

## Testing Conventions

### `AppContainer.makeDefault()` Per Test

Each test class creates a fresh `AppContainer` in `setUp`:

```swift
@MainActor
final class TerminalMemoryLifecycleTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-memory-lifecycle")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container.terminalServices.focusCoordinator.unfocusCurrent()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }
}
```

### Teardown Discipline

- `container.terminalServices.focusCoordinator.unfocusCurrent()` is called in `tearDown` to release terminal focus state.
- `container = nil` ensures the entire object graph is released.
- Temporary directories are created with `makeTempDirectory(prefix:)` and removed in `tearDown` with `try? FileManager.default.removeItem(at:)`.

### Test Classes Are `@MainActor`

All test classes are annotated `@MainActor` to match the isolation of the types under test.

---

## Additional Patterns

### Lazy Activation

`ProjectSession` defers expensive setup until first use via `activateIfNeeded()`:

```swift
func activateIfNeeded() {
    guard !hasShutdown else { return }
    guard !hasActivatedCore else { return }
    hasActivatedCore = true
    wireViewModels()
    restoreLocalSessionState()
    wireLocalPersistence()
}
```

### Combine Subscription Wiring

Combine pipelines are stored in `Set<AnyCancellable>` and wired in activation methods. They use `.debounce`, `.removeDuplicates()`, and `.receive(on: RunLoop.main)`:

```swift
terminalViewModel.tabsPublisher
    .combineLatest(terminalViewModel.activeTabIDPublisher)
    .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
    .receive(on: RunLoop.main)
    .sink { [weak self] _, _ in
        self?.persistLocalSessionState()
    }
    .store(in: &cancellables)
```

### `VibeSpaceState` Is a Value Type

`VibeSpaceState` is a struct (not a class). It is mutated in-place through `VibeSpaceCatalogStore.mutateVibeSpace(id:_:)`. This ensures SwiftUI observation triggers correctly via `@Published`.

### `ContentViewStableDependencies`

Long-lived coordinators that should not be recreated on every SwiftUI body evaluation are grouped into `ContentViewStableDependencies: ObservableObject`, created once during `makeContentViewDependencies()`.

### Output Classification Queue

CPU-intensive work (e.g., terminal output classification) is dispatched to a dedicated serial `DispatchQueue` and results are coalesced before dispatching back to main:

```swift
private let outputClassificationQueue = DispatchQueue(
    label: "com.crispyvibe.terminal.output-classification",
    qos: .userInitiated
)
```

### `willTerminateNotification` Persistence

`ProjectSession` subscribes to `NSApplication.willTerminateNotification` to persist layout and terminal state before app exit:

```swift
NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        guard let self else { return }
        self.layoutPersistence.setPaneLayout(self.paneLayout, for: self.rootURL)
        self.persistLocalSessionState()
        self.terminalViewModel.shutdown()
    }
    .store(in: &cancellables)
```
