import SwiftUI
import AppKit

struct TerminalSpotlightCardView<SpotlightContent: View, InputBarContent: View>: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @EnvironmentObject private var themeManager: CrispyVibesThemeManager

    let spotlight: TerminalSpotlightState
    let onDismiss: () -> Void
    let onPin: (() -> Void)?
    let pinAccessibilityLabel: String?
    let shortcutDefinitions: [TerminalShortcutDefinition]
    let onShortcutSelected: ((TerminalShortcutDefinition) -> Void)?
    let onManageShortcutsRequested: (() -> Void)?
    let onSendSignal: ((String) -> Void)?
    let onRenamePersistentTab: (TerminalViewModel, UUID, String) -> Void
    let spotlightContent: () -> SpotlightContent
    let inputBarContent: () -> InputBarContent

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: spotlight.headerIconName)
                    .foregroundStyle(spotlight.accentColor ?? activeThemePalette.accentColor)

                HStack(spacing: 6) {
                    if isRenaming, case let .persistent(vm, tabID) = spotlight.source {
                        TextField("", text: $renameText, onCommit: {
                            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            onRenamePersistentTab(vm, tabID, trimmed)
                            isRenaming = false
                        })
                        .textFieldStyle(.plain)
                        .font(AppTypographyTokens.subheadlineSemibold)
                        .foregroundStyle(activeThemePalette.primaryTextColor)
                        .frame(maxWidth: 200)
                        .focused($isRenameFieldFocused)
                        .onExitCommand { isRenaming = false }
                        .onAppear { isRenameFieldFocused = true }
                    } else {
                        Text(spotlight.title)
                            .font(AppTypographyTokens.subheadlineSemibold)
                            .lineLimit(1)
                            .foregroundStyle(activeThemePalette.primaryTextColor)
                            .onTapGesture(count: 2) {
                                if case .persistent = spotlight.source {
                                    renameText = spotlight.title
                                    isRenaming = true
                                }
                            }
                    }

                    if spotlight.showsTemporaryBadge {
                        Text(AppStrings.Terminal.temporary)
                            .font(AppTypographyTokens.caption2Semibold)
                            .foregroundStyle(activeThemePalette.secondaryTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(activeThemePalette.selectionBackgroundColor.opacity(0.22))
                            .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 8)

                Text(spotlight.workingDirectoryURL.path)
                    .font(AppTypographyTokens.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(activeThemePalette.secondaryTextColor)

                if let onSendSignal {
                    TerminalCommandsMenu(
                        textColor: activeThemePalette.secondaryTextColor,
                        shortcuts: shortcutDefinitions,
                        onRunShortcut: { shortcut in
                            onShortcutSelected?(shortcut)
                        },
                        onManageShortcutsRequested: onManageShortcutsRequested,
                        onSendSignal: onSendSignal
                    )
                    .accessibilityIdentifier("terminal.spotlight.commands")
                }

                if let onSplitTerminalRequested = spotlight.onSplitTerminalRequested {
                    CrispyVibesIconButton(systemName: "square.split.2x1", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: "Split Terminal") {
                        onSplitTerminalRequested()
                    }
                    .help(AppStrings.Terminal.splitTerminal)
                }

                if let onTemporaryTerminalRequested = spotlight.onTemporaryTerminalRequested {
                    CrispyVibesIconButton(systemName: "scope", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: "New Temporary Terminal") {
                        onTemporaryTerminalRequested()
                    }
                    .help(AppStrings.Terminal.newTemporaryTerminal)
                }

                if let onPin, let pinAccessibilityLabel {
                    CrispyVibesIconButton(systemName: "pin", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: pinAccessibilityLabel) {
                        onPin()
                    }
                    .help(pinAccessibilityLabel)
                    .accessibilityIdentifier("terminal.spotlight.pin")
                }

                CrispyVibesIconButton(systemName: "xmark.circle.fill", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: "Close Terminal Spotlight") {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(activeThemePalette.canvasSecondaryBackgroundColor)

            Divider()

            spotlightContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if spotlight.source.showsComposeInputBar {
                inputBarContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(activeThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: themeManager.theme.radius(11), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: themeManager.theme.radius(11), style: .continuous)
                .stroke(activeThemePalette.borderColorValue.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 26, x: 0, y: 15)
        .accessibilityIdentifier("terminal.spotlight.overlay")
        .onTapGesture(count: 2) {
            onDismiss()
        }
    }
}

extension ContentView {
    @ViewBuilder
    func terminalSpotlightCard(for spotlight: TerminalSpotlightState) -> some View {
        let pinMetadata = spotlightPinMetadata(for: spotlight)
        TerminalSpotlightCardView(
            spotlight: spotlight,
            onDismiss: closeTerminalSpotlight,
            onPin: pinMetadata?.action,
            pinAccessibilityLabel: pinMetadata?.label,
            shortcutDefinitions: spotlight.shortcutDefinitions,
            onShortcutSelected: spotlight.onShortcutSelected,
            onManageShortcutsRequested: spotlight.onManageShortcutsRequested,
            onSendSignal: spotlightSendSignalHandler(for: spotlight),
            onRenamePersistentTab: { terminalViewModel, tabID, title in
                terminalViewModel.renameTab(tabID, to: title)
            },
            spotlightContent: { terminalSpotlightContent(for: spotlight) },
            inputBarContent: {
                SpotlightTerminalInputBar(
                    spotlight: spotlight,
                    vibespaceProjects: vibespaceView.activeVibeSpaceProjects
                )
            }
        )
    }

    private func spotlightSendSignalHandler(for spotlight: TerminalSpotlightState) -> ((String) -> Void)? {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            return { signal in
                terminalViewModel.session(for: tabID)?.sendRawText(signal)
            }
        case let .transient(session):
            return { signal in
                session.sendRawText(signal)
            }
        case .vibeCast, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    @ViewBuilder
    private func terminalSpotlightContent(for spotlight: TerminalSpotlightState) -> some View {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            if let resolvedTab = terminalViewModel.tabs.first(where: { $0.id == tabID }) {
                TerminalSessionView(
                    tab: resolvedTab,
                    viewModel: terminalViewModel,
                    isActive: true,
                    sessionAccessibilityIdentifier: "terminal.spotlight.session",
                    sessionHostAccessibilityIdentifier: "terminal.spotlight.host",
                    inlineTriggerTerminalTitle: resolvedTab.title.isEmpty ? spotlight.title : resolvedTab.title,
                    inlineTriggerSearchRoots: spotlightInlineTriggerSearchRoots(for: spotlight, fallbackDirectory: resolvedTab.workingDirectory),
                    inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                    onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                    onSessionSelected: { selectedTabID in
                        presentTerminalSpotlight(
                            terminalViewModel: terminalViewModel,
                            tabID: selectedTabID,
                            title: spotlight.title,
                            accentColor: spotlight.accentColor,
                            owningProjectRootURL: spotlight.owningProjectRootURL,
                            surfaceID: spotlight.surfaceID
                        )
                    },
                    onSessionDoubleClicked: { _ in
                        dismissTerminalSpotlight()
                    },
                    onSplitTerminalRequested: { tab in
                        createSplitTerminal(
                            in: terminalViewModel,
                            directoryURL: tab.workingDirectory,
                            surfaceID: spotlight.surfaceID,
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
                                createSplitTerminal(
                                    in: terminalViewModel,
                                    directoryURL: tab.workingDirectory,
                                    surfaceID: spotlight.surfaceID,
                                    owningProjectRootURL: spotlight.owningProjectRootURL
                                )
                            },
                            owningProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onOpenInEditorPaneRequested: { tab in
                        openTerminalInEditorPane(tabID: tab.id, projectRootURL: spotlight.owningProjectRootURL)
                    },
                    onLinkTargetActivated: { url in
                        openTerminalLinkTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onFileSystemTargetActivated: { url in
                        openTerminalFileSystemTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    }
                )
            } else {
                ContentUnavailableView(
                    "Terminal Unavailable",
                    systemImage: "terminal",
                    description: Text(AppStrings.Terminal.selectedUnavailable)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .transient(session):
            TerminalSessionHostView(
                session: session,
                displayDensity: .regular,
                isActive: true,
                accessibilityIdentifier: "terminal.spotlight.host",
                inlineTriggerTerminalTitle: spotlight.title,
                inlineTriggerSearchRoots: spotlightInlineTriggerSearchRoots(
                    for: spotlight,
                    fallbackDirectory: session.currentWorkingDirectory
                ),
                inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                onSplitTerminalRequested: spotlight.onSplitTerminalRequested,
                onTemporaryTerminalRequested: spotlight.onTemporaryTerminalRequested,
                onLinkTargetActivated: { url in
                    openTerminalLinkTarget(
                        url,
                        preferredProjectRootURL: spotlight.owningProjectRootURL
                    )
                },
                onFileSystemTargetActivated: { url in
                    openTerminalFileSystemTarget(
                        url,
                        preferredProjectRootURL: spotlight.owningProjectRootURL
                    )
                }
            )
            .id(session.viewIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .vibeCast:
            VibeCastView(
                store: contentViewerStore.vibeCastStore,
                terminalSources: vibespaceView.activeVibeSpaceProjects.map { project in
                    .init(
                        id: project.id.uuidString,
                        projectTitle: project.title,
                        projectRootURL: project.rootURL,
                        accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color ?? activeThemePalette.accentColor,
                        viewModel: project.terminalViewModel
                    )
                },
                isActive: true,
                onManageShortcutsRequested: spotlight.onManageShortcutsRequested
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .acp(_, storeID):
            if let store = contentViewerStore.acpStore(for: storeID) {
                ACPStandalonePaneContentView(
                    store: store,
                    projects: vibespaceView.activeVibeSpaceProjects,
                    displayMode: .spotlight,
                    onLinkTargetActivated: { url in
                        openTerminalLinkTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onFileSystemTargetActivated: { target in
                        openTerminalFileSystemTarget(
                            target,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    AppStrings.ACP.unavailableTitle,
                    systemImage: "sparkles",
                    description: Text(AppStrings.ACP.unavailableDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .filePreview(target, group):
            FileContentWithCommentsPanel(
                panel: group.commentsPanel,
                store: appContainer.vibespaceCommentStore,
                filePath: target.standardizedFileURL.path,
                editorContent: {
                    MarkdownEditorView(
                        viewModel: group.markdownViewModel,
                        showsTopBar: false,
                        headerLayout: .embedded
                    )
                    .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
                    .environment(\.commentsPanelEnvironment, group.commentsPanel)
                    .environment(\.commentsFilePathEnvironment, target.standardizedFileURL.path)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .file(tileID, fileURL):
            let fileContext = resolvedFileOpenContext(
                for: fileURL,
                preferredProjectRootURL: spotlight.owningProjectRootURL
            )
            let group = dockedFileViewerCoordinator.editorGroup(
                for: tileID,
                fileURL: fileURL,
                documentReference: fileContext.reference,
                fileContentProvider: fileContext.fileContentProvider
            )
            FileContentWithCommentsPanel(
                panel: group.commentsPanel,
                store: appContainer.vibespaceCommentStore,
                filePath: fileURL.standardizedFileURL.path,
                editorContent: {
                    MarkdownEditorView(
                        viewModel: group.markdownViewModel,
                        showsTopBar: false,
                        headerLayout: .embedded
                    )
                    .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
                    .environment(\.commentsPanelEnvironment, group.commentsPanel)
                    .environment(\.commentsFilePathEnvironment, fileURL.standardizedFileURL.path)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browserPreview(snapshot):
            let vm = spotlightBrowserPreviewViewModel(
                snapshot: snapshot,
                projectPath: spotlight.owningProjectRootURL?.path
            )
            BrowserContentView(viewModel: vm, presentation: .spotlight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browser(tileID, url):
            let vm = dockedBrowserCoordinator.viewModel(for: tileID, url: url)
            BrowserContentView(viewModel: vm, presentation: .spotlight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func spotlightInlineTriggerSearchRoots(
        for spotlight: TerminalSpotlightState,
        fallbackDirectory: URL
    ) -> [URL] {
        var roots: [URL] = [fallbackDirectory]
        if let owningProjectRootURL = spotlight.owningProjectRootURL {
            roots.append(owningProjectRootURL)
        }
        roots.append(contentsOf: vibespaceView.activeVibeSpaceProjects.map(\.rootURL))
        roots.append(spotlight.workingDirectoryURL)

        var seen = Set<String>()
        return roots.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private struct SpotlightPinMetadata {
        let label: String
        let action: () -> Void
    }

    private func spotlightPinMetadata(for spotlight: TerminalSpotlightState) -> SpotlightPinMetadata? {
        switch vibespaceView.selectedCanvasMode {
        case .detailed:
            guard spotlightSupportsDetailedPin(spotlight) else { return nil }
            return SpotlightPinMetadata(label: "Open in Viewer", action: {
                pinSpotlightToDetailedViewer(spotlight)
            })
        case .terminalOnly:
            guard spotlightSupportsBoardPin(spotlight) else { return nil }
            return SpotlightPinMetadata(label: "Pin to Dock", action: {
                pinSpotlightToTerminalBoard(spotlight)
            })
        }
    }

    private func spotlightSupportsDetailedPin(_ spotlight: TerminalSpotlightState) -> Bool {
        switch spotlight.source {
        case .filePreview, .file, .browserPreview, .browser:
            return true
        case .persistent, .transient, .vibeCast, .acp:
            return false
        }
    }

    private func spotlightSupportsBoardPin(_ spotlight: TerminalSpotlightState) -> Bool {
        switch spotlight.source {
        case .filePreview, .browserPreview:
            return true
        case .persistent, .transient, .vibeCast, .acp, .file, .browser:
            return false
        }
    }

    private func pinSpotlightToDetailedViewer(_ spotlight: TerminalSpotlightState) {
        switch spotlight.source {
        case let .filePreview(target, _):
            let fileContext = resolvedFileOpenContext(
                for: target.url,
                preferredProjectRootURL: spotlight.owningProjectRootURL
            )
            contentViewerStore.openFileInTab(
                at: target.url,
                line: target.line,
                column: target.column,
                projectIdentifier: fileContext.reference.projectIdentifier,
                fileContentProvider: fileContext.fileContentProvider
            )
        case let .file(_, fileURL):
            let fileContext = resolvedFileOpenContext(
                for: fileURL,
                preferredProjectRootURL: spotlight.owningProjectRootURL
            )
            contentViewerStore.openFileInTab(
                at: fileURL,
                projectIdentifier: fileContext.reference.projectIdentifier,
                fileContentProvider: fileContext.fileContentProvider
            )
        case let .browserPreview(snapshot):
            let fallbackURL = snapshot.urlString.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!
            let effectiveSnapshot = dockedBrowserCoordinator.previewSnapshot(fallbackURL: fallbackURL) ?? snapshot
            let reference = BrowserTabReference(
                url: effectiveSnapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL,
                projectPath: spotlight.owningProjectRootURL?.path
            )
            dockedBrowserCoordinator.restoreDetailedBrowser(reference: reference, snapshot: effectiveSnapshot)
            contentViewerStore.activeGroup.openTab(.webPage(reference: reference))
        case let .browser(tileID, url):
            let viewModel = dockedBrowserCoordinator.viewModel(for: tileID, url: url)
            let currentURL = viewModel.currentURL ?? url
            let reference = BrowserTabReference(
                url: currentURL,
                projectPath: spotlight.owningProjectRootURL?.path,
                linkedTileID: tileID
            )
            dockedBrowserCoordinator.restoreDetailedBrowser(
                reference: reference,
                snapshot: viewModel.sessionSnapshot()
            )
            contentViewerStore.activeGroup.openTab(.webPage(reference: reference))
        case .persistent, .transient, .vibeCast, .acp:
            return
        }
        dismissTerminalSpotlight()
    }

    private func pinSpotlightToTerminalBoard(_ spotlight: TerminalSpotlightState) {
        guard let boardStore = vibespaceHydrationCoordinator.boardStore else { return }

        switch spotlight.source {
        case let .filePreview(target, group):
            guard let tileID = boardStore.pinPreviewToDock(fileURL: target.url) else { return }
            dockedFileViewerCoordinator.assignEditorGroup(group, for: tileID, fileURL: target.url)
        case let .browserPreview(snapshot):
            let fallbackURL = snapshot.urlString.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!
            let effectiveSnapshot = dockedBrowserCoordinator.previewSnapshot(fallbackURL: fallbackURL) ?? snapshot
            let resolvedURL = effectiveSnapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL
            guard let tileID = boardStore.pinBrowserToDock(
                url: resolvedURL,
                projectPath: spotlight.owningProjectRootURL?.path
            ) else { return }
            dockedBrowserCoordinator.promotePreview(to: tileID)
        case .persistent, .transient, .vibeCast, .acp, .file, .browser:
            return
        }
        dismissTerminalSpotlight()
    }
}

private struct SpotlightTerminalPastedImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let escapedPath: String
}

struct SpotlightTerminalInputBar: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.boardInlinePickerOverlayController) private var boardInlinePickerOverlayController
    @Environment(\.composeHistoryStore) private var composeHistoryStore
    @Environment(\.crispyvibesUIScale) private var uiScale
    let spotlight: TerminalSpotlightState
    let vibespaceProjects: [AnyProjectSession]

    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    private var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @State private var inputText = ""
    @State private var pendingSelectionLocation: Int?
    @State private var isRephrasing = false
    @State private var drafts: [UUID: String] = [:]
    @State private var imageDrafts: [UUID: [SpotlightTerminalPastedImage]] = [:]
    @State private var pastedImages: [SpotlightTerminalPastedImage] = []
    @State private var focusTrigger = false
    @StateObject private var inlineTrigger = TerminalInlineTriggerController()
    @State private var historyNavigator: ComposeHistoryNavigator?

    private var session: TerminalSession? {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            return terminalViewModel.session(for: tabID)
        case let .transient(session):
            return session
        case .vibeCast, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    var body: some View {
        if session != nil {
            // Fixed reserved space — compose bar floats as overlay, growing upward
            Color.clear
                .frame(height: uiScale.chromeSize(ComposeLayoutTokens.compactBarHeight + 20))
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if !pastedImages.isEmpty {
                            pastedImageStrip
                        }
                        TerminalComposeInputView(
                            text: $inputText,
                            pendingSelectionLocation: $pendingSelectionLocation,
                            isRephrasing: isRephrasing,
                            requestFocus: focusTrigger,
                            canSendOverride: canSendInputPayload,
                    onSend: { sendInput() },
                    onRephrase: { rephrase() },
                    inlineOverlayActive: inlineTrigger.isPresented,
                    onInlineMoveUp: { _ = inlineTrigger.handleCommand(.moveUp) },
                    onInlineMoveDown: { _ = inlineTrigger.handleCommand(.moveDown) },
                    onInlineMoveRight: { _ = inlineTrigger.handleCommand(.moveRight) },
                    onInlineConfirm: { _ = inlineTrigger.handleCommand(.confirm) },
                    onInlineDismiss: dismissInlineTrigger,
                    onPasteImage: { image in appendPastedImage(image) },
                    onHistoryBack: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateBack(currentText: inputText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            inputText = text
                        }
                    },
                    onHistoryForward: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateForward(currentText: inputText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            inputText = text
                        }
                    }
                )
            }
            }
            .onAppear {
                if let composeHistoryStore {
                    historyNavigator = ComposeHistoryNavigator(store: composeHistoryStore)
                }
                historyNavigator?.attach(to: session?.id)
                focusTrigger = true
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
            }
            .onChange(of: terminalIdentity) { oldID, newID in
                guard oldID != newID else { return }
                if let oldID {
                    drafts[oldID] = inputText
                    imageDrafts[oldID] = pastedImages
                }
                if let newID {
                    inputText = drafts[newID] ?? ""
                    pastedImages = imageDrafts[newID] ?? []
                } else {
                    inputText = ""
                    pastedImages = []
                }
                historyNavigator?.attach(to: newID)
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
                focusTrigger = false
                DispatchQueue.main.async { focusTrigger = true }
            }
            .onChange(of: inputText) { _, _ in
                if historyNavigator?.isApplyingNavigation == true {
                    historyNavigator?.isApplyingNavigation = false
                } else {
                    historyNavigator?.resetOnUnrelatedEdit()
                }
                syncInlineTriggerBuffer()
            }
            .onChange(of: configuredInlineTrigger) { _, _ in
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
            }
            .onChange(of: spotlight.title) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: spotlight.shortcutDefinitions.map { "\($0.id.uuidString):\($0.name):\($0.command)" }) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: vibespaceProjectRootPaths) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: currentSessionSearchDirectoryPath) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onDisappear {
                clearBoardInlinePickerOverlay()
                inlineTrigger.shutdown()
            }
            .onReceive(inlineTrigger.objectWillChange) { _ in
                guard boardInlinePickerOverlayController != nil else { return }
                DispatchQueue.main.async {
                    syncBoardInlinePickerOverlay()
                }
            }
        }
    }

    private var pastedImageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pastedImages) { pastedImage in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: pastedImage.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: uiScale.iconSize(52), height: uiScale.iconSize(52))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(palette.borderColorValue.opacity(0.35), lineWidth: 1)
                            )

                        Button {
                            pastedImages.removeAll { $0.id == pastedImage.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypographyTokens.caption)
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                    .help(pastedImage.escapedPath)
                }
            }
            .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(ComposeLayoutTokens.backgroundOpacity))
    }

    private var terminalIdentity: UUID? {
        switch spotlight.source {
        case let .persistent(_, tabID): return tabID
        case let .transient(session): return session.id
        case .vibeCast, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    private var inlinePathSearchRoots: [URL] {
        var orderedRoots: [URL] = []
        if let currentSessionDirectoryURL = currentSessionSearchDirectoryURL {
            orderedRoots.append(currentSessionDirectoryURL)
        }
        if let owningProjectRootURL = spotlight.owningProjectRootURL, owningProjectRootURL.isFileURL {
            orderedRoots.append(owningProjectRootURL)
        }
        orderedRoots.append(contentsOf: vibespaceProjects.compactMap { project in
            guard project.projectSession != nil else { return nil }
            let rootURL = project.rootURL.standardizedFileURL
            return rootURL.isFileURL ? rootURL : nil
        })
        if spotlight.workingDirectoryURL.isFileURL {
            orderedRoots.append(spotlight.workingDirectoryURL)
        }

        var seen = Set<String>()
        return orderedRoots.compactMap { rootURL in
            let normalized = rootURL.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private var vibespaceProjectRootPaths: [String] {
        inlinePathSearchRoots.map(\.path)
    }

    private var currentSessionSearchDirectoryPath: String? {
        currentSessionSearchDirectoryURL?.path
    }

    private var currentSessionSearchDirectoryURL: URL? {
        guard let directoryURL = session?.currentWorkingDirectory.standardizedFileURL,
              directoryURL.isFileURL else {
            return nil
        }
        return directoryURL
    }

    private var parsedInlineTrigger: SpotlightComposeInlineTrigger? {
        SpotlightComposeInlineTrigger.parse(
            inputText,
            triggerToken: AppPreferences.normalizedTerminalComposeInlineTrigger(configuredInlineTrigger)
        )
    }

    private var inputPayloadText: String {
        let typedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagePaths = pastedImages.map(\.escapedPath)
        guard !typedText.isEmpty else {
            return imagePaths.joined(separator: " ")
        }
        guard !imagePaths.isEmpty else {
            return typedText
        }
        return ([typedText] + imagePaths).joined(separator: " ")
    }

    private var canSendInputPayload: Bool {
        !inputPayloadText.isEmpty
    }

    private func sendInput() {
        let text = inputPayloadText
        guard !text.isEmpty else { return }
        session?.sendRawTextWithEnter(text)
        historyNavigator?.append(text)
        inputText = ""
        pastedImages = []
        if let terminalIdentity {
            drafts[terminalIdentity] = ""
            imageDrafts[terminalIdentity] = []
        }
        syncInlineTriggerBuffer()
    }

    private func appendPastedImage(_ image: NSImage) {
        guard let escapedPath = savePastedImage(image) else { return }
        pastedImages.append(SpotlightTerminalPastedImage(image: image, escapedPath: escapedPath))
        requestComposeFocus()
    }

    private func savePastedImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crispyvibes-terminal-paste",
            isDirectory: true
        )
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "clipboard-\(timestamp)-\(UUID().uuidString.prefix(8)).png"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: .atomic)
            return ShellEscaping.singleQuote(fileURL.path)
        } catch {
            return nil
        }
    }

    private func rephrase() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRephrasing else { return }
        isRephrasing = true
        Task.detached {
            let result = VibeCastRephraseService.rephrase(text)
            await MainActor.run {
                if let result { inputText = result }
                isRephrasing = false
            }
        }
    }

    private func dismissInlineTrigger() {
        _ = inlineTrigger.handleCommand(.dismiss)
        requestComposeFocus()
        syncBoardInlinePickerOverlay()
    }

    private func requestComposeFocus() {
        focusTrigger = false
        DispatchQueue.main.async {
            focusTrigger = true
        }
    }

    private func replaceInlineTrigger(with replacement: String) {
        guard let trigger = parsedInlineTrigger else {
            return
        }
        let newText = trigger.prefixText + replacement
        inputText = newText
        pendingSelectionLocation = (newText as NSString).length
    }

    private func syncInlineTriggerConfiguration() {
        let sessionRef = session
        inlineTrigger.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: inlinePathSearchRoots,
            shortcuts: spotlight.shortcutDefinitions,
            terminalTitle: spotlight.title,
            currentDirectoryProvider: { [weak sessionRef] in
                sessionRef?.currentWorkingDirectory ?? spotlight.workingDirectoryURL
            },
            insertionHandler: { replacement in
                replaceInlineTrigger(with: replacement)
            },
            focusHandler: requestComposeFocus,
            manageShortcutsHandler: spotlight.onManageShortcutsRequested
        )
        syncBoardInlinePickerOverlay()
    }

    private func syncInlineTriggerBuffer() {
        inlineTrigger.syncBufferText(inputText)
        syncBoardInlinePickerOverlay()
    }

    private var boardInlinePickerOverlayOwnerID: String {
        "terminal-spotlight:\(terminalIdentity?.uuidString ?? spotlight.title)"
    }

    private var manageShortcutsAction: (() -> Void)? {
        guard spotlight.onManageShortcutsRequested != nil else { return nil }
        let inlineTriggerRef = inlineTrigger
        return { [weak inlineTriggerRef] in
            inlineTriggerRef?.runManageShortcutsAction()
        }
    }

    private func syncBoardInlinePickerOverlay() {
        guard let boardInlinePickerOverlayController else { return }
        guard inlineTrigger.isPresented else {
            boardInlinePickerOverlayController.clear(ownerID: boardInlinePickerOverlayOwnerID)
            return
        }
        let inlineTriggerRef = inlineTrigger

        boardInlinePickerOverlayController.update(
            ownerID: boardInlinePickerOverlayOwnerID,
            presentation: BoardInlinePickerOverlayPresentation(
                title: AppStrings.Terminal.ComposeTriggers.pickerTitle,
                queryText: inlineTrigger.queryText,
                featuredAction: inlineTrigger.featuredPanelAction,
                rows: inlineTrigger.panelRows,
                statusText: inlineTrigger.footerText,
                hintText: inlineTrigger.hintText,
                actionTitle: inlineTrigger.manageShortcutsActionTitle,
                onAction: manageShortcutsAction,
                onFeaturedAction: { [weak inlineTriggerRef] in
                    inlineTriggerRef?.applyFeaturedAction()
                },
                onDismiss: { [weak inlineTriggerRef] in
                    _ = inlineTriggerRef?.handleCommand(.dismiss)
                },
                onSelect: { [weak inlineTriggerRef] rowID in
                    inlineTriggerRef?.applyResult(id: rowID)
                }
            )
        )
    }

    private func clearBoardInlinePickerOverlay() {
        boardInlinePickerOverlayController?.clear(ownerID: boardInlinePickerOverlayOwnerID)
    }
}
