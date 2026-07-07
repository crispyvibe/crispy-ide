import AppKit
import Combine
import SwiftUI

struct VibeSpaceCanvasSurfaceView<StackedProjectRail: View, FocusedProjectPane: View, TerminalSpotlightOverlay: View>: View {
    @Environment(\.appThemePalette) private var appThemePalette
    private struct ProjectRailSplitConfiguration {
        let isVerticalSplit: Bool
        let primaryAtEnd: Bool
        let primarySize: Binding<CGFloat>
        let minPrimary: CGFloat
        let maxPrimary: CGFloat
        let minSecondary: CGFloat
    }

    let vibespaceID: UUID?
    let vibespaceView: VibeSpaceViewContext
    let stackedRailObservedVibeSpace: StackedRailObservedVibeSpace
    let projectActivityTracker: ProjectActivityTracker
    let contentViewerStore: ContentViewerStore
    let splitViewStore: SplitViewStore
    let acpVibeSpaceSessionService: ACPVibeSpaceSessionService
    let layoutPersistence: LayoutPersistenceService
    let stackedRailOverlayCoordinator: StackedRailExpansionOverlayCoordinator
    let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry
    /// F049: optional comment store. When non-nil, the content viewer renders
    /// the per-pane comments side-panel for file tabs.
    var commentStore: VibeSpaceCommentStore? = nil
    let isSpotlightPresented: Bool
    let contentHeaderCornerRadii: RectangleCornerRadii
    let contentPanelCornerRadii: RectangleCornerRadii
    let activeVibeSpaceHiddenRailTerminalIDsByProjectPath: [String: Set<UUID>]
    let projectColorTagsByPath: [String: ProjectColorTag]
    let dockedFileViewerCoordinator: DockedFileViewerCoordinator?
    let dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator?
    let dockPreviewBridge: DockPreviewBridge?
    var dockedBrowserCoordinator: DockedBrowserCoordinator?
    var onFileSpotlightRequested: ((UUID, URL) -> Void)?
    var onBrowserSpotlightRequested: ((UUID, URL) -> Void)?
    /// Service-layer-owned terminal board store. Passed in instead of created as
    /// a `@StateObject` inside the board view so it is reachable from the CLI router
    /// and notification handlers regardless of canvas mode.
    let boardStore: VibeSpaceTerminalBoardStore
    let onAddProjectsRequested: () -> Void
    let onSpotlightRequested: (TerminalViewModel, UUID, String, Color?, URL?) -> Void
    let onACPSpotlightRequested: (UUID, UUID) -> Void
    let onTemporaryTerminalRequested: (TerminalViewModel, URL, String, Color?, URL?) -> Void
    let onTemporaryShortcutRequested: (TerminalViewModel, TerminalShortcutDefinition, URL, String, Color?, URL?) -> Void
    let onManageShortcutsRequested: () -> Void
    let shortcutDefinitionsForProjectPath: (String?) -> [TerminalShortcutDefinition]
    let onVibeCastSpotlightRequested: () -> Void
    let onTileDetachRequested: (UUID, CGPoint) -> Void
    let boardWindowTransferTargets: (VibeSpaceTerminalBoardStore, UUID) -> [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onTileSendToNewBoardWindowRequested: (UUID, VibeSpaceTerminalBoardStore, UUID) -> Void
    let onTileSendToBoardWindowRequested: (UUID, UUID, VibeSpaceTerminalBoardStore, UUID) -> Void
    /// F048-R13: bulk-move every tile on `sourceSurfaceID` whose `projectPath`
    /// matches the right-clicked tile's project to a new detached board window.
    let onTileSendAllFromProjectToNewBoardWindowRequested: (String, VibeSpaceTerminalBoardStore, UUID) -> Void
    let onOpenTerminalInEditorPane: (UUID, UUID) -> Void
    let onLinkTargetActivated: (URL, URL?) -> Void
    let onFileSystemTargetActivated: (TerminalFileSystemTarget, URL?) -> Void
    let onSynchronizeStackedRailStore: () -> Void
    let onDismissTerminalSpotlight: () -> Void
    let stackedProjectRail: () -> StackedProjectRail
    let focusedProjectPane: () -> FocusedProjectPane
    let terminalSpotlightOverlay: () -> TerminalSpotlightOverlay

    @State private var activatedCanvasModes: Set<VibeSpaceCanvasMode> = []
    @StateObject private var boardInlinePickerOverlayController = BoardInlinePickerOverlayController()

    private var projectRailSplitConfiguration: ProjectRailSplitConfiguration {
        switch vibespaceView.selectedRailPosition {
        case .left:
            return ProjectRailSplitConfiguration(
                isVerticalSplit: true,
                primaryAtEnd: false,
                primarySize: vibespaceView.railSizeBinding(for: .left),
                minPrimary: 150,
                maxPrimary: .greatestFiniteMagnitude,
                minSecondary: 0
            )
        case .right:
            return ProjectRailSplitConfiguration(
                isVerticalSplit: true,
                primaryAtEnd: true,
                primarySize: vibespaceView.railSizeBinding(for: .right),
                minPrimary: 150,
                maxPrimary: .greatestFiniteMagnitude,
                minSecondary: 0
            )
        case .top:
            return ProjectRailSplitConfiguration(
                isVerticalSplit: false,
                primaryAtEnd: false,
                primarySize: vibespaceView.railSizeBinding(for: .top),
                minPrimary: 80,
                maxPrimary: 420,
                minSecondary: 120
            )
        case .bottom:
            return ProjectRailSplitConfiguration(
                isVerticalSplit: false,
                primaryAtEnd: true,
                primarySize: vibespaceView.railSizeBinding(for: .bottom),
                minPrimary: 80,
                maxPrimary: 420,
                minSecondary: 120
            )
        }
    }

    var body: some View {
        ZStack {
            if shouldRenderCanvasMode(.detailed) {
                detailedProjectCanvas
                    .environment(
                        \.terminalHostOwnershipParticipationEnabled,
                        vibespaceView.selectedCanvasMode == .detailed
                    )
                    .environment(
                        \.browserHostOwnershipParticipationEnabled,
                        vibespaceView.selectedCanvasMode == .detailed
                    )
                    .opacity(vibespaceView.selectedCanvasMode == .detailed ? 1 : 0)
                    .allowsHitTesting(vibespaceView.selectedCanvasMode == .detailed)
                    .accessibilityHidden(vibespaceView.selectedCanvasMode != .detailed)
                    .zIndex(vibespaceView.selectedCanvasMode == .detailed ? 1 : 0)
            }

            if shouldRenderCanvasMode(.terminalOnly) {
                terminalOnlyProjectCanvas
                    .environment(
                        \.terminalHostOwnershipParticipationEnabled,
                        vibespaceView.selectedCanvasMode == .terminalOnly
                    )
                    .environment(
                        \.browserHostOwnershipParticipationEnabled,
                        vibespaceView.selectedCanvasMode == .terminalOnly
                    )
                    .opacity(vibespaceView.selectedCanvasMode == .terminalOnly ? 1 : 0)
                    .allowsHitTesting(vibespaceView.selectedCanvasMode == .terminalOnly)
                    .accessibilityHidden(vibespaceView.selectedCanvasMode != .terminalOnly)
                    .zIndex(vibespaceView.selectedCanvasMode == .terminalOnly ? 1 : 0)
            }

            if vibespaceView.selectedCanvasMode == .detailed {
                StackedRailExpansionCanvasOverlay(
                    coordinator: stackedRailOverlayCoordinator
                )
                .zIndex(220)
            }
        }
        .padding(.leading, 0)
        .padding(.trailing, 0)
        .padding(.bottom, 0)
        .overlay {
            terminalSpotlightOverlay()
        }
        .overlay {
            VibeSpaceInlinePickerOverlayLayer(controller: boardInlinePickerOverlayController)
                .zIndex(300)
        }
        .environment(\.boardInlinePickerOverlayController, boardInlinePickerOverlayController)
        .onChange(of: vibespaceView.selectedCanvasMode) { _, _ in
            activatedCanvasModes.insert(vibespaceView.selectedCanvasMode)
            stackedRailOverlayCoordinator.dismiss()
            onDismissTerminalSpotlight()
        }
        .onChange(of: vibespaceID) { _, _ in
            stackedRailOverlayCoordinator.dismiss()
            onDismissTerminalSpotlight()
            onSynchronizeStackedRailStore()
        }
        .onAppear(perform: onSynchronizeStackedRailStore)
        .onAppear {
            activatedCanvasModes.insert(vibespaceView.selectedCanvasMode)
        }
        .onChange(of: stackedRailObservedVibeSpace) { _, _ in
            onSynchronizeStackedRailStore()
        }
        .onChange(of: vibespaceView.activeVibeSpaceProjects.map(\.id)) { _, _ in
            projectActivityTracker.track(projects: vibespaceView.activeVibeSpaceProjects)
        }
    }

    private func shouldRenderCanvasMode(_ mode: VibeSpaceCanvasMode) -> Bool {
        activatedCanvasModes.contains(mode) || vibespaceView.selectedCanvasMode == mode
    }

    private var contentViewerSurface: some View {
        ContentViewerView(
            store: contentViewerStore,
            splitStore: splitViewStore,
            activityTracker: projectActivityTracker,
            acpVibeSpaceSessionService: acpVibeSpaceSessionService,
            vibespaceID: vibespaceID,
            projects: vibespaceView.activeVibeSpaceProjects,
            focusedProjectRootPath: vibespaceView.focusedProject?.rootURL.standardizedFileURL.path,
            projectColorTagsByPath: projectColorTagsByPath,
            terminalSessionResolver: { projectID, tabID in
                vibespaceView.activeVibeSpaceProjects.first(where: { $0.id == projectID })?.terminal.session(for: tabID)
            },
            dockedBrowserCoordinator: dockedBrowserCoordinator,
            onLinkTargetActivated: { url in
                onLinkTargetActivated(url, vibespaceView.focusedProject?.rootURL)
            },
            onFileSystemTargetActivated: { target in
                onFileSystemTargetActivated(target, vibespaceView.focusedProject?.rootURL)
            },
            commentStore: commentStore
        )
        .onHover { isHovering in
            if isHovering {
                stackedRailOverlayCoordinator.dismiss()
            }
        }
    }

    private var detailedContentPane: some View {
        Group {
            if vibespaceView.isDetailedTerminalPaneCollapsed {
                contentViewerSurface
                    .overlay(alignment: .bottomTrailing) {
                        expandTerminalTrayButton
                            .padding(.trailing, 14)
                            .padding(.bottom, 14)
                    }
            } else {
                NativeSplitView(
                    isVerticalSplit: false,
                    primaryAtEnd: true,
                    primarySize: vibespaceView.detailedTerminalPaneHeightBinding(),
                    minPrimary: 160,
                    maxPrimary: 10000,
                    minSecondary: 200
                ) {
                    focusedProjectPane()
                } secondary: {
                    contentViewerSurface
                }
            }
        }
    }

    private var expandTerminalTrayButton: some View {
        Button {
            vibespaceView.detailedTerminalPaneCollapsedBinding().wrappedValue = false
        } label: {
            Label("Show Terminal", systemImage: "chevron.up")
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(0.7), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vibespace.detailed.terminal-tray.expand")
    }

    @ViewBuilder
    var detailedProjectCanvas: some View {
        if vibespaceView.activeVibeSpaceProjects.count <= 1 {
            detailedContentPane
        } else {
            let configuration = projectRailSplitConfiguration
            NativeSplitView(
                isVerticalSplit: configuration.isVerticalSplit,
                primaryAtEnd: configuration.primaryAtEnd,
                primarySize: configuration.primarySize,
                minPrimary: configuration.minPrimary,
                maxPrimary: configuration.maxPrimary,
                minSecondary: configuration.minSecondary
            ) {
                stackedProjectRail()
            } secondary: {
                detailedContentPane
            }
        }
    }

    private var terminalOnlyProjectCanvas: some View {
        VibeSpaceTerminalOnlyView(
            vibespaceID: vibespaceID,
            isVisible: vibespaceView.selectedCanvasMode == .terminalOnly,
            isSpotlightPresented: isSpotlightPresented,
            projects: vibespaceView.activeVibeSpaceProjects,
            projectColorTagsByPath: projectColorTagsByPath,
            hiddenTerminalIDsByProjectPath: [:],
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            headerCornerRadii: contentHeaderCornerRadii,
            onAddProjectsRequested: {
                onAddProjectsRequested()
            },
            onSpotlightRequested: { terminalViewModel, tabID, title, accentColor, owningProjectRootURL in
                onSpotlightRequested(terminalViewModel, tabID, title, accentColor, owningProjectRootURL)
            },
            onACPSpotlightRequested: { tileID, storeID in
                onACPSpotlightRequested(tileID, storeID)
            },
            onTemporaryTerminalRequested: { terminalViewModel, directoryURL, title, accentColor, owningProjectRootURL in
                onTemporaryTerminalRequested(
                    terminalViewModel,
                    directoryURL,
                    title,
                    accentColor,
                    owningProjectRootURL
                )
            },
            onTemporaryShortcutRequested: { terminalViewModel, shortcut, directoryURL, title, accentColor, owningProjectRootURL in
                onTemporaryShortcutRequested(
                    terminalViewModel,
                    shortcut,
                    directoryURL,
                    title,
                    accentColor,
                    owningProjectRootURL
                )
            },
            onLinkTargetActivated: { url, preferredProjectRootURL in
                onLinkTargetActivated(url, preferredProjectRootURL)
            },
            onFileSystemTargetActivated: { url, preferredProjectRootURL in
                onFileSystemTargetActivated(url, preferredProjectRootURL)
            },
            onManageShortcutsRequested: onManageShortcutsRequested,
            shortcutDefinitionsForProjectPath: shortcutDefinitionsForProjectPath,
            onVibeCastSpotlightRequested: {
                onVibeCastSpotlightRequested()
            },
            onTileDetachRequested: onTileDetachRequested,
            boardWindowTransferTargets: boardWindowTransferTargets,
            onTileSendToNewBoardWindowRequested: onTileSendToNewBoardWindowRequested,
            onTileSendToBoardWindowRequested: onTileSendToBoardWindowRequested,
            onTileSendAllFromProjectToNewBoardWindowRequested: onTileSendAllFromProjectToNewBoardWindowRequested,
            onOpenTerminalInEditorPane: { projectID, tabID in
                onOpenTerminalInEditorPane(projectID, tabID)
            },
            vibeCastStore: contentViewerStore.vibeCastStore,
            acpStoreLookup: { id in
                contentViewerStore.acpStore(for: id)
            },
            createACPPaneStore: {
                let store = contentViewerStore.makeACPStore(
                    focusedProject: acpVibeSpaceSessionService.focusedProject,
                    preferredAgentID: acpVibeSpaceSessionService.preferredAgentID,
                    vibespaceID: vibespaceID
                )
                contentViewerStore.ensureACPPaneTab(id: store.id)
                return store
            },
            restoreACPPaneStore: { snapshot in
                let store = contentViewerStore.restoreACPStore(
                    from: snapshot,
                    vibespaceID: vibespaceID
                )
                contentViewerStore.ensureACPPaneTab(id: store.id)
                return store
            },
            removeACPPaneStore: { id in
                contentViewerStore.removeACPStore(id: id)
            },
            showACPControls: true,
            dockedFileViewerCoordinator: dockedFileViewerCoordinator,
            dockedBrowserCoordinator: dockedBrowserCoordinator,
            dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
            dockPreviewBridge: dockPreviewBridge,
            onFileSpotlightRequested: onFileSpotlightRequested,
            onBrowserSpotlightRequested: onBrowserSpotlightRequested,
            boardStore: boardStore
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: contentPanelCornerRadii,
                style: .continuous
            )
        )
        .accessibilityIdentifier("vibespace.terminal-only")
    }
}

private struct VibeSpaceInlinePickerOverlayLayer: View {
    @ObservedObject var controller: BoardInlinePickerOverlayController

