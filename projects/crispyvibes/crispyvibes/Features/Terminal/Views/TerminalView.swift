import SwiftUI

struct TerminalView: View {
    enum HeaderLayout: Equatable {
        case floating
        case embedded
    }

    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var viewModel: TerminalViewModel
    @ObservedObject private var tabActivitySummary: TerminalTabActivitySummary
    let defaultDirectory: URL
    var onTerminalInteraction: (() -> Void)? = nil
    var onActiveTabChanged: ((UUID) -> Void)? = nil
    var onSessionDoubleClicked: ((UUID) -> Void)? = nil
    var onSplitTerminalRequested: ((TerminalTab) -> Void)? = nil
    var onTemporaryTerminalRequested: ((TerminalTab) -> Void)? = nil
    var onTemporaryShortcutRequested: ((TerminalShortcutDefinition, URL) -> Void)? = nil
    var onOpenInEditorPaneRequested: ((TerminalTab) -> Void)? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil
    var onManageShortcutsRequested: (() -> Void)? = nil
    var presentationMode: TerminalPresentationMode = .singleActiveTab
    var headerLayout: HeaderLayout = .floating
    var embeddedHeaderCornerRadii: RectangleCornerRadii? = nil
    var showsHeaderSummaryActivityIndicator: Bool = true
    var showsInlineTerminalActions = true
    var showsSplitPresentationToggle = true
    var additionalHeaderControls: AnyView? = nil
    var shortcutProvider: VibeSpaceShortcutProvider?
    var dragContentViewerTabProvider: ((TerminalTab) -> ContentViewerTab?)? = nil
    @State private var expandedTabID: UUID?
    @State private var cachedStyling: TerminalStyling?
    @State private var isSplitMode = false
    @State private var splitSecondaryTabID: UUID?

    init(
        viewModel: TerminalViewModel,
        defaultDirectory: URL,
        onTerminalInteraction: (() -> Void)? = nil,
        onActiveTabChanged: ((UUID) -> Void)? = nil,
        onSessionDoubleClicked: ((UUID) -> Void)? = nil,
        onSplitTerminalRequested: ((TerminalTab) -> Void)? = nil,
        onTemporaryTerminalRequested: ((TerminalTab) -> Void)? = nil,
        onTemporaryShortcutRequested: ((TerminalShortcutDefinition, URL) -> Void)? = nil,
        onOpenInEditorPaneRequested: ((TerminalTab) -> Void)? = nil,
        onLinkTargetActivated: ((URL) -> Void)? = nil,
        onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil,
        onManageShortcutsRequested: (() -> Void)? = nil,
        presentationMode: TerminalPresentationMode = .singleActiveTab,
        headerLayout: HeaderLayout = .floating,
        embeddedHeaderCornerRadii: RectangleCornerRadii? = nil,
        showsHeaderSummaryActivityIndicator: Bool = true,
        showsInlineTerminalActions: Bool = true,
        showsSplitPresentationToggle: Bool = true,
        additionalHeaderControls: AnyView? = nil,
        shortcutProvider: VibeSpaceShortcutProvider? = nil,
        dragContentViewerTabProvider: ((TerminalTab) -> ContentViewerTab?)? = nil
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._tabActivitySummary = ObservedObject(wrappedValue: viewModel.tabActivitySummary)
        self.defaultDirectory = defaultDirectory
        self.onTerminalInteraction = onTerminalInteraction
        self.onActiveTabChanged = onActiveTabChanged
        self.onSessionDoubleClicked = onSessionDoubleClicked
        self.onSplitTerminalRequested = onSplitTerminalRequested
        self.onTemporaryTerminalRequested = onTemporaryTerminalRequested
        self.onTemporaryShortcutRequested = onTemporaryShortcutRequested
        self.onOpenInEditorPaneRequested = onOpenInEditorPaneRequested
        self.onLinkTargetActivated = onLinkTargetActivated
        self.onFileSystemTargetActivated = onFileSystemTargetActivated
        self.onManageShortcutsRequested = onManageShortcutsRequested
        self.presentationMode = presentationMode
        self.headerLayout = headerLayout
        self.embeddedHeaderCornerRadii = embeddedHeaderCornerRadii
        self.showsHeaderSummaryActivityIndicator = showsHeaderSummaryActivityIndicator
        self.showsInlineTerminalActions = showsInlineTerminalActions
        self.showsSplitPresentationToggle = showsSplitPresentationToggle
        self.additionalHeaderControls = additionalHeaderControls
        self.shortcutProvider = shortcutProvider
        self.dragContentViewerTabProvider = dragContentViewerTabProvider
    }

