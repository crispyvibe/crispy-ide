import AppKit
import SwiftUI

/// Shared browser chrome that attaches the live WKWebView through ownership-aware hosts.
struct BrowserContentView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    /// F049-v2: comment store comes from RootView-level env. When non-nil
    /// the browser dock includes the comments toolbar toggle + side panel.
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStore: VibeSpaceCommentStore?
    @ObservedObject var viewModel: BrowserPanelViewModel
    @StateObject private var suggestionsController = BrowserSuggestionsController()
    var presentation: BrowserHostPresentation = .detailed

    var body: some View {
        // F049-v2: bind the store on every body evaluation so it's never
        // nil when a page-load triggers refreshCommentsForCurrentPage().
        // The element picker works because it doesn't depend on any
        // external store — it's self-contained JS. Comments need the store
        // to know which threads to decorate.
        let _ = { viewModel.commentsStore = commentStore }()

        return BrowserContentWithCommentsPanel(
            panel: viewModel.commentsPanel,
            viewModel: viewModel,
            store: commentStore,
            browserContent: { contentBody }
        )
    }

    private var contentBody: some View {
        VStack(spacing: 0) {
            addressBar
            if viewModel.isLoading, viewModel.estimatedProgress > 0, viewModel.estimatedProgress < 1 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(palette.accentColor)
                        .frame(width: geo.size.width * viewModel.estimatedProgress)
                }
                .frame(height: 2)
                .animation(.linear(duration: 0.15), value: viewModel.estimatedProgress)
            }
            if suggestionsController.hasSuggestions {
                suggestionsDropdown
            }
            if viewModel.isFindVisible {
                findBar
            }
            Divider()
            ZStack {
                BrowserSessionHostView(
                    viewModel: viewModel,
                    presentation: presentation
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = viewModel.navigationError {
                    browserErrorView(error: error)
                }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 4) {
            CrispyVibesIconButton(systemName: "chevron.left", size: 12, padding: 5,
                            color: viewModel.canGoBack ? palette.secondaryTextColor : palette.secondaryTextColor.opacity(0.3),
                            accessibilityLabel: AppStrings.Browser.back) { viewModel.goBack() }
                .accessibilityIdentifier("browser.back")

            CrispyVibesIconButton(systemName: "chevron.right", size: 12, padding: 5,
                            color: viewModel.canGoForward ? palette.secondaryTextColor : palette.secondaryTextColor.opacity(0.3),
                            accessibilityLabel: AppStrings.Browser.forward) { viewModel.goForward() }
                .accessibilityIdentifier("browser.forward")

            if let data = viewModel.faviconData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: uiScale.iconSize(14), height: uiScale.iconSize(14))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else if viewModel.hasOnlySecureContent {
                Image(systemName: "lock.fill").font(AppTypographyTokens.scaledSystem(10))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "globe").font(AppTypographyTokens.scaledSystem(12))
                    .foregroundStyle(palette.secondaryTextColor)
            }

            BrowserAddressField(
                text: $viewModel.addressBarText,
                onSubmit: { navigateToAddressBarText() },
                onArrowDown: { suggestionsController.moveSelectionDown() },
                onArrowUp: { suggestionsController.moveSelectionUp() },
                onEscape: { suggestionsController.dismissSuggestions() },
                autoFocus: viewModel.currentURL == nil
            )
            .font(AppTypographyTokens.scaledSystem(12))
            .onChange(of: viewModel.addressBarText) { _, newValue in
                suggestionsController.handleAddressBarTextChange(
                    newValue,
                    currentURL: viewModel.currentURL,
                    historyStore: viewModel.historyStore
                )
            }
            .onChange(of: viewModel.currentURL) { _, _ in
                suggestionsController.handleCurrentURLChange()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(palette.canvasBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(AppStrings.Browser.addressField)
            .accessibilityIdentifier("browser.address-field")

            if viewModel.isLoading {
                CrispyVibesIconButton(systemName: "xmark", size: 12, padding: 5,
                                color: palette.secondaryTextColor,
                                accessibilityLabel: AppStrings.Browser.stopLoading) { viewModel.stopLoading() }
                    .accessibilityIdentifier("browser.stop")
            } else {
                CrispyVibesIconButton(systemName: "arrow.clockwise", size: 12, padding: 5,
                                color: palette.secondaryTextColor,
                                accessibilityLabel: AppStrings.Browser.reload) { viewModel.reload() }
                    .accessibilityIdentifier("browser.reload")
            }

            CrispyVibesIconButton(systemName: "square.dashed", size: 12, padding: 5,
                            color: viewModel.isElementPickerActive ? palette.accentColor : palette.secondaryTextColor,
                            accessibilityLabel: "Select Element") { viewModel.toggleElementPicker() }
                .help(viewModel.isElementPickerActive ? "Deactivate Picker" : "Select Element")
                .accessibilityIdentifier("browser.element-picker")

            // F049-v2: comments toggle for browser surfaces. Appears only
            // when the comment store is reachable (the env value is set).
            if commentStore != nil {
                CrispyVibesIconButton(
                    systemName: viewModel.commentsPanel.isOpen ? "quote.bubble.fill" : "quote.bubble",
                    size: 12,
                    padding: 5,
                    color: viewModel.commentsPanel.isOpen ? palette.accentColor : palette.secondaryTextColor,
                    accessibilityLabel: AppStrings.Comments.toolbarToggleHelp
                ) { viewModel.commentsPanel.togglePanel() }
                    .help(viewModel.commentsPanel.isOpen
                          ? AppStrings.Comments.closePanel
                          : AppStrings.Comments.toolbarToggleHelp)
                    .accessibilityIdentifier("browser.comments-toggle")
            }

            browserOverflowMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.canvasSecondaryBackgroundColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.chrome")
    }

    private var browserOverflowMenu: some View {
        Menu {
            Button { viewModel.goBack() } label: { Label(AppStrings.Browser.back, systemImage: "chevron.left") }
                .disabled(!viewModel.canGoBack)
            Button { viewModel.goForward() } label: { Label(AppStrings.Browser.forward, systemImage: "chevron.right") }
                .disabled(!viewModel.canGoForward)
            Divider()
            Button { viewModel.zoomIn() } label: { Label(AppStrings.Browser.zoomIn, systemImage: "plus.magnifyingglass") }
            Button { viewModel.resetZoom() } label: { Label(AppStrings.Browser.resetZoom, systemImage: "arrow.counterclockwise") }
            Button { viewModel.zoomOut() } label: { Label(AppStrings.Browser.zoomOut, systemImage: "minus.magnifyingglass") }
            Divider()
            Button { viewModel.startFind() } label: { Label(AppStrings.Browser.findInPage, systemImage: "magnifyingglass") }
            Button { viewModel.openInSystemBrowser() } label: { Label(AppStrings.Browser.openInDefaultBrowser, systemImage: "safari") }
            Divider()
            Button { viewModel.toggleElementPicker() } label: {
                Label(viewModel.isElementPickerActive ? "Deactivate Picker" : "Select Element", systemImage: "cursorarrow.click.2")
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(AppTypographyTokens.scaledSystem(12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: uiScale.iconSize(20))
        .foregroundStyle(palette.secondaryTextColor)
        .accessibilityIdentifier("browser.overflow-menu")
    }

    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestionsController.suggestionItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    suggestionsController.selectSuggestion(at: index)
                    navigate(to: item.navigationValue)
                } label: {
                    HStack {
                        suggestionRowContent(for: item)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .background(suggestionRowBackground(isSelected: suggestionsController.isSelectedSuggestion(at: index)))
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(palette.borderColorValue.opacity(0.5), lineWidth: 0.5))
        .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            TextField(AppStrings.Browser.findPlaceholder, text: Binding(
                get: { viewModel.findQuery },
                set: { viewModel.updateFindQuery($0) }
            ))
            .textFieldStyle(.plain).font(AppTypographyTokens.scaledSystem(12))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(palette.canvasBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onSubmit { viewModel.findNext() }

            if viewModel.findMatchCount > 0 {
                Text("\(viewModel.findCurrentMatch)/\(viewModel.findMatchCount)")
                    .font(AppTypographyTokens.scaledSystem(10))
                    .foregroundStyle(palette.secondaryTextColor)
            }

            Button { viewModel.findPrevious() } label: {
                Image(systemName: "chevron.up").font(AppTypographyTokens.scaledSystem(10))
            }.buttonStyle(.plain).foregroundStyle(palette.secondaryTextColor)

            Button { viewModel.findNext() } label: {
                Image(systemName: "chevron.down").font(AppTypographyTokens.scaledSystem(10))
            }.buttonStyle(.plain).foregroundStyle(palette.secondaryTextColor)

            Button { viewModel.dismissFind() } label: {
                Image(systemName: "xmark").font(AppTypographyTokens.scaledSystem(10))
            }.buttonStyle(.plain).foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private func browserErrorView(error: NSError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppTypographyTokens.scaledSystem(32))
                .foregroundStyle(palette.secondaryTextColor)
            Text(AppStrings.Browser.failedToLoad)
                .font(AppTypographyTokens.scaledSystem(14, weight: .medium))
            Text(error.localizedDescription)
                .font(AppTypographyTokens.scaledSystem(12))
                .foregroundStyle(palette.secondaryTextColor)
                .multilineTextAlignment(.center)
            Button(AppStrings.Common.retry) { viewModel.reload() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvasBackgroundColor)
    }

    private func navigateToAddressBarText() {
        if let selectedSuggestion = suggestionsController.selectedSuggestion {
            navigate(to: selectedSuggestion.navigationValue)
            return
        }
        suggestionsController.commitNavigation {
            viewModel.navigateSmart(viewModel.addressBarText)
        }
    }

    private func navigate(to value: String) {
        viewModel.addressBarText = value
        suggestionsController.commitNavigation {
            viewModel.navigateSmart(value)
        }
    }

    @ViewBuilder
    private func suggestionRowContent(for item: BrowserSuggestionItem) -> some View {
        Image(systemName: item.iconName).font(AppTypographyTokens.scaledSystem(10))
            .foregroundStyle(palette.secondaryTextColor)

        VStack(alignment: .leading, spacing: 1) {
            Text(item.titleText)
                .font(AppTypographyTokens.scaledSystem(11))
                .lineLimit(1)
                .foregroundStyle(palette.primaryTextColor)

            if let subtitle = item.subtitleText {
                Text(subtitle)
                    .font(AppTypographyTokens.scaledSystem(10))
                    .lineLimit(1)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
    }

    private func suggestionRowBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.accentColor.opacity(0.16))
            } else {
                Color.clear
            }
        }
    }
}

private struct BrowserSuggestionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case history(BrowserHistoryStore.Entry)
        case remote(String)
    }

    let id: String
    let kind: Kind

    var navigationValue: String {
        switch kind {
        case let .history(entry):
            entry.url
        case let .remote(value):
            value
        }
    }

    var iconName: String {
        switch kind {
        case .history:
            "clock"
        case .remote:
            "magnifyingglass"
        }
    }

    var titleText: String {
        switch kind {
        case let .history(entry):
            entry.title ?? entry.url
        case let .remote(value):
            "Search for \"\(value)\""
        }
    }

    var subtitleText: String? {
        switch kind {
        case let .history(entry):
            entry.title == nil ? nil : entry.url
        case .remote:
            nil
        }
    }
}

