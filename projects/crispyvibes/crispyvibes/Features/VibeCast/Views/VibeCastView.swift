import Combine
import SwiftUI

struct VibeCastView: View {
    struct TerminalSource: Identifiable {
        let id: String
        let projectTitle: String
        let projectRootURL: URL
        let accentColor: Color
        let viewModel: TerminalViewModel
    }

    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.boardInlinePickerOverlayController) private var boardInlinePickerOverlayController
    @Environment(\.composeHistoryStore) private var composeHistoryStore
    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    private var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @ObservedObject var store: VibeCastStore
    var terminalSources: [TerminalSource]
    var isActive: Bool = false
    var onManageShortcutsRequested: (() -> Void)? = nil
    @State private var isTargetPopoverPresented = false
    @State private var pendingSelectionLocation: Int?
    @State private var composeFocusRequest = false
    @State private var observedTabsBySourceID: [String: [TerminalTab]] = [:]
    @State private var terminalTabObservers: [String: AnyCancellable] = [:]
    @StateObject private var inlineTrigger = TerminalInlineTriggerController()
    @State private var historyNavigator: ComposeHistoryNavigator?

    private var allTabs: [(tab: TerminalTab, viewModel: TerminalViewModel, projectTitle: String, projectRootURL: URL, accentColor: Color)] {
        terminalSources.flatMap { source in
            tabs(for: source).map {
                (
                    tab: $0,
                    viewModel: source.viewModel,
                    projectTitle: source.projectTitle,
                    projectRootURL: source.projectRootURL,
                    accentColor: source.accentColor
                )
            }
        }
    }

    private var availableTabIDs: [UUID] {
        allTabs.map(\.tab.id)
    }

    private var resolvedTarget: (tab: TerminalTab, viewModel: TerminalViewModel, projectTitle: String, projectRootURL: URL, accentColor: Color)? {
        if let targetID = store.targetTabID,
           let match = allTabs.first(where: { $0.tab.id == targetID }) {
            return match
        }
        return allTabs.first
    }

    private var targetTabName: String {
        guard let target = resolvedTarget else { return "No Terminal" }
        return "\(target.projectTitle) / \(target.tab.title)"
    }

    var body: some View {
        VStack(spacing: 0) {
            messageHistory
            composeArea
        }
        .background(palette.canvasBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
        .onAppear(perform: startObservingTerminalTabs)
        .onAppear {
            configureOnAppear()
        }
        .onChange(of: terminalSources.map(\.id)) { _, _ in
            startObservingTerminalTabs()
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            requestComposeFocus()
        }
        .onChange(of: store.composeText) { _, _ in
            handleComposeTextChange()
        }
        .onChange(of: configuredInlineTrigger) { _, _ in
            syncInlineTriggerConfiguration()
            inlineTrigger.reconcileBufferText(store.composeText)
            syncBoardInlinePickerOverlay()
        }
        .onChange(of: store.targetTabID) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onChange(of: targetTabName) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onChange(of: inlinePathSearchRootPaths) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onChange(of: inlineShortcutSignature) { _, _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .focusProjectByNumber)) { notification in
            guard let index = notification.userInfo?[AppCommandUserInfoKey.index] as? Int,
                  index > 0, index <= terminalSources.count else { return }
            let source = terminalSources[index - 1]
            let sourceTabs = tabs(for: source)
            guard !sourceTabs.isEmpty else { return }

            let currentTargetInSameProject = store.targetTabID.flatMap { tid in
                sourceTabs.first(where: { $0.id == tid })
            } != nil
            let result = ProjectTerminalCycler.resolve(
                isAlreadyFocused: currentTargetInSameProject,
                tabIDs: sourceTabs.map(\.id),
                activeTabID: store.targetTabID
            )
            switch result {
            case .focusProject:
                store.targetTabID = sourceTabs.first?.id
            case let .cycleTerminal(nextTabID):
                store.targetTabID = nextTabID
            case .noOp:
                break
            }
        }
    }

    // MARK: - Message History

    private var messageHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.groupedMessages) { group in
                        messageGroupView(group)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: store.messages.count) { _, _ in
                if let lastID = store.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageGroupView(_ group: VibeCastMessageGroup) -> some View {
        let color = allTabs.first(where: { $0.tab.id == group.targetTabID })?.accentColor ?? palette.accentColor
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("→ \(group.targetTabName)")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .padding(.bottom, 2)

            ForEach(group.messages) { message in
                HStack(alignment: .top, spacing: 8) {
                    Text(message.text)
                        .font(AppTypographyTokens.scaledSystem(12, design: .monospaced))
                        .foregroundStyle(palette.primaryTextColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(message.timestamp, style: .time)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor.opacity(0.5))
                }
                .padding(8)
                .background(palette.canvasSecondaryBackgroundColor.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous))
                .id(message.id)
            }
        }
    }

    // MARK: - Compose Area

    private var composeArea: some View {
        VStack(spacing: 0) {
            // Target row
            HStack(spacing: 6) {
                if let color = resolvedTarget?.accentColor {
                    Circle().fill(color).frame(width: 7, height: 7)
                }

                HStack(spacing: 4) {
                    Text(targetTabName)
                    CrispyVibesIconButton(systemName: "chevron.down", size: 10, padding: 4, color: palette.secondaryTextColor, accessibilityLabel: "Select Target Terminal") {
                        isTargetPopoverPresented.toggle()
                    }
                }
                .popover(isPresented: $isTargetPopoverPresented, arrowEdge: .top) {
                    targetSelectionPopover
                }

                Spacer()
            }
            .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
            .padding(.vertical, ComposeLayoutTokens.contentVerticalPadding)

            composeInputView
            .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !store.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !allTabs.isEmpty
    }

    private var parsedInlineTrigger: SpotlightComposeInlineTrigger? {
        SpotlightComposeInlineTrigger.parse(
            store.composeText,
            triggerToken: AppPreferences.normalizedTerminalComposeInlineTrigger(configuredInlineTrigger)
        )
    }

    private var inlinePathSearchRoots: [URL] {
        guard let target = resolvedTarget else { return [] }

        var roots: [URL] = [target.tab.workingDirectory, target.projectRootURL]
        if let session = target.viewModel.session(for: target.tab.id) {
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

    private var inlinePathSearchRootPaths: [String] {
        inlinePathSearchRoots.map(\.path)
    }

    private var inlineShortcutDefinitions: [TerminalShortcutDefinition] {
        resolvedTarget?.viewModel.shortcutCommands ?? []
    }

    private var inlineShortcutSignature: [String] {
        inlineShortcutDefinitions.map { "\($0.id.uuidString):\($0.name):\($0.command)" }
    }

    private func sendMessage() {
        let text = store.composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let target = resolvedTarget else { return }
        historyNavigator?.append(text)
        let name = targetTabName
        let message = store.send(text: text, targetTabID: target.tab.id, targetTabName: name)
        target.viewModel.session(for: message.targetTabID)?.sendRawTextWithEnter(message.text)
        syncInlineTriggerBuffer()
    }

    private func handleComposeTextChange() {
        if historyNavigator?.isApplyingNavigation == true {
            historyNavigator?.isApplyingNavigation = false
        } else {
            historyNavigator?.resetOnUnrelatedEdit()
        }
        syncInlineTriggerBuffer()
    }

    private func configureOnAppear() {
        if let composeHistoryStore {
            historyNavigator = ComposeHistoryNavigator(store: composeHistoryStore)
        }
        historyNavigator?.attach(to: store.id)
        requestComposeFocus()
        syncInlineTriggerConfiguration()
        inlineTrigger.reconcileBufferText(store.composeText)
        syncBoardInlinePickerOverlay()
    }

    private var historyBackAction: (() -> Void)? {
        guard historyNavigator != nil else { return nil }
        return {
            guard let historyNavigator else { return }
            let nav = historyNavigator.navigateBack(currentText: store.composeText)
            if case let .replace(text) = nav {
                historyNavigator.isApplyingNavigation = true
                store.composeText = text
            }
        }
    }

    private var historyForwardAction: (() -> Void)? {
        guard historyNavigator != nil else { return nil }
        return {
            guard let historyNavigator else { return }
            let nav = historyNavigator.navigateForward(currentText: store.composeText)
            if case let .replace(text) = nav {
                historyNavigator.isApplyingNavigation = true
                store.composeText = text
            }
        }
    }

    private var composeInputView: some View {
        TerminalComposeInputView(
            text: $store.composeText,
            pendingSelectionLocation: $pendingSelectionLocation,
            initialHeight: 108,
            isRephrasing: store.isRephrasing,
            showBroadcast: true,
            requestFocus: composeFocusRequest,
            showsResizeHandle: false,
            showsBackground: false,
            verticalPadding: 0,
            onSend: { sendMessage() },
            onBroadcast: { sendToAll() },
            onRephrase: { store.rephrase() },
            onCycleTargetUp: { cycleTarget(by: -1) },
            onCycleTargetDown: { cycleTarget(by: 1) },
            inlineOverlayActive: inlineTrigger.isPresented,
            onInlineMoveUp: { _ = inlineTrigger.handleCommand(.moveUp) },
            onInlineMoveDown: { _ = inlineTrigger.handleCommand(.moveDown) },
            onInlineMoveRight: { _ = inlineTrigger.handleCommand(.moveRight) },
            onInlineConfirm: { _ = inlineTrigger.handleCommand(.confirm) },
            onInlineDismiss: dismissInlineTrigger,
            onHistoryBack: historyBackAction,
            onHistoryForward: historyForwardAction
        )
    }

    private func sendToAll() {
        let text = store.composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        historyNavigator?.append(text)
        for entry in allTabs {
            let name = "\(entry.projectTitle) / \(entry.tab.title)"
            let message = store.send(text: text, targetTabID: entry.tab.id, targetTabName: name)
            entry.viewModel.session(for: message.targetTabID)?.sendRawTextWithEnter(message.text)
        }
        syncInlineTriggerBuffer()
    }

    private func cycleTarget(by offset: Int) {
        let tabs = allTabs
        guard tabs.count > 1 else { return }
        let currentIndex = store.targetTabID.flatMap { tid in
            tabs.firstIndex(where: { $0.tab.id == tid })
        } ?? 0
        let nextIndex = (currentIndex + offset + tabs.count) % tabs.count
        store.targetTabID = tabs[nextIndex].tab.id
    }

    private func dismissInlineTrigger() {
        _ = inlineTrigger.handleCommand(.dismiss)
        requestComposeFocus()
        syncBoardInlinePickerOverlay()
    }

    private func replaceInlineTrigger(with replacement: String) {
        guard let trigger = parsedInlineTrigger else {
            return
        }
        let newText = trigger.prefixText + replacement
        store.composeText = newText
        pendingSelectionLocation = (newText as NSString).length
    }

    private func syncInlineTriggerConfiguration() {
        let resolvedTarget = resolvedTarget
        inlineTrigger.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: inlinePathSearchRoots,
            shortcuts: inlineShortcutDefinitions,
            terminalTitle: resolvedTarget.map { "\($0.projectTitle) / \($0.tab.title)" } ?? AppStrings.VibeCast.title,
            currentDirectoryProvider: { [weak viewModel = resolvedTarget?.viewModel, tabID = resolvedTarget?.tab.id, fallbackDirectory = resolvedTarget?.tab.workingDirectory] in
                guard let viewModel, let tabID else { return fallbackDirectory }
                return viewModel.session(for: tabID)?.currentWorkingDirectory ?? fallbackDirectory
            },
            insertionHandler: { replacement in
                replaceInlineTrigger(with: replacement)
            },
            focusHandler: requestComposeFocus,
            manageShortcutsHandler: onManageShortcutsRequested
        )
        syncBoardInlinePickerOverlay()
    }

    private func requestComposeFocus() {
        composeFocusRequest = false
        DispatchQueue.main.async {
            composeFocusRequest = true
        }
    }

    private func syncInlineTriggerBuffer() {
        inlineTrigger.syncBufferText(store.composeText)
        syncBoardInlinePickerOverlay()
    }

    private var boardInlinePickerOverlayOwnerID: String {
        "vibecast:\(ObjectIdentifier(store).hashValue)"
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

    private var manageShortcutsAction: (() -> Void)? {
        guard onManageShortcutsRequested != nil else { return nil }
        let inlineTriggerRef = inlineTrigger
        return { [weak inlineTriggerRef] in
            inlineTriggerRef?.runManageShortcutsAction()
        }
    }

    private func syncTargetSelection() {
        guard !availableTabIDs.isEmpty else {
            store.targetTabID = nil
            return
        }

        if let targetTabID = store.targetTabID, availableTabIDs.contains(targetTabID) {
            return
        }

        store.targetTabID = availableTabIDs.first
    }

    private func tabs(for source: TerminalSource) -> [TerminalTab] {
        observedTabsBySourceID[source.id] ?? source.viewModel.tabs
    }

    private var targetSelectionPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(terminalSources) { source in
                    targetSectionView(for: source)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .frame(width: 300)
        .frame(maxHeight: 280)
        .background(palette.canvasBackgroundColor)
    }

    @ViewBuilder
    private func targetSectionView(for source: TerminalSource) -> some View {
        let sourceTabs = tabs(for: source)
        if !sourceTabs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.projectTitle)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)

                ForEach(sourceTabs) { tab in
                    targetRow(for: tab, source: source)
                }
            }
        }
    }

    private func targetRow(for tab: TerminalTab, source: TerminalSource) -> some View {
        let isSelected = store.targetTabID == tab.id

        return Button {
            store.targetTabID = tab.id
            isTargetPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(source.accentColor)
                Text(tab.title)
                    .foregroundStyle(source.accentColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                    .fill(isSelected ? source.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func startObservingTerminalTabs() {
        terminalTabObservers.removeAll()

        for source in terminalSources {
            observedTabsBySourceID[source.id] = source.viewModel.tabs
            terminalTabObservers[source.id] = source.viewModel.tabsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [sourceID = source.id] tabs in
                    observedTabsBySourceID[sourceID] = tabs
                    syncTargetSelection()
                }
        }

        let validSourceIDs = Set(terminalSources.map(\.id))
        observedTabsBySourceID = observedTabsBySourceID.filter { validSourceIDs.contains($0.key) }
        syncTargetSelection()
    }
}
