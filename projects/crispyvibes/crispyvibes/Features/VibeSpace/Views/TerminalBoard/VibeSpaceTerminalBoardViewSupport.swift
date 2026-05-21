import SwiftUI

struct BoardWindowTransferContextMenuItems: View {
    let targets: [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onSendToNewBoardWindow: (() -> Void)?
    let onSendToBoardWindow: ((UUID) -> Void)?

    var body: some View {
        if onSendToNewBoardWindow != nil || (onSendToBoardWindow != nil && !targets.isEmpty) {
            Divider()

            if let onSendToNewBoardWindow {
                Button(AppStrings.Terminal.Tile.sendToNewBoardWindow) {
                    onSendToNewBoardWindow()
                }
            }

            if let onSendToBoardWindow, !targets.isEmpty {
                Menu(AppStrings.Terminal.Tile.sendToBoardWindow) {
                    ForEach(targets) { target in
                        Button(target.title) {
                            onSendToBoardWindow(target.id)
                        }
                    }
                }
            }
        }
    }
}

struct MinimizedTerminalTabView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject private var activityState: TerminalTabActivityState
    let title: String
    let accentColor: Color
    let onTap: () -> Void
    let onRestore: () -> Void
    let onClose: () -> Void
    let boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onSendToNewBoardWindow: (() -> Void)?
    let onSendToBoardWindow: ((UUID) -> Void)?

    init(
        title: String,
        accentColor: Color,
        activityState: TerminalTabActivityState?,
        onTap: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onClose: @escaping () -> Void,
        boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = [],
        onSendToNewBoardWindow: (() -> Void)? = nil,
        onSendToBoardWindow: ((UUID) -> Void)? = nil
    ) {
        self.title = title
        self.accentColor = accentColor
        self._activityState = ObservedObject(
            wrappedValue: activityState ?? TerminalTabActivityState(id: UUID(), isActive: false)
        )
        self.onTap = onTap
        self.onRestore = onRestore
        self.onClose = onClose
        self.boardWindowTransferTargets = boardWindowTransferTargets
        self.onSendToNewBoardWindow = onSendToNewBoardWindow
        self.onSendToBoardWindow = onSendToBoardWindow
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(CrispyVibesHeaderStyle.compact.titleFont(scale: chromeScale))
                .terminalActivityPulse(isActive: activityState.isActive, color: accentColor)

            Text(title)
                .font(CrispyVibesHeaderStyle.compact.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)

            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .compact,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Close Minimized Terminal"
            ) {
                onClose()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(accentColor.opacity(0.3), lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onRestore() }
        .onTapGesture { onTap() }
        .contextMenu {
            Button(AppStrings.Terminal.Tile.restore) { onRestore() }
            Button(AppStrings.Terminal.closeTerminal) { onClose() }
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow
            )
        }
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }
}

struct VibeCastBoardTileCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject var store: VibeCastStore
    let projects: [AnyProjectSession]
    let projectColorTagsByPath: [String: ProjectColorTag]
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onSpotlight: () -> Void
    let onManageShortcutsRequested: (() -> Void)?
    let boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onSendToNewBoardWindow: (() -> Void)?
    let onSendToBoardWindow: ((UUID) -> Void)?
    var interactionController: BoardInteractionController?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(appThemePalette.primaryTextColor.opacity(0.10)).frame(height: 1)
            VibeCastView(
                store: store,
                terminalSources: projects.map {
                    .init(
                        id: $0.id.uuidString,
                        projectTitle: $0.title,
                        projectRootURL: $0.rootURL,
                        accentColor: projectColorTagsByPath[$0.rootURL.standardizedFileURL.path]?.color ?? appThemePalette.accentColor,
                        viewModel: $0.terminalViewModel
                    )
                },
                isActive: isActive,
                onManageShortcutsRequested: onManageShortcutsRequested
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(
                    isActive ? appThemePalette.accentColor.opacity(0.58) : appThemePalette.primaryTextColor.opacity(0.06),
                    lineWidth: isActive ? 0.9 : 0.2
                )
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .accessibilityIdentifier("vibespace.terminal-board.vibecast-tile")
        .accessibilityValue(isActive ? "active" : "inactive")
        .contextMenu {
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow
            )
        }
    }

    private var header: some View {
        CrispyVibesHeaderChrome(style: .card, background: appThemePalette.canvasSecondaryBackgroundColor) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .foregroundStyle(appThemePalette.accentColor)
            Text(AppStrings.VibeCast.title)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)
            Spacer(minLength: 6)
            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Close VibeCast Tile"
            ) {
                onClose()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSpotlight() }
        .onTapGesture { onSelect() }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("terminalBoard"))
                .onChanged { value in
                    guard let controller = interactionController else { return }
                    if case .idle = controller.state {
                        controller.dragStarted(at: value.startLocation)
                    }
                    if controller.isMoving {
                        controller.dragMoved(to: value.location)
                    }
                }
                .onEnded { _ in
                    interactionController?.dragEnded()
                }
        )
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }
}