@MainActor
private final class BrowserSuggestionsController: ObservableObject {
    private enum Constants {
        static let historySuggestionLimit = 5
        static let remoteSuggestionLimit = 3
        static let remoteSuggestionDebounceNanoseconds: UInt64 = 250_000_000
        static let remoteSuggestionTimeout: TimeInterval = 1.0
        static let remoteSuggestionURL = "https://suggestqueries.google.com/complete/search"
        static let remoteSuggestionClient = "firefox"
    }

    @Published private(set) var historySuggestions: [BrowserHistoryStore.Entry] = []
    @Published private(set) var remoteSuggestions: [String] = []
    @Published private(set) var selectedSuggestionIndex: Int?

    private var suggestionDebounceTask: Task<Void, Never>?
    private var suppressSuggestions = false

    deinit {
        suggestionDebounceTask?.cancel()
    }

    var hasSuggestions: Bool {
        !historySuggestions.isEmpty || !remoteSuggestions.isEmpty
    }

    var suggestionItems: [BrowserSuggestionItem] {
        let historyItems = historySuggestions.map {
            BrowserSuggestionItem(id: "history.\($0.id.uuidString)", kind: .history($0))
        }
        let remoteItems = remoteSuggestions.map {
            BrowserSuggestionItem(id: "remote.\($0)", kind: .remote($0))
        }
        return historyItems + remoteItems
    }

