import Foundation

struct AppContainer {
    let appPersistenceStore: AppPersistenceDataStore
    let vibespacePersistenceStore: VibeSpacePersistenceStore
    let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry
    let terminalBoardDetachedWindowManager: VibeSpaceTerminalBoardDetachedWindowManager
    let layoutPersistence: LayoutPersistenceService
    let shelfStore: ShelfStore
    let detachedWindowManager: EditorDetachedWindowManager
    let vibespaceManagement: VibeSpaceManagementService
    let themeManager: CrispyVibesThemeManager
    let experimentalFeatures: ExperimentalFeaturesService
    let vibespaceInteraction: VibeSpaceInteractionService
    let terminalServices: TerminalServices
    let terminalViewModelDependencies: TerminalViewModelDependencies
    let operationMetricsStore: OperationMetricsStore
    let acpObservabilityStore: ACPObservabilityStore
    let acpSessionManager: ACPSessionManager
    let acpVibeSpaceContextStore: ACPVibeSpaceContextStore
    let acpVibeSpaceSessionService: ACPVibeSpaceSessionService
    let acpDeveloperToolsService: ACPDeveloperToolsService
    let agentConversationStore: AgentConversationStore
    /// F049: central comment store for the active vibespace. Wraps the
    /// existing `agentConversationStore` for RPC.
    let vibespaceCommentStore: VibeSpaceCommentStore
    /// F053: quick todos & sticky notes store for the active vibespace.
    let vibespaceTodoStore: VibeSpaceTodoStore
    /// F049-R05 + F049-R13: orchestrates anchor relocation + file lifecycle.
    let commentLifecycleCoordinator: CommentLifecycleCoordinator
    let externalAgentSessionService: ExternalAgentSessionService
    let acpSessionRegistry: ACPSessionRegistry
    let dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator
    let paneWorkerFactory: PaneWorkerFactory
    let browserHistoryStore: BrowserHistoryStore
    let composeHistoryStore: ComposeHistoryStore
    /// Captures every Foundation Models generation for the terminal context summary
    /// feature so developer tools can show received → sent → result. F041.
    let contextSummaryObservabilityStore: ContextSummaryObservabilityStore

    func makePaneWorker(pane: PaneWorkerKind) -> any PaneWorkerExecuting {
        paneWorkerFactory(pane)
    }

    @MainActor
    func makeAppShellStore() -> AppShellStore {
        AppShellStore()
    }

    @MainActor
    func makeVibeSpaceCatalogStore() -> VibeSpaceCatalogStore {
        VibeSpaceCatalogStore(
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            terminalBoardDetachedWindowManager: terminalBoardDetachedWindowManager
        )
    }

    @MainActor
    func makeMarkdownViewModel(bufferStore: DocumentBufferStore) -> MarkdownViewModel {
        MarkdownViewModel(worker: makePaneWorker(pane: .editor), bufferStore: bufferStore)
    }

    @MainActor
    func makeFolderExplorerViewModel() -> FolderExplorerViewModel {
        FolderExplorerViewModel(worker: makePaneWorker(pane: .explorer))
    }

    @MainActor
    func makeTerminalViewModel() -> TerminalViewModel {
        TerminalViewModel(
            dependencies: terminalViewModelDependencies,
            worker: makePaneWorker(pane: .terminal)
        )
    }

    @MainActor
    func makeTerminalSpotlightCoordinator() -> TerminalSpotlightCoordinator {
        TerminalSpotlightCoordinator(diagnosticsSnapshot: terminalServices.diagnosticsSnapshot)
    }

    @MainActor
    func makeDockedBrowserCoordinator() -> DockedBrowserCoordinator {
        let coordinator = DockedBrowserCoordinator()
        coordinator.historyStore = browserHistoryStore
        coordinator.agentAPIFactory = { vm in BrowserAgentAPI(viewModel: vm) }
        return coordinator
    }

    @MainActor
    func makeVibeSpaceCloneRepositoryCoordinator() -> VibeSpaceCloneRepositoryCoordinator {
        VibeSpaceCloneRepositoryCoordinator()
    }

    @MainActor
    func makeVibeSpaceSourceControlViewModel() -> VibeSpaceSourceControlViewModel {
        VibeSpaceSourceControlViewModel(workerFactory: paneWorkerFactory)
    }

