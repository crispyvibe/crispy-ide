import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private struct VibeSpaceLifecycleState: Equatable {
        let activeVibeSpaceID: UUID?
        let vibespaceCount: Int
    }

    private struct VibeSpaceSourceControlSyncState: Equatable {
        let activeVibeSpaceID: UUID?
        let projectPaths: [String]
        let focusedProjectID: UUID?
        let selectedFilePath: String?
        let sourceControlSettings: VibeSpaceSourceControlSettings
    }

    private struct ACPVibeSpaceSyncState: Equatable {
        let vibespaceID: UUID?
        let focusedProjectIdentifier: String?
        let defaultAgentID: String
        let projectOverrideAgentID: String?
    }

    @Environment(\.colorScheme) var systemColorScheme
    let appContainer: AppContainer
    @StateObject var appShellStore: AppShellStore
    @StateObject var vibespaceCatalogStore: VibeSpaceCatalogStore
    @StateObject var vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator
    @State var expandedVibeSpaceSidebarProjectPaths: Set<String> = []
    @State private var isShowingQuickCapture = false

    @ViewBuilder
    private var quickCaptureOverlay: some View {
        if isShowingQuickCapture {
            TodoQuickCaptureOverlay(
                store: appContainer.vibespaceTodoStore,
                projects: activeVibeSpaceSession.projects.map {
                    TodoCaptureProject(id: $0.rootURL.standardizedFileURL.path, name: $0.title)
                },
                initialProjectPath: activeVibeSpaceSession.focusedProject?.rootURL.standardizedFileURL.path,
                onClose: { isShowingQuickCapture = false }
            )
        }
    }
    @State var didApplyUITestOverrides = false
    @State var isHoveringSideMenuItem: AppSideMenuItem?
    @State var hiddenRailTerminalIDsByVibeSpace: [UUID: [String: Set<UUID>]] = [:]
    @State var isHiddenRailSectionExpanded = true
    @State var untrustedVibeSpaceName: String?
    @State var hasAcceptedDisclaimer: Bool
    @State private var hasResolvedDisclaimerState = false
    @StateObject var walkthroughController: FeatureWalkthroughController
    @StateObject var layoutPersistence: LayoutPersistenceService
    @StateObject var shelfStore: ShelfStore
    @StateObject var themeManager: CrispyVibesThemeManager
    @StateObject var vibespaceSourceControlViewModel: VibeSpaceSourceControlViewModel
    @StateObject var contentViewerStore: ContentViewerStore
    @StateObject var projectActivityTracker: ProjectActivityTracker
    @StateObject var splitViewStore: SplitViewStore
    @StateObject var stackedRailOverlayCoordinator = StackedRailExpansionOverlayCoordinator()
    @StateObject private var stableDependencies: ContentViewStableDependencies
    @StateObject var dockPreviewBridge: DockPreviewBridge
    @StateObject var dockedFileViewerCoordinator: DockedFileViewerCoordinator
    @StateObject var dockedBrowserCoordinator: DockedBrowserCoordinator
    @StateObject var dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator
    @StateObject var boardStore: VibeSpaceTerminalBoardStore
    @StateObject var vibespaceShortcutProvider: VibeSpaceShortcutProvider
    @State var externalAgentSessionPreview: ExternalAgentTranscript?
    let vibespaceManagement: VibeSpaceManagementService
    @AppStorage(AppPreferences.appearancePreferenceKey)
    var appearancePreference = AppPreferences.defaultAppearancePreference
    @AppStorage(AppPreferences.terminalShellPreferenceKey)
    var terminalShellPreference = AppPreferences.defaultTerminalShellPreference
    @AppStorage(AppPreferences.appThemePresetKey)
    var appThemePreset = AppPreferences.defaultAppThemePreset
    @AppStorage(AppPreferences.appCustomThemePaletteJSONKey)
    var appCustomThemePaletteJSON = AppPreferences.defaultAppCustomThemePaletteJSON
    @AppStorage(AppPreferences.appSideMenuDockPositionKey)
    var appSideMenuDockPositionRaw = AppPreferences.defaultAppSideMenuDockPosition
    @AppStorage(AppPreferences.codeFontSizeKey)
    var codeFontSize = AppPreferences.defaultCodeFontSize
    @AppStorage(AppPreferences.defaultRailPositionKey)
    var defaultRailPositionRaw = AppPreferences.defaultRailPositionRawValue
    @AppStorage(AppPreferences.acpDefaultAgentIDKey)
    var acpDefaultAgentID = ""

    @MainActor
    init(container: AppContainer) {
        appContainer = container
        let dependencies = container.makeContentViewDependencies()
        _layoutPersistence = StateObject(wrappedValue: dependencies.layoutPersistence)
        _appShellStore = StateObject(wrappedValue: dependencies.appShellStore)
        _vibespaceCatalogStore = StateObject(wrappedValue: dependencies.vibespaceCatalogStore)
        _vibespaceHydrationCoordinator = StateObject(wrappedValue: dependencies.vibespaceHydrationCoordinator)
        _walkthroughController = StateObject(wrappedValue: dependencies.walkthroughController)
        _shelfStore = StateObject(wrappedValue: dependencies.shelfStore)
        _themeManager = StateObject(wrappedValue: dependencies.themeManager)
        _vibespaceSourceControlViewModel = StateObject(wrappedValue: dependencies.vibespaceSourceControlViewModel)
        _contentViewerStore = StateObject(wrappedValue: dependencies.contentViewerStore)
        _projectActivityTracker = StateObject(wrappedValue: dependencies.projectActivityTracker)
        _splitViewStore = StateObject(wrappedValue: dependencies.splitViewStore)
        _stableDependencies = StateObject(wrappedValue: dependencies.stableDependencies)
        _dockPreviewBridge = StateObject(wrappedValue: dependencies.dockPreviewBridge)
        _dockedFileViewerCoordinator = StateObject(wrappedValue: dependencies.dockedFileViewerCoordinator)
        _dockedBrowserCoordinator = StateObject(wrappedValue: dependencies.dockedBrowserCoordinator)
        _dockedAgentPreviewCoordinator = StateObject(wrappedValue: dependencies.dockedAgentPreviewCoordinator)
        _boardStore = StateObject(wrappedValue: dependencies.boardStore)
        _vibespaceShortcutProvider = StateObject(wrappedValue: dependencies.vibespaceShortcutProvider)
        _hasAcceptedDisclaimer = State(initialValue: dependencies.hasAcceptedDisclaimer)
        vibespaceManagement = container.vibespaceManagement
    }

    var terminalSpotlightCoordinator: TerminalSpotlightCoordinator {
        stableDependencies.terminalSpotlightCoordinator
    }

    var sshPickerOverlayController: SSHPickerOverlayController {
        stableDependencies.sshPickerOverlayController
    }

    var vibespaceCloneRepositoryCoordinator: VibeSpaceCloneRepositoryCoordinator {
        stableDependencies.vibespaceCloneRepositoryCoordinator
    }

    var stackedRailStore: StackedRailTerminalStore {
        stableDependencies.stackedRailStore
    }

    var homeCatalogCoordinator: HomeCatalogCoordinator {
        stableDependencies.homeCatalogCoordinator
    }

    var vibespaceCanvasActionsCoordinator: VibeSpaceCanvasActionsCoordinator {
        stableDependencies.vibespaceCanvasActionsCoordinator
    }

    private var vibespaceLifecycleState: VibeSpaceLifecycleState {
        VibeSpaceLifecycleState(
            activeVibeSpaceID: activeVibeSpaceID,
            vibespaceCount: vibespaceCatalogStore.count
        )
    }

    private var vibespaceSourceControlSyncState: VibeSpaceSourceControlSyncState {
        VibeSpaceSourceControlSyncState(
            activeVibeSpaceID: activeVibeSpaceID,
            projectPaths: activeVibeSpaceSession.projects.map { $0.rootURL.standardizedFileURL.path },
            focusedProjectID: activeVibeSpaceSession.focusedProject?.id,
            selectedFilePath: activeVibeSpaceSession.sourceControlSelectedFileURL?.standardizedFileURL.path,
            sourceControlSettings: activeVibeSpaceSession.vibespace?.sourceControlSettings ?? .default
        )
    }

    private var acpVibeSpaceSyncState: ACPVibeSpaceSyncState {
        let focusedProjectIdentifier = activeVibeSpaceSession.focusedProject?.projectIdentifier
        return ACPVibeSpaceSyncState(
            vibespaceID: activeVibeSpaceID,
            focusedProjectIdentifier: focusedProjectIdentifier,
            defaultAgentID: acpDefaultAgentID,
            projectOverrideAgentID: focusedProjectIdentifier.flatMap { identifier in
                guard let activeVibeSpaceID else { return nil }
                return projectACPAgentOverrideID(for: activeVibeSpaceID, projectPath: identifier)
            }
        )
    }

    var activeVibeSpaceID: UUID? {
        appShellStore.activeVibeSpaceID
    }

    var isShowingHome: Bool {
        appShellStore.isShowingHome
    }

    var activeSurface: AppShellStore.ActiveSurface? {
        appShellStore.activeSurface
    }

    var activeModalSheet: AppShellStore.ActiveModalSheet? {
        appShellStore.activeModalSheet
    }

    var vibespaceSidebarTab: FolderExplorerViewModel.SidebarTab {
        appShellStore.vibespaceSidebarTab
    }

    var isVibeSpaceSidebarVisible: Bool {
        appShellStore.isVibeSpaceSidebarVisible
    }

    var activeVibeSpaceSettingsVibeSpaceID: UUID? {
        appShellStore.activeVibeSpaceSettingsVibeSpaceID
    }

    var isPresentingSurface: Bool {
        appShellStore.isPresentingSurface
    }

    @ViewBuilder
    var mainContent: some View {
        if let vibespaceSettingsVibeSpaceID = activeVibeSpaceSettingsVibeSpaceID {
            vibespaceSettingsSheet(for: vibespaceSettingsVibeSpaceID)
        } else if case .appSettings = activeSurface {
            appSettingsSheet()
        } else if !hasAnyVibeSpace || isShowingHome {
            emptyState
        } else {
            projectCanvas
        }
    }

    @ViewBuilder
    private var walkthroughOverlayLayer: some View {
        if walkthroughController.isPresented {
            FeatureWalkthroughOverlay(controller: walkthroughController)
        }
    }

    private var styledContent: some View {
        shellContent
            .background(activeThemePalette.windowBackgroundColor)
            .applyingAppAccentTheme(activeThemePalette.accentColor)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleExternalFileDrop(providers)
            }
    }

    private var shouldPresentDisclaimer: Bool {
        hasResolvedDisclaimerState && !hasAcceptedDisclaimer
    }

    private var shouldBlockForDisclaimerBootstrap: Bool {
        !hasResolvedDisclaimerState
    }

    private func bootstrapAppEntryState() {
        applyUITestOverridesIfNeeded()
        ensureAuthDefaultsIfNeeded()
        hasAcceptedDisclaimer = vibespaceManagement.hasAcceptedDisclaimer()
        hasResolvedDisclaimerState = true
        restoreDetachedTerminalBoardWindowsForActiveVibeSpace()
    }

    private func handleExternalFileDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) { [self] in
            guard !urls.isEmpty else { return }
            openFilesInShelf(urls)
        }
        return true
    }

    private func resolvedGhosttyProjectRootURL(for currentDirectoryURL: URL?, sessionID: UUID?) -> URL? {
        if let sessionID {
            if let activeMatch = activeVibeSpaceSession.projects.first(where: { project in
                project.terminal.tabs.contains { tab in
                    project.terminal.session(for: tab.id)?.id == sessionID
                }
            }) {
                return activeMatch.rootURL.standardizedFileURL
            }

            if let globalMatch = allVibeSpaceProjects().first(where: { entry in
                entry.project.terminal.tabs.contains { tab in
                    entry.project.terminal.session(for: tab.id)?.id == sessionID
                }
            }) {
                return globalMatch.project.rootURL.standardizedFileURL
            }
        }

        guard let currentDirectoryURL else { return nil }
        return VibeSpaceProjectRoutingUseCase()
            .terminalProjectMatch(
                for: currentDirectoryURL.standardizedFileURL,
                preferredProjectRootURL: currentDirectoryURL.standardizedFileURL,
                candidates: vibespaceCatalogStore.allProjects()
            )?
            .project
            .rootURL
            .standardizedFileURL
    }

    /// F021-R15: resolve the owning project path for a content-viewer tab.
    /// Returns nil for tab kinds that have no project association (vibeCast,
    /// acpPane). For file tabs, finds the longest project-root prefix match.
    private func resolveOwningProjectPath(for tab: ContentViewerTab) -> String? {
        let projects = activeVibeSpaceSession.projects
        switch tab.kind {
        case .file(let reference):
            let normalizedFilePath = reference.url.standardizedFileURL.path
            let candidates = projects.map { $0.projectIdentifier }
            return candidates
                .filter { normalizedFilePath == $0 || normalizedFilePath.hasPrefix($0 + "/") }
                .max(by: { $0.count < $1.count })
        case .webPage(let reference):
            return reference.projectPath
        case .terminal(let projectID, _):
            return projects.first(where: { $0.id == projectID })?.projectIdentifier
        case .vibeCast, .todos, .acpPane:
            return nil
        }
    }

    private var lifecycleAwareContent: some View {
        styledContent
            .onAppear {
                contentViewerStore.splitStore = splitViewStore
                applyUITestOverridesIfNeeded()
                ensureAuthDefaultsIfNeeded()
                shelfStore.loadIfNeeded()
                handleInitialCatalogLoad()
                synchronizeVibeSpaceSidebarExpansion()
                handleVibeSpaceLifecycleChange()
                syncVibeSpaceSourceControlContext()
                syncVibeSpaceShortcutProvider()
            }
            .onDisappear {
                homeCatalogCoordinator.cancelCatalogLoading()
                vibespaceHydrationCoordinator.cancelVibeSpaceHydration()
                terminalSpotlightCoordinator.dismiss(animated: false)
                vibespaceHydrationCoordinator.persistEditorSessionStateNow()
            }
            .onReceive(splitViewStore.objectWillChange) { _ in
                scheduleEditorSessionStateSave()
            }
            .onChange(of: vibespaceLifecycleState) { _, _ in
                handleVibeSpaceLifecycleChange()
            }
            .onChange(of: activeVibeSpaceSession.vibespace?.name) { _, _ in
                syncWindowTitleWithVibeSpace()
            }
            .onChange(of: selectedVibeSpaceCanvasMode) { _, _ in
                syncWindowTitleWithVibeSpace()
            }
            .onChange(of: activeVibeSpaceSession.focusedProject?.id) { _, _ in
                syncWindowTitleWithVibeSpace()
            }
            .onChange(of: contentViewerStore.markdownViewModel.fileURL) { _, fileURL in
                shelfStore.syncSelection(from: fileURL)
            }
            .onChange(of: activeVibeSpaceID) { oldID, newID in
                vibespaceHydrationCoordinator.handleActiveVibeSpaceChange(from: oldID, to: newID)
                synchronizeVibeSpaceSidebarExpansion()
                projectActivityTracker.track(projects: activeVibeSpaceSession.projects)
                syncVibeSpaceShortcutProvider(vibespaceIDOverride: newID)
                syncACPVibeSpaceContext(vibespaceIDOverride: newID)
                restoreDetachedTerminalBoardWindowsForActiveVibeSpace()
            }
            .onChange(of: activeVibeSpaceSession.focusedProject?.id) { _, _ in
                synchronizeVibeSpaceSidebarExpansion()
                syncVibeSpaceShortcutProvider()
                syncACPVibeSpaceContext()
            }
            .onChange(of: selectedVibeSpaceCanvasMode) { _, _ in
                if selectedVibeSpaceCanvasMode == .terminalOnly {
                    expandedVibeSpaceSidebarProjectPaths = []
                } else {
                    synchronizeVibeSpaceSidebarExpansion()
                }
            }
            .onChange(of: selectedProjectRailPosition) { _, _ in
                let isDetailedCanvas = selectedVibeSpaceCanvasMode == .detailed
                guard isDetailedCanvas else { return }
                synchronizeVibeSpaceSidebarExpansion()
            }
            .onChange(of: terminalShellPreference) { _, _ in
                UserDefaults.standard.set(
                    true,
                    forKey: AppPreferences.terminalShellPreferenceExplicitSelectionKey
                )
                guard let activeVibeSpaceID else { return }
                refreshTerminalShellResolutionContexts(for: activeVibeSpaceID)
            }
            .task(id: vibespaceSourceControlSyncState) {
                syncVibeSpaceSourceControlContext()
            }
            .task(id: acpVibeSpaceSyncState) {
                syncACPVibeSpaceContext()
            }
    }

    private func handleVibeSpaceLifecycleChange() {
        walkthroughController.evaluateAutoPresentation(hasVibeSpace: hasAnyVibeSpace)
        syncWindowTitleWithVibeSpace()
        syncVibeSpaceShortcutProvider()
        syncACPVibeSpaceContext()
    }

    private func syncVibeSpaceShortcutProvider(vibespaceIDOverride: UUID? = nil) {
        vibespaceShortcutProvider.update(
            vibespaceID: vibespaceIDOverride ?? activeVibeSpaceSession.vibespaceID ?? activeVibeSpaceID,
            focusedProjectPath: activeVibeSpaceSession.focusedProject?.rootURL.path
        )
    }

    private func syncACPVibeSpaceContext(vibespaceIDOverride: UUID? = nil) {
        let vibespaceID = vibespaceIDOverride ?? activeVibeSpaceSession.vibespaceID ?? activeVibeSpaceID
        let focusedProject = activeVibeSpaceSession.focusedProject
        appContainer.acpVibeSpaceContextStore.update(
            vibespaceID: vibespaceID,
            focusedProject: focusedProject
        )
        appContainer.acpVibeSpaceSessionService.sync(
            focusedProject: focusedProject,
            preferredAgentID: resolvedACPAgentID(
                vibespaceID: vibespaceID,
                focusedProject: focusedProject
            ),
            vibespaceID: vibespaceID
        )
    }

    private func resolvedACPAgentID(
        vibespaceID: UUID?,
        focusedProject: AnyProjectSession?
    ) -> String? {
        if let vibespaceID,
           let focusedProject,
           let overrideAgentID = projectACPAgentOverrideID(
               for: vibespaceID,
               projectPath: focusedProject.projectIdentifier
           ) {
            return overrideAgentID
        }
        return AppPreferences.acpDefaultAgentID()
    }

    private func handleInitialCatalogLoad() {
        let handledExternalOpen = homeCatalogCoordinator.drainPendingExternalOpenRequestsIfNeeded(
            openFilesInShelf: openFilesInShelf,
            focusProject: { project, forceTerminalFocus in
                vibespaceCanvasActionsCoordinator.focusProject(
                    project,
                    forceTerminalFocus: forceTerminalFocus
                )
            },
            openTerminalOnlyVibeSpaceView: {
                vibespaceCanvasActionsCoordinator.openTerminalOnlyVibeSpaceView()
            }
        )
        if !handledExternalOpen {
            loadVibeSpaceCatalogIfNeeded()
        }
    }

    private var notificationAwareContent: some View {
        applyVibeSpaceCommandNotifications(
            to: applyProjectLifecycleNotifications(
                to: applySystemAndGhosttyNotifications(to: lifecycleAwareContent)
            )
        )
    }

    /// F021-R13 / R18 / R19: park, activate (unpark), and remove project
    /// lifecycle commands posted from sidebar context menus. Split into its own
    /// modifier function to keep `applySystemAndGhosttyNotifications` within the
    /// SwiftUI type-checker's complexity budget.
    private func applyProjectLifecycleNotifications<Content: View>(to content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .parkProjectRequested)) { notification in
                // F021-R13: park the requested project (right-click → "Park Project").
                guard let projectID = notification.userInfo?[AppCommandUserInfoKey.projectID] as? UUID else { return }
                vibespaceCanvasActionsCoordinator.parkProject(id: projectID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .activateProjectRequested)) { notification in
                // F021-R13: activate (unpark) the requested project.
                guard let projectPath = notification.userInfo?[AppCommandUserInfoKey.projectPath] as? String else { return }
                _ = vibespaceCanvasActionsCoordinator.unparkProject(path: projectPath)
            }
            .onReceive(NotificationCenter.default.publisher(for: .removeProjectRequested)) { notification in
                // F021-R18: remove the requested live project (right-click → "Remove Project").
                guard let projectID = notification.userInfo?[AppCommandUserInfoKey.projectID] as? UUID else { return }
                vibespaceCanvasActionsCoordinator.removeProject(id: projectID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .removeParkedProjectRequested)) { notification in
                // F021-R19: remove the requested parked project without activating it.
                guard let projectPath = notification.userInfo?[AppCommandUserInfoKey.projectPath] as? String else { return }
                vibespaceCanvasActionsCoordinator.removeParkedProject(path: projectPath)
            }
    }

    private func applySystemAndGhosttyNotifications<Content: View>(to content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportDiagnostics)) { _ in
                DiagnosticsExportService.exportInteractive(
                    using: appContainer.vibespacePersistenceStore,
                    operationMetricsStore: appContainer.operationMetricsStore,
                    acpObservabilityStore: appContainer.acpObservabilityStore,
                    acpObservabilityMode: appContainer.experimentalFeatures.acpObservabilityMode
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .spotlightRestoreRequested)) { _ in
                restoreOrDismissSpotlight()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewBrowserRequested)) { notification in
                let url = notification.userInfo?["url"] as? URL ?? URL(string: "about:blank")!
                // F012-R17: each browser is owned by exactly one project. If the
                // caller did not supply a `projectPath`, auto-associate the new
                // browser with the currently focused project. If no project is
                // focused, block creation — there is no valid owner.
                let resolvedProjectPath = (notification.userInfo?["projectPath"] as? String)
                    ?? activeVibeSpaceSession.focusedProject?.projectIdentifier
                guard let projectPath = resolvedProjectPath else {
                    agentCLILogger.notice("browser open suppressed: no focused project to own browser")
                    return
                }
                let browserID = notification.userInfo?["browserID"] as? UUID ?? UUID()

                // Resolve the user's current canvas mode. CLI-initiated opens MUST NOT
                // force a mode switch — the browser appears wherever the user is currently
                // looking. The board store is service-layer-owned so it is always available.
                let canvasMode: VibeSpaceCanvasMode = activeVibeSpaceID
                    .map { layoutPersistence.canvasMode(for: $0) } ?? .terminalOnly

                switch canvasMode {
                case .terminalOnly:
                    // Pin to the board and eagerly create the browser VM so subsequent
                    // CLI commands (snapshot, click, etc.) can reach the agentAPI without
                    // racing the view render cycle.
                    if boardStore.pinBrowserToDock(id: browserID, url: url, projectPath: projectPath) != nil {
                        _ = dockedBrowserCoordinator.viewModel(for: browserID, url: url)
                        agentCLILogger.notice("browser pinned to board: \(browserID.uuidString, privacy: .public)")
                    } else {
                        agentCLILogger.notice("browser pin failed (board full?) for \(browserID.uuidString, privacy: .public)")
                    }
                case .detailed:
                    // Open in the content viewer (visible in detailed mode).
                    // `ContentViewerStore.openWebPage` eagerly creates the detailed-view
                    // VM at the service layer via `browserTabEagerCreateHandler`, so
                    // `agentAPI(for:)` succeeds immediately for subsequent CLI commands.
                    contentViewerStore.openWebPage(url: url, projectPath: projectPath, browserID: browserID)
                    agentCLILogger.notice("browser opened in content viewer: \(browserID.uuidString, privacy: .public)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeBrowserRequested)) { notification in
                guard let browserID = notification.userInfo?["browserID"] as? UUID else { return }
                // Try the board first. If the browser is a pinned tile, removing
                // the tile state stops the view from re-rendering it (which would
                // otherwise resurrect the VM via `coordinator.viewModel(for:url:)`).
                if let surfaceID = boardStore.surfaceID(containing: browserID) {
                    boardStore.removeTile(browserID, surfaceID: surfaceID)
                    dockedBrowserCoordinator.removeViewModel(for: browserID)
                    agentCLILogger.notice("browser closed (board): \(browserID.uuidString, privacy: .public)")
                    return
                }
                // Otherwise look for a content-viewer tab in any editor group.
                // `splitViewStore.closeTab` invokes `browserTabCloseHandler` which
                // calls `coordinator.removeDetailedBrowser(browserID:)`, so the VM
                // is removed as part of closing the tab.
                let tabID = "web:\(browserID.uuidString)"
                for group in splitViewStore.editorGroups.values {
                    if let tab = group.tabs.first(where: { $0.id == tabID }) {
                        splitViewStore.closeTab(tab, in: group)
                        agentCLILogger.notice("browser closed (content viewer): \(browserID.uuidString, privacy: .public)")
                        return
                    }
                }
                // Not found in either surface — VM may still exist in the coordinator
                // dictionaries (e.g., from a pre-render eager create whose tile/tab
                // never reached the layout). Drop both kinds defensively.
                dockedBrowserCoordinator.removeViewModel(for: browserID)
                dockedBrowserCoordinator.removeDetailedBrowser(browserID: browserID)
                agentCLILogger.notice("browser closed (orphan vm): \(browserID.uuidString, privacy: .public)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .contentViewerTabActivated)) { notification in
                // F021-R15 / R16 / R17: when a content-viewer tab becomes active,
                // resolve its owning project and switch focus. Idempotent — the
                // focus call is suppressed if the resolved project is already
                // focused, so programmatic activations from `focusProject` itself
                // do not recurse.
                guard let tab = notification.userInfo?[AppCommandUserInfoKey.tab] as? ContentViewerTab else { return }
                guard let owningProjectPath = resolveOwningProjectPath(for: tab) else { return }
                let projects = activeVibeSpaceSession.projects
                guard let owner = projects.first(where: { $0.projectIdentifier == owningProjectPath }) else { return }
                if activeVibeSpaceSession.focusedProject?.id == owner.id { return }
                vibespaceCanvasActionsCoordinator.focusProject(owner)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardTileActivated)) { notification in
                // F021-R17: when a board tile becomes active, switch focused
                // project to the tile's owning project. Same idempotency guard
                // as the content-viewer tab listener.
                guard let projectPath = notification.userInfo?[AppCommandUserInfoKey.projectPath] as? String else { return }
                let projects = activeVibeSpaceSession.projects
                guard let owner = projects.first(where: { $0.projectIdentifier == projectPath }) else { return }
                if activeVibeSpaceSession.focusedProject?.id == owner.id { return }
                vibespaceCanvasActionsCoordinator.focusProject(owner)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghosttyOpenLinkTargetRequested)) { notification in
                guard let url = notification.userInfo?[AppCommandUserInfoKey.url] as? URL else { return }
                let currentDirectoryURL = notification.userInfo?[AppCommandUserInfoKey.currentDirectoryURL] as? URL
                let sessionID = notification.userInfo?[AppCommandUserInfoKey.sessionID] as? UUID
                openTerminalLinkTarget(
                    url,
                    preferredProjectRootURL: resolvedGhosttyProjectRootURL(
                        for: currentDirectoryURL,
                        sessionID: sessionID
                    )
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghosttyOpenFileSystemTargetRequested)) { notification in
                guard let url = notification.userInfo?[AppCommandUserInfoKey.url] as? URL else { return }
                let currentDirectoryURL = notification.userInfo?[AppCommandUserInfoKey.currentDirectoryURL] as? URL
                let sessionID = notification.userInfo?[AppCommandUserInfoKey.sessionID] as? UUID
                let line = notification.userInfo?[AppCommandUserInfoKey.line] as? Int
                let column = notification.userInfo?[AppCommandUserInfoKey.column] as? Int
                openTerminalFileSystemTarget(
                    TerminalFileSystemTarget(url: url, line: line, column: column),
                    preferredProjectRootURL: resolvedGhosttyProjectRootURL(
                        for: currentDirectoryURL,
                        sessionID: sessionID
                    )
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .terminalAddFileToShelfRequested)) { notification in
                guard let url = notification.userInfo?[AppCommandUserInfoKey.url] as? URL else { return }
                openFilesInShelf([url])
            }
    }

    private func applyVibeSpaceCommandNotifications<Content: View>(to content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .focusProjectByNumber)) { notification in
                guard let index = vibespaceCanvasActionsCoordinator.shortcutProjectIndex(from: notification) else { return }
                vibespaceCanvasActionsCoordinator.focusProject(numbered: index)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusNextProject)) { _ in
                vibespaceCanvasActionsCoordinator.focusAdjacentProject(offset: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPreviousProject)) { _ in
                vibespaceCanvasActionsCoordinator.focusAdjacentProject(offset: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusNextProjectTerminal)) { _ in
                vibespaceCanvasActionsCoordinator.focusAdjacentTerminal(inFocusedProjectBy: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPreviousProjectTerminal)) { _ in
                vibespaceCanvasActionsCoordinator.focusAdjacentTerminal(inFocusedProjectBy: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardNavigateRight)) { _ in
                guard terminalSpotlightCoordinator.spotlight != nil else { return }
                switchSpotlight(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardNavigateLeft)) { _ in
                guard terminalSpotlightCoordinator.spotlight != nil else { return }
                switchSpotlight(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardMoveProjectToNewWindowRequested)) { notification in
                guard let surfaceID = notification.userInfo?[AppCommandUserInfoKey.sourceSurfaceID] as? UUID else { return }
                bulkMoveCurrentProjectToNewWindow(sourceSurfaceID: surfaceID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardRecallProjectFromWindowRequested)) { notification in
                guard let surfaceID = notification.userInfo?[AppCommandUserInfoKey.sourceSurfaceID] as? UUID else { return }
                recallProjectFromWindow(sourceSurfaceID: surfaceID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDetailedVibeSpaceView)) { _ in
                vibespaceCanvasActionsCoordinator.openDetailedVibeSpaceView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTerminalOnlyVibeSpaceView)) { _ in
                vibespaceCanvasActionsCoordinator.openTerminalOnlyVibeSpaceView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleVibeCast)) { _ in
                vibespaceCanvasActionsCoordinator.toggleVibeCast()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTodos)) { _ in
                vibespaceCanvasActionsCoordinator.toggleTodos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createTerminalRequested)) { notification in
                createTerminalFromToolbar(notification: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
                appShellStore.presentAppSettings(.general)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openExternalPaths)) { _ in
                _ = homeCatalogCoordinator.drainPendingExternalOpenRequestsIfNeeded(
                    openFilesInShelf: openFilesInShelf,
                    focusProject: { project, forceTerminalFocus in
                        vibespaceCanvasActionsCoordinator.focusProject(
                            project,
                            forceTerminalFocus: forceTerminalFocus
                        )
                    },
                    openTerminalOnlyVibeSpaceView: {
                        vibespaceCanvasActionsCoordinator.openTerminalOnlyVibeSpaceView()
                    }
                )
            }
    }

    var body: some View {
        notificationAwareContent
            .allowsHitTesting(!(shouldPresentDisclaimer || shouldBlockForDisclaimerBootstrap))
            .accessibilityHidden(shouldPresentDisclaimer || shouldBlockForDisclaimerBootstrap)
            .toolbar {
                if activeVibeSpaceID != nil {
                    vibespaceActionsToolbarContent
                }
            }
            .overlay { walkthroughOverlayLayer }
            .overlay { quickCaptureOverlay }
            .onReceive(NotificationCenter.default.publisher(for: .quickCaptureTodo)) { _ in
                isShowingQuickCapture = true
            }
            .overlay {
                if let externalAgentSessionPreview {
                    ExternalAgentSessionPreviewPanel(
                        transcript: externalAgentSessionPreview,
                        onDismiss: { self.externalAgentSessionPreview = nil }
                    )
                    .zIndex(500)
                }
            }
            .overlay {
                if shouldBlockForDisclaimerBootstrap {
                    activeThemePalette.windowBackgroundColor
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                } else if shouldPresentDisclaimer {
                    disclaimerGate
                }
            }
            .onAppear(perform: bootstrapAppEntryState)
            .alert(
                AppStrings.Alert.vibespaceConfigModified,
                isPresented: Binding(
                    get: { untrustedVibeSpaceName != nil },
                    set: { if !$0 { untrustedVibeSpaceName = nil } }
                )
            ) {
                Button(AppStrings.Alert.iUnderstand) {
                    untrustedVibeSpaceName = nil
                }
            } message: {
                Text(
                    AppStrings.Alert.vibespaceConfigModifiedMessage(
                        vibespaceName: untrustedVibeSpaceName ?? ""
                    )
                )
            }
            // Apply env values at body level (outside `.toolbar { }`) so the
            // toolbar items, popovers presented from them, and any future
            // sheets/menus all inherit the configured theme palette, UI scale,
            // and crispyvibesTheme. Previously these lived on `styledContent`
            // (inside `notificationAwareContent`), which meant `.toolbar` was
            // outside the env-injected hierarchy and toolbar items resolved
            // env values to their hard-coded defaults (e.g. the `.ph`
            // palette's orange accent, default UI scale).
            //
            // NOTE: `.applyingAppAccentTheme` is intentionally NOT here — it
            // sets `.tint`, which `Menu` views automatically apply to their
            // label icons. Applying it at body level would tint every toolbar
            // Menu's icon with the accent color. It stays on `styledContent`
            // so the canvas content gets accent-tinted but the toolbar does
            // not. Popovers presented from toolbar items re-inject the
            // accent tint themselves where they need it.
            .applyingAppThemePalette(activeThemePalette)
            .applyingCrispyVibesUIScale(CrispyVibesUIScale(codeFontSize: codeFontSize))
            .buttonBorderShape(themeManager.theme.borderShape.buttonBorderShape)
            .environment(\.crispyvibesTheme, themeManager.theme)
            .environment(\.composeHistoryStore, appContainer.composeHistoryStore)
            .environmentObject(themeManager)
            .preferredColorScheme(preferredAppColorScheme)
    }
}
