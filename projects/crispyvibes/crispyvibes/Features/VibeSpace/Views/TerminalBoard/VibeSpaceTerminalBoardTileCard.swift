import SwiftUI

struct VibeSpaceTerminalBoardTileCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    let tile: VibeSpaceTerminalBoardTile
    @ObservedObject var terminalViewModel: TerminalViewModel
    @ObservedObject private var tabActivityState: TerminalTabActivityState
    let terminalTabID: UUID
    let projectTitle: String?
    let projectAccentColor: Color?
    let isActive: Bool
    let isCanvasVisible: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onSpotlight: () -> Void
    let onSplitTerminal: () -> Void
    let onTemporaryTerminal: () -> Void
    let shortcutDefinitions: [TerminalShortcutDefinition]
    let inlineTriggerSearchRoots: [URL]
    let onRunShortcut: ((TerminalShortcutDefinition) -> Void)?
    let onManageShortcutsRequested: (() -> Void)?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    var onOpenInEditorPaneRequested: (() -> Void)? = nil
    var boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = []
    var onSendToNewBoardWindow: (() -> Void)? = nil
    var onSendToBoardWindow: ((UUID) -> Void)? = nil
    /// F048-R13 context menu: bulk-move all tiles for this tile's project.
    var onSendAllFromProjectToNewBoardWindow: (() -> Void)? = nil
    var interactionController: BoardInteractionController?

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isTileHovered = false
    @FocusState private var isRenameFieldFocused: Bool

    init(
        tile: VibeSpaceTerminalBoardTile,
        terminalViewModel: TerminalViewModel,
        terminalTabID: UUID,
        projectTitle: String?,
        projectAccentColor: Color?,
        isActive: Bool,
        isCanvasVisible: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onMinimize: @escaping () -> Void,
        onSpotlight: @escaping () -> Void,
        onSplitTerminal: @escaping () -> Void,
        onTemporaryTerminal: @escaping () -> Void,
        shortcutDefinitions: [TerminalShortcutDefinition] = [],
        inlineTriggerSearchRoots: [URL] = [],
        onRunShortcut: ((TerminalShortcutDefinition) -> Void)? = nil,
        onManageShortcutsRequested: (() -> Void)? = nil,
        onLinkTargetActivated: ((URL) -> Void)? = nil,
        onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil,
        onOpenInEditorPaneRequested: (() -> Void)? = nil,
        boardWindowTransferTargets: [VibeSpaceTerminalBoardSurfaceTransferTarget] = [],
        onSendToNewBoardWindow: (() -> Void)? = nil,
        onSendToBoardWindow: ((UUID) -> Void)? = nil,
        onSendAllFromProjectToNewBoardWindow: (() -> Void)? = nil,
        interactionController: BoardInteractionController? = nil
    ) {
        self.tile = tile
        self._terminalViewModel = ObservedObject(wrappedValue: terminalViewModel)
        self._tabActivityState = ObservedObject(
            wrappedValue: terminalViewModel.tabActivityStateOrInactive(for: terminalTabID)
        )
        self.terminalTabID = terminalTabID
        self.projectTitle = projectTitle
        self.projectAccentColor = projectAccentColor
        self.isActive = isActive
        self.isCanvasVisible = isCanvasVisible
        self.onSelect = onSelect
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onSpotlight = onSpotlight
        self.onSplitTerminal = onSplitTerminal
        self.onTemporaryTerminal = onTemporaryTerminal
        self.shortcutDefinitions = shortcutDefinitions
        self.inlineTriggerSearchRoots = inlineTriggerSearchRoots
        self.onRunShortcut = onRunShortcut
        self.onManageShortcutsRequested = onManageShortcutsRequested
        self.onLinkTargetActivated = onLinkTargetActivated
        self.onFileSystemTargetActivated = onFileSystemTargetActivated
        self.onOpenInEditorPaneRequested = onOpenInEditorPaneRequested
        self.boardWindowTransferTargets = boardWindowTransferTargets
        self.onSendToNewBoardWindow = onSendToNewBoardWindow
        self.onSendToBoardWindow = onSendToBoardWindow
        self.onSendAllFromProjectToNewBoardWindow = onSendAllFromProjectToNewBoardWindow
        self.interactionController = interactionController
    }

    private var terminalTab: TerminalTab? {
        terminalViewModel.tabs.first(where: { $0.id == terminalTabID })
    }

    private var panelBackgroundColor: Color {
        appThemePalette.canvasBackgroundColor
    }

    private var headerBackgroundColor: Color {
        appThemePalette.canvasSecondaryBackgroundColor
    }

    private var resolvedProjectAccentColor: Color {
        projectAccentColor ?? appThemePalette.accentColor
    }

    private var borderColor: Color {
        isActive
            ? resolvedProjectAccentColor.opacity(0.58)
            : appThemePalette.primaryTextColor.opacity(0.06)
    }

    private var hasActivity: Bool {
        tabActivityState.isActive
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }

    private func startSessionIfNeededForDisplay() {
        guard isCanvasVisible else { return }
        terminalViewModel.session(for: terminalTabID)?.startIfNeeded()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(headerBackgroundColor)

            Group {
                if let session = terminalViewModel.session(for: terminalTabID) {
                    TerminalSessionHostView(
                        session: session,
                        displayDensity: .regular,
                        isActive: isActive,
                        allowsOwnershipParticipation: isCanvasVisible,
                        accessibilityIdentifier: "vibespace.terminal-board.session",
                        inlineTriggerTerminalTitle: terminalTab?.title ?? projectTitle ?? "Terminal",
                        inlineTriggerSearchRoots: inlineTriggerSearchRoots,
                        inlineTriggerShortcuts: shortcutDefinitions,
                        onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                        onSplitTerminalRequested: onSplitTerminal,
                        onTemporaryTerminalRequested: onTemporaryTerminal,
                        onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                    .id(session.viewIdentity)
                    .onTapGesture(count: 2) {
                        onSpotlight()
                    }
                    .onTapGesture {
                        onSelect()
                    }
                } else {
                    ContentUnavailableView(
                        AppStrings.Terminal.noSession,
                        systemImage: "terminal",
                        description: Text(AppStrings.Terminal.noSessionDescription)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.18), value: isTileHovered)
        .animation(.easeOut(duration: 0.18), value: isActive)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.borderShape.cornerRadius, style: .continuous)
                .stroke(
                    crispyvibesTheme.borderVisible ? borderColor : borderColor.opacity(0),
                    lineWidth: isActive ? 0.9 : 0.2
                )
        )
        .onHover { isTileHovered = $0 }
        .accessibilityIdentifier("vibespace.terminal-board.tile")
        .accessibilityValue(isActive ? "active" : "inactive")
        .contentShape(Rectangle())
        .contextMenu {
            Button(AppStrings.Terminal.Tile.minimize) {
                onMinimize()
            }
            Button(AppStrings.Terminal.splitTerminal) {
                onSplitTerminal()
            }
            Button(AppStrings.Terminal.newTemporaryTerminal) {
                onTemporaryTerminal()
            }
            BoardWindowTransferContextMenuItems(
                targets: boardWindowTransferTargets,
                onSendToNewBoardWindow: onSendToNewBoardWindow,
                onSendToBoardWindow: onSendToBoardWindow,
                onSendAllFromProjectToNewBoardWindow: onSendAllFromProjectToNewBoardWindow
            )
        }
        .onAppear(perform: startSessionIfNeededForDisplay)
        .onChange(of: isActive) { _, _ in
            startSessionIfNeededForDisplay()
        }
        .onChange(of: isCanvasVisible) { _, _ in
            startSessionIfNeededForDisplay()
        }
    }

    private var header: some View {
        CrispyVibesHeaderChrome(style: .card, background: .clear) {
            Image(systemName: "terminal")
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .terminalActivityPulse(isActive: hasActivity, color: resolvedProjectAccentColor)

            Text(projectTitle ?? "Terminal")
                .font(CrispyVibesHeaderStyle.card.titleFont(scale: chromeScale))
                .lineLimit(1)
                .foregroundStyle(appThemePalette.primaryTextColor)

            if let branchName = terminalTab?.gitBranchName, !branchName.isEmpty {
                Label(branchName, systemImage: "arrow.triangle.branch")
                    .font(CrispyVibesHeaderStyle.card.detailFont(scale: chromeScale))
                    .lineLimit(1)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .padding(.leading, 2)
            }

            Spacer(minLength: 6)

            if isRenaming {
                TextField("", text: $renameText, onCommit: {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    terminalViewModel.renameTab(terminalTabID, to: trimmed)
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(appThemePalette.primaryTextColor)
                .frame(maxWidth: 220)
                .focused($isRenameFieldFocused)
                .onExitCommand { isRenaming = false }
                .onAppear { isRenameFieldFocused = true }
            } else {
                Text(terminalTab?.title ?? tile.workingDirectoryPath)
                    .font(CrispyVibesHeaderStyle.card.detailFont(scale: chromeScale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(maxWidth: 220, alignment: .trailing)
                    .help(terminalTab?.workingDirectory.path ?? tile.workingDirectoryPath)
                    .onTapGesture(count: 2) {
                        renameText = terminalTab?.title ?? ""
                        isRenaming = true
                    }
            }

            TerminalCommandsMenu(
                textColor: appThemePalette.secondaryTextColor,
                shortcuts: shortcutDefinitions,
                onRunShortcut: { shortcut in
                    onRunShortcut?(shortcut)
                },
                onManageShortcutsRequested: onManageShortcutsRequested,
                onSendSignal: sendSignalToTileSession(_:)
            )
            .accessibilityIdentifier("vibespace.terminal-board.tile.commands")

            CrispyVibesIconButton(
                systemName: "minus.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Minimize Terminal Tile"
            ) {
                onMinimize()
            }

            CrispyVibesIconButton(
                systemName: "xmark.circle.fill",
                variant: .card,
                color: appThemePalette.secondaryTextColor,
                accessibilityLabel: "Close Terminal Tile"
            ) {
                onClose()
            }
        }
        .contentShape(Rectangle())
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

    private func sendSignalToTileSession(_ text: String) {
        terminalViewModel.session(for: terminalTabID)?.sendRawText(text)
    }
}
