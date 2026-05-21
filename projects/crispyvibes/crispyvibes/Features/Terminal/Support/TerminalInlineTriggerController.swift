import Combine
import Foundation

enum TerminalInlineTriggerCommand {
    case moveUp
    case moveDown
    case moveRight
    case confirm
    case dismiss
    case deleteBackward
}

@MainActor
final class TerminalInlineTriggerController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var results: [SpotlightComposeInlineResult] = []
    @Published private(set) var selectableResults: [SpotlightComposeInlineResult] = []
    @Published private(set) var highlightedIndex = 0
    @Published private(set) var isFeaturedActionSelected = false

    private let pathSearch = SpotlightComposePathSearchController()
    private let promptActions = SpotlightComposeInlinePromptAction.allCases

    private var cancellables = Set<AnyCancellable>()
    private var promptTask: Task<Void, Never>?

    private var triggerToken = AppPreferences.defaultTerminalComposeInlineTrigger
    private var query = ""
    private var dismissedPrefixText: String?
    private var activePrefixText: String?
    private var lastSyncedTriggerPrefix: String?
    private var inlinePromptError: String?
    private var isRunningPromptAction = false
    private var searchRoots: [URL] = []
    private var shortcuts: [TerminalShortcutDefinition] = []
    private var terminalTitle: String?
    private var currentDirectoryProvider: (() -> URL?)?
    private var insertionHandler: ((String) -> Void)?
    private var focusHandler: (() -> Void)?
    private var manageShortcutsHandler: (() -> Void)?

    var queryText: String {
        query
    }

    init() {
        pathSearch.$matches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshResults()
            }
            .store(in: &cancellables)

        pathSearch.$isSearching
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshResults()
            }
            .store(in: &cancellables)

        pathSearch.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshResults()
            }
            .store(in: &cancellables)
    }

    deinit {
        promptTask?.cancel()
        promptTask = nil
    }

    /// Breaks retain cycles between stored closures and the owning view.
    /// Must be called from `onDisappear` on every surface that configures this controller.
    func shutdown() {
        closePicker()
        currentDirectoryProvider = nil
        insertionHandler = nil
        focusHandler = nil
        manageShortcutsHandler = nil
        cancellables.removeAll()
        searchRoots = []
    }

    var footerText: String {
        if let inlinePromptError, !inlinePromptError.isEmpty {
            return inlinePromptError
        }
        if let errorMessage = pathSearch.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return AppStrings.Terminal.ComposeTriggers.noResults
        }
        if pathSearch.isSearching && pathSearch.matches.isEmpty {
            return AppStrings.Terminal.ComposeTriggers.searchingPaths
        }
        let pathCount = results.filter(\.isPath).count
        let shortcutCount = results.filter(\.isShortcut).count
        switch (pathCount, shortcutCount) {
        case let (paths, shortcuts) where paths > 0 && shortcuts > 0:
            return "\(AppStrings.Terminal.ComposeTriggers.pathResultCount(paths)) • \(AppStrings.Terminal.ComposeTriggers.shortcutResultCount(shortcuts))"
        case let (paths, _) where paths > 0:
            return AppStrings.Terminal.ComposeTriggers.pathResultCount(paths)
        case let (_, shortcuts) where shortcuts > 0:
            return AppStrings.Terminal.ComposeTriggers.shortcutResultCount(shortcuts)
        case _:
            return AppStrings.Terminal.ComposeTriggers.noResults
        }
    }

    var hintText: String {
        if featuredAction != nil {
            return "\(AppStrings.Terminal.ComposeTriggers.rightArrowGenerateHint) • \(AppStrings.Terminal.ComposeTriggers.confirmHint)"
        }
        return AppStrings.Terminal.ComposeTriggers.confirmHint
    }

    var selectedResultID: String? {
        guard !isFeaturedActionSelected else { return nil }
        guard selectableResults.indices.contains(highlightedIndex) else { return nil }
        return selectableResults[highlightedIndex].id
    }

    var panelRows: [SpotlightComposeInlinePanelRow] {
        SpotlightComposeInlineResultProvider.panelRows(from: results, selectedResultID: selectedResultID)
    }

    var featuredAction: SpotlightComposeInlineResult? {
        SpotlightComposeInlineResultProvider.featuredAction(from: results)
    }

    var featuredPanelAction: SpotlightComposeInlinePanelAction? {
        guard let featuredAction else { return nil }
        return SpotlightComposeInlinePanelAction(
            title: featuredAction.title,
            systemImage: featuredAction.systemImage,
            isSelected: isFeaturedActionSelected,
            isDisabled: featuredAction.isDisabled
        )
    }

    var manageShortcutsActionTitle: String? {
        manageShortcutsHandler == nil ? nil : AppStrings.TerminalShortcuts.manageShortcuts
    }

    func configure(
        triggerToken: String,
        searchRoots: [URL],
        shortcuts: [TerminalShortcutDefinition],
        terminalTitle: String?,
        currentDirectoryProvider: (() -> URL?)?,
        insertionHandler: ((String) -> Void)?,
        focusHandler: (() -> Void)?,
        manageShortcutsHandler: (() -> Void)?
    ) {
        self.triggerToken = AppPreferences.normalizedTerminalComposeInlineTrigger(triggerToken)
        self.searchRoots = Self.deduplicatedLocalDirectories(searchRoots)
        self.shortcuts = shortcuts
        self.terminalTitle = terminalTitle
        self.currentDirectoryProvider = currentDirectoryProvider
        self.insertionHandler = insertionHandler
        self.focusHandler = focusHandler
        self.manageShortcutsHandler = manageShortcutsHandler

        if isPresented {
            syncPathSearch()
            refreshResults()
        }
    }

    func handleTextInput(_ text: String) -> Bool {
        guard !triggerToken.isEmpty else { return false }
        guard !text.isEmpty else { return false }

        if !isPresented {
            guard text == triggerToken else { return false }
            presentPicker(initialQuery: "")
            return true
        }

        if text == triggerToken && query.isEmpty {
            closePicker()
            insertionHandler?(triggerToken)
            requestFocus()
            return true
        }

        query.append(text)
        inlinePromptError = nil
        syncPathSearch()
        refreshResults()
        return true
    }

    /// Called from `onChange(of: text)` — user is actively typing. Can open the picker.
    func syncBufferText(_ text: String) {
        syncBuffer(text, canActivate: true)
    }

    /// Called from `onAppear`, config changes, view transitions. Never opens the picker.
    func reconcileBufferText(_ text: String) {
        syncBuffer(text, canActivate: false)
    }

    private func syncBuffer(_ text: String, canActivate: Bool) {
        guard !triggerToken.isEmpty else { return }

        guard let parsedTrigger = SpotlightComposeInlineTrigger.parse(text, triggerToken: triggerToken) else {
            lastSyncedTriggerPrefix = nil
            dismissedPrefixText = nil
            guard isPresented else { return }
            closePicker()
            return
        }

        let prefix = parsedTrigger.prefixText
        let nextQuery = parsedTrigger.query
        let triggerIsNew = lastSyncedTriggerPrefix != prefix
        lastSyncedTriggerPrefix = prefix

        if !isPresented {
            guard canActivate && triggerIsNew else { return }
            if dismissedPrefixText == prefix { return }
            dismissedPrefixText = nil
            presentPicker(initialQuery: nextQuery, prefixText: prefix)
            return
        }

        // Double-trigger: close and insert literal
        if nextQuery == triggerToken && query.isEmpty {
            dismissedPrefixText = prefix
            closePicker()
            insertionHandler?(triggerToken)
            requestFocus()
            return
        }

        guard query != nextQuery else { return }
        query = nextQuery
        inlinePromptError = nil
        syncPathSearch()
        refreshResults()
    }

    func handleCommand(_ command: TerminalInlineTriggerCommand) -> Bool {
        guard isPresented else { return false }

        switch command {
        case .moveUp:
            if isFeaturedActionSelected {
                if !selectableResults.isEmpty {
                    isFeaturedActionSelected = false
                    highlightedIndex = selectableResults.count - 1
                }
                return true
            }
            guard !selectableResults.isEmpty else {
                if featuredAction != nil { isFeaturedActionSelected = true }
                return true
            }
            if highlightedIndex == 0, featuredAction != nil {
                isFeaturedActionSelected = true
            } else {
                highlightedIndex = (highlightedIndex - 1 + selectableResults.count) % selectableResults.count
            }
        case .moveDown:
            if isFeaturedActionSelected {
                if !selectableResults.isEmpty {
                    isFeaturedActionSelected = false
                    highlightedIndex = 0
                }
                return true
            }
            guard !selectableResults.isEmpty else {
                if featuredAction != nil { isFeaturedActionSelected = true }
                return true
            }
            if highlightedIndex == selectableResults.count - 1, featuredAction != nil {
                isFeaturedActionSelected = true
            } else {
                highlightedIndex = (highlightedIndex + 1) % selectableResults.count
            }
        case .moveRight:
            guard featuredAction != nil else { return true }
            isFeaturedActionSelected = true
        case .confirm:
            if isFeaturedActionSelected, let featuredAction {
                apply(featuredAction)
                return true
            }
            guard selectableResults.indices.contains(highlightedIndex) else { return true }
            apply(selectableResults[highlightedIndex])
        case .dismiss:
            dismissedPrefixText = activePrefixText
            closePicker()
            requestFocus()
        case .deleteBackward:
            guard !query.isEmpty else {
                closePicker()
                requestFocus()
                return true
            }
            query.removeLast()
            inlinePromptError = nil
            syncPathSearch()
            refreshResults()
        }

        return true
    }

    func applyResult(id: String) {
        guard let result = results.first(where: { $0.id == id }) else { return }
        apply(result)
    }

    func applyFeaturedAction() {
        guard let featuredAction, !featuredAction.isDisabled else { return }
        apply(featuredAction)
    }

    func runManageShortcutsAction() {
        manageShortcutsHandler?()
    }

    private func presentPicker(initialQuery: String, prefixText: String? = nil) {
        isPresented = true
        query = initialQuery
        activePrefixText = prefixText
        dismissedPrefixText = nil
        inlinePromptError = nil
        highlightedIndex = 0
        isFeaturedActionSelected = false
        syncPathSearch()
        refreshResults()
    }

    private func closePicker() {
        promptTask?.cancel()
        promptTask = nil
        isPresented = false
        query = ""
        activePrefixText = nil
        inlinePromptError = nil
        isRunningPromptAction = false
        highlightedIndex = 0
        isFeaturedActionSelected = false
        pathSearch.stop()
        refreshResults()
    }

    private func requestFocus() {
        focusHandler?()
    }

    private func syncPathSearch() {
        guard isPresented else {
            pathSearch.stop()
            return
        }
        pathSearch.configure(searchRoots: searchRoots)
        pathSearch.updateQuery(query)
    }

    private func refreshResults() {
        let previousSelectedID = selectedResultID
        let refreshedResults = SpotlightComposeInlineResultProvider.results(
            query: query,
            pathMatches: pathSearch.matches,
            shortcuts: shortcuts,
            promptActions: promptActions,
            isRunningPromptAction: isRunningPromptAction
        )
        results = refreshedResults
        selectableResults = refreshedResults.filter { !$0.isDisabled && !$0.isPromptAction }
        reconcileSelection(previousSelectedID: previousSelectedID)
    }

    private func reconcileSelection(previousSelectedID: String?) {
        guard isPresented else {
            highlightedIndex = 0
            isFeaturedActionSelected = false
            return
        }

        let hasFeaturedAction = featuredAction != nil
        guard !selectableResults.isEmpty else {
            highlightedIndex = 0
            isFeaturedActionSelected = hasFeaturedAction
            return
        }

        if isFeaturedActionSelected, hasFeaturedAction {
            return
        } else if let previousSelectedID,
           let preservedIndex = selectableResults.firstIndex(where: { $0.id == previousSelectedID }) {
            highlightedIndex = preservedIndex
            isFeaturedActionSelected = false
        } else if highlightedIndex >= selectableResults.count {
            highlightedIndex = selectableResults.count - 1
            isFeaturedActionSelected = false
        } else {
            isFeaturedActionSelected = false
        }
    }

    private func apply(_ result: SpotlightComposeInlineResult) {
        switch result {
        case let .path(match):
            guard let replacement = match.insertionText(currentDirectory: currentDirectoryProvider?()) else { return }
            closePicker()
            insertionHandler?(replacement)
            requestFocus()
        case let .shortcut(shortcut):
            closePicker()
            insertionHandler?(shortcut.command)
            requestFocus()
        case let .promptAction(action, _, _):
            runPromptAction(action)
        }
    }

    private func runPromptAction(_ action: SpotlightComposeInlinePromptAction) {
        let userInput = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userInput.isEmpty, !isRunningPromptAction else { return }

        inlinePromptError = nil
        isRunningPromptAction = true
        refreshResults()

        let title = terminalTitle ?? "Terminal"
        let workingDirectoryPath = currentDirectoryProvider?()?.path ?? ""
        let context = SpotlightComposeInlinePromptContext(
            terminalTitle: title,
            workingDirectoryPath: workingDirectoryPath
        )

        promptTask?.cancel()
        promptTask = Task { [userInput, context] in
            let result = await Task.detached(priority: .userInitiated) {
                SpotlightComposeInlinePromptService.run(
                    action: action,
                    userInput: userInput,
                    context: context
                )
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.isRunningPromptAction = false
                self.refreshResults()
                guard let result, !result.isEmpty else {
                    self.inlinePromptError = AppStrings.Terminal.ComposeTriggers.promptFailed
                    self.requestFocus()
                    return
                }

                self.closePicker()
                self.insertionHandler?(result)
                self.requestFocus()
            }
        }
    }

    private static func deduplicatedLocalDirectories(_ roots: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var seen = Set<String>()

        return roots.compactMap { root in
            guard root.isFileURL else { return nil }
            let normalized = root.standardizedFileURL
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }
}