@MainActor
final class BoardInteractionDelegateAdapter: BoardInteractionDelegate {
    private let boardStore: VibeSpaceTerminalBoardStore
    private let surfaceID: UUID
    private let tileContextProvider: (UUID) -> BoardDragProxyInfo?
    private let minimizedContextProvider: (UUID) -> BoardDragProxyInfo?
    private let detachTileHandler: ((UUID, CGPoint) -> Void)?

    init(
        boardStore: VibeSpaceTerminalBoardStore,
        surfaceID: UUID = VibeSpaceTerminalBoardState.primarySurfaceID,
        tileContextProvider: @escaping (UUID) -> BoardDragProxyInfo?,
        minimizedContextProvider: @escaping (UUID) -> BoardDragProxyInfo?,
        detachTileHandler: ((UUID, CGPoint) -> Void)? = nil
    ) {
        self.boardStore = boardStore
        self.surfaceID = surfaceID
        self.tileContextProvider = tileContextProvider
        self.minimizedContextProvider = minimizedContextProvider
        self.detachTileHandler = detachTileHandler
    }

    func interactionController(_ controller: BoardInteractionController, didMoveTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) {
        boardStore.moveTile(tileID, using: intent, surfaceID: surfaceID)
    }

    func interactionController(_ controller: BoardInteractionController, didRestoreMinimizedTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) {
        boardStore.restoreMinimizedTile(tileID, using: intent, surfaceID: surfaceID)
    }

    func interactionController(_ controller: BoardInteractionController, didDetachTile tileID: UUID, atScreenPoint screenPoint: CGPoint) {
        detachTileHandler?(tileID, screenPoint)
    }

    func interactionController(_ controller: BoardInteractionController, didResizeColumns leftColumnID: UUID, rightColumnID: UUID, leftWeight: Double, rightWeight: Double, commit: Bool) {
        boardStore.setColumnWeights(
            leftColumnID: leftColumnID,
            rightColumnID: rightColumnID,
            leftWeight: leftWeight,
            rightWeight: rightWeight,
            commit: commit,
            surfaceID: surfaceID
        )
    }

    func interactionController(_ controller: BoardInteractionController, didResizeRows columnID: UUID, upperTileID: UUID, lowerTileID: UUID, upperWeight: Double, lowerWeight: Double, commit: Bool) {
        boardStore.setRowWeights(
            columnID: columnID,
            upperTileID: upperTileID,
            lowerTileID: lowerTileID,
            upperWeight: upperWeight,
            lowerWeight: lowerWeight,
            commit: commit,
            surfaceID: surfaceID
        )
    }

    func interactionController(_ controller: BoardInteractionController, didActivateTile tileID: UUID) {
        boardStore.activateTile(tileID, requestFocus: false, surfaceID: surfaceID)
    }

    func interactionControllerDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo? {
        tileContextProvider(tileID)
    }

    func interactionControllerMinimizedDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo? {
        minimizedContextProvider(tileID)
    }
}

struct BoardMetricsAdapter: BoardMetricsProviding {
    let metrics: VibeSpaceTerminalBoardMetrics
    let layout: VibeSpaceTerminalBoardLayout
    let hitTestContext: BoardHitTesting.Context

    var boardSize: CGSize { metrics.size }

    func frame(for tileID: UUID) -> CGRect {
        metrics.frame(for: tileID)
    }

    func hitTest(at point: CGPoint) -> BoardHitRegion {
        BoardHitTesting.hitTest(at: point, context: hitTestContext)
    }

    func dockingGuide(at point: CGPoint, excluding tileID: UUID?) -> VibeSpaceTerminalBoardDockingGuide? {
        metrics.dockingGuide(at: point, excluding: tileID)
    }

    func columnWeights(leftColumnID: UUID, rightColumnID: UUID) -> (left: Double, right: Double)? {
        guard let leftCol = layout.columns.first(where: { $0.id == leftColumnID }),
              let rightCol = layout.columns.first(where: { $0.id == rightColumnID }) else { return nil }
        return (left: leftCol.widthWeight, right: rightCol.widthWeight)
    }

    func rowWeights(columnID: UUID, upperTileID: UUID, lowerTileID: UUID) -> (upper: Double, lower: Double)? {
        guard let column = layout.columns.first(where: { $0.id == columnID }),
              let upper = column.tiles.first(where: { $0.id == upperTileID }),
              let lower = column.tiles.first(where: { $0.id == lowerTileID }) else { return nil }
        return (upper: upper.heightWeight, lower: lower.heightWeight)
    }

    func horizontalWeightDelta(for pixelDelta: CGFloat) -> Double {
        metrics.horizontalWeightDelta(for: pixelDelta)
    }

    func verticalWeightDelta(for pixelDelta: CGFloat, columnID: UUID) -> Double {
        metrics.verticalWeightDelta(for: pixelDelta, columnID: columnID)
    }

    func previewLayout(moving tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) -> VibeSpaceTerminalBoardLayout? {
        layout.previewLayout(moving: tileID, with: intent)
    }
}
