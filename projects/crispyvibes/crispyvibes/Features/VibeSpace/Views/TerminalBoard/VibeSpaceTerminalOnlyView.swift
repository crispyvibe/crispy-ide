import SwiftUI
#if os(macOS)
import AppKit
#endif

struct VibeSpaceTerminalBoardSurfaceTransferTarget: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct VibeSpaceTerminalOnlyView: View {
    @Environment(\.appThemePalette) var appThemePalette
    @Environment(\.crispyvibesTheme) var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) var codeFontSize = AppPreferences.defaultCodeFontSize
    let vibespaceID: UUID?
    let surfaceID: UUID
    let isVisible: Bool
    let isSpotlightPresented: Bool
    let projects: [AnyProjectSession]
    let projectColorTagsByPath: [String: ProjectColorTag]
    let hiddenTerminalIDsByProjectPath: [String: Set<UUID>]
    let layoutPersistence: LayoutPersistenceService
    let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry
    let headerCornerRadii: RectangleCornerRadii
    let onAddProjectsRequested: () -> Void
    let onSpotlightRequested: (TerminalViewModel, UUID, String, Color?, URL?) -> Void
    let onACPSpotlightRequested: (UUID, UUID) -> Void
    let onTemporaryTerminalRequested: (TerminalViewModel, URL, String, Color?, URL?) -> Void
    let onTemporaryShortcutRequested: (TerminalViewModel, TerminalShortcutDefinition, URL, String, Color?, URL?) -> Void
    let onLinkTargetActivated: (URL, URL?) -> Void
    let onFileSystemTargetActivated: (TerminalFileSystemTarget, URL?) -> Void
    let onManageShortcutsRequested: () -> Void
    let shortcutDefinitionsForProjectPath: (String?) -> [TerminalShortcutDefinition]
    let onVibeCastSpotlightRequested: () -> Void
    var onTileDetachRequested: ((UUID, CGPoint) -> Void)? = nil
    var boardWindowTransferTargets: ((VibeSpaceTerminalBoardStore, UUID) -> [VibeSpaceTerminalBoardSurfaceTransferTarget])? = nil
    var onTileSendToNewBoardWindowRequested: ((UUID, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil
    var onTileSendToBoardWindowRequested: ((UUID, UUID, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil
    /// F048-R13: invoked from a tile's context menu "Send All From This
    /// Project to New Window" item. The callee bulk-moves every tile on
    /// `sourceSurfaceID` whose `projectPath == projectPath` to a new
    /// detached board window.
    var onTileSendAllFromProjectToNewBoardWindowRequested: ((String, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil
    var onOpenTerminalInEditorPane: ((UUID, UUID) -> Void)? = nil
    var vibeCastStore: VibeCastStore?
    var acpStoreLookup: ((UUID) -> ACPStandaloneSessionStore?)? = nil
    var createACPPaneStore: (() -> ACPStandaloneSessionStore)? = nil
    var restoreACPPaneStore: ((ACPStandalonePaneSnapshot) -> ACPStandaloneSessionStore)? = nil
    var removeACPPaneStore: ((UUID) -> Void)? = nil
    var showACPControls: Bool = false
    var dockedFileViewerCoordinator: DockedFileViewerCoordinator?
    var dockedBrowserCoordinator: DockedBrowserCoordinator?
    var dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator?
    var dockPreviewBridge: DockPreviewBridge?
    var onFileSpotlightRequested: ((UUID, URL) -> Void)?
    var onBrowserSpotlightRequested: ((UUID, URL) -> Void)?

    @StateObject var boardStore: VibeSpaceTerminalBoardStore
    @StateObject var interactionController = BoardInteractionController()
    @State var delegateAdapter: BoardInteractionDelegateAdapter?
    @State var boardAlertMessage: String?
    @State var currentBoardSize: CGSize = .zero
    init(
        vibespaceID: UUID?,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID,
        isVisible: Bool = true,
        isSpotlightPresented: Bool = false,
        projects: [AnyProjectSession],
        projectColorTagsByPath: [String: ProjectColorTag] = [:],
        hiddenTerminalIDsByProjectPath: [String: Set<UUID>] = [:],
        layoutPersistence: LayoutPersistenceService,
        terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry,
        headerCornerRadii: RectangleCornerRadii,
        onAddProjectsRequested: @escaping () -> Void,
        onSpotlightRequested: @escaping (TerminalViewModel, UUID, String, Color?, URL?) -> Void,
        onACPSpotlightRequested: @escaping (UUID, UUID) -> Void,
        onTemporaryTerminalRequested: @escaping (TerminalViewModel, URL, String, Color?, URL?) -> Void,
        onTemporaryShortcutRequested: @escaping (TerminalViewModel, TerminalShortcutDefinition, URL, String, Color?, URL?) -> Void,
        onLinkTargetActivated: @escaping (URL, URL?) -> Void,
        onFileSystemTargetActivated: @escaping (TerminalFileSystemTarget, URL?) -> Void,
        onManageShortcutsRequested: @escaping () -> Void,
        shortcutDefinitionsForProjectPath: @escaping (String?) -> [TerminalShortcutDefinition],
        onVibeCastSpotlightRequested: @escaping () -> Void = {},
        onTileDetachRequested: ((UUID, CGPoint) -> Void)? = nil,
        boardWindowTransferTargets: ((VibeSpaceTerminalBoardStore, UUID) -> [VibeSpaceTerminalBoardSurfaceTransferTarget])? = nil,
        onTileSendToNewBoardWindowRequested: ((UUID, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil,
        onTileSendToBoardWindowRequested: ((UUID, UUID, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil,
        onTileSendAllFromProjectToNewBoardWindowRequested: ((String, VibeSpaceTerminalBoardStore, UUID) -> Void)? = nil,
        onOpenTerminalInEditorPane: ((UUID, UUID) -> Void)? = nil,
        vibeCastStore: VibeCastStore? = nil,
        acpStoreLookup: ((UUID) -> ACPStandaloneSessionStore?)? = nil,
        createACPPaneStore: (() -> ACPStandaloneSessionStore)? = nil,
        restoreACPPaneStore: ((ACPStandalonePaneSnapshot) -> ACPStandaloneSessionStore)? = nil,
        removeACPPaneStore: ((UUID) -> Void)? = nil,
        showACPControls: Bool = false,
        dockedFileViewerCoordinator: DockedFileViewerCoordinator? = nil,
        dockedBrowserCoordinator: DockedBrowserCoordinator? = nil,
        dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator? = nil,
        dockPreviewBridge: DockPreviewBridge? = nil,
        onFileSpotlightRequested: ((UUID, URL) -> Void)? = nil,
        onBrowserSpotlightRequested: ((UUID, URL) -> Void)? = nil,
        boardStore: VibeSpaceTerminalBoardStore
    ) {
        self.vibespaceID = vibespaceID
        self.surfaceID = surfaceID
        self.isVisible = isVisible
        self.isSpotlightPresented = isSpotlightPresented
        self.projects = projects
        self.projectColorTagsByPath = projectColorTagsByPath
        self.hiddenTerminalIDsByProjectPath = hiddenTerminalIDsByProjectPath
        self.layoutPersistence = layoutPersistence
        self.terminalBoardStandaloneRegistry = terminalBoardStandaloneRegistry
        self.headerCornerRadii = headerCornerRadii
        self.onAddProjectsRequested = onAddProjectsRequested
        self.onSpotlightRequested = onSpotlightRequested
        self.onACPSpotlightRequested = onACPSpotlightRequested
        self.onTemporaryTerminalRequested = onTemporaryTerminalRequested
        self.onTemporaryShortcutRequested = onTemporaryShortcutRequested
        self.onLinkTargetActivated = onLinkTargetActivated
        self.onFileSystemTargetActivated = onFileSystemTargetActivated
        self.onManageShortcutsRequested = onManageShortcutsRequested
        self.shortcutDefinitionsForProjectPath = shortcutDefinitionsForProjectPath
        self.onVibeCastSpotlightRequested = onVibeCastSpotlightRequested
        self.onTileDetachRequested = onTileDetachRequested
        self.boardWindowTransferTargets = boardWindowTransferTargets
        self.onTileSendToNewBoardWindowRequested = onTileSendToNewBoardWindowRequested
        self.onTileSendToBoardWindowRequested = onTileSendToBoardWindowRequested
        self.onTileSendAllFromProjectToNewBoardWindowRequested = onTileSendAllFromProjectToNewBoardWindowRequested
        self.onOpenTerminalInEditorPane = onOpenTerminalInEditorPane
        self.vibeCastStore = vibeCastStore
        self.acpStoreLookup = acpStoreLookup
        self.createACPPaneStore = createACPPaneStore
        self.restoreACPPaneStore = restoreACPPaneStore
        self.removeACPPaneStore = removeACPPaneStore
        self.showACPControls = showACPControls
        self.dockedFileViewerCoordinator = dockedFileViewerCoordinator
        self.dockedBrowserCoordinator = dockedBrowserCoordinator
        self.dockedAgentPreviewCoordinator = dockedAgentPreviewCoordinator
        self.dockPreviewBridge = dockPreviewBridge
        self.onFileSpotlightRequested = onFileSpotlightRequested
        self.onBrowserSpotlightRequested = onBrowserSpotlightRequested
        _boardStore = StateObject(wrappedValue: boardStore)
    }

    var body: some View {
        applyBoardLifecycle(to: boardContent)
    }
}