    @MainActor
    func makeFeatureWalkthroughController() -> FeatureWalkthroughController {
        FeatureWalkthroughController()
    }

    @MainActor
    func makeStackedRailTerminalStore() -> StackedRailTerminalStore {
        StackedRailTerminalStore()
    }

    @MainActor
    func makeEditorGroupStore(id: UUID = UUID(), bufferStore: DocumentBufferStore) -> EditorGroupStore {
        EditorGroupStore(
            id: id,
            markdownViewModel: makeMarkdownViewModel(bufferStore: bufferStore),
            commentsPanel: CommentsPanelStore()
        )
    }

    @MainActor
    func makeSplitViewStore() -> SplitViewStore {
        let sharedBufferStore = DocumentBufferStore()
        return makeSplitViewStore(bufferStore: sharedBufferStore)
    }

    @MainActor
    func makeSplitViewStore(bufferStore: DocumentBufferStore) -> SplitViewStore {
        SplitViewStore { [self] id in
            self.makeEditorGroupStore(id: id, bufferStore: bufferStore)
        }
    }

    @MainActor
    func makeContentViewerStore() -> ContentViewerStore {
        let sharedBufferStore = DocumentBufferStore()
        return makeContentViewerStore(bufferStore: sharedBufferStore)
    }

    @MainActor
    func makeContentViewerStore(bufferStore: DocumentBufferStore) -> ContentViewerStore {
        ContentViewerStore(
            conversationStore: agentConversationStore,
            editorGroupFactory: { [self] id in
                self.makeEditorGroupStore(id: id, bufferStore: bufferStore)
            },
            sessionRegistry: acpSessionRegistry
        )
    }

    @MainActor
    func makeProjectActivityTracker() -> ProjectActivityTracker {
        ProjectActivityTracker()
    }

