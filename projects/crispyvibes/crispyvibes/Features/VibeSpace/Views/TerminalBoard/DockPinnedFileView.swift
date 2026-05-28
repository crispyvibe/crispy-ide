import SwiftUI

struct DockPinnedFileView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    /// F049: comment store comes from RootView-level env. When non-nil, the
    /// file tile docks the comments panel + floating button + overlays.
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStore: VibeSpaceCommentStore?
    let fileURL: URL
    let isActive: Bool
    @ObservedObject var editorGroup: EditorGroupStore
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onSpotlight: () -> Void
    var boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = []
    var onSendToNewBoardWindow: (() -> Void)? = nil
    var onSendToBoardWindow: ((UUID) -> Void)? = nil
    /// F048-R13 context menu: bulk-move all tiles for this file's project.
    var onSendAllFromProjectToNewBoardWindow: (() -> Void)? = nil
    var interactionController: BoardInteractionController?

    var body: some View {
        FileContentWithCommentsPanel(
            panel: editorGroup.commentsPanel,
            store: commentStore,
            filePath: fileURL.standardizedFileURL.path,
            editorContent: {
                MarkdownEditorView(
                    viewModel: editorGroup.markdownViewModel,
                    showsTopBar: false,
                    headerLayout: .embedded
                )
                .environment(\.vibespaceCommentStoreEnvironment, commentStore)
                .environment(\.commentsPanelEnvironment, editorGroup.commentsPanel)
                .environment(\.commentsFilePathEnvironment, fileURL.standardizedFileURL.path)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 30)
        .onTapGesture { onSelect() }
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
        .accessibilityIdentifier("vibespace.terminal-board.file-tile")
        .accessibilityValue(isActive ? "active" : "inactive")
        .contentShape(Rectangle())
        .contextMenu {
            Button(AppStrings.Terminal.Tile.minimize) { onMinimize() }
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow,
                onSendAllFromProjectToNewBoardWindow: onSendAllFromProjectToNewBoardWindow
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
            Image(systemName: iconName)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .foregroundStyle(appThemePalette.accentColor)

            Text(fileURL.lastPathComponent)
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .onTapGesture(count: 2) { onSpotlight() }

            Spacer(minLength: 6)

            Text(fileURL.deletingLastPathComponent().lastPathComponent)
                .font(CrispyVibesHeaderStyle.card.detailFont(scale: chromeScale))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .frame(maxWidth: 220, alignment: .trailing)

            CrispyVibesIconButton(
                systemName: "minus.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Minimize File Tile"
            ) {
                onMinimize()
            }

            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Close File Tile"
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

    private var iconName: String {
        let ext = fileURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.text.image" }
        if ["md", "markdown"].contains(ext) { return "doc.richtext" }
        if ["doc", "docx"].contains(ext) { return "doc.text.fill" }
        if ["ppt", "pptx"].contains(ext) { return "rectangle.stack.fill" }
        if ["xls", "xlsx"].contains(ext) { return "tablecells.fill" }
        return "doc.text"
    }
}