    var selectedSuggestion: BrowserSuggestionItem? {
        guard let selectedSuggestionIndex,
              suggestionItems.indices.contains(selectedSuggestionIndex) else { return nil }
        return suggestionItems[selectedSuggestionIndex]
    }

    func handleAddressBarTextChange(
        _ query: String,
        currentURL: URL?,
        historyStore: BrowserHistoryStore?
    ) {
        if query != currentURL?.absoluteString {
            suppressSuggestions = false
        }
        guard !suppressSuggestions else { return }
        refreshSuggestions(for: query, historyStore: historyStore)
    }

    func handleCurrentURLChange() {
        suppressSuggestions = true
        dismissSuggestions()
    }

    func commitNavigation(_ navigate: () -> Void) {
        suppressSuggestions = true
        dismissSuggestions()
        navigate()
    }

    func moveSelectionDown() {
        guard hasSuggestions else { return }
        let nextIndex = min((selectedSuggestionIndex ?? -1) + 1, suggestionItems.count - 1)
        applySelection(at: nextIndex)
    }

    func moveSelectionUp() {
        guard hasSuggestions else { return }
        let nextIndex = max((selectedSuggestionIndex ?? suggestionItems.count) - 1, 0)
        applySelection(at: nextIndex)
    }

    func selectSuggestion(at index: Int) {
        applySelection(at: index)
    }