    @MainActor
    func makeContentViewDependencies() -> ContentViewDependencies {
        let appShellStore = makeAppShellStore()
        appShellStore.operationMetricsStore = operationMetricsStore
        let vibespaceCatalogStore = makeVibeSpaceCatalogStore()
        cliCommandRouter.attachVibeSpaceCatalogStore(vibespaceCatalogStore)
        cliCommandRouter.attachVibeSpaceManagement(vibespaceManagement)
        // F049: bind comment store to the active vibespace so writes/reads
        // are scoped to the focused space. The closure captures the catalog
        // store weakly via the AppContainer reference held by the binding.
        vibespaceCommentStore.bindActiveVibeSpace(provider: vibespaceCatalogStore) { [weak vibespaceCatalogStore, weak appShellStore] in
            guard let catalog = vibespaceCatalogStore, let activeID = appShellStore?.activeVibeSpaceID else {
                return vibespaceCatalogStore?.vibespaces.first?.id.uuidString
            }
            return catalog.vibespaces.first(where: { $0.id == activeID })?.id.uuidString
        }
        // F053: bind the todo store to the active vibespace using the same
        // resolver so todo reads/writes are scoped to the focused space.
        vibespaceTodoStore.bindActiveVibeSpace(provider: vibespaceCatalogStore) { [weak vibespaceCatalogStore, weak appShellStore] in
            guard let catalog = vibespaceCatalogStore, let activeID = appShellStore?.activeVibeSpaceID else {
                return vibespaceCatalogStore?.vibespaces.first?.id.uuidString
            }
            return catalog.vibespaces.first(where: { $0.id == activeID })?.id.uuidString
        }
        let walkthroughController = makeFeatureWalkthroughController()
        let vibespaceSourceControlViewModel = makeVibeSpaceSourceControlViewModel()
        let sharedBufferStore = DocumentBufferStore()
        let contentViewerStore = makeContentViewerStore(bufferStore: sharedBufferStore)
        let projectActivityTracker = makeProjectActivityTracker()
        let splitViewStore = makeSplitViewStore(bufferStore: sharedBufferStore)
        let vibespaceHydrationCoordinator = VibeSpaceHydrationCoordinator(
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            layoutPersistence: layoutPersistence,
            splitViewStore: splitViewStore,
            contentViewerStore: contentViewerStore,
            commentLifecycle: commentLifecycleCoordinator
        )
        let dockPreviewBridge = DockPreviewBridge()
        let dockedFileViewerCoordinator = DockedFileViewerCoordinator { [self] id in
            self.makeEditorGroupStore(id: id, bufferStore: sharedBufferStore)
        }
        let dockedBrowserCoordinator = makeDockedBrowserCoordinator()
        cliCommandRouter.attachDockedBrowserCoordinator(dockedBrowserCoordinator)
        // Create the terminal board store at the service layer so it is reachable
        // before any view renders. This is required by the Agent CLI: commands like
        // `crispy browser open` may arrive while the user is in `.detailed` canvas
        // mode (where the board view is not in the SwiftUI hierarchy), or before the
        // board view's `onAppear` has fired. Owning the store here removes the race.
        let boardStore = VibeSpaceTerminalBoardStore(
            vibespaceID: appShellStore.activeVibeSpaceID,
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            snapshotProviders: .browserBacked(coordinator: dockedBrowserCoordinator)
        )
        vibespaceHydrationCoordinator.boardStore = boardStore
        let vibespaceShortcutProvider = VibeSpaceShortcutProvider(vibespaceManagement: vibespaceManagement)
        let layoutPersistenceRef = layoutPersistence
        let canvasModeProvider: () -> VibeSpaceCanvasMode = { [weak appShellStore] in
            layoutPersistenceRef.canvasMode(for: appShellStore?.activeVibeSpaceID)
        }
        vibespaceHydrationCoordinator.dockPreviewBridge = dockPreviewBridge
        vibespaceHydrationCoordinator.canvasModeProvider = canvasModeProvider
        vibespaceHydrationCoordinator.operationMetricsStore = operationMetricsStore
        vibespaceHydrationCoordinator.dockedBrowserCoordinator = dockedBrowserCoordinator
        dockedBrowserCoordinator.onOpenNewBrowser = { url, projectPath in
            var userInfo: [String: Any] = ["url": url]
            if let projectPath { userInfo["projectPath"] = projectPath }
            NotificationCenter.default.post(name: .openNewBrowserRequested, object: nil, userInfo: userInfo)
        }
        dockedBrowserCoordinator.projectPathForTile = { [weak vibespaceHydrationCoordinator] tileID in
            vibespaceHydrationCoordinator?.boardStore?.tile(for: tileID)?.projectPath
        }
        dockedBrowserCoordinator.onDetailedSessionStateChanged = { [weak vibespaceHydrationCoordinator] in
            vibespaceHydrationCoordinator?.scheduleEditorSessionStateSave()
        }
        splitViewStore.browserSessionSnapshotProvider = { [weak dockedBrowserCoordinator] reference in
            dockedBrowserCoordinator?.snapshotDetailedBrowser(for: reference)
        }
        splitViewStore.browserTabRestoreHandler = { [weak dockedBrowserCoordinator] reference, snapshot in
            dockedBrowserCoordinator?.restoreDetailedBrowser(reference: reference, snapshot: snapshot)
        }
        splitViewStore.browserTabCloseHandler = { [weak dockedBrowserCoordinator] reference in
            dockedBrowserCoordinator?.removeDetailedBrowser(browserID: reference.browserID)
        }
        splitViewStore.acpPaneCloseHandler = { [weak contentViewerStore] id in
            contentViewerStore?.removeACPStore(id: id)
        }
        splitViewStore.acpPaneSnapshotProvider = { [weak contentViewerStore] id in
            contentViewerStore?.acpSnapshot(for: id)
        }
        splitViewStore.acpPaneRestoreHandler = { [weak contentViewerStore] snapshot in
            guard let contentViewerStore else { return }
            _ = contentViewerStore.restoreACPStore(from: snapshot)
        }
        contentViewerStore.browserTabCloseHandler = { [weak dockedBrowserCoordinator] reference in
            dockedBrowserCoordinator?.removeDetailedBrowser(browserID: reference.browserID)
        }
        // Eager VM creation so any caller of `openWebPage` (CLI handler, link clicks,
        // file opens, restore) gets a populated `detailedViewGroups[browserID]` before
        // SwiftUI renders. This eliminates the race where `agentAPI(for:)` is asked
        // about a browser whose VM hasn't been instantiated yet.
        contentViewerStore.browserTabEagerCreateHandler = { [weak dockedBrowserCoordinator] reference in
            _ = dockedBrowserCoordinator?.viewModel(for: reference)
        }
        let stableDependencies = ContentViewStableDependencies(
            appContainer: self,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            vibespaceHydrationCoordinator: vibespaceHydrationCoordinator,
            shelfStore: shelfStore,
            walkthroughController: walkthroughController,
            layoutPersistence: layoutPersistence,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            dockPreviewBridge: dockPreviewBridge,
            canvasModeProvider: canvasModeProvider,
            dockedBrowserCoordinator: dockedBrowserCoordinator
        )

        return ContentViewDependencies(
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            vibespaceHydrationCoordinator: vibespaceHydrationCoordinator,
            walkthroughController: walkthroughController,
            layoutPersistence: layoutPersistence,
            shelfStore: shelfStore,
            themeManager: themeManager,
            vibespaceSourceControlViewModel: vibespaceSourceControlViewModel,
            contentViewerStore: contentViewerStore,
            projectActivityTracker: projectActivityTracker,
            splitViewStore: splitViewStore,
            stableDependencies: stableDependencies,
            dockPreviewBridge: dockPreviewBridge,
            dockedFileViewerCoordinator: dockedFileViewerCoordinator,
            dockedBrowserCoordinator: dockedBrowserCoordinator,
            dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
            boardStore: boardStore,
            vibespaceShortcutProvider: vibespaceShortcutProvider,
            hasAcceptedDisclaimer: vibespaceManagement.hasAcceptedDisclaimer()
        )
    }