    var body: some View {
        if let presentation = controller.presentation {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        presentation.onDismiss?()
                    }
                BoardInlinePickerOverlayView(presentation: presentation)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct VibeSpaceSSHPickerOverlayLayer: View {
    @ObservedObject var controller: SSHPickerOverlayController

    var body: some View {
        if let presentation = controller.presentation {
            ZStack {
                // Click-blocking scrim — captures clicks so they don't fall through to the
                // canvas, but no visible color/dim (the glass background of the picker
                // needs to sample the canvas content).
                Color.clear
                    .contentShape(Rectangle())

                SSHConnectionPicker(
                    viewModel: presentation.viewModel,
                    profileStore: presentation.profileStore,
                    onFolderSelected: presentation.onFolderSelected,
                    onCancel: presentation.onCancel
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .transition(.opacity)
            .onExitCommand(perform: presentation.onCancel)
        }
    }
}

extension ContentView {
    var projectColorTagsByPath: [String: ProjectColorTag] {
        vibespaceView.activeVibeSpaceProjects.reduce(into: [:]) { result, project in
            guard let tag = vibespaceCanvasActionsCoordinator.colorTag(for: project) else { return }
            result[project.rootURL.standardizedFileURL.path] = tag
        }
    }

    var projectCanvas: some View {
        VibeSpaceCanvasSurfaceView(
            vibespaceID: vibespaceShell.activeVibeSpaceID,
            vibespaceView: vibespaceView,
            stackedRailObservedVibeSpace: stackedRailObservedVibeSpace,
            projectActivityTracker: projectActivityTracker,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            acpVibeSpaceSessionService: appContainer.acpVibeSpaceSessionService,
            layoutPersistence: layoutPersistence,
            stackedRailOverlayCoordinator: stackedRailOverlayCoordinator,
            terminalBoardStandaloneRegistry: appContainer.terminalBoardStandaloneRegistry,
            commentStore: appContainer.vibespaceCommentStore,
            isSpotlightPresented: terminalSpotlightCoordinator.spotlight != nil,
            contentHeaderCornerRadii: contentHeaderCornerRadii,
            contentPanelCornerRadii: contentPanelCornerRadii,
            activeVibeSpaceHiddenRailTerminalIDsByProjectPath: activeVibeSpaceHiddenRailTerminalIDsByProjectPath,
            projectColorTagsByPath: projectColorTagsByPath,
            dockedFileViewerCoordinator: dockedFileViewerCoordinator,
            dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
            dockPreviewBridge: dockPreviewBridge,
            dockedBrowserCoordinator: dockedBrowserCoordinator,
            onFileSpotlightRequested: { tileID, fileURL in
                pushCurrentSpotlightForRestore()
                presentFileSpotlight(tileID: tileID, fileURL: fileURL)
            },
            onBrowserSpotlightRequested: { tileID, url in
                presentBrowserSpotlight(tileID: tileID, url: url)
            },
            boardStore: boardStore,
            onAddProjectsRequested: {
                homeCatalogCoordinator.addProjectsToActiveVibeSpaceFromFolderPicker(
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
            },
            onSpotlightRequested: { terminalViewModel, tabID, title, accentColor, owningProjectRootURL in
                presentTerminalSpotlight(
                    terminalViewModel: terminalViewModel,
                    tabID: tabID,
                    title: title,
                    accentColor: accentColor,
                    owningProjectRootURL: owningProjectRootURL,
                    surfaceID: VibeSpaceTerminalBoardState.primarySurfaceID
                )
            },
            onACPSpotlightRequested: { tileID, storeID in
                presentACPSpotlight(tileID: tileID, storeID: storeID)
            },
            onTemporaryTerminalRequested: { terminalViewModel, directoryURL, title, accentColor, owningProjectRootURL in
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: directoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        createSplitTerminal(
                            in: terminalViewModel,
                            directoryURL: directoryURL,
                            surfaceID: VibeSpaceTerminalBoardState.primarySurfaceID,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            onTemporaryShortcutRequested: { terminalViewModel, shortcut, directoryURL, title, accentColor, owningProjectRootURL in
                presentTemporaryTerminalSpotlight(
                    title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? title
                        : shortcut.name,
                    accentColor: accentColor,
                    directoryURL: directoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        createSplitTerminal(
                            in: terminalViewModel,
                            directoryURL: directoryURL,
                            surfaceID: VibeSpaceTerminalBoardState.primarySurfaceID,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL,
                    initialCommand: shortcut.command
                )
            },
            onManageShortcutsRequested: {
                vibespaceShell.presentVibeSpaceSettings(.shortcuts)
            },
            shortcutDefinitionsForProjectPath: { projectPath in
                guard let activeVibeSpaceID = vibespaceShell.activeVibeSpaceID else { return [] }
                let vibespaceShortcuts = vibespaceShortcutProvider.vibespaceShortcuts
                let projectShortcuts = projectPath.map {
                    vibespaceManagement.projectShortcuts(
                        vibespaceID: activeVibeSpaceID,
                        projectPath: $0
                    )
                } ?? []
                return vibespaceShortcuts + projectShortcuts
            },
            onVibeCastSpotlightRequested: { presentVibeCastSpotlight() },
            onTileDetachRequested: { tileID, screenPoint in
                detachTerminalBoardTile(tileID, atScreenPoint: screenPoint)
            },
            boardWindowTransferTargets: { boardStore, sourceSurfaceID in
                terminalBoardWindowTransferTargets(
                    boardStore: boardStore,
                    sourceSurfaceID: sourceSurfaceID,
                    vibespaceID: vibespaceShell.activeVibeSpaceID
                )
            },
            onTileSendToNewBoardWindowRequested: { tileID, boardStore, sourceSurfaceID in
                sendTerminalBoardTileToNewWindow(
                    tileID,
                    boardStore: boardStore,
                    sourceSurfaceID: sourceSurfaceID,
                    vibespaceID: vibespaceShell.activeVibeSpaceID
                )
            },
            onTileSendToBoardWindowRequested: { tileID, targetSurfaceID, boardStore, sourceSurfaceID in
                sendTerminalBoardTile(
                    tileID,
                    boardStore: boardStore,
                    sourceSurfaceID: sourceSurfaceID,
                    targetSurfaceID: targetSurfaceID,
                    vibespaceID: vibespaceShell.activeVibeSpaceID
                )
            },
            onTileSendAllFromProjectToNewBoardWindowRequested: { projectPath, _, sourceSurfaceID in
                bulkMoveProjectToNewWindow(
                    projectPath: projectPath,
                    sourceSurfaceID: sourceSurfaceID
                )
            },
            onOpenTerminalInEditorPane: { projectID, tabID in
                contentViewerStore.activeGroup.openTab(.terminal(projectID: projectID, tabID: tabID))
            },
            onLinkTargetActivated: openTerminalLinkTarget,
            onFileSystemTargetActivated: { url, preferredProjectRootURL in
                openTerminalFileSystemTarget(
                    url,
                    preferredProjectRootURL: preferredProjectRootURL
                )
            },
            onSynchronizeStackedRailStore: synchronizeStackedRailStore,
            onDismissTerminalSpotlight: dismissTerminalSpotlight,
            stackedProjectRail: { stackedProjectRail },
            focusedProjectPane: { focusedProjectPane },
            terminalSpotlightOverlay: { terminalSpotlightOverlay }
        )
        .overlay {
            VibeSpaceSSHPickerOverlayLayer(controller: sshPickerOverlayController)
                .zIndex(310)
        }
    }

    func detachTerminalBoardTile(
        _ tileID: UUID,
        atScreenPoint screenPoint: CGPoint,
        excludingWindowID: UUID? = nil,
        sourceSurfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID
    ) {
        guard let vibespaceID = vibespaceShell.activeVibeSpaceID else { return }
        guard let boardStore = vibespaceHydrationCoordinator.boardStore else { return }
        guard let tile = boardStore.tile(for: tileID, includeMinimized: true, surfaceID: sourceSurfaceID) else { return }

        if sourceSurfaceID != boardStore.primarySurfaceID,
           appContainer.terminalBoardDetachedWindowManager.window(
            id: excludingWindowID,
            contains: screenPoint
           ) {
            return
        }

        if let targetSurfaceID = appContainer.terminalBoardDetachedWindowManager.surfaceID(
            vibespaceID: vibespaceID,
            atScreenPoint: screenPoint,
            excluding: excludingWindowID
        ) {
            _ = boardStore.moveTile(tileID, fromSurface: sourceSurfaceID, toSurface: targetSurfaceID)
            refreshDetachedBoardWindowTitle(
                boardStore: boardStore,
                surfaceID: targetSurfaceID,
                vibespaceID: vibespaceID
            )
            refreshDetachedBoardWindowTitle(
                boardStore: boardStore,
                surfaceID: sourceSurfaceID,
                vibespaceID: vibespaceID
            )
            closeDetachedSurfaceIfEmpty(
                boardStore: boardStore,
                sourceSurfaceID: sourceSurfaceID,
                sourceWindowID: excludingWindowID,
                vibespaceID: vibespaceID
            )
            return
        }

        if sourceSurfaceID != boardStore.primarySurfaceID,
           isScreenPointInsideNonDetachedAppWindow(screenPoint) {
            _ = boardStore.moveTile(tileID, fromSurface: sourceSurfaceID, toSurface: boardStore.primarySurfaceID)
            refreshDetachedBoardWindowTitle(
                boardStore: boardStore,
                surfaceID: sourceSurfaceID,
                vibespaceID: vibespaceID
            )
            closeDetachedSurfaceIfEmpty(
                boardStore: boardStore,
                sourceSurfaceID: sourceSurfaceID,
                sourceWindowID: excludingWindowID,
                vibespaceID: vibespaceID
            )
            return
        }

        let windowTitle = boardStore.displayTitle(for: tile)
        guard let detachedTile = boardStore.detachTile(tileID, fromSurface: sourceSurfaceID) else { return }
        let surfaceID = boardStore.createDetachedSurface(with: detachedTile, title: windowTitle)
        openDetachedTerminalBoardWindow(
            vibespaceID: vibespaceID,
            surfaceID: surfaceID,
            boardStore: boardStore,
            title: windowTitle
        )
        closeDetachedSurfaceIfEmpty(
            boardStore: boardStore,
            sourceSurfaceID: sourceSurfaceID,
            sourceWindowID: excludingWindowID,
            vibespaceID: vibespaceID
        )
    }

    func terminalBoardWindowTransferTargets(
        boardStore: VibeSpaceTerminalBoardStore,
        sourceSurfaceID: UUID,
        vibespaceID: UUID?
    ) -> [VibeSpaceTerminalBoardSurfaceTransferTarget] {
        var targets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = []

        if sourceSurfaceID != boardStore.primarySurfaceID {
            targets.append(
                VibeSpaceTerminalBoardSurfaceTransferTarget(
                    id: boardStore.primarySurfaceID,
                    title: AppStrings.Terminal.Tile.primaryBoardWindow
                )
            )
        }

        let detachedSurfaceIDs = appContainer.terminalBoardDetachedWindowManager.orderedSurfaceIDs(for: vibespaceID)
        for (index, surfaceID) in detachedSurfaceIDs.filter({ $0 != sourceSurfaceID }).enumerated() {
            targets.append(
                VibeSpaceTerminalBoardSurfaceTransferTarget(
                    id: surfaceID,
                    title: boardStore.surfaceTransferTitle(for: surfaceID, ordinal: index + 1)
                )
            )
        }

        return targets
    }

    func sendTerminalBoardTileToNewWindow(
        _ tileID: UUID,
        boardStore: VibeSpaceTerminalBoardStore,
        sourceSurfaceID: UUID,
        sourceWindowID: UUID? = nil,
        vibespaceID: UUID?
    ) {
        guard let vibespaceID else { return }
        guard let tile = boardStore.tile(for: tileID, includeMinimized: true, surfaceID: sourceSurfaceID) else { return }
        let windowTitle = boardStore.displayTitle(for: tile)
        guard let detachedTile = boardStore.detachTile(tileID, fromSurface: sourceSurfaceID) else { return }
        let targetSurfaceID = boardStore.createDetachedSurface(with: detachedTile, title: windowTitle)
        openDetachedTerminalBoardWindow(
            vibespaceID: vibespaceID,
            surfaceID: targetSurfaceID,
            boardStore: boardStore,
            title: windowTitle
        )
        refreshDetachedBoardWindowTitle(
            boardStore: boardStore,
            surfaceID: sourceSurfaceID,
            vibespaceID: vibespaceID
        )
        closeDetachedSurfaceIfEmpty(
            boardStore: boardStore,
            sourceSurfaceID: sourceSurfaceID,
            sourceWindowID: sourceWindowID,
            vibespaceID: vibespaceID
        )
    }

    func sendTerminalBoardTile(
        _ tileID: UUID,
        boardStore: VibeSpaceTerminalBoardStore,
        sourceSurfaceID: UUID,
        targetSurfaceID: UUID,
        sourceWindowID: UUID? = nil,
        vibespaceID: UUID?
    ) {
        guard sourceSurfaceID != targetSurfaceID else { return }
        guard boardStore.tile(for: tileID, includeMinimized: true, surfaceID: sourceSurfaceID) != nil else { return }
        guard boardStore.moveTile(tileID, fromSurface: sourceSurfaceID, toSurface: targetSurfaceID) else { return }
        refreshDetachedBoardWindowTitle(
            boardStore: boardStore,
            surfaceID: targetSurfaceID,
            vibespaceID: vibespaceID
        )
        refreshDetachedBoardWindowTitle(
            boardStore: boardStore,
            surfaceID: sourceSurfaceID,
            vibespaceID: vibespaceID
        )

        if targetSurfaceID == boardStore.primarySurfaceID {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            appContainer.terminalBoardDetachedWindowManager.focusSurface(targetSurfaceID, vibespaceID: vibespaceID)
        }

        closeDetachedSurfaceIfEmpty(
            boardStore: boardStore,
            sourceSurfaceID: sourceSurfaceID,
            sourceWindowID: sourceWindowID,
            vibespaceID: vibespaceID
        )
    }

    func refreshDetachedBoardWindowTitle(
        boardStore: VibeSpaceTerminalBoardStore,
        surfaceID: UUID,
        vibespaceID: UUID?
    ) {
        guard surfaceID != boardStore.primarySurfaceID else { return }
        guard !boardStore.isSurfaceEmpty(surfaceID) else { return }
        appContainer.terminalBoardDetachedWindowManager.setTitle(
            boardStore.surfaceTitle(for: surfaceID),
            forSurfaceID: surfaceID,
            vibespaceID: vibespaceID
        )
    }

    /// F048-R13: bulk-move every tile on `sourceSurfaceID` belonging to the
    /// currently focused project into a new detached board window. Used by the
    /// keyboard shortcut path; for a tile-anchored variant (context menu),
    /// see `bulkMoveProjectToNewWindow(projectPath:sourceSurfaceID:)`.
    ///
    /// Behavior per F048 spec:
    /// - **R14 board mode only**: no-op when `selectedCanvasMode != .terminalOnly`.
    /// - No focused project, or focused project has no tiles on the source
    ///   surface, → silent no-op.
    func bulkMoveCurrentProjectToNewWindow(sourceSurfaceID: UUID) {
        guard let focusedProject = vibespaceView.focusedProject else { return }
        bulkMoveProjectToNewWindow(
            projectPath: focusedProject.projectIdentifier,
            sourceSurfaceID: sourceSurfaceID,
            windowTitle: focusedProject.title
        )
    }

    /// F048-R13: bulk-move every tile on `sourceSurfaceID` belonging to
    /// `projectPath` into a new detached board window. Driven by both the
    /// keyboard shortcut (via `bulkMoveCurrentProjectToNewWindow`) and the
    /// tile context menu's "Send All From This Project" action.
    ///
    /// Behavior:
    /// - **R14 board mode only**: no-op when `selectedCanvasMode != .terminalOnly`.
    /// - Project has no tiles on the source surface → silent no-op.
    /// - Tiles are detached in a single store mutation; a fresh detached
    ///   surface is created with all of them; R15 source-surface
    ///   reorganization is automatic via the existing layout reflow.
    /// - The existing `closeDetachedSurfaceIfEmpty` path closes the source
    ///   window if the source itself is detached and now empty (consistent
    ///   with single-tile transfer behavior).
    func bulkMoveProjectToNewWindow(
        projectPath: String,
        sourceSurfaceID: UUID,
        windowTitle: String? = nil
    ) {
        guard vibespaceView.selectedCanvasMode == .terminalOnly else { return }
        guard let vibespaceID = vibespaceShell.activeVibeSpaceID else { return }

        let detachedTiles = boardStore.bulkDetachTilesForProject(
            projectPath,
            fromSurface: sourceSurfaceID
        )
        guard !detachedTiles.isEmpty else { return }

        let resolvedTitle = windowTitle
            ?? vibespaceView.activeVibeSpaceProjects
                .first(where: { $0.projectIdentifier == projectPath })?
                .title
            ?? URL(fileURLWithPath: projectPath).lastPathComponent
        let targetSurfaceID = boardStore.createDetachedSurface(
            with: detachedTiles,
            title: resolvedTitle
        )
        openDetachedTerminalBoardWindow(
            vibespaceID: vibespaceID,
            surfaceID: targetSurfaceID,
            boardStore: boardStore,
            title: resolvedTitle
        )

        let sourceWindowID = appContainer.terminalBoardDetachedWindowManager
            .windowID(forSurfaceID: sourceSurfaceID, vibespaceID: vibespaceID)
        refreshDetachedBoardWindowTitle(
            boardStore: boardStore,
            surfaceID: sourceSurfaceID,
            vibespaceID: vibespaceID
        )
        closeDetachedSurfaceIfEmpty(
            boardStore: boardStore,
            sourceSurfaceID: sourceSurfaceID,
            sourceWindowID: sourceWindowID,
            vibespaceID: vibespaceID
        )
    }

    /// F048-R16: bulk-recall every tile on a detached surface back to the
    /// primary surface, then close the now-empty detached window.
    ///
    /// Behavior:
    /// - Silent no-op when `sourceSurfaceID` is the primary surface (recall
    ///   only meaningful from a detached window).
    /// - Uses the existing `closeDetachedSurface(_:mergeIntoPrimary: true)`
    ///   flow which handles overflow gracefully (tiles exceeding the primary
    ///   surface's 16-tile cap roll into `minimizedTiles`).
    /// - The detached window's NSWindow is dismissed via the standard
    ///   `closeAfterTransfer` path so the user-close handler doesn't fire
    ///   double-merge.
    func recallProjectFromWindow(sourceSurfaceID: UUID) {
        guard sourceSurfaceID != boardStore.primarySurfaceID else { return }
        guard let vibespaceID = vibespaceShell.activeVibeSpaceID else { return }
        guard !boardStore.isSurfaceEmpty(sourceSurfaceID) else { return }

        let sourceWindowID = appContainer.terminalBoardDetachedWindowManager
            .windowID(forSurfaceID: sourceSurfaceID, vibespaceID: vibespaceID)
        boardStore.closeDetachedSurface(sourceSurfaceID, mergeIntoPrimary: true)
        appContainer.terminalBoardDetachedWindowManager.closeAfterTransfer(id: sourceWindowID)
    }

    /// Re-opens any detached terminal-board windows that the layout for the active
    /// vibespace declares as open. Called from ContentView's lifecycle on initial
    /// appear and on vibespace change. The board store is service-layer-owned, so
    /// `detachedSurfaces` is authoritative regardless of canvas mode.
    func restoreDetachedTerminalBoardWindowsForActiveVibeSpace() {
        guard let activeID = activeVibeSpaceID else { return }
        for surface in boardStore.detachedSurfaces {
            openDetachedTerminalBoardWindow(
                vibespaceID: activeID,
                surfaceID: surface.id,
                boardStore: boardStore,
                title: boardStore.surfaceTitle(for: surface.id)
            )
        }
    }

    func openDetachedTerminalBoardWindow(
        vibespaceID: UUID,
        surfaceID: UUID,
        boardStore: VibeSpaceTerminalBoardStore,
        title: String
    ) {
        guard !appContainer.terminalBoardDetachedWindowManager.containsSurface(surfaceID, vibespaceID: vibespaceID) else {
            return
        }
        var detachedWindowID: UUID?

        detachedWindowID = appContainer.terminalBoardDetachedWindowManager.openWindow(
            vibespaceID: vibespaceID,
            surfaceID: surfaceID,
            title: title,
            placement: boardStore.boardState.surface(id: surfaceID)?.placement,
            toolbarConfiguration: detachedTerminalBoardToolbarConfiguration(
                boardStore: boardStore,
                surfaceID: surfaceID,
                vibespaceID: vibespaceID
            ),
            onUserClose: { [weak boardStore] in
                boardStore?.closeDetachedSurface(surfaceID, mergeIntoPrimary: true)
            },
            onPlacementChanged: { [weak boardStore] placement in
                boardStore?.setSurfacePlacement(placement, for: surfaceID)
            },
            onTitleChanged: { [weak boardStore] title in
                boardStore?.setSurfaceTitle(title, for: surfaceID)
            }
        ) {
            DetachedTerminalBoardWindowRoot(themeManager: themeManager, commentStore: appContainer.vibespaceCommentStore) {
                DetachedTerminalBoardWindowContent(
                    vibespaceID: vibespaceID,
                    surfaceID: surfaceID,
                    boardStore: boardStore,
                    projects: vibespaceView.activeVibeSpaceProjects,
                    projectColorTagsByPath: projectColorTagsByPath,
                    layoutPersistence: layoutPersistence,
                    terminalBoardStandaloneRegistry: appContainer.terminalBoardStandaloneRegistry,
                    headerCornerRadii: contentHeaderCornerRadii,
                    terminalServices: appContainer.terminalServices,
                    vibeCastStore: contentViewerStore.vibeCastStore,
                    dockedFileViewerCoordinator: dockedFileViewerCoordinator,
                    dockedBrowserCoordinator: dockedBrowserCoordinator,
                    dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
                    onManageShortcutsRequested: {
                        vibespaceShell.presentVibeSpaceSettings(.shortcuts)
                    },
                    shortcutDefinitionsForProjectPath: { projectPath in
                        let vibespaceShortcuts = vibespaceShortcutProvider.vibespaceShortcuts
                        let projectShortcuts = projectPath.map {
                            vibespaceManagement.projectShortcuts(
                                vibespaceID: vibespaceID,
                                projectPath: $0
                            )
                        } ?? []
                        return vibespaceShortcuts + projectShortcuts
                    },
                    onTileDetachRequested: { tileID, screenPoint in
                        detachTerminalBoardTile(
                            tileID,
                            atScreenPoint: screenPoint,
                            excludingWindowID: detachedWindowID,
                            sourceSurfaceID: surfaceID
                        )
                    },
                    boardWindowTransferTargets: {
                        terminalBoardWindowTransferTargets(
                            boardStore: boardStore,
                            sourceSurfaceID: surfaceID,
                            vibespaceID: vibespaceID
                        )
                    },
                    onTileSendToNewBoardWindowRequested: { tileID in
                        sendTerminalBoardTileToNewWindow(
                            tileID,
                            boardStore: boardStore,
                            sourceSurfaceID: surfaceID,
                            sourceWindowID: detachedWindowID,
                            vibespaceID: vibespaceID
                        )
                    },
                    onTileSendToBoardWindowRequested: { tileID, targetSurfaceID in
                        sendTerminalBoardTile(
                            tileID,
                            boardStore: boardStore,
                            sourceSurfaceID: surfaceID,
                            targetSurfaceID: targetSurfaceID,
                            sourceWindowID: detachedWindowID,
                            vibespaceID: vibespaceID
                        )
                    },
                    onTileSendAllFromProjectToNewBoardWindowRequested: { projectPath in
                        bulkMoveProjectToNewWindow(
                            projectPath: projectPath,
                            sourceSurfaceID: surfaceID
                        )
                    },
                    onOpenTerminalInEditorPane: { projectID, tabID in
                        contentViewerStore.activeGroup.openTab(.terminal(projectID: projectID, tabID: tabID))
                    },
                    onLinkTargetActivated: openTerminalLinkTarget,
                    onFileSystemTargetActivated: { target, preferredProjectRootURL in
                        openTerminalFileSystemTarget(target, preferredProjectRootURL: preferredProjectRootURL)
                    },
                    acpStoreLookup: { id in
                        contentViewerStore.acpStore(for: id)
                    },
                    createACPPaneStore: {
                        let store = contentViewerStore.makeACPStore(
                            focusedProject: appContainer.acpVibeSpaceSessionService.focusedProject,
                            preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID,
                            vibespaceID: vibespaceID
                        )
                        contentViewerStore.ensureACPPaneTab(id: store.id)
                        return store
                    },
                    restoreACPPaneStore: { snapshot in
                        let store = contentViewerStore.restoreACPStore(
                            from: snapshot,
                            vibespaceID: vibespaceID
                        )
                        contentViewerStore.ensureACPPaneTab(id: store.id)
                        return store
                    },
                    removeACPPaneStore: { id in
                        contentViewerStore.removeACPStore(id: id)
                    },
                    onOpenVibeLaneACPPane: { target in
                        contentViewerStore.openVibeLaneACPPane(
                            target: target,
                            projects: vibespaceView.activeVibeSpaceProjects,
                            vibespaceID: vibespaceID
                        )
                    },
                    makePreviewEditorGroup: {
                        appContainer.makeEditorGroupStore(bufferStore: DocumentBufferStore())
                    }
                )
            }
        }
    }

    func detachedTerminalBoardToolbarConfiguration(
        boardStore: VibeSpaceTerminalBoardStore,
        surfaceID: UUID,
        vibespaceID: UUID
    ) -> VibeSpaceTerminalBoardWindowToolbarConfiguration {
        VibeSpaceTerminalBoardWindowToolbarConfiguration(
            stateChanges: boardStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            addVibeCast: {
                boardStore.addVibeCastTile(surfaceID: surfaceID)
            },
            addAgent: {
                let store = contentViewerStore.makeACPStore(
                    focusedProject: appContainer.acpVibeSpaceSessionService.focusedProject,
                    preferredAgentID: appContainer.acpVibeSpaceSessionService.preferredAgentID,
                    vibespaceID: vibespaceID
                )
                contentViewerStore.ensureACPPaneTab(id: store.id)
                _ = boardStore.addACPTile(snapshot: store.snapshot, surfaceID: surfaceID)
            },
            addBrowser: {
                _ = boardStore.pinBrowserToDock(
                    url: URL(string: "about:blank")!,
                    projectPath: boardStore.activeProjectPath(surfaceID: surfaceID),
                    surfaceID: surfaceID
                )
            },
            canAddVibeCast: {
                let layout = boardStore.layout(for: surfaceID)
                return layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount &&
                    !layout.tiles.contains(where: { $0.isVibeCast })
            },
            canAddAgent: {
                boardStore.layout(for: surfaceID).tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount
            },
            canAddBrowser: {
                boardStore.layout(for: surfaceID).tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount
            },
            projects: activeVibeSpaceSession.projects,
            focusedProject: activeVibeSpaceSession.focusedProject,
            colorForProject: { [vibespaceCanvasActionsCoordinator] project in
                vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color
            },
            // The detached window's New Terminal popover bypasses the
            // notification dispatch used by the main toolbar (which always
            // targets the primary surface). Calling `boardStore.addTile`
            // directly with this window's `surfaceID` keeps the new tile
            // anchored to the originating detached window. Temporary
            // spotlight requests still fall through to a tile here because
            // detached windows do not host a spotlight overlay — the
            // spotlight UI lives only in the main canvas.
            onCreateTerminal: { directoryURL, projectPath, _ in
                _ = boardStore.addTile(
                    projectPath: projectPath,
                    directoryURL: directoryURL.standardizedFileURL,
                    preferStandalone: projectPath == nil,
                    surfaceID: surfaceID
                )
            },
            canAddTerminal: {
                boardStore.layout(for: surfaceID).tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount
            }
        )
    }

    func closeDetachedSurfaceIfEmpty(
        boardStore: VibeSpaceTerminalBoardStore,
        sourceSurfaceID: UUID,
        sourceWindowID: UUID?,
        vibespaceID: UUID?
    ) {
        guard sourceSurfaceID != boardStore.primarySurfaceID else { return }
        guard boardStore.isSurfaceEmpty(sourceSurfaceID) else { return }
        boardStore.closeDetachedSurface(sourceSurfaceID, mergeIntoPrimary: false)
        appContainer.terminalBoardDetachedWindowManager.closeAfterTransfer(id: sourceWindowID)
    }

    func isScreenPointInsideNonDetachedAppWindow(_ screenPoint: CGPoint) -> Bool {
        let point = NSPoint(x: screenPoint.x, y: screenPoint.y)
        return NSApp.windows.contains { window in
            window.isVisible &&
                window.frame.contains(point) &&
                !appContainer.terminalBoardDetachedWindowManager.containsManagedWindow(window)
        }
    }

    @ViewBuilder
    var focusedProjectPane: some View {
        if let focusedProject = vibespaceView.focusedProject {
            FocusedProjectView(
                project: focusedProject,
                onClose: { vibespaceCanvasActionsCoordinator.removeProject(id: focusedProject.id) },
                projectColorTag: vibespaceCanvasActionsCoordinator.colorTag(for: focusedProject),
                onProjectColorTagChanged: {
                    vibespaceCanvasActionsCoordinator.setColorTag($0, for: focusedProject)
                },
                headerCornerRadii: contentHeaderCornerRadii,
                isTerminalTrayCollapsed: vibespaceView.isDetailedTerminalPaneCollapsed,
                onToggleTerminalTrayCollapsed: {
                    let binding = vibespaceView.detailedTerminalPaneCollapsedBinding()
                    binding.wrappedValue.toggle()
                },
                onTerminalSpotlightRequested: { tabID in
                    presentTerminalSpotlight(
                        terminalViewModel: focusedProject.terminalViewModel,
                        tabID: tabID,
                        title: focusedProject.title,
                        accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: focusedProject)?.color,
                        owningProjectRootURL: focusedProject.rootURL
                    )
                },
                onTemporaryTerminalRequested: { directoryURL in
                    presentTemporaryTerminalSpotlight(
                        title: focusedProject.title,
                        accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: focusedProject)?.color,
                        directoryURL: directoryURL,
                        shellResolutionProvider: { [shellResolutionProviderStore = focusedProject.terminal.shellResolutionProviderStore] in
                            shellResolutionProviderStore.resolve()
                        },
                        onSplitTerminalRequested: {
                            createSplitTerminal(
                                in: focusedProject.terminalViewModel,
                                directoryURL: directoryURL
                            )
                        },
                        owningProjectRootURL: focusedProject.rootURL
                    )
                },
                onTemporaryShortcutRequested: { shortcut, directoryURL in
                    presentTemporaryTerminalSpotlight(
                        title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? focusedProject.title
                            : shortcut.name,
                        accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: focusedProject)?.color,
                        directoryURL: directoryURL,
                        shellResolutionProvider: { [shellResolutionProviderStore = focusedProject.terminal.shellResolutionProviderStore] in
                            shellResolutionProviderStore.resolve()
                        },
                        onSplitTerminalRequested: {
                            createSplitTerminal(
                                in: focusedProject.terminalViewModel,
                                directoryURL: directoryURL
                            )
                        },
                        owningProjectRootURL: focusedProject.rootURL,
                        initialCommand: shortcut.command
                    )
                },
                onOpenTerminalInEditorPaneRequested: { tabID in
                    contentViewerStore.activeGroup.openTab(.terminal(projectID: focusedProject.id, tabID: tabID))
                },
                onManageShortcutsRequested: {
                    vibespaceShell.presentVibeSpaceSettings(.shortcuts)
                },
                onLinkTargetActivated: { url in
                    openTerminalLinkTarget(
                        url,
                        preferredProjectRootURL: focusedProject.rootURL
                    )
                },
                onFileSystemTargetActivated: { url in
                    openTerminalFileSystemTarget(
                        url,
                        preferredProjectRootURL: focusedProject.rootURL
                    )
                },
                shortcutProvider: vibespaceShortcutProvider
            )
            .onHover { isHovering in
                if isHovering {
                    stackedRailOverlayCoordinator.dismiss()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: contentPanelCornerRadii,
                    style: .continuous
                )
            )
            .accessibilityIdentifier("project.focused")
        } else {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text(
                        vibespaceView.unresolvedProjectCount > 0
                            ? "\(vibespaceView.activeVibeSpace?.name ?? "VibeSpace") has \(vibespaceView.unresolvedProjectCount) missing folder path(s). Open VibeSpace Settings to relink or remove them."
                            : "No projects in \(vibespaceView.activeVibeSpace?.name ?? "this vibespace"). Add one to get started."
                    )
                )
                if vibespaceView.unresolvedProjectCount == 0 {
                    Button {
                        homeCatalogCoordinator.addProjectsToActiveVibeSpaceFromFolderPicker(
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
                    } label: {
                        Label("Add Project(s)", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityIdentifier("vibespace.empty.add-projects")
                } else {
                    Button {
                        homeCatalogCoordinator.addVibeSpaceFromFolderPicker()
                    } label: {
                        Label("Reopen VibeSpace Folder(s)", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityIdentifier("vibespace.empty.reopen-vibespace")
                }
            }
            .background(activeThemePalette.canvasBackgroundColor)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: contentPanelCornerRadii,
                    style: .continuous
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DetachedTerminalBoardWindowContent: View {
    @Environment(\.appThemePalette) private var activeThemePalette

    let vibespaceID: UUID
    let surfaceID: UUID
    @ObservedObject var boardStore: VibeSpaceTerminalBoardStore
    let projects: [AnyProjectSession]
    let projectColorTagsByPath: [String: ProjectColorTag]
    let layoutPersistence: LayoutPersistenceService
    let terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry
    let headerCornerRadii: RectangleCornerRadii
    let terminalServices: TerminalServices
    @ObservedObject var vibeCastStore: VibeCastStore
    @ObservedObject var dockedFileViewerCoordinator: DockedFileViewerCoordinator
    @ObservedObject var dockedBrowserCoordinator: DockedBrowserCoordinator
    var dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator?
    @Environment(\.vibespaceTodoStoreEnvironment) private var spotlightTodoStore
    let onManageShortcutsRequested: () -> Void
    let shortcutDefinitionsForProjectPath: (String?) -> [TerminalShortcutDefinition]
    let onTileDetachRequested: (UUID, CGPoint) -> Void
    let boardWindowTransferTargets: () -> [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onTileSendToNewBoardWindowRequested: (UUID) -> Void
    let onTileSendToBoardWindowRequested: (UUID, UUID) -> Void
    /// F048-R13: bulk-move all tiles on this detached surface that share
    /// `projectPath` to a new detached window.
    let onTileSendAllFromProjectToNewBoardWindowRequested: (String) -> Void
    let onOpenTerminalInEditorPane: (UUID, UUID) -> Void
    let onLinkTargetActivated: (URL, URL?) -> Void
    let onFileSystemTargetActivated: (TerminalFileSystemTarget, URL?) -> Void
    let acpStoreLookup: (UUID) -> ACPStandaloneSessionStore?
    let createACPPaneStore: (() -> ACPStandaloneSessionStore)?
    let restoreACPPaneStore: ((ACPStandalonePaneSnapshot) -> ACPStandaloneSessionStore)?
    let removeACPPaneStore: (UUID) -> Void
    let onOpenVibeLaneACPPane: (VibeLaneACPChatTarget) -> Void
    let makePreviewEditorGroup: () -> EditorGroupStore

    @StateObject private var spotlightCoordinator: TerminalSpotlightCoordinator

    init(
        vibespaceID: UUID,
        surfaceID: UUID,
        boardStore: VibeSpaceTerminalBoardStore,
        projects: [AnyProjectSession],
        projectColorTagsByPath: [String: ProjectColorTag],
        layoutPersistence: LayoutPersistenceService,
        terminalBoardStandaloneRegistry: VibeSpaceTerminalBoardStandaloneRegistry,
        headerCornerRadii: RectangleCornerRadii,
        terminalServices: TerminalServices,
        vibeCastStore: VibeCastStore,
        dockedFileViewerCoordinator: DockedFileViewerCoordinator,
        dockedBrowserCoordinator: DockedBrowserCoordinator,
        dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator? = nil,
        onManageShortcutsRequested: @escaping () -> Void,
        shortcutDefinitionsForProjectPath: @escaping (String?) -> [TerminalShortcutDefinition],
        onTileDetachRequested: @escaping (UUID, CGPoint) -> Void,
        boardWindowTransferTargets: @escaping () -> [VibeSpaceTerminalBoardSurfaceTransferTarget],
        onTileSendToNewBoardWindowRequested: @escaping (UUID) -> Void,
        onTileSendToBoardWindowRequested: @escaping (UUID, UUID) -> Void,
        onTileSendAllFromProjectToNewBoardWindowRequested: @escaping (String) -> Void,
        onOpenTerminalInEditorPane: @escaping (UUID, UUID) -> Void,
        onLinkTargetActivated: @escaping (URL, URL?) -> Void,
        onFileSystemTargetActivated: @escaping (TerminalFileSystemTarget, URL?) -> Void,
        acpStoreLookup: @escaping (UUID) -> ACPStandaloneSessionStore?,
        createACPPaneStore: (() -> ACPStandaloneSessionStore)? = nil,
        restoreACPPaneStore: ((ACPStandalonePaneSnapshot) -> ACPStandaloneSessionStore)? = nil,
        removeACPPaneStore: @escaping (UUID) -> Void,
        onOpenVibeLaneACPPane: @escaping (VibeLaneACPChatTarget) -> Void,
        makePreviewEditorGroup: @escaping () -> EditorGroupStore
    ) {
        self.vibespaceID = vibespaceID
        self.surfaceID = surfaceID
        self.boardStore = boardStore
        self.projects = projects
        self.projectColorTagsByPath = projectColorTagsByPath
        self.layoutPersistence = layoutPersistence
        self.terminalBoardStandaloneRegistry = terminalBoardStandaloneRegistry
        self.headerCornerRadii = headerCornerRadii
        self.terminalServices = terminalServices
        self.vibeCastStore = vibeCastStore
        self.dockedFileViewerCoordinator = dockedFileViewerCoordinator
        self.dockedBrowserCoordinator = dockedBrowserCoordinator
        self.dockedAgentPreviewCoordinator = dockedAgentPreviewCoordinator
        self.onManageShortcutsRequested = onManageShortcutsRequested
        self.shortcutDefinitionsForProjectPath = shortcutDefinitionsForProjectPath
        self.onTileDetachRequested = onTileDetachRequested
        self.boardWindowTransferTargets = boardWindowTransferTargets
        self.onTileSendToNewBoardWindowRequested = onTileSendToNewBoardWindowRequested
        self.onTileSendToBoardWindowRequested = onTileSendToBoardWindowRequested
        self.onTileSendAllFromProjectToNewBoardWindowRequested = onTileSendAllFromProjectToNewBoardWindowRequested
        self.onOpenTerminalInEditorPane = onOpenTerminalInEditorPane
        self.onLinkTargetActivated = onLinkTargetActivated
        self.onFileSystemTargetActivated = onFileSystemTargetActivated
        self.acpStoreLookup = acpStoreLookup
        self.createACPPaneStore = createACPPaneStore
        self.restoreACPPaneStore = restoreACPPaneStore
        self.removeACPPaneStore = removeACPPaneStore
        self.onOpenVibeLaneACPPane = onOpenVibeLaneACPPane
        self.makePreviewEditorGroup = makePreviewEditorGroup
        _spotlightCoordinator = StateObject(
            wrappedValue: TerminalSpotlightCoordinator(diagnosticsSnapshot: terminalServices.diagnosticsSnapshot)
        )
    }

    var body: some View {
        ZStack {
            board
            spotlightOverlay
        }
    }

    private var board: some View {
        VibeSpaceTerminalOnlyView(
            vibespaceID: vibespaceID,
            surfaceID: surfaceID,
            isVisible: true,
            isSpotlightPresented: spotlightCoordinator.spotlight != nil,
            projects: projects,
            projectColorTagsByPath: projectColorTagsByPath,
            hiddenTerminalIDsByProjectPath: [:],
            layoutPersistence: layoutPersistence,
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            headerCornerRadii: headerCornerRadii,
            onAddProjectsRequested: {},
            onSpotlightRequested: presentTerminalSpotlight,
            onACPSpotlightRequested: presentACPSpotlight,
            onTemporaryTerminalRequested: { terminalViewModel, directoryURL, title, accentColor, owningProjectRootURL in
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: directoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        addTerminalTile(
                            directoryURL: directoryURL,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            onTemporaryShortcutRequested: { terminalViewModel, shortcut, directoryURL, title, accentColor, owningProjectRootURL in
                presentTemporaryTerminalSpotlight(
                    title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : shortcut.name,
                    accentColor: accentColor,
                    directoryURL: directoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        addTerminalTile(
                            directoryURL: directoryURL,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL,
                    initialCommand: shortcut.command
                )
            },
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: { target, preferredProjectRootURL in
                presentFilePreviewSpotlight(target: target, owningProjectRootURL: preferredProjectRootURL)
            },
            onManageShortcutsRequested: onManageShortcutsRequested,
            shortcutDefinitionsForProjectPath: shortcutDefinitionsForProjectPath,
            onVibeCastSpotlightRequested: { presentVibeCastSpotlight() },
            onTileDetachRequested: onTileDetachRequested,
            boardWindowTransferTargets: { _, _ in boardWindowTransferTargets() },
            onTileSendToNewBoardWindowRequested: { tileID, _, _ in
                onTileSendToNewBoardWindowRequested(tileID)
            },
            onTileSendToBoardWindowRequested: { tileID, targetSurfaceID, _, _ in
                onTileSendToBoardWindowRequested(tileID, targetSurfaceID)
            },
            onTileSendAllFromProjectToNewBoardWindowRequested: { projectPath, _, _ in
                onTileSendAllFromProjectToNewBoardWindowRequested(projectPath)
            },
            onOpenTerminalInEditorPane: onOpenTerminalInEditorPane,
            vibeCastStore: vibeCastStore,
            acpStoreLookup: acpStoreLookup,
            createACPPaneStore: createACPPaneStore,
            restoreACPPaneStore: restoreACPPaneStore,
            removeACPPaneStore: removeACPPaneStore,
            showACPControls: false,
            dockedFileViewerCoordinator: dockedFileViewerCoordinator,
            dockedBrowserCoordinator: dockedBrowserCoordinator,
            dockedAgentPreviewCoordinator: dockedAgentPreviewCoordinator,
            dockPreviewBridge: nil,
            onFileSpotlightRequested: { tileID, fileURL in
                presentFileSpotlight(tileID: tileID, fileURL: fileURL)
            },
            onBrowserSpotlightRequested: { tileID, url in
                presentBrowserSpotlight(tileID: tileID, url: url)
            },
            boardStore: boardStore
        )
    }

    private var spotlightOverlay: some View {
        TerminalSpotlightOverlayHostView(
            coordinator: spotlightCoordinator,
            items: flatSpotlightItems,
            projectColorTag: { project in
                projectColorTagsByPath[project.rootURL.standardizedFileURL.path]
            },
            onDismiss: closeSpotlight,
            onFocusSpotlight: focusSpotlight,
            onInstallScrollMonitor: {
                spotlightCoordinator.installScrollMonitor(onSwitchSpotlight: switchSpotlight)
            },
            onRemoveScrollMonitor: {
                spotlightCoordinator.removeScrollMonitor()
            },
            onSwitchSpotlight: switchSpotlight,
            onReorderTerminalTab: { draggedItem, targetItem, placement in
                guard case let .terminal(_, draggedTab) = draggedItem,
                      case let .terminal(_, targetTab) = targetItem else {
                    return false
                }
                return boardStore.moveTerminalTabTile(
                    draggedTab.id,
                    relativeTo: targetTab.id,
                    placement: placement,
                    surfaceID: surfaceID
                )
            },
            cardContent: { spotlight in
                TerminalSpotlightCardView(
                    spotlight: spotlight,
                    onDismiss: closeSpotlight,
                    onPin: nil,
                    pinAccessibilityLabel: nil,
                    shortcutDefinitions: spotlight.shortcutDefinitions,
                    onShortcutSelected: spotlight.onShortcutSelected,
                    onManageShortcutsRequested: spotlight.onManageShortcutsRequested,
                    onSendSignal: sendSignalHandler(for: spotlight),
                    onRenamePersistentTab: { terminalViewModel, tabID, title in
                        terminalViewModel.renameTab(tabID, to: title)
                    },
                    spotlightContent: {
                        spotlightContent(for: spotlight)
                    },
                    inputBarContent: {
                        SpotlightTerminalInputBar(
                            spotlight: spotlight,
                            vibespaceProjects: projects
                        )
                    }
                )
            }
        )
    }

    private var flatSpotlightItems: [SpotlightItem] {
        let layout = boardStore.layout(for: surfaceID)
        var items: [SpotlightItem] = []
        for tile in layout.tiles {
            if let context = boardStore.tileContext(for: tile) {
                if let project = context.projectPath.flatMap({ path in
                    projects.first(where: { $0.rootURL.standardizedFileURL.path == path })
                }) {
                    items.append(.terminal(project: project, tab: context.terminalTab))
                }
            } else if tile.isVibeCast {
                items.append(.vibeCast)
            } else if let snapshot = tile.acpSnapshot,
                      let store = acpStoreLookup(snapshot.id) {
                let accentColor = store.selectedProject(from: projects)
                    .flatMap { projectColorTagsByPath[$0.rootURL.standardizedFileURL.path]?.color }
                items.append(.acp(tileID: tile.id, storeID: snapshot.id, title: store.tabTitle, accentColor: accentColor))
            } else if let fileURL = tile.fileURL {
                items.append(.file(tileID: tile.id, fileURL: fileURL))
            } else if let url = tile.browserURL {
                items.append(.browser(tileID: tile.id, url: url))
            }
        }
        if !items.isEmpty {
            items.append(.vibeLanes)
        }
        return items
    }

    private func setSpotlight(_ spotlight: TerminalSpotlightState?, animated: Bool = true) {
        spotlightCoordinator.setSpotlight(
            spotlight,
            animated: animated,
            onFocusSpotlight: focusSpotlight
        )
    }

    private func presentTerminalSpotlight(
        terminalViewModel: TerminalViewModel,
        tabID: UUID,
        title: String,
        accentColor: Color?,
        owningProjectRootURL: URL?
    ) {
        presentTerminalSpotlight(
            terminalViewModel: terminalViewModel,
            tabID: tabID,
            title: title,
            accentColor: accentColor,
            owningProjectRootURL: owningProjectRootURL,
            animated: true
        )
    }

    private func presentTerminalSpotlight(
        terminalViewModel: TerminalViewModel,
        tabID: UUID,
        title: String,
        accentColor: Color?,
        owningProjectRootURL: URL?,
        surfaceID targetSurfaceID: UUID? = nil,
        animated: Bool
    ) {
        guard let tab = terminalViewModel.tabs.first(where: { $0.id == tabID }) else { return }
        let workingDirectoryURL = tab.workingDirectory.standardizedFileURL
        let spotlight = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(terminalViewModel: terminalViewModel, tabID: tabID),
            title: title,
            accentColor: accentColor,
            workingDirectoryURL: workingDirectoryURL,
            onSplitTerminalRequested: {
                addTerminalTile(
                    directoryURL: workingDirectoryURL,
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            onTemporaryTerminalRequested: {
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: workingDirectoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        addTerminalTile(
                            directoryURL: workingDirectoryURL,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            shortcutDefinitions: shortcutDefinitionsForProjectPath(owningProjectRootURL?.standardizedFileURL.path),
            onShortcutSelected: { shortcut in
                executeTerminalShortcut(
                    shortcut,
                    viewModel: terminalViewModel,
                    defaultDirectory: workingDirectoryURL,
                    onTemporaryShortcutRequested: { shortcut, directoryURL in
                        presentTemporaryTerminalSpotlight(
                            title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : shortcut.name,
                            accentColor: accentColor,
                            directoryURL: directoryURL,
                            shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                            onSplitTerminalRequested: {
                                addTerminalTile(
                                    directoryURL: directoryURL,
                                    owningProjectRootURL: owningProjectRootURL
                                )
                            },
                            owningProjectRootURL: owningProjectRootURL,
                            initialCommand: shortcut.command
                        )
                    }
                )
            },
            onManageShortcutsRequested: onManageShortcutsRequested,
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: targetSurfaceID ?? surfaceID
        )
        setSpotlight(spotlight, animated: animated)
    }

    @discardableResult
    private func addTerminalTile(
        directoryURL: URL,
        owningProjectRootURL: URL?
    ) -> Bool {
        let projectPath = owningProjectRootURL?.standardizedFileURL.path
        return boardStore.addTile(
            projectPath: projectPath,
            directoryURL: directoryURL.standardizedFileURL,
            preferStandalone: projectPath == nil,
            surfaceID: surfaceID
        )
    }

    private func presentTemporaryTerminalSpotlight(
        title: String,
        accentColor: Color?,
        directoryURL: URL,
        shellResolutionProvider: @escaping @Sendable () -> TerminalShellResolution,
        onSplitTerminalRequested: (() -> Void)? = nil,
        owningProjectRootURL: URL?,
        initialCommand: String? = nil
    ) {
        let normalizedDirectoryURL = directoryURL.standardizedFileURL
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: normalizedDirectoryURL,
            terminalServices: terminalServices,
            shellResolutionProvider: shellResolutionProvider
        )
        let spotlight = TerminalSpotlightState(
            id: UUID(),
            source: .transient(session: session),
            title: title,
            accentColor: accentColor,
            workingDirectoryURL: normalizedDirectoryURL,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: {
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: normalizedDirectoryURL,
                    shellResolutionProvider: shellResolutionProvider,
                    onSplitTerminalRequested: onSplitTerminalRequested,
                    owningProjectRootURL: owningProjectRootURL,
                    initialCommand: initialCommand
                )
            },
            shortcutDefinitions: shortcutDefinitionsForProjectPath(owningProjectRootURL?.standardizedFileURL.path),
            onManageShortcutsRequested: onManageShortcutsRequested,
            isTemporary: true,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: surfaceID
        )
        setSpotlight(spotlight)
        let command = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !command.isEmpty {
            session.sendStartupCommand(command)
        }
    }

    private func presentVibeCastSpotlight(animated: Bool = true) {
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .vibeCast,
                title: AppStrings.VibeCast.title,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: nil
            ),
            animated: animated
        )
    }

    private func presentVibeLanesSpotlight(animated: Bool = true) {
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .vibeLanes,
                title: AppStrings.VibeLanes.title,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: nil
            ),
            animated: animated
        )
    }

    private func presentACPSpotlight(tileID: UUID, storeID: UUID) {
        guard let store = acpStoreLookup(storeID) else { return }
        let selectedProject = store.selectedProject(from: projects)
        let owningProjectRootURL = selectedProject?.rootURL.standardizedFileURL
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .acp(tileID: tileID, storeID: storeID),
                title: store.tabTitle,
                accentColor: selectedProject.flatMap { projectColorTagsByPath[$0.rootURL.standardizedFileURL.path]?.color },
                workingDirectoryURL: owningProjectRootURL ?? URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: owningProjectRootURL
            )
        )
    }

    private func presentFilePreviewSpotlight(
        target: TerminalFileSystemTarget,
        owningProjectRootURL: URL?,
        animated: Bool = true
    ) {
        let normalizedTarget = TerminalFileSystemTarget(
            url: target.standardizedFileURL,
            line: target.line,
            column: target.column
        )
        let group = makePreviewEditorGroup()
        group.openFileInTab(
            at: normalizedTarget.url,
            line: normalizedTarget.line,
            column: normalizedTarget.column
        )
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .filePreview(target: normalizedTarget, group: group),
                title: normalizedTarget.url.lastPathComponent,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: normalizedTarget.url.deletingLastPathComponent(),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: true,
                owningProjectRootURL: owningProjectRootURL
            ),
            animated: animated
        )
    }

    private func presentFileSpotlight(tileID: UUID, fileURL: URL, animated: Bool = true) {
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .file(tileID: tileID, fileURL: fileURL),
                title: fileURL.lastPathComponent,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: fileURL.deletingLastPathComponent(),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: nil
            ),
            animated: animated
        )
    }

    private func presentBrowserSpotlight(tileID: UUID, url: URL, animated: Bool = true) {
        setSpotlight(
            TerminalSpotlightState(
                id: UUID(),
                source: .browser(tileID: tileID, url: url),
                title: url.host ?? url.absoluteString,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: nil
            ),
            animated: animated
        )
    }

    private func closeSpotlight() {
        dockedBrowserCoordinator.dismissPreview()
        spotlightCoordinator.dismiss()
    }

    private func focusSpotlight(_ spotlight: TerminalSpotlightState) {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            guard let tab = terminalViewModel.tabs.first(where: { $0.id == tabID }) else { return }
            terminalViewModel.selectTab(tab)
        case let .transient(session):
            session.startIfNeeded()
        case let .browser(tileID, url):
            dockedBrowserCoordinator.viewModel(for: tileID, url: url).focus()
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview:
            break
        }
    }

    private func switchSpotlight(by offset: Int) {
        guard let spotlight = spotlightCoordinator.spotlight,
              let currentIndex = spotlightItemIndex(for: spotlight) else { return }
        let items = flatSpotlightItems
        guard !items.isEmpty else { return }
        let nextIndex = (currentIndex + offset + items.count) % items.count
        let entryOffset = spotlightCoordinator.prepareSwitchTransition(offset: offset)
        switch items[nextIndex] {
        case let .terminal(project, tab):
            presentTerminalSpotlight(
                terminalViewModel: project.terminalViewModel,
                tabID: tab.id,
                title: tab.title.isEmpty ? project.title : tab.title,
                accentColor: projectColorTagsByPath[project.rootURL.standardizedFileURL.path]?.color,
                owningProjectRootURL: project.rootURL,
                surfaceID: surfaceID,
                animated: false
            )
        case .vibeCast:
            presentVibeCastSpotlight(animated: false)
        case .vibeLanes:
            presentVibeLanesSpotlight(animated: false)
        case let .acp(tileID, storeID, _, _):
            presentACPSpotlight(tileID: tileID, storeID: storeID)
        case let .file(tileID, fileURL):
            presentFileSpotlight(tileID: tileID, fileURL: fileURL, animated: false)
        case let .browser(tileID, url):
            presentBrowserSpotlight(tileID: tileID, url: url, animated: false)
        }
        spotlightCoordinator.animateSwipeOffset(entryOffset)
        spotlightCoordinator.animateSwipeOffset(0, animation: .spring(response: 0.35, dampingFraction: 0.82))
    }

    private func spotlightItemIndex(for spotlight: TerminalSpotlightState) -> Int? {
        flatSpotlightItems.firstIndex { item in
            switch (spotlight.source, item) {
            case let (.persistent(_, tabID), .terminal(_, tab)):
                return tab.id == tabID
            case (.vibeCast, .vibeCast):
                return true
            case (.vibeLanes, .vibeLanes):
                return true
            case let (.acp(tileID, _), .acp(candidateTileID, _, _, _)):
                return tileID == candidateTileID
            case let (.file(tileID, _), .file(candidateTileID, _)):
                return tileID == candidateTileID
            case let (.browser(tileID, _), .browser(candidateTileID, _)):
                return tileID == candidateTileID
            default:
                return false
            }
        }
    }

    private func sendSignalHandler(for spotlight: TerminalSpotlightState) -> ((String) -> Void)? {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            return { signal in terminalViewModel.session(for: tabID)?.sendRawText(signal) }
        case let .transient(session):
            return { signal in session.sendRawText(signal) }
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    @ViewBuilder
    private func spotlightContent(for spotlight: TerminalSpotlightState) -> some View {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            if let tab = terminalViewModel.tabs.first(where: { $0.id == tabID }) {
                TerminalSessionView(
                    tab: tab,
                    viewModel: terminalViewModel,
                    isActive: true,
                    sessionAccessibilityIdentifier: "terminal.spotlight.session",
                    sessionHostAccessibilityIdentifier: "terminal.spotlight.host",
                    inlineTriggerTerminalTitle: tab.title.isEmpty ? spotlight.title : tab.title,
                    inlineTriggerSearchRoots: [tab.workingDirectory, spotlight.owningProjectRootURL].compactMap { $0 },
                    inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                    onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                    onSessionSelected: { selectedTabID in
                        presentTerminalSpotlight(
                            terminalViewModel: terminalViewModel,
                            tabID: selectedTabID,
                            title: spotlight.title,
                            accentColor: spotlight.accentColor,
                            owningProjectRootURL: spotlight.owningProjectRootURL,
                            surfaceID: surfaceID,
                            animated: false
                        )
                    },
                    onSessionDoubleClicked: { _ in closeSpotlight() },
                    onSplitTerminalRequested: { tab in
                        addTerminalTile(
                            directoryURL: tab.workingDirectory,
                            owningProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onTemporaryTerminalRequested: { tab in
                        presentTemporaryTerminalSpotlight(
                            title: spotlight.title,
                            accentColor: spotlight.accentColor,
                            directoryURL: tab.workingDirectory,
                            shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                            onSplitTerminalRequested: {
                                addTerminalTile(
                                    directoryURL: tab.workingDirectory,
                                    owningProjectRootURL: spotlight.owningProjectRootURL
                                )
                            },
                            owningProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onOpenInEditorPaneRequested: { tab in
                        if let owningProjectRootURL = spotlight.owningProjectRootURL?.standardizedFileURL,
                           let project = projects.first(where: { $0.rootURL.standardizedFileURL == owningProjectRootURL }) {
                            onOpenTerminalInEditorPane(project.id, tab.id)
                        }
                    },
                    onLinkTargetActivated: { url in
                        onLinkTargetActivated(url, spotlight.owningProjectRootURL)
                    },
                    onFileSystemTargetActivated: { target in
                        presentFilePreviewSpotlight(target: target, owningProjectRootURL: spotlight.owningProjectRootURL)
                    }
                )
            } else {
                ContentUnavailableView("Terminal Unavailable", systemImage: "terminal")
            }
        case let .transient(session):
            TerminalSessionHostView(
                session: session,
                displayDensity: .regular,
                isActive: true,
                accessibilityIdentifier: "terminal.spotlight.host",
                inlineTriggerTerminalTitle: spotlight.title,
                inlineTriggerSearchRoots: [session.currentWorkingDirectory, spotlight.owningProjectRootURL].compactMap { $0 },
                inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                onSplitTerminalRequested: spotlight.onSplitTerminalRequested,
                onTemporaryTerminalRequested: spotlight.onTemporaryTerminalRequested,
                onLinkTargetActivated: { url in onLinkTargetActivated(url, spotlight.owningProjectRootURL) },
                onFileSystemTargetActivated: { target in
                    presentFilePreviewSpotlight(target: target, owningProjectRootURL: spotlight.owningProjectRootURL)
                }
            )
        case .vibeCast:
            VibeCastView(
                store: vibeCastStore,
                terminalSources: projects.map {
                    .init(
                        id: $0.id.uuidString,
                        projectTitle: $0.title,
                        projectRootURL: $0.rootURL,
                        accentColor: projectColorTagsByPath[$0.rootURL.standardizedFileURL.path]?.color ?? activeThemePalette.accentColor,
                        viewModel: $0.terminalViewModel
                    )
                },
                isActive: true,
                onManageShortcutsRequested: onManageShortcutsRequested
            )
        case .vibeLanes:
            VibeLaneSurfaceView(
                focusedProjectPath: projects.first?.rootURL.standardizedFileURL.path,
                onOpenACPSession: onOpenVibeLaneACPPane
            )
        case .todos:
            if let spotlightTodoStore {
                TodosSurfaceView(store: spotlightTodoStore, focusedProjectPath: spotlight.owningProjectRootURL?.path)
            } else {
                ContentUnavailableView(AppStrings.Todos.title, systemImage: "checklist")
            }
        case let .acp(_, storeID):
            if let store = acpStoreLookup(storeID) {
                ACPStandalonePaneContentView(
                    store: store,
                    projects: projects,
                    displayMode: .spotlight,
                    onLinkTargetActivated: { url in onLinkTargetActivated(url, spotlight.owningProjectRootURL) },
                    onFileSystemTargetActivated: { target in
                        presentFilePreviewSpotlight(target: target, owningProjectRootURL: spotlight.owningProjectRootURL)
                    }
                )
            } else {
                ContentUnavailableView(AppStrings.ACP.unavailableTitle, systemImage: "sparkles")
            }
        case let .filePreview(_, group):
            MarkdownEditorView(viewModel: group.markdownViewModel, showsTopBar: false, headerLayout: .embedded)
        case let .file(tileID, fileURL):
            MarkdownEditorView(
                viewModel: dockedFileViewerCoordinator.editorGroup(for: tileID, fileURL: fileURL).markdownViewModel,
                showsTopBar: false,
                headerLayout: .embedded
            )
        case let .browser(tileID, url):
            BrowserContentView(
                viewModel: dockedBrowserCoordinator.viewModel(for: tileID, url: url),
                presentation: .spotlight
            )
        case .browserPreview:
            ContentUnavailableView("Browser Unavailable", systemImage: "globe")
        }
    }
}

private struct DetachedTerminalBoardWindowRoot<Content: View>: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var themeManager: CrispyVibesThemeManager
    @AppStorage(AppPreferences.appearancePreferenceKey)
    private var appearancePreference = AppPreferences.defaultAppearancePreference
    @AppStorage(AppPreferences.appThemePresetKey)
    private var appThemePreset = AppPreferences.defaultAppThemePreset
    @AppStorage(AppPreferences.appCustomThemePaletteJSONKey)
    private var appCustomThemePaletteJSON = AppPreferences.defaultAppCustomThemePaletteJSON

    let content: Content
    var commentStore: VibeSpaceCommentStore?

    init(
        themeManager: CrispyVibesThemeManager,
        commentStore: VibeSpaceCommentStore? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.themeManager = themeManager
        self.commentStore = commentStore
        self.content = content()
    }

    private var activeThemePalette: AppThemePalette {
        AppThemeResolver.palette(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: systemColorScheme,
            themePresetRaw: appThemePreset,
            customThemeJSON: appCustomThemePaletteJSON
        )
    }

    private var preferredAppColorScheme: ColorScheme? {
        AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: systemColorScheme,
            themePresetRaw: appThemePreset,
            customThemeJSON: appCustomThemePaletteJSON
        )
    }

    var body: some View {
        content
            .background(activeThemePalette.windowBackgroundColor)
            .applyingAppThemePalette(activeThemePalette)
            .applyingAppAccentTheme(activeThemePalette.accentColor)
            .buttonBorderShape(themeManager.theme.borderShape.buttonBorderShape)
            .environment(\.crispyvibesTheme, themeManager.theme)
            .environment(\.vibespaceCommentStoreEnvironment, commentStore)
            .environmentObject(themeManager)
            .environment(\.terminalHostOwnershipPriorityBoost, 40)
            .environment(\.browserHostOwnershipPriorityBoost, 40)
            .preferredColorScheme(preferredAppColorScheme)
    }
}
