import Combine
import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    private struct ViewState: Equatable {
        var tabs: [TerminalTab] = []
        var activeTabID: UUID?
        var errorMessage: String?
        var workerStatus: PaneWorkerStatus = .ready
        var availablePresets: [TerminalPresetDefinition] = []
        var shortcutCommands: [TerminalShortcutDefinition] = []
    }

    static let builtInPresets: [TerminalPresetDefinition] = CLIToolCatalog.terminalPresetDefinitions

    static func preset(id: String?) -> TerminalPresetDefinition? {
        CLIToolCatalog.terminalPreset(id: id)
    }

    static func availableBuiltInPresets(
        using dependencies: TerminalViewModelDependencies
    ) -> [TerminalPresetDefinition] {
        dependencies.presetDiagnostics.availablePresets(from: builtInPresets)
    }

    @Published private var viewState: ViewState

    var tabs: [TerminalTab] {
        get { currentViewState.tabs }
        set { mutateViewState { $0.tabs = newValue } }
    }

    var activeTabID: UUID? {
        get { currentViewState.activeTabID }
        set { mutateViewState { $0.activeTabID = newValue } }
    }

    var errorMessage: String? {
        get { currentViewState.errorMessage }
        set { mutateViewState { $0.errorMessage = newValue } }
    }

    var workerStatus: PaneWorkerStatus {
        get { currentViewState.workerStatus }
        set { mutateViewState { $0.workerStatus = newValue } }
    }

    var availablePresets: [TerminalPresetDefinition] {
        get { currentViewState.availablePresets }
        set { mutateViewState { $0.availablePresets = newValue } }
    }

    var shortcutCommands: [TerminalShortcutDefinition] {
        get { currentViewState.shortcutCommands }
        set { mutateViewState { $0.shortcutCommands = newValue } }
    }

    var tabsPublisher: AnyPublisher<[TerminalTab], Never> {
        $viewState
            .map(\.tabs)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var activeTabIDPublisher: AnyPublisher<UUID?, Never> {
        $viewState
            .map(\.activeTabID)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var sessions: [UUID: TerminalSession] = [:]
    /// Configures each new TerminalSession after creation (e.g., SSH processLaunchOverride).
    var sessionConfigurator: ((TerminalSession) -> Void)?
    /// Host label shown on remote terminal tabs (e.g., "devserver").
    var defaultHostLabel: String?
    var tabActivityStates: [UUID: TerminalTabActivityState] = [:]
    var activeTabActivityCount = 0
    let inactiveTabActivityState = TerminalTabActivityState(id: UUID(), isActive: false)
    let worker: any PaneWorkerExecuting
    let terminalServices: TerminalServices
    let shellResolutionProviderStore = TerminalShellResolutionProvider(
        initialContext: TerminalShellResolutionContext(
            appDefault: AppPreferences.storedTerminalShellPreference()
        )
    )
    let presetDiagnostics: TerminalPresetAvailabilityDiagnostics
    let shortcutStore: TerminalShortcutStore
    let operationMetricsStore: OperationMetricsStore?
    var shortcutStoreObserver: NSObjectProtocol?
    let tabActivitySummary = TerminalTabActivitySummary()
    private var isBatchingViewStateUpdates = false
    private var pendingBatchedViewState: ViewState?

    init(
        dependencies: TerminalViewModelDependencies,
        worker: any PaneWorkerExecuting
    ) {
        let presetDiagnostics = dependencies.presetDiagnostics
        let shortcutStore = dependencies.shortcutStore
        let terminalServices = dependencies.terminalServices
        self.worker = worker
        self.presetDiagnostics = presetDiagnostics
        self.shortcutStore = shortcutStore
        self.terminalServices = terminalServices
        self.operationMetricsStore = dependencies.operationMetricsStore
        viewState = ViewState(
            availablePresets: presetDiagnostics.availablePresets(from: Self.builtInPresets),
            shortcutCommands: shortcutStore.load()
        )
        shortcutStoreObserver = NotificationCenter.default.addObserver(
            forName: TerminalShortcutStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadShortcutCommands()
            }
        }
    }

    deinit {
        if let shortcutStoreObserver {
            NotificationCenter.default.removeObserver(shortcutStoreObserver)
        }
        MainActor.assumeIsolated {
            for tabID in tabs.map(\.id) {
                teardownGitHeadWatcher(for: tabID)
            }
            terminateAllSessions()
        }
    }

    var activeTab: TerminalTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    func tabActivityState(for tabID: UUID) -> TerminalTabActivityState? {
        tabActivityStates[tabID]
    }

    func tabActivityStateOrInactive(for tabID: UUID) -> TerminalTabActivityState {
        tabActivityStates[tabID] ?? inactiveTabActivityState
    }

    func refreshAvailablePresets() {
        availablePresets = presetDiagnostics.availablePresets(from: Self.builtInPresets)
    }

    func updateShellResolutionContext(_ context: TerminalShellResolutionContext) {
        shellResolutionProviderStore.updateContext(context)
    }

    func clearError() {
        errorMessage = nil
    }

    private func reloadShortcutCommands() {
        shortcutCommands = shortcutStore.load()
    }

    func withStateUpdates(_ updates: () -> Void) {
        if isBatchingViewStateUpdates {
            updates()
            return
        }

        isBatchingViewStateUpdates = true
        pendingBatchedViewState = viewState
        updates()

        let finalState = pendingBatchedViewState ?? viewState
        pendingBatchedViewState = nil
        isBatchingViewStateUpdates = false

        guard finalState != viewState else { return }
        viewState = finalState
    }

    private var currentViewState: ViewState {
        if isBatchingViewStateUpdates, let pendingBatchedViewState {
            return pendingBatchedViewState
        }
        return viewState
    }

    private func mutateViewState(_ mutate: (inout ViewState) -> Void) {
        if isBatchingViewStateUpdates {
            var next = pendingBatchedViewState ?? viewState
            mutate(&next)
            pendingBatchedViewState = next
            return
        }

        var next = viewState
        mutate(&next)
        guard next != viewState else { return }
        viewState = next
    }
}
