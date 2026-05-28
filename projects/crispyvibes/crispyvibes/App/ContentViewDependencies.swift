import SwiftUI

@MainActor
struct ContentViewDependencies {
    let appShellStore: AppShellStore
    let vibespaceCatalogStore: VibeSpaceCatalogStore
    let vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator
    let walkthroughController: FeatureWalkthroughController
    let layoutPersistence: LayoutPersistenceService
    let shelfStore: ShelfStore
    let themeManager: CrispyVibesThemeManager
    let vibespaceSourceControlViewModel: VibeSpaceSourceControlViewModel
    let contentViewerStore: ContentViewerStore
    let projectActivityTracker: ProjectActivityTracker
    let splitViewStore: SplitViewStore
    let stableDependencies: ContentViewStableDependencies
    let dockPreviewBridge: DockPreviewBridge
    let dockedFileViewerCoordinator: DockedFileViewerCoordinator
    let dockedBrowserCoordinator: DockedBrowserCoordinator
    let dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator
    /// Service-layer-owned terminal board store. Created in
    /// `AppContainer.makeContentViewDependencies` so it is available before any view
    /// renders (required for Agent CLI commands that manipulate board tiles).
    let boardStore: VibeSpaceTerminalBoardStore
    let vibespaceShortcutProvider: VibeSpaceShortcutProvider
    let hasAcceptedDisclaimer: Bool
}

@MainActor
final class ContentViewStableDependencies: ObservableObject {
    let terminalSpotlightCoordinator: TerminalSpotlightCoordinator
    let vibespaceCloneRepositoryCoordinator: VibeSpaceCloneRepositoryCoordinator
    let stackedRailStore: StackedRailTerminalStore
    let homeCatalogCoordinator: HomeCatalogCoordinator
    let vibespaceCanvasActionsCoordinator: VibeSpaceCanvasActionsCoordinator
    let sshPickerOverlayController: SSHPickerOverlayController

    init(
        appContainer: AppContainer,
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator,
        shelfStore: ShelfStore,
        walkthroughController: FeatureWalkthroughController,
        layoutPersistence: LayoutPersistenceService,
        contentViewerStore: ContentViewerStore,
        splitViewStore: SplitViewStore,
        dockPreviewBridge: DockPreviewBridge? = nil,
        canvasModeProvider: (() -> VibeSpaceCanvasMode)? = nil,
        dockedBrowserCoordinator: DockedBrowserCoordinator? = nil
    ) {
        let terminalSpotlightCoordinator = appContainer.makeTerminalSpotlightCoordinator()
        let vibespaceCloneRepositoryCoordinator = appContainer.makeVibeSpaceCloneRepositoryCoordinator()
        let stackedRailStore = appContainer.makeStackedRailTerminalStore()

        self.terminalSpotlightCoordinator = terminalSpotlightCoordinator
        self.vibespaceCloneRepositoryCoordinator = vibespaceCloneRepositoryCoordinator
        self.stackedRailStore = stackedRailStore
        self.sshPickerOverlayController = SSHPickerOverlayController()
        self.homeCatalogCoordinator = HomeCatalogCoordinator(
            appContainer: appContainer,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            vibespaceManagement: appContainer.vibespaceManagement,
            layoutPersistence: layoutPersistence,
            shelfStore: shelfStore,
            walkthroughController: walkthroughController,
            terminalSpotlightCoordinator: terminalSpotlightCoordinator,
            vibespaceHydrationCoordinator: vibespaceHydrationCoordinator
        )
        self.vibespaceCanvasActionsCoordinator = VibeSpaceCanvasActionsCoordinator(
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            vibespaceManagement: appContainer.vibespaceManagement,
            vibespaceHydrationCoordinator: vibespaceHydrationCoordinator,
            vibespaceInteraction: appContainer.vibespaceInteraction,
            splitViewStore: splitViewStore,
            contentViewerStore: contentViewerStore,
            layoutPersistence: layoutPersistence,
            commentLifecycle: appContainer.commentLifecycleCoordinator
        )
        self.vibespaceCanvasActionsCoordinator.dockPreviewBridge = dockPreviewBridge
        self.vibespaceCanvasActionsCoordinator.canvasModeProvider = canvasModeProvider
        self.vibespaceCanvasActionsCoordinator.operationMetricsStore = appContainer.operationMetricsStore
        // F012-R18 / F021-R10: enables browser teardown on project remove + park.
        self.vibespaceCanvasActionsCoordinator.dockedBrowserCoordinator = dockedBrowserCoordinator
        // F044-R80–R82: enable CLI vibespace.addProject / removeProject / parkProject.
        appContainer.cliCommandRouter.attachVibeSpaceActionsCoordinator(self.vibespaceCanvasActionsCoordinator)
    }
}
