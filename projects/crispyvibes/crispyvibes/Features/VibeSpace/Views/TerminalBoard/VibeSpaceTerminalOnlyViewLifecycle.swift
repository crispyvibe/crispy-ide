import SwiftUI
import Combine

extension VibeSpaceTerminalOnlyView {
    var boardContent: some View {
        VStack(spacing: 0) {
            boardHeader

            Divider()

            GeometryReader { proxy in
                boardCanvas(proxy: proxy)
            }

            if !surfaceLayout.minimizedTiles.isEmpty {
                minimizedTabBar
            }
        }
        .overlay {
            if let coordinator = dockedFileViewerCoordinator,
               let fileURL = coordinator.previewFileURL,
               let group = coordinator.previewEditorGroup {
                GeometryReader { proxy in
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { coordinator.dismissPreview() }
                    DockPreviewPanel(
                        fileURL: fileURL,
                        editorGroup: group,
                        containerSize: proxy.size,
                        onPin: {
                            if let tileID = boardStore.pinPreviewToDock(fileURL: fileURL, surfaceID: surfaceID) {
                                coordinator.promotePreview(to: tileID)
                            }
                        },
                        onDismiss: { coordinator.dismissPreview() }
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
        .overlay {
            if let coordinator = dockedAgentPreviewCoordinator,
               coordinator.previewThreadId != nil,
               let store = coordinator.previewStore {
                GeometryReader { proxy in
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { coordinator.dismissPreview() }
                    AgentDockPreviewPanel(
                        store: store,
                        title: coordinator.previewTitle ?? "Conversation",
                        projects: projects,
                        containerSize: proxy.size,
                        onPin: {
                            if let promoted = coordinator.promotePreview() {
                                _ = boardStore.addACPTile(snapshot: promoted.snapshot, surfaceID: surfaceID)
                            }
                        },
                        onDismiss: { coordinator.dismissPreview() }
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
    }

    func boardCanvas(proxy: GeometryProxy) -> some View {
        let layout = surfaceLayout
        let baseMetrics = VibeSpaceTerminalBoardMetrics(
            size: proxy.size,
            layout: layout
        )
        let cursorRegions = BoardCursorRegions.regions(from: layout, boardSize: proxy.size)

        let movingState: BoardInteractionState.MovingTileState? = {
            if case let .movingTile(state) = interactionController.state { return state }
            return nil
        }()
        let movingMinimizedState: BoardInteractionState.MovingMinimizedState? = {
            if case let .movingMinimized(state) = interactionController.state { return state }
            return nil
        }()

        return ZStack(alignment: .topLeading) {
            ForEach(layout.tiles) { tile in
                tileCard(tile, metrics: baseMetrics)
            }

            if !interactionController.isMoving {
                BoardDividerVisualsOverlay(
                    layout: layout,
                    metrics: baseMetrics,
                    hoveredRegion: interactionController.hoveredRegion,
                    isInteracting: interactionController.isResizing
                )
                .allowsHitTesting(false)
                .zIndex(30)
            }

            if !interactionController.isMoving {
                ForEach(baseMetrics.columnResizeHandles()) { handle in
                    resizeHandle(handle.frame)
                }

                ForEach(baseMetrics.rowResizeHandles()) { handle in
                    resizeHandle(handle.frame)
                }
            }

            if let movingState, let previewLayout = movingState.previewLayout {
                let previewMetrics = VibeSpaceTerminalBoardMetrics(size: proxy.size, layout: previewLayout)
                VibeSpaceTerminalBoardLayoutPreviewOverlay(
                    layout: previewLayout,
                    metrics: previewMetrics,
                    movingTileID: movingState.tileID
                )
                .zIndex(60)
            }

            if let guide = movingState?.dockingGuide ?? movingMinimizedState?.dockingGuide {
                VibeSpaceTerminalBoardDockingGuideOverlay(
                    guide: guide,
                    boardSize: baseMetrics.size
                )
                .zIndex(70)
            }

            if let proxy = interactionController.dragProxy,
               let pointer = movingState?.pointer ?? movingMinimizedState?.pointer {
                VibeSpaceTerminalBoardDragProxyView(
                    title: proxy.title,
                    subtitle: proxy.subtitle,
                    pointerLocation: pointer,
                    sourceFrame: proxy.sourceFrame
                )
                .zIndex(120)
            }

            #if os(macOS)
            BoardCursorRectsView(
                cursorRegions: interactionController.isMoving ? [] : cursorRegions,
                controller: interactionController
            )
            .allowsHitTesting(false)
            #endif
        }
        .coordinateSpace(name: "terminalBoard")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(boardBackgroundColor)
        .animation(interactionController.isResizing ? nil : .spring(response: 0.30, dampingFraction: 0.86), value: layout)
        .onAppear {
            updateBoardInteractionMetrics(size: proxy.size, layout: layout)
            dockedFileViewerCoordinator?.dockedFiles = boardStore.dockedFileEntries(surfaceID: surfaceID)
            syncACPPaneStores()
        }
        .onChange(of: proxy.size) { _, newSize in
            updateBoardInteractionMetrics(size: newSize, layout: surfaceLayout)
        }
        .onChange(of: surfaceLayout) { _, newLayout in
            updateBoardInteractionMetrics(size: proxy.size, layout: newLayout)
            dockedFileViewerCoordinator?.dockedFiles = boardStore.dockedFileEntries(surfaceID: surfaceID)
        }
    }

    func resizeHandle(_ frame: CGRect) -> some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .offset(x: frame.minX, y: frame.minY)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("terminalBoard"))
                    .onChanged { value in
                        if case .idle = interactionController.state {
                            interactionController.dragStarted(at: value.startLocation)
                        }
                        interactionController.dragMoved(to: value.location)
                    }
                    .onEnded { _ in interactionController.dragEnded() }
            )
            .zIndex(40)
    }

    func applyBoardLifecycle<V: View>(to content: V) -> some View {
        applyBoardPresentations(
            to: applyBoardNotificationHandlers(
                to: applyBoardChangeObservers(
                    to: content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(boardBackgroundColor)
                        .onAppear {
                            configureBoardInteraction()
                            syncACPPaneStores()
                        }
                )
            )
        )
    }

    private func applyBoardChangeObservers<V: View>(to content: V) -> some View {
        content
            .onChange(of: vibespaceID) { _, newVibeSpaceID in
                resyncBoard(for: newVibeSpaceID)
            }
            .onChange(of: projectPathSnapshot) { _, _ in
                boardStore.syncProjects(projects)
            }
            .onChange(of: surfaceLayout) { _, _ in
                syncACPPaneStores()
            }
            .onChange(of: hiddenTerminalIDsByProjectPath) { _, updatedHiddenTerminalIDs in
                boardStore.setHiddenTerminalIDsByProjectPath(updatedHiddenTerminalIDs)
            }
    }

    private func applyBoardNotificationHandlers<V: View>(to content: V) -> some View {
        content
            .onReceive(
                dockPreviewBridge?.$pendingFileURL.compactMap({ $0 }).eraseToAnyPublisher()
                ?? Empty().eraseToAnyPublisher()
            ) { fileURL in
                if let _ = dockPreviewBridge?.consumePending() {
                    onFileSystemTargetActivated(
                        TerminalFileSystemTarget(url: fileURL, line: nil, column: nil),
                        preferredProjectRootURL(for: fileURL)
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusNextProjectTerminal)) { _ in
                guard !isSpotlightPresented else { return }
                navigateSpatially(.down)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPreviousProjectTerminal)) { _ in
                guard !isSpotlightPresented else { return }
                navigateSpatially(.up)
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyInTerminal)) { _ in
                boardStore.copyActiveTileTerminal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteInTerminal)) { _ in
                boardStore.pasteActiveTileTerminal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardNavigateRight)) { _ in
                guard !isSpotlightPresented else { return }
                navigateSpatially(.right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .boardNavigateLeft)) { _ in
                guard !isSpotlightPresented else { return }
                navigateSpatially(.left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addACPTileToBoard)) { _ in
                addACPTileAction()
            }
            .onReceive(
                dockedBrowserCoordinator?.browserSessionDidChange.eraseToAnyPublisher()
                    ?? Empty().eraseToAnyPublisher()
            ) { _ in
                boardStore.commit()
            }
    }

    private func applyBoardPresentations<V: View>(to content: V) -> some View {
        content
            .alert(AppStrings.Terminal.boardTitle, isPresented: boardAlertIsPresented) {
                Button(AppStrings.Common.ok, role: .cancel) {
                    boardAlertMessage = nil
                }
            } message: {
                Text(boardAlertMessage ?? "")
            }
    }

    var boardAlertIsPresented: Binding<Bool> {
        Binding(
            get: { boardAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    boardAlertMessage = nil
                }
            }
        )
    }

    func configureBoardInteraction() {
        boardStore.setHiddenTerminalIDsByProjectPath(hiddenTerminalIDsByProjectPath)
        boardStore.syncProjects(projects)
        boardStore.seedInitialTileIfNeeded(projects: projects)
        let adapter = BoardInteractionDelegateAdapter(
            boardStore: boardStore,
            surfaceID: surfaceID,
            tileContextProvider: { [boardStore, interactionController] tileID in
                let frame = interactionController.metricsProvider?.frame(for: tileID) ?? .zero
                return boardStore.dragProxyInfo(for: tileID, sourceFrame: frame, surfaceID: surfaceID)
            },
            minimizedContextProvider: { [boardStore] tileID in
                boardStore.minimizedDragProxyInfo(for: tileID, surfaceID: surfaceID)
            },
            detachTileHandler: onTileDetachRequested
        )
        delegateAdapter = adapter
        interactionController.delegate = adapter
    }

    func resyncBoard(for newVibeSpaceID: UUID?) {
        boardStore.updateVibeSpaceID(newVibeSpaceID)
        boardStore.setHiddenTerminalIDsByProjectPath(hiddenTerminalIDsByProjectPath)
        boardStore.syncProjects(projects)
        boardStore.seedInitialTileIfNeeded(projects: projects)
    }

    private func preferredProjectRootURL(for fileURL: URL) -> URL? {
        let normalizedFileURL = fileURL.standardizedFileURL
        return projects.first(where: {
            let rootURL = $0.rootURL.standardizedFileURL
            let rootPath = rootURL.path
            let filePath = normalizedFileURL.path
            return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
        })?.rootURL.standardizedFileURL
    }
}