    func isSelectedSuggestion(at index: Int) -> Bool {
        selectedSuggestionIndex == index
    }

    private func refreshSuggestions(
        for query: String,
        historyStore: BrowserHistoryStore?
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissSuggestions()
            return
        }

        historySuggestions = (historyStore)
            .map { $0.suggestions(for: trimmed, limit: Constants.historySuggestionLimit) } ?? []
        if historySuggestions.isEmpty {
            selectedSuggestionIndex = nil
        } else if selectedSuggestionIndex == nil || !(selectedSuggestionIndex! < suggestionItems.count) {
            selectedSuggestionIndex = 0
        }

        suggestionDebounceTask?.cancel()
        suggestionDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Constants.remoteSuggestionDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await fetchRemoteSuggestions(for: trimmed)
        }
    }

    private func fetchRemoteSuggestions(for query: String) async {
        var components = URLComponents(string: Constants.remoteSuggestionURL)
        components?.queryItems = [
            URLQueryItem(name: "client", value: Constants.remoteSuggestionClient),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components?.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = Constants.remoteSuggestionTimeout
        req.setValue(BrowserPanelViewModel.safariUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 2, let list = root[1] as? [String] else {
            await MainActor.run { remoteSuggestions = [] }
            return
        }
        await MainActor.run {
            remoteSuggestions = Array(list.prefix(Constants.remoteSuggestionLimit))
            if self.selectedSuggestionIndex == nil, !self.suggestionItems.isEmpty {
                self.selectedSuggestionIndex = 0
            } else if let index = self.selectedSuggestionIndex, index >= self.suggestionItems.count {
                self.selectedSuggestionIndex = self.suggestionItems.isEmpty ? nil : self.suggestionItems.count - 1
            }
        }
    }

    func dismissSuggestions() {
        historySuggestions = []
        remoteSuggestions = []
        selectedSuggestionIndex = nil
        suggestionDebounceTask?.cancel()
    }

    private func applySelection(at index: Int) {
        guard suggestionItems.indices.contains(index) else { return }
        selectedSuggestionIndex = index
    }
}