    private var expandedTab: TerminalTab? {
        guard let expandedTabID else { return nil }
        return viewModel.tabs.first(where: { $0.id == expandedTabID })
    }

    private var activeTab: TerminalTab? {
        viewModel.activeTab
    }

    private var styling: TerminalStyling {
        cachedStyling ?? TerminalStyling(palette: appThemePalette)
    }

    private var isRailPresentation: Bool {
        presentationMode == .stackedTabs
    }

    private var canSplit: Bool {
        presentationMode == .singleActiveTab && viewModel.tabs.count >= 2
    }

    private var isSplitPresentationActive: Bool {
        showsSplitPresentationToggle && isSplitMode
    }

    private var splitSecondaryTab: TerminalTab? {
        guard isSplitPresentationActive else { return nil }
        if let splitSecondaryTabID,
           let tab = viewModel.tabs.first(where: { $0.id == splitSecondaryTabID }),
           tab.id != viewModel.activeTabID {
            return tab
        }
        return viewModel.tabs.first(where: { $0.id != viewModel.activeTabID })
    }

    private var headerHasActivity: Bool {
        tabActivitySummary.hasAnyActivity
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .zIndex(2)
            if let errorMessage = viewModel.errorMessage {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(styling.warningColor)
                    Text(errorMessage)
                        .font(AppTypographyTokens.caption)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    CrispyVibesIconButton(systemName: "xmark.circle.fill", size: 12, padding: 4, color: styling.secondaryTextColor) {
                        viewModel.clearError()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(styling.warningColor.opacity(0.18))
            }
            Divider()

            terminalCanvas
                .clipped()
                .zIndex(1)
        }
        .background(styling.panelBackgroundColor)
        .onReceive(NotificationCenter.default.publisher(for: .copyInTerminal)) { _ in
            viewModel.copyActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteInTerminal)) { _ in
            viewModel.pasteActiveTab()
        }
        .onAppear {
            refreshCachedStyling(for: appThemePalette)
            viewModel.refreshAvailablePresets()
        }
        .onChange(of: appThemePalette) { _, newPalette in
            refreshCachedStyling(for: newPalette)
        }
        .onChange(of: viewModel.tabs.map(\.id)) { _, tabIDs in
            if let expandedTabID, !tabIDs.contains(expandedTabID) {
                self.expandedTabID = nil
            }
            if let splitSecondaryTabID, !tabIDs.contains(splitSecondaryTabID) {
                self.splitSecondaryTabID = nil
            }
            if tabIDs.count < 2 {
                isSplitMode = false
            }
        }
        .overlay {
            expandedSessionOverlay
        }
    }

    @ViewBuilder
    private var terminalCanvas: some View {
        if viewModel.tabs.isEmpty {
            ContentUnavailableView(
                AppStrings.Terminal.noSession,
                systemImage: "terminal",
                description: Text(AppStrings.Terminal.noSessionDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch presentationMode {
            case .singleActiveTab:
                if isSplitPresentationActive, let activeTab = viewModel.activeTab, let secondaryTab = splitSecondaryTab {
                    splitTerminalCanvas(primary: activeTab, secondary: secondaryTab)
                } else if let activeTab = viewModel.activeTab {
                    if expandedTabID == activeTab.id {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TerminalSessionView(
                            tab: activeTab,
                            viewModel: viewModel,
                            isActive: true,
                            sessionAccessibilityIdentifier: "terminal.session",
                            sessionHostAccessibilityIdentifier: "terminal.focused.host",
                            inlineTriggerSearchRoots: inlineTriggerSearchRoots(for: activeTab),
                            inlineTriggerShortcuts: activeShortcuts,
                            onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                            onSessionSelected: { tabID in
                                selectAndFocusTab(tabID)
                            },
                            onSessionDoubleClicked: { tabID in
                                handleSessionDoubleClick(tabID)
                            },
                            onSplitTerminalRequested: onSplitTerminalRequested,
                            onTemporaryTerminalRequested: onTemporaryTerminalRequested,
                            onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
                            onLinkTargetActivated: onLinkTargetActivated,
                            onFileSystemTargetActivated: onFileSystemTargetActivated
                        )
                    }
                } else {
                    ContentUnavailableView(
                        AppStrings.Terminal.noSession,
                        systemImage: "terminal",
                        description: Text(AppStrings.Terminal.noSessionDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .stackedTabs:
                stackedTerminalSessions
            }
        }
    }

    private var stackedTerminalSessions: some View {
        GeometryReader { proxy in
            let tabCount = max(viewModel.tabs.count, 1)
            let dividerCount = max(tabCount - 1, 0)
            let availableHeight = max(proxy.size.height - CGFloat(dividerCount), 1)
            let paneHeight = availableHeight / CGFloat(tabCount)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.tabs.enumerated()), id: \.element.id) { index, tab in
                    Group {
                        if expandedTabID == tab.id {
                            Color.clear
                        } else {
                            TerminalSessionView(
                                tab: tab,
                                viewModel: viewModel,
                                isActive: tab.id == viewModel.activeTabID,
                                sessionAccessibilityIdentifier: "terminal.stacked.session",
                                sessionHostAccessibilityIdentifier: "terminal.stacked.host",
                                inlineTriggerSearchRoots: inlineTriggerSearchRoots(for: tab),
                                inlineTriggerShortcuts: activeShortcuts,
                                onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                                onSessionSelected: { tabID in
                                    selectAndFocusTab(tabID)
                                },
                                onSessionDoubleClicked: { tabID in
                                    handleSessionDoubleClick(tabID)
                                },
                                onSplitTerminalRequested: onSplitTerminalRequested,
                                onTemporaryTerminalRequested: onTemporaryTerminalRequested,
                                onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
                                onLinkTargetActivated: onLinkTargetActivated,
                                onFileSystemTargetActivated: onFileSystemTargetActivated
                            )
                            .background(tab.id == viewModel.activeTabID ? styling.stackedActiveSessionBackground : Color.clear)
                        }
                    }
                    .frame(height: paneHeight)

                    if index < viewModel.tabs.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier("terminal.stacked.container")
    }

    private func splitTerminalCanvas(primary: TerminalTab, secondary: TerminalTab) -> some View {
        HStack(spacing: 1) {
            TerminalSessionView(
                tab: primary,
                viewModel: viewModel,
                isActive: true,
                sessionAccessibilityIdentifier: "terminal.split.primary",
                sessionHostAccessibilityIdentifier: "terminal.split.primary.host",
                inlineTriggerSearchRoots: inlineTriggerSearchRoots(for: primary),
                inlineTriggerShortcuts: activeShortcuts,
                onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                onSessionSelected: { tabID in selectAndFocusTab(tabID) },
                onSessionDoubleClicked: { tabID in handleSessionDoubleClick(tabID) },
                onSplitTerminalRequested: onSplitTerminalRequested,
                onTemporaryTerminalRequested: onTemporaryTerminalRequested,
                onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            TerminalSessionView(
                tab: secondary,
                viewModel: viewModel,
                isActive: false,
                sessionAccessibilityIdentifier: "terminal.split.secondary",
                sessionHostAccessibilityIdentifier: "terminal.split.secondary.host",
                inlineTriggerSearchRoots: inlineTriggerSearchRoots(for: secondary),
                inlineTriggerShortcuts: activeShortcuts,
                onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                onSessionSelected: { tabID in selectAndFocusTab(tabID) },
                onSessionDoubleClicked: { tabID in handleSessionDoubleClick(tabID) },
                onSplitTerminalRequested: onSplitTerminalRequested,
                onTemporaryTerminalRequested: onTemporaryTerminalRequested,
                onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("terminal.split.container")
    }

    private func selectAndFocusTab(_ tabID: UUID) {
        onTerminalInteraction?()
        guard let tab = viewModel.tabs.first(where: { $0.id == tabID }) else { return }
        if viewModel.activeTabID != tabID {
            viewModel.selectTab(tab)
            onActiveTabChanged?(tabID)
        }
        viewModel.focusActiveTerminal()
    }

    private var activeTerminalHeaderActions: some View {
        HStack(spacing: 6) {
            if let activeTab,
               let onSplitTerminalRequested {
                terminalHeaderActionButton(
                    systemName: "square.split.2x1",
                    title: AppStrings.Terminal.splitTerminal
                ) {
                    onTerminalInteraction?()
                    onSplitTerminalRequested(activeTab)
                }
            }

            if let activeTab,
               let onTemporaryTerminalRequested {
                terminalHeaderActionButton(
                    systemName: "scope",
                    title: AppStrings.Terminal.newTemporaryTerminal
                ) {
                    onTerminalInteraction?()
                    onTemporaryTerminalRequested(activeTab)
                }
            }
        }
    }

    private var commandsMenu: some View {
        TerminalCommandsMenu(
            textColor: styling.secondaryTextColor,
            shortcuts: activeShortcuts,
            agentPresets: viewModel.availablePresets,
            showsAgentCLIMenu: true,
            onRunShortcut: runShortcut(_:),
            onManageShortcutsRequested: onManageShortcutsRequested,
            onSendSignal: sendSignalToActiveSession(_:),
            onLaunchAgent: launchAgentPreset(_:mode:)
        )
    }

    private var activeShortcuts: [TerminalShortcutDefinition] {
        shortcutProvider?.mergedShortcuts ?? viewModel.shortcutCommands
    }

    private func inlineTriggerSearchRoots(for tab: TerminalTab) -> [URL] {
        var roots: [URL] = [defaultDirectory, tab.workingDirectory]
        if let session = viewModel.session(for: tab.id) {
            roots.append(session.currentWorkingDirectory)
        }

        var seen = Set<String>()
        return roots.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private func sendSignalToActiveSession(_ text: String) {
        guard let activeTabID = viewModel.activeTabID,
              let session = viewModel.session(for: activeTabID) else { return }
        session.sendRawText(text)
    }

    private func terminalHeaderActionButton(
        systemName: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        CrispyVibesIconButton(
            systemName: systemName,
            variant: headerLayout == .embedded ? .card : .compact,
            color: styling.secondaryTextColor,
            accessibilityLabel: title,
            action: action
        )
            .help(title)
    }

    private var tabBarContent: some View {
        HStack(spacing: 8) {
            if showsHeaderSummaryActivityIndicator && headerHasActivity {
                ActivityIndicator()
                    .transition(.opacity)
                    .padding(.leading, 2)
            }

            tabStrip
                .frame(maxWidth: .infinity, alignment: .leading)

            terminalHeaderControls
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var tabBar: some View {
        if headerLayout == .embedded {
            let embeddedBar = CrispyVibesHeaderChrome(style: .card, background: styling.headerBackgroundColor) {
                tabBarContent
            }

            if let embeddedHeaderCornerRadii {
                embeddedBar
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: embeddedHeaderCornerRadii,
                            style: .continuous
                        )
                    )
            } else {
                embeddedBar
                }
        } else {
            CrispyVibesHeaderChrome(style: .compact) {
                tabBarContent
            }
            .background(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                    .fill(styling.headerBackgroundColor)
            )
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.tabs) { tab in
                    let isSelected = tab.id == viewModel.activeTabID
                    TerminalTabBarItem(
                        tab: tab,
                        activityState: viewModel.tabActivityStateOrInactive(for: tab.id),
                        isSelected: isSelected,
                        style: styling.tabChipStyle,
                        showsBorder: false,
                        onSelect: {
                            selectAndFocusTab(tab.id)
                        },
                        onClose: {
                            onTerminalInteraction?()
                            viewModel.closeTab(tab)
                            if let activeTabID = viewModel.activeTabID {
                                onActiveTabChanged?(activeTabID)
                            }
                        },
                        onRename: { newName in
                            viewModel.renameTab(tab.id, to: newName)
                        },
                        dragItemProvider: activeTabDragItemProvider(for: tab, isSelected: isSelected)
                    )
                }

                CrispyVibesIconButton(
                    systemName: "plus.circle",
                    variant: headerLayout == .embedded ? .card : .compact,
                    color: styling.secondaryTextColor,
                    accessibilityLabel: "New Terminal Tab"
                ) {
                    onTerminalInteraction?()
                    let createdTabID = viewModel.createUserTab(defaultDirectory: defaultDirectory)
                    if let activeTabID = createdTabID {
                        onActiveTabChanged?(activeTabID)
                    }
                    DispatchQueue.main.async {
                        viewModel.focusActiveTerminal()
                    }
                }
                .padding(.leading, 2)
                .accessibilityIdentifier("terminal.tab.add")
            }
        }
    }

    private var terminalHeaderControls: some View {
        HStack(spacing: 8) {
            if showsSplitPresentationToggle && canSplit { splitToggleButton }
            if showsInlineTerminalActions {
                activeTerminalHeaderActions
            }
            commandsMenu
            if let additionalHeaderControls {
                additionalHeaderControls
            }
        }
    }

    private func activeTabDragItemProvider(for tab: TerminalTab, isSelected: Bool) -> (() -> NSItemProvider)? {
        guard isSelected,
              let dragContentViewerTabProvider,
              let contentViewerTab = dragContentViewerTabProvider(tab) else {
            return nil
        }
        return {
            ContentViewerTabDragSupport.makeItemProvider(for: contentViewerTab)
        }
    }

    private var splitToggleButton: some View {
        terminalHeaderActionButton(
            systemName: isSplitMode ? "rectangle" : "rectangle.split.1x2",
            title: isSplitMode ? "Single Tab" : "Split View"
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSplitMode.toggle()
                if !isSplitMode { splitSecondaryTabID = nil }
            }
        }
    }

    private func launchAgentPreset(_ preset: TerminalPresetDefinition, mode: TerminalPresetLaunchMode) {
        onTerminalInteraction?()
        viewModel.launchPreset(
            preset,
            mode: mode,
            directoryURL: viewModel.activeTab?.workingDirectory ?? defaultDirectory
        )
        if let activeTabID = viewModel.activeTabID {
            onActiveTabChanged?(activeTabID)
        }
    }

    private func runShortcut(_ shortcut: TerminalShortcutDefinition) {
        executeTerminalShortcut(
            shortcut,
            viewModel: viewModel,
            defaultDirectory: defaultDirectory,
            onTemporaryShortcutRequested: onTemporaryShortcutRequested,
            onTerminalInteraction: onTerminalInteraction,
            onActiveTabChanged: onActiveTabChanged
        )
    }

    private func toggleExpandedTab(_ tabID: UUID) {
        if expandedTabID == tabID {
            expandedTabID = nil
            return
        }
        expandedTabID = tabID
        selectAndFocusTab(tabID)
    }

    private func handleSessionDoubleClick(_ tabID: UUID) {
        if let onSessionDoubleClicked {
            onSessionDoubleClicked(tabID)
            return
        }
        toggleExpandedTab(tabID)
    }

    @ViewBuilder
    private var expandedSessionOverlay: some View {
        if let expandedTab {
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture {
                        expandedTabID = nil
                    }

                VStack(spacing: 0) {
                    TerminalSessionView(
                        tab: expandedTab,
                        viewModel: viewModel,
                        isActive: expandedTab.id == viewModel.activeTabID,
                        sessionAccessibilityIdentifier: "terminal.expanded.session",
                        sessionHostAccessibilityIdentifier: "terminal.expanded.host",
                        inlineTriggerSearchRoots: inlineTriggerSearchRoots(for: expandedTab),
                        inlineTriggerShortcuts: activeShortcuts,
                        onManageInlineTriggerShortcutsRequested: onManageShortcutsRequested,
                        onSessionSelected: { tabID in
                            selectAndFocusTab(tabID)
                        },
                        onSessionDoubleClicked: { tabID in
                            toggleExpandedTab(tabID)
                        },
                        onSplitTerminalRequested: onSplitTerminalRequested,
                        onTemporaryTerminalRequested: onTemporaryTerminalRequested,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                }
                .frame(maxWidth: 1024, maxHeight: 720)
                .background(styling.panelBackgroundColor)
                .overlay {
                    if !isRailPresentation {
                        Rectangle()
                            .stroke(styling.activeBorderColor, lineWidth: 1)
                    }
                }
                .shadow(color: Color.black.opacity(0.26), radius: 22, x: 0, y: 14)
                .padding(24)
                .accessibilityIdentifier("terminal.expanded.overlay")
            }
            .transition(.opacity)
        }
    }

    private func refreshCachedStyling(for palette: AppThemePalette) {
        cachedStyling = TerminalStyling(palette: palette)
    }

    private struct TerminalStyling {
        let tabChipStyle: TerminalTabChipStyle
        let stackedActiveSessionBackground: Color
        let panelBackgroundColor: Color
        let warningColor: Color
        let headerBackgroundColor: Color
        let secondaryTextColor: Color

        var activeBorderColor: Color { tabChipStyle.activeBorderColor }

        init(palette: AppThemePalette) {
            let baseActiveBackground = palette.selectionBackgroundColor.opacity(0.18)
            tabChipStyle = TerminalTabChipStyle(palette: palette)
            stackedActiveSessionBackground = baseActiveBackground.opacity(0.20)
            panelBackgroundColor = palette.canvasBackgroundColor
            warningColor = palette.warningColor
            headerBackgroundColor = palette.canvasSecondaryBackgroundColor
            secondaryTextColor = palette.secondaryTextColor
        }
    }
}

@MainActor
func executeTerminalShortcut(
    _ shortcut: TerminalShortcutDefinition,
    viewModel: TerminalViewModel,
    defaultDirectory: URL,
    onTemporaryShortcutRequested: ((TerminalShortcutDefinition, URL) -> Void)? = nil,
    onTerminalInteraction: (() -> Void)? = nil,
    onActiveTabChanged: ((UUID) -> Void)? = nil
) {
    onTerminalInteraction?()
    let workingDirectory = viewModel.activeTab?.workingDirectory ?? defaultDirectory
    switch shortcut.launchBehavior {
    case .currentTerminal, .newPermanentTerminal:
        viewModel.runShortcut(
            shortcut,
            defaultDirectory: workingDirectory
        )
        if let activeTabID = viewModel.activeTabID {
            onActiveTabChanged?(activeTabID)
        }
    case .newTemporaryTerminal:
        if let onTemporaryShortcutRequested {
            onTemporaryShortcutRequested(shortcut, workingDirectory)
        } else {
            viewModel.runShortcut(
                shortcut,
                defaultDirectory: workingDirectory
            )
            if let activeTabID = viewModel.activeTabID {
                onActiveTabChanged?(activeTabID)
            }
        }
    }
}