    @MainActor
    func makeProjectSessionDependencies(vibespaceID: UUID?) -> ProjectSessionDependencies {
        ProjectSessionDependencies(
            layoutPersistence: layoutPersistence,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            folderExplorerViewModelFactory: makeFolderExplorerViewModel,
            terminalViewModelFactory: makeTerminalViewModel,
            detachedWindowManager: detachedWindowManager,
            directoryWatcher: DirectoryWatcher()
        )
    }

    @MainActor
    func makeProjectSession(rootURL: URL, vibespaceID: UUID?) -> AnyProjectSession {
        AnyProjectSession(ProjectSession(
            rootURL: rootURL,
            dependencies: makeProjectSessionDependencies(vibespaceID: vibespaceID)
        ))
    }

    /// Creates a project session from a stored identifier (local path or SSH URI).
    @MainActor
    func makeProjectSessionFromIdentifier(_ identifier: String, vibespaceID: UUID?) -> AnyProjectSession {
        if let parsed = SSHConnectionProfile.parse(identifier: identifier) {
            let conn = sshConnectionManager.connection(for: parsed.profile)
            return AnyProjectSession(RemoteProjectSession(
                connection: conn,
                remotePath: parsed.remotePath,
                terminalViewModelFactory: { [self] in makeTerminalViewModel() },
                vibespaceManagement: vibespaceManagement,
                vibespaceID: vibespaceID
            ))
        }
        return makeProjectSession(rootURL: URL(fileURLWithPath: identifier), vibespaceID: vibespaceID)
    }

    let sshConnectionManager: SSHConnectionManager
    let cliCommandRouter: CLICommandRouter
    let cliSocketServer: CLISocketServer
    /// F049-R08: app-wide owner of locally-spawned Jupyter servers.
    let jupyterServerService: JupyterServerService

    @MainActor
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

    @MainActor
    func makeVibeSpaceState(
        config: VibeSpaceConfigFile,
        projectConfigs: [String: ProjectConfigFile] = [:],
        existingDirectoryPaths: Set<String>? = nil
    ) -> VibeSpaceState {
        let vibespaceID = config.id
        return VibeSpaceState(
            config: config,
            projectConfigs: projectConfigs,
            existingDirectoryPaths: existingDirectoryPaths,
            projectSessionFactory: { [self] rootURL in
                makeProjectSession(rootURL: rootURL, vibespaceID: vibespaceID)
            },
            identifierSessionFactory: { [self] identifier in
                makeProjectSessionFromIdentifier(identifier, vibespaceID: vibespaceID)
            }
        )
    }

