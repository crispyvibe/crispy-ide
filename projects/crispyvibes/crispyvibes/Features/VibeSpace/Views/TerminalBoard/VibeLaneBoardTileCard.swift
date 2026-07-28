import SwiftUI

@MainActor
struct VibeLaneBoardTileCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize

    let focusedProjectPath: String?
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onSpotlight: () -> Void
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void
    let onOpenFileTarget: (TerminalFileSystemTarget) -> Void
    let boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget]
    let onSendToNewBoardWindow: (() -> Void)?
    let onSendToBoardWindow: ((UUID) -> Void)?
    let onSendAllFromProjectToNewBoardWindow: (() -> Void)?
    var interactionController: BoardInteractionController?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(appThemePalette.primaryTextColor.opacity(0.10)).frame(height: 1)
            VibeLaneSurfaceView(
                focusedProjectPath: focusedProjectPath,
                onOpenACPSession: onOpenACPSession,
                onOpenFileTarget: onOpenFileTarget
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
        .accessibilityIdentifier("vibespace.terminal-board.vibe-lanes-tile")
        .accessibilityValue(isActive ? "active" : "inactive")
        .contextMenu {
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow,
                onSendAllFromProjectToNewBoardWindow: onSendAllFromProjectToNewBoardWindow
            )
        }
    }

    private var header: some View {
        CrispyVibesHeaderChrome(style: .card, background: appThemePalette.canvasSecondaryBackgroundColor) {
            Image(systemName: VibeLaneVisualIdentity.symbolName)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .foregroundStyle(appThemePalette.accentColor)
            Text(AppStrings.VibeLanes.title)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)
            Spacer(minLength: 6)
            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: AppStrings.Common.close
            ) {
                onClose()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSpotlight() }
        .onTapGesture { onSelect() }
        .simultaneousGesture(
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
