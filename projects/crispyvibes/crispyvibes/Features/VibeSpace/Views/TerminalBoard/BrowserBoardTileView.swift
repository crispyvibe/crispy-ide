import SwiftUI
import WebKit

struct BrowserBoardTileView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject var viewModel: BrowserPanelViewModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onSpotlight: () -> Void
    var boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = []
    var onSendToNewBoardWindow: (() -> Void)? = nil
    var onSendToBoardWindow: ((UUID) -> Void)? = nil
    var interactionController: BoardInteractionController?

    var body: some View {
        BrowserContentView(
            viewModel: viewModel,
            presentation: .board(isActive: isActive)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 30)
        .overlay(alignment: .top) {
            header
                .scrollAssistGlassBackground(in: UnevenRoundedRectangle(
                    topLeadingRadius: crispyvibesTheme.borderShape.cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: crispyvibesTheme.borderShape.cornerRadius
                ))
        }
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(
                    crispyvibesTheme.borderVisible ? borderColor : borderColor.opacity(0),
                    lineWidth: isActive ? 0.9 : 0.2
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser Tile")
        .accessibilityIdentifier("vibespace.terminal-board.browser-tile")
        .contextMenu {
            Button(AppStrings.Terminal.Tile.minimize) { onMinimize() }
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow
            )
        }
    }

    private var borderColor: Color {
        isActive ? appThemePalette.accentColor : appThemePalette.borderColorValue
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }

    private var header: some View {
        CrispyVibesHeaderChrome(style: .card, background: .clear) {
            Image(systemName: "globe")
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .foregroundStyle(appThemePalette.accentColor)

            Text(viewModel.displayTitle)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .onTapGesture(count: 2) { onSpotlight() }

            Spacer(minLength: 6)

            CrispyVibesIconButton(
                systemName: "minus.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Minimize Browser Tile"
            ) { onMinimize() }

            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Close Browser Tile"
            ) { onClose() }
        }
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

}