    @MainActor
    static func makeDefault() -> AppContainer {
        let operationMetricsStore = OperationMetricsStore()
        let acpObservabilityStore = ACPObservabilityStore()
        let acpSessionManager = ACPSessionManager(observabilityStore: acpObservabilityStore)
        let acpVibeSpaceContextStore = ACPVibeSpaceContextStore()
        let agentConversationStore = AgentConversationStore()
        let vibespaceCommentStore = VibeSpaceCommentStore(conversationStore: agentConversationStore)
        let vibespaceTodoStore = VibeSpaceTodoStore(conversationStore: agentConversationStore)
        let commentLifecycleCoordinator = CommentLifecycleCoordinator(store: vibespaceCommentStore)
        let externalAgentSessionService = ExternalAgentSessionService()
        let makeACPStandaloneStore: @MainActor (UUID, UUID?) -> ACPStandaloneSessionStore = { id, vibespaceID in
            let chatVM = ACPChatViewModel(
                sessionManager: acpSessionManager,
                conversationStore: agentConversationStore
            )
            return ACPStandaloneSessionStore(
                id: id,
                sessionManager: acpSessionManager,
                conversationStore: agentConversationStore,
                chatViewModel: chatVM,
                vibespaceID: vibespaceID
            )
        }
        let acpSessionRegistry = ACPSessionRegistry(storeFactory: makeACPStandaloneStore)
        let dockedAgentPreviewCoordinator = DockedAgentPreviewCoordinator(
            sessionRegistry: acpSessionRegistry
        )
        let acpVibeSpaceSessionService = ACPVibeSpaceSessionService()
        let acpDeveloperToolsService = ACPDeveloperToolsService(
            sessionManager: acpSessionManager,
            vibespaceContextStore: acpVibeSpaceContextStore
        )
        let explorerWorker = MeasuredPaneWorker(
            inner: PaneWorkerClient(pane: .explorer),
            metricsStore: operationMetricsStore,
            kind: .explorer
        )
        let sourceControlWorker = MeasuredPaneWorker(
            inner: PaneWorkerClient(pane: .sourceControl),
            metricsStore: operationMetricsStore,
            kind: .sourceControl
        )
        let editorWorker = MeasuredPaneWorker(
            inner: PaneWorkerClient(pane: .editor),
            metricsStore: operationMetricsStore,
            kind: .editor
        )
        let terminalWorker = MeasuredPaneWorker(
            inner: PaneWorkerClient(pane: .terminal),
            metricsStore: operationMetricsStore,
            kind: .terminal
        )
        let measuredPaneWorkerFactory: PaneWorkerFactory = { pane in
            switch pane {
            case .explorer:
                return explorerWorker
            case .sourceControl:
                return sourceControlWorker
            case .editor:
                return editorWorker
            case .terminal:
                return terminalWorker
            }
        }
        let appPersistenceStore = AppPersistenceDataStore()
        let vibespacePersistenceStore = VibeSpacePersistenceStore(store: appPersistenceStore)
        let vibespaceManagement = VibeSpaceManagementService(persistenceStore: vibespacePersistenceStore)
        let layoutPersistence = LayoutPersistenceService(persistenceStore: appPersistenceStore)
        let vibespaceInteraction = VibeSpaceInteractionService()
        let composeHistoryStore = ComposeHistoryStore()
        let experimentalFeaturesService = ExperimentalFeaturesService()
        let contextSummaryObservabilityStore = ContextSummaryObservabilityStore()
        let terminalServices = TerminalServices(
            focusCoordinator: TerminalFocusCoordinator(),
            diagnosticsSnapshot: TerminalDiagnosticsSnapshot(),
            hostOwnershipCoordinator: TerminalHostOwnershipCoordinator(),
            vibespaceInteraction: vibespaceInteraction,
            composeHistoryStore: composeHistoryStore
        )
        // Wire the per-terminal context-summary factory. The factory captures the
        // experimental flag service so each `TerminalSession` consults the current
        // value at construction time without instantiating its own copy
        // (F041-R11, coding-guidelines: no service-locator instantiation in domain
        // code). Returning nil disables the LLM-driven session for that terminal
        // while still keeping the lightweight insight observer alive for compose
        // history.
        terminalServices.contextSummarySessionFactory = { [weak experimentalFeaturesService] observer in
            guard experimentalFeaturesService?.isTerminalInsightEnabled == true else { return nil }
            return TerminalContextSummarySession(
                insightObserver: observer,
                summaryGenerator: ContextSummaryGenerator(
                    observabilityStore: contextSummaryObservabilityStore
                )
            )
        }
        // Diagnostic recorder: every sensitive classification in any terminal
        // is written into the same context-summary trace store so the
        // developer-tools surface can show it alongside live and sandbox
        // generations. The screen snapshot supplied by the observer is by
        // construction the surface state that did NOT contain the typed
        // text, so it's safe to retain. F041-T07.
        terminalServices.insightObserverConfigurator = { observer in
            observer.onSensitiveClassification = { [weak contextSummaryObservabilityStore] info in
                guard let store = contextSummaryObservabilityStore else { return }
                store.record(
                    ContextSummaryTrace(
                        source: .live,
                        received: "",
                        sent: nil,
                        result: .classifiedSensitive(
                            screenSnapshot: info.screenSnapshot,
                            typedText: info.typedText,
                            attempts: info.attempts
                        ),
                        latency: 0,
                        timestamp: info.timestamp
                    )
                )
            }
        }
        let terminalViewModelDependencies = TerminalViewModelDependencies(
            presetDiagnostics: TerminalPresetAvailabilityDiagnostics(),
            shortcutStore: TerminalShortcutStore(),
            terminalServices: terminalServices,
            operationMetricsStore: operationMetricsStore
        )
        let makeMarkdownViewModel: @MainActor () -> MarkdownViewModel = {
            MarkdownViewModel(worker: measuredPaneWorkerFactory(.editor), bufferStore: DocumentBufferStore())
        }
        let makeTerminalViewModel: @MainActor () -> TerminalViewModel = {
            TerminalViewModel(
                dependencies: terminalViewModelDependencies,
                worker: measuredPaneWorkerFactory(.terminal)
            )
        }
        let terminalBoardStandaloneRegistry = VibeSpaceTerminalBoardStandaloneRegistry(
            makeTerminalViewModel: makeTerminalViewModel
        )
        let terminalBoardDetachedWindowManager = VibeSpaceTerminalBoardDetachedWindowManager()
        let detachedWindowManager = EditorDetachedWindowManager(
            markdownViewModelFactory: makeMarkdownViewModel
        )
        layoutPersistence.setVibeSpacePersistenceStore(vibespacePersistenceStore)
        let shelfStore = ShelfStore(persistenceStore: appPersistenceStore)
        let cliCommandRouter = CLICommandRouter(shelfStore: shelfStore)
        cliCommandRouter.attachVibeSpaceCommentStore(vibespaceCommentStore)
        cliCommandRouter.attachVibeSpaceTodoStore(vibespaceTodoStore)
        let cliSocketServer = CLISocketServer(router: cliCommandRouter)
        return AppContainer(
            appPersistenceStore: appPersistenceStore,
            vibespacePersistenceStore: vibespacePersistenceStore,
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            terminalBoardDetachedWindowManager: terminalBoardDetachedWindowManager,
            layoutPersistence: layoutPersistence,
            shelfStore: shelfStore,
            detachedWindowManager: detachedWindowManager,
            vibespaceManagement: vibespaceManagement,
            themeManager: CrispyVibesThemeManager(),
            experimentalFeatures: experimentalFeaturesService,
            vibespaceInteraction: vibespaceInteraction,
            terminalServices: terminalServices,
            terminalViewModelDependencies: terminalViewModelDependencies,
            operationMetricsStore: operationMetricsStore,
            acpObservabilityStore: acpObservabilityStore,
            acpSessionManager: acpSessionManager,
            acpVibeSpaceContextStore: acpVibeSpaceContextStore,
            acpVibeSpaceSessionService: acpVibeSpaceSessionService,
            acpDeveloperToolsService: acpDeveloperToolsService,
            agentConversationStore: agentConversationStore,
            vibespaceCommentStore: vibespaceCommentStore,
            vibespaceTodoStore: vibespaceTodoStore,
            commentLifecycleCoordinator: commentLifecycleCoordinator,
            externalAgentSessionService: externalAgentSessionService,
            acpSessionRegistry: acpSessionRegistry,
            dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
            paneWorkerFactory: measuredPaneWorkerFactory,
            browserHistoryStore: BrowserHistoryStore(),
            composeHistoryStore: composeHistoryStore,
            contextSummaryObservabilityStore: contextSummaryObservabilityStore,
            sshConnectionManager: SSHConnectionManager(),
            cliCommandRouter: cliCommandRouter,
            cliSocketServer: cliSocketServer,
            jupyterServerService: JupyterServerService()
        )
    }

}
