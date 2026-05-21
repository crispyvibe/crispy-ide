import SwiftUI

extension VibeSpaceTerminalOnlyView {
    func boardWindowTargetsForTransferMenu() -> [VibeSpaceTerminalBoardSurfaceTransferTarget] {
        boardWindowTransferTargets?(boardStore, surfaceID) ?? []
    }

    func sendToNewBoardWindowAction(for tileID: UUID) -> (() -> Void)? {
        guard let onTileSendToNewBoardWindowRequested else { return nil }
        return {
            onTileSendToNewBoardWindowRequested(tileID, boardStore, surfaceID)
        }
    }

    func sendToBoardWindowAction(for tileID: UUID) -> ((UUID) -> Void)? {
        guard let onTileSendToBoardWindowRequested else { return nil }
        return { targetSurfaceID in
            onTileSendToBoardWindowRequested(tileID, targetSurfaceID, boardStore, surfaceID)
        }
    }

    var minimizedTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(surfaceLayout.minimizedTiles) { tile in
                    minimizedTab(for: tile)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.92))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: surfaceLayout.minimizedTiles.map(\.id))
    }

    func minimizedTab(for tile: VibeSpaceTerminalBoardTile) -> some View {
        let context = boardStore.tileContext(for: tile)
        let projectAccentColor = accentColor(for: tile.projectPath)
        let activityState = context.map { $0.terminalViewModel.tabActivityStateOrInactive(for: $0.terminalTab.id) }
        let boardWindowTargets = boardWindowTargetsForTransferMenu()

        let title: String
        let accent: Color
        if let snapshot = tile.acpSnapshot {
            title = acpStoreLookup?(snapshot.id)?.tabTitle ?? AppStrings.ACP.agentContentTitle
            accent = projectAccentColor ?? appThemePalette.accentColor
        } else if let fileURL = tile.fileURL {
            title = fileURL.lastPathComponent
            accent = appThemePalette.accentColor
        } else {
            title = context?.projectTitle ?? "Terminal"
            accent = projectAccentColor ?? appThemePalette.accentColor
        }

        return MinimizedTerminalTabView(
            title: title,
            accentColor: accent,
            activityState: activityState,
            onTap: {
                boardStore.restoreTile(tile.id, surfaceID: surfaceID)
            },
            onRestore: {
                boardStore.restoreTile(tile.id, surfaceID: surfaceID)
            },
            onClose: {
                if tile.isFile { dockedFileViewerCoordinator?.removeGroup(for: tile.id) }
                if tile.isBrowser { dockedBrowserCoordinator?.removeViewModel(for: tile.id) }
                if let snapshot = tile.acpSnapshot { removeACPPaneStore?(snapshot.id) }
                boardStore.removeTile(tile.id, surfaceID: surfaceID)
            },
            boardWindowTransferTargets: boardWindowTargets,
            onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
            onSendToBoardWindow: sendToBoardWindowAction(for: tile.id)
        )
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("terminalBoard"))
                .onChanged { value in
                    if case .idle = interactionController.state {
                        interactionController.dragStartedFromMinimized(tileID: tile.id, at: value.startLocation)
                    }
                    interactionController.dragMoved(to: value.location)
                }
                .onEnded { _ in
                    interactionController.dragEnded()
                }
        )
    }

    func tileCard(
        _ tile: VibeSpaceTerminalBoardTile,
        metrics: VibeSpaceTerminalBoardMetrics
    ) -> some View {
        let frame = metrics.frame(for: tile)
        let isDragging = interactionController.movingTileID == tile.id
        let isActive = surfaceLayout.activeTileID == tile.id
        let tileAccentColor = accentColor(for: tile.projectPath) ?? appThemePalette.accentColor
        let boardWindowTargets = boardWindowTargetsForTransferMenu()

        return Group {
            if tile.isVibeCast, let vibeCastStore {
                VibeCastBoardTileCard(
                    store: vibeCastStore,
                    projects: projects,
                    projectColorTagsByPath: projectColorTagsByPath,
                    isActive: isActive,
                    onSelect: { boardStore.activateTile(tile.id, requestFocus: true, surfaceID: surfaceID) },
                    onClose: { boardStore.removeTile(tile.id, surfaceID: surfaceID) },
                    onSpotlight: { onVibeCastSpotlightRequested() },
                    onManageShortcutsRequested: onManageShortcutsRequested,
                    boardWindowTransferTargets: boardWindowTargets,
                    onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
                    onSendToBoardWindow: sendToBoardWindowAction(for: tile.id),
                    interactionController: interactionController
                )
            } else if tile.isFile, let fileURL = tile.fileURL,
                      let coordinator = dockedFileViewerCoordinator {
                let group = coordinator.editorGroup(for: tile.id, fileURL: fileURL)
                DockPinnedFileView(
                    fileURL: fileURL,
                    isActive: isActive,
                    editorGroup: group,
                    onSelect: { boardStore.activateTile(tile.id, requestFocus: false, surfaceID: surfaceID) },
                    onClose: {
                        coordinator.removeGroup(for: tile.id)
                        boardStore.removeTile(tile.id, surfaceID: surfaceID)
                    },
                    onMinimize: { boardStore.minimizeTile(tile.id, surfaceID: surfaceID) },
                    onSpotlight: { onFileSpotlightRequested?(tile.id, fileURL) },
                    boardWindowTransferTargets: boardWindowTargets,
                    onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
                    onSendToBoardWindow: sendToBoardWindowAction(for: tile.id),
                    interactionController: interactionController
                )
            } else if tile.isBrowser, let url = tile.browserURL,
                      let coordinator = dockedBrowserCoordinator {
                BrowserBoardTileView(
                    viewModel: coordinator.viewModel(for: tile.id, url: url),
                    isActive: isActive,
                    onSelect: { boardStore.activateTile(tile.id, requestFocus: false, surfaceID: surfaceID) },
                    onClose: {
                        coordinator.removeViewModel(for: tile.id)
                        boardStore.removeTile(tile.id, surfaceID: surfaceID)
                    },
                    onMinimize: { boardStore.minimizeTile(tile.id, surfaceID: surfaceID) },
                    onSpotlight: { onBrowserSpotlightRequested?(tile.id, url) },
                    boardWindowTransferTargets: boardWindowTargets,
                    onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
                    onSendToBoardWindow: sendToBoardWindowAction(for: tile.id),
                    interactionController: interactionController
                )
            } else if let snapshot = tile.acpSnapshot,
                      let store = acpStoreLookup?(snapshot.id) {
                ACPBoardTileCard(
                    store: store,
                    projects: projects,
                    isActive: isActive,
                    projectAccentColor: store.selectedProject(from: projects).flatMap { accentColor(for: $0.rootURL.standardizedFileURL.path) },
                    onLinkTargetActivated: { url in
                        onLinkTargetActivated(url, store.selectedProject(from: projects)?.rootURL)
                    },
                    onFileSystemTargetActivated: { target in
                        onFileSystemTargetActivated(target, store.selectedProject(from: projects)?.rootURL)
                    },
                    onSelect: { boardStore.activateTile(tile.id, requestFocus: false, surfaceID: surfaceID) },
                    onClose: {
                        removeACPPaneStore?(snapshot.id)
                        boardStore.removeTile(tile.id, surfaceID: surfaceID)
                    },
                    onMinimize: { boardStore.minimizeTile(tile.id, surfaceID: surfaceID) },
                    onSpotlight: { onACPSpotlightRequested(tile.id, snapshot.id) },
                    boardWindowTransferTargets: boardWindowTargets,
                    onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
                    onSendToBoardWindow: sendToBoardWindowAction(for: tile.id),
                    interactionController: interactionController
                )
            } else if let context = boardStore.tileContext(for: tile) {
                let projectAccentColor = accentColor(for: context.projectPath)
                let shortcutDefinitions = shortcutDefinitionsForProjectPath(context.projectPath)
                let inlineTriggerSearchRoots = [projectURL(for: context.projectPath), context.terminalTab.workingDirectory]
                    .compactMap { $0 }
                VibeSpaceTerminalBoardTileCard(
                    tile: tile,
                    terminalViewModel: context.terminalViewModel,
                    terminalTabID: context.terminalTab.id,
                    projectTitle: context.projectTitle,
                    projectAccentColor: projectAccentColor,
                    isActive: isActive,
                    isCanvasVisible: isVisible,
                    onSelect: {
                        boardStore.activateTile(tile.id, requestFocus: true, surfaceID: surfaceID)
                    },
                    onClose: {
                        boardStore.removeTile(tile.id, surfaceID: surfaceID)
                    },
                    onMinimize: {
                        boardStore.minimizeTile(tile.id, surfaceID: surfaceID)
                    },
                    onSpotlight: {
                        onSpotlightRequested(
                            context.terminalViewModel,
                            context.terminalTab.id,
                            context.projectTitle,
                            projectAccentColor,
                            projectURL(for: context.projectPath)
                        )
                    },
                    onSplitTerminal: {
                        _ = boardStore.addTile(
                            projectPath: context.projectPath,
                            directoryURL: context.terminalTab.workingDirectory,
                            preferStandalone: context.projectPath == nil,
                            surfaceID: surfaceID
                        )
                    },
                    onTemporaryTerminal: {
                        onTemporaryTerminalRequested(
                            context.terminalViewModel,
                            context.terminalTab.workingDirectory,
                            context.projectTitle,
                            projectAccentColor,
                            projectURL(for: context.projectPath)
                        )
                    },
                    shortcutDefinitions: shortcutDefinitions,
                    inlineTriggerSearchRoots: inlineTriggerSearchRoots,
                    onRunShortcut: { shortcut in
                        executeTerminalShortcut(
                            shortcut,
                            viewModel: context.terminalViewModel,
                            defaultDirectory: context.terminalTab.workingDirectory,
                            onTemporaryShortcutRequested: { shortcut, directoryURL in
                                onTemporaryShortcutRequested(
                                    context.terminalViewModel,
                                    shortcut,
                                    directoryURL,
                                    context.projectTitle,
                                    projectAccentColor,
                                    projectURL(for: context.projectPath)
                                )
                            },
                            onTerminalInteraction: {
                                boardStore.activateTile(tile.id, requestFocus: true, surfaceID: surfaceID)
                            },
                            onActiveTabChanged: { _ in
                                boardStore.activateTile(tile.id, requestFocus: true, surfaceID: surfaceID)
                            }
                        )
                    },
                    onManageShortcutsRequested: onManageShortcutsRequested,
                    onLinkTargetActivated: { url in
                        onLinkTargetActivated(
                            url,
                            projectURL(for: context.projectPath)
                        )
                    },
                    onFileSystemTargetActivated: { url in
                        onFileSystemTargetActivated(
                            url,
                            projectURL(for: context.projectPath)
                        )
                    },
                    onOpenInEditorPaneRequested: {
                        openTerminalInEditorPane(
                            projectPath: context.projectPath,
                            terminalTabID: context.terminalTab.id
                        )
                    },
                    boardWindowTransferTargets: boardWindowTargets,
                    onSendToNewBoardWindow: sendToNewBoardWindowAction(for: tile.id),
                    onSendToBoardWindow: sendToBoardWindowAction(for: tile.id),
                    interactionController: interactionController
                )
            } else {
                unresolvedTileCard(
                    for: tile,
                    isActive: isActive,
                    isVisible: isVisible
                )
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .shadow(color: isActive ? tileAccentColor.opacity(0.3) : .clear, radius: 8)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(isDragging ? 0.32 : 1)
        .zIndex(isDragging ? 10 : 1)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    func unresolvedTileCard(
        for tile: VibeSpaceTerminalBoardTile,
        isActive: Bool,
        isVisible: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Label(tile.isACP ? AppStrings.ACP.unavailableTitle : "Terminal Missing", systemImage: "exclamationmark.triangle")
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
            Text(tile.isACP ? AppStrings.ACP.unavailableDescription : tile.workingDirectoryPath)
                .font(AppTypographyTokens.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(appThemePalette.secondaryTextColor)
            Button(AppStrings.Terminal.Tile.remove) {
                if let snapshot = tile.acpSnapshot { removeACPPaneStore?(snapshot.id) }
                boardStore.removeTile(tile.id, surfaceID: surfaceID)
            }
            .buttonStyle(.crispyvibesText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(appThemePalette.borderColorValue.opacity(0.5), lineWidth: 0.8)
        )
        .onAppear {
            guard isVisible, !tile.isACP else { return }
            boardStore.restoreTerminalIfNeeded(for: tile.id, surfaceID: surfaceID)
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue, isVisible, !tile.isACP else { return }
            boardStore.restoreTerminalIfNeeded(for: tile.id, surfaceID: surfaceID)
        }
        .onChange(of: isVisible) { _, newValue in
            guard newValue, !tile.isACP else { return }
            boardStore.restoreTerminalIfNeeded(for: tile.id, surfaceID: surfaceID)
        }
    }
}

private struct ACPBoardTileCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme

    @ObservedObject var store: ACPStandaloneSessionStore
    @State private var showingSettings = false
    let projects: [AnyProjectSession]
    let isActive: Bool
    let projectAccentColor: Color?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onSpotlight: () -> Void
    let boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onSendToNewBoardWindow: (() -> Void)?
    let onSendToBoardWindow: ((UUID) -> Void)?
    var interactionController: BoardInteractionController?

    private var tileAccentColor: Color {
        projectAccentColor ?? appThemePalette.accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .terminalActivityPulse(isActive: store.chatViewModel.isStreaming, color: tileAccentColor)
                Text(store.tabTitle)
                    .font(AppTypographyTokens.captionSemibold)
                    .lineLimit(1)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                if let projectTitle = store.selectedProject(from: projects)?.title {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        Text(projectTitle)
                            .lineLimit(1)
                    }
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                }
                Spacer(minLength: 6)
                if store.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else if store.isConnected {
                    Circle()
                        .fill(appThemePalette.successColor)
                        .frame(width: 7, height: 7)
                        .help("Connected")
                }
                CrispyVibesIconButton(
                    systemName: showingSettings ? "chevron.left.circle.fill" : "line.3.horizontal.decrease.circle.fill",
                    variant: .card,
                    color: showingSettings ? tileAccentColor : appThemePalette.secondaryTextColor,
                    accessibilityLabel: showingSettings ? "Show chat" : "Show agent settings"
                ) {
                    showingSettings.toggle()
                }
                CrispyVibesIconButton(
                    systemName: "minus.circle.fill",
                    variant: .card,
                    color: appThemePalette.secondaryTextColor,
                    accessibilityLabel: AppStrings.Terminal.Tile.minimize
                ) {
                    onMinimize()
                }
                CrispyVibesIconButton(
                    systemName: "xmark.circle.fill",
                    variant: .card,
                    color: appThemePalette.secondaryTextColor,
                    accessibilityLabel: AppStrings.ACP.closeAgentTile
                ) {
                    onClose()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(appThemePalette.canvasSecondaryBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onTapGesture(count: 2) { onSpotlight() }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("terminalBoard"))
                    .onChanged { value in
                        guard let interactionController else { return }
                        if case .idle = interactionController.state {
                            interactionController.dragStarted(at: value.startLocation)
                        }
                        if interactionController.isMoving {
                            interactionController.dragMoved(to: value.location)
                        }
                    }
                    .onEnded { _ in
                        interactionController?.dragEnded()
                    }
            )

            Rectangle()
                .fill(appThemePalette.primaryTextColor.opacity(0.10))
                .frame(height: 1)

            ACPStandalonePaneContentView(
                store: store,
                projects: projects,
                displayMode: .board,
                showingSettings: $showingSettings,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(isActive ? tileAccentColor.opacity(0.58) : appThemePalette.primaryTextColor.opacity(0.06), lineWidth: isActive ? 0.9 : 0.2)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .accessibilityIdentifier("vibespace.terminal-board.agent-tile")
        .contextMenu {
            Button(AppStrings.Terminal.Tile.minimize) { onMinimize() }
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow
            )
        }
    }
}
