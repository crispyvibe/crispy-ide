import Combine
import Foundation

/// Per-pane editor group — each split pane owns one of these.
/// Mirrors the file-related subset of ContentViewerStore but is fully independent.
@MainActor
final class EditorGroupStore: ObservableObject, Identifiable {
    static let navigationHistoryLimit = 100
    private enum GitFileTabPresentation: Equatable {
        case diff(rootURL: URL, relativePath: String, statusCode: String)
        case preloadedDiff(content: String, relativePath: String, statusCode: String)
        case historicalContent(rootURL: URL, relativePath: String, titleSuffix: String)
    }

    let id: UUID
    let markdownViewModel: MarkdownViewModel

    @Published var tabs: [ContentViewerTab] = []
    @Published var activeTabID: String?

    /// F049-R06: per-pane comments side-panel state. Each split pane owns
    /// one of these so panel visibility and selection are independent.
    /// Injected via init so `AppContainer` controls the lifecycle (per
    /// composition-root rule) rather than the store creating it itself.
    let commentsPanel: CommentsPanelStore

    private var fileContentProviderByTabID: [String: any FileContentProviding] = [:]
    private var gitPresentationByTabID: [String: GitFileTabPresentation] = [:]
    private var previewTabID: String?
    private var backNavigationTabIDs: [String] = []
    private var forwardNavigationTabIDs: [String] = []

    var activeTab: ContentViewerTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    var activeFileDocumentReference: FileDocumentReference? {
        guard case .file(let reference)? = activeTab?.kind else { return nil }
        return reference
    }

    var activeFileContentProvider: (any FileContentProviding)? {
        guard let activeTabID else { return nil }
        return fileContentProviderByTabID[activeTabID]
    }

    var canNavigateBack: Bool {
        markdownViewModel.canNavigateBackInRenderedDocument
            || backNavigationTabIDs.contains(where: hasTab(withID:))
    }

    var canNavigateForward: Bool {
        markdownViewModel.canNavigateForwardInRenderedDocument
            || forwardNavigationTabIDs.contains(where: hasTab(withID:))
    }

    init(
        id: UUID = UUID(),
        markdownViewModel: MarkdownViewModel,
        commentsPanel: CommentsPanelStore
    ) {
        self.id = id
        self.markdownViewModel = markdownViewModel
        self.commentsPanel = commentsPanel
        markdownViewModel.linkedFileOpenHandler = { [weak self] url, reference in
            guard let self else { return }
            self.openLinkedFile(
                at: url,
                documentReference: reference,
                fileContentProvider: self.markdownViewModel.fileContentProvider
            )
        }
        markdownViewModel.renderedNavigationFallbackHandler = { [weak self] direction in
            self?.navigateAcrossFiles(direction)
        }
    }

    // MARK: - File Operations

    func filteredTabs(scope: ViewerScope, focusedProjectRootPath: String?) -> [ContentViewerTab] {
        guard scope == .focusedProject, let rootPath = focusedProjectRootPath else { return tabs }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return tabs.filter { tab in
            switch tab.kind {
            case .file(let reference):
                let url = reference.url
                return url.standardizedFileURL.path.hasPrefix(prefix)
            case .webPage(let reference):
                return reference.projectPath == rootPath
            case .vibeCast, .todos, .vibeLanes, .terminal, .acpPane:
                return true
            }
        }
    }

    func openTab(_ tab: ContentViewerTab, fileContentProvider: (any FileContentProviding)? = nil) {
        switch tab.kind {
        case .file(let reference):
            openFileInTab(
                at: reference.url,
                documentReference: reference,
                fileContentProvider: fileContentProvider
            )
        case .vibeCast, .todos, .vibeLanes, .webPage, .terminal, .acpPane:
            activateOrInsertTab(tab, setActive: true)
        }
    }

    func previewFile(
        at url: URL,
        projectIdentifier: String? = nil,
        fileContentProvider: (any FileContentProviding)? = nil
    ) {
        let reference = FileDocumentReference(url: url, projectIdentifier: projectIdentifier)
        let tab = ContentViewerTab.file(reference: reference)

        // Remove previous preview tab if it's a different file
        if let oldID = previewTabID, oldID != tab.id {
            closeTab(oldID)
        }

        gitPresentationByTabID.removeValue(forKey: tab.id)
        applyFileContentProvider(fileContentProvider, for: tab.id)
        activateOrInsertTab(tab, setActive: true)
        previewTabID = tab.id
        markdownViewModel.fileContentProvider = fileContentProviderForFileTab(tab)
        markdownViewModel.previewFile(at: reference.url, documentReference: reference)
    }

    func openFileInTab(
        at url: URL,
        line: Int? = nil,
        column: Int? = nil,
        documentReference: FileDocumentReference? = nil,
        projectIdentifier: String? = nil,
        fileContentProvider: (any FileContentProviding)? = nil,
        suppressConnectionReadinessErrors: Bool = false
    ) {
        let reference = documentReference
            ?? FileDocumentReference(url: url, projectIdentifier: projectIdentifier)
        let tab = ContentViewerTab.file(reference: reference)
        if previewTabID == tab.id { previewTabID = nil }
        applyFileContentProvider(fileContentProvider, for: tab.id)
        gitPresentationByTabID.removeValue(forKey: tab.id)
        activateOrInsertTab(tab, setActive: true)
        markdownViewModel.fileContentProvider = fileContentProviderForFileTab(tab)
        markdownViewModel.openFileInTab(
            at: reference.url,
            line: line,
            column: column,
            documentReference: reference,
            suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
        )
    }

    func navigateBack() {
        if markdownViewModel.canNavigateBackInRenderedDocument {
            markdownViewModel.requestRenderedNavigation(.back)
        } else {
            navigateAcrossFiles(.back)
        }
    }

    func navigateForward() {
        if markdownViewModel.canNavigateForwardInRenderedDocument {
            markdownViewModel.requestRenderedNavigation(.forward)
        } else {
            navigateAcrossFiles(.forward)
        }
    }

    /// Updates a known file tab's provider without activating that tab.
    func updateFileContentProvider(
        _ fileContentProvider: (any FileContentProviding)?,
        for reference: FileDocumentReference
    ) {
        guard let fileContentProvider else { return }
        let tabID = ContentViewerTab.file(reference: reference).id
        guard hasTab(withID: tabID), fileContentProviderByTabID[tabID] == nil else { return }
        applyFileContentProvider(fileContentProvider, for: tabID)
        guard activeTabID == tabID else { return }
        markdownViewModel.fileContentProvider = fileContentProvider
        markdownViewModel.openFile(
            at: reference.url,
            documentReference: reference,
            suppressConnectionReadinessErrors: true
        )
    }

    private func openLinkedFile(
        at url: URL,
        documentReference: FileDocumentReference,
        fileContentProvider: (any FileContentProviding)?
    ) {
        let targetTabID = ContentViewerTab.file(reference: documentReference).id
        if let sourceTabID = activeTabID, sourceTabID != targetTabID {
            Self.append(sourceTabID, to: &backNavigationTabIDs)
            forwardNavigationTabIDs.removeAll()
        }
        openFileInTab(
            at: url,
            documentReference: documentReference,
            fileContentProvider: fileContentProvider
        )
    }

    /// Upgrades an existing file tab's project-qualified identity in place.
    func upgradeFileReference(
        from previousReference: FileDocumentReference,
        to reference: FileDocumentReference,
        fileContentProvider: (any FileContentProviding)?
    ) {
        let previousTabID = ContentViewerTab.file(reference: previousReference).id
        let replacementTab = ContentViewerTab.file(reference: reference)
        guard previousTabID != replacementTab.id,
              let index = tabs.firstIndex(where: { $0.id == previousTabID }) else {
            updateFileContentProvider(fileContentProvider, for: reference)
            return
        }

        let wasActive = activeTabID == previousTabID
        let previousProvider = fileContentProviderByTabID.removeValue(forKey: previousTabID)
        let previousPresentation = gitPresentationByTabID.removeValue(forKey: previousTabID)
        tabs[index] = replacementTab
        fileContentProviderByTabID[replacementTab.id] = fileContentProvider ?? previousProvider
        if let previousPresentation {
            gitPresentationByTabID[replacementTab.id] = previousPresentation
        }
        backNavigationTabIDs = backNavigationTabIDs.map {
            $0 == previousTabID ? replacementTab.id : $0
        }
        forwardNavigationTabIDs = forwardNavigationTabIDs.map {
            $0 == previousTabID ? replacementTab.id : $0
        }
        if previewTabID == previousTabID { previewTabID = replacementTab.id }
        if wasActive { activeTabID = replacementTab.id }

        if wasActive {
            markdownViewModel.fileContentProvider = fileContentProviderForFileTab(replacementTab)
        }
        markdownViewModel.upgradeEditorTabReference(
            from: previousReference,
            to: reference,
            suppressConnectionReadinessErrors: true
        )
    }

    func previewGitDiff(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        statusCode: String,
        projectIdentifier: String? = nil
    ) {
        let reference = FileDocumentReference(url: fileURL, projectIdentifier: projectIdentifier)
        let tab = ContentViewerTab.file(reference: reference)
        applyFileContentProvider(nil, for: tab.id)
        gitPresentationByTabID[tab.id] = .diff(
            rootURL: rootURL.standardizedFileURL,
            relativePath: relativePath,
            statusCode: statusCode
        )
        activateOrInsertTab(tab, setActive: true)
        markdownViewModel.fileContentProvider = nil
        markdownViewModel.previewGitDiff(
            rootURL: rootURL,
            fileURL: fileURL,
            relativePath: relativePath,
            statusCode: statusCode,
            documentReference: reference
        )
    }

    func previewGitDiffContent(
        _ content: String,
        fileURL: URL,
        relativePath: String,
        statusCode: String,
        projectIdentifier: String
    ) {
        let reference = FileDocumentReference(
            url: fileURL,
            projectIdentifier: projectIdentifier
        )
        let tab = ContentViewerTab.file(reference: reference)
        applyFileContentProvider(nil, for: tab.id)
        gitPresentationByTabID[tab.id] = .preloadedDiff(
            content: content,
            relativePath: relativePath,
            statusCode: statusCode
        )
        activateOrInsertTab(tab, setActive: true)
        markdownViewModel.fileContentProvider = nil
        markdownViewModel.previewGitDiffContent(
            content,
            fileURL: fileURL,
            relativePath: relativePath,
            statusCode: statusCode,
            documentReference: reference
        )
    }

    func previewGitFileContent(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        titleSuffix: String,
        projectIdentifier: String? = nil
    ) {
        let reference = FileDocumentReference(url: fileURL, projectIdentifier: projectIdentifier)
        let tab = ContentViewerTab.file(reference: reference)
        applyFileContentProvider(nil, for: tab.id)
        gitPresentationByTabID[tab.id] = .historicalContent(
            rootURL: rootURL.standardizedFileURL,
            relativePath: relativePath,
            titleSuffix: titleSuffix
        )
        activateOrInsertTab(tab, setActive: true)
        markdownViewModel.fileContentProvider = nil
        markdownViewModel.previewGitFileContent(
            rootURL: rootURL,
            fileURL: fileURL,
            relativePath: relativePath,
            titleSuffix: titleSuffix,
            documentReference: reference
        )
    }

    enum TabActivationMode {
        case userInitiated
        case reconciliation
        case lifecycleFallback
    }

    func activateTab(
        _ tabID: String,
        suppressConnectionReadinessErrors: Bool = false,
        mode: TabActivationMode = .userInitiated
    ) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        let selectionChanged = activeTabID != tabID
        guard selectionChanged || mode == .userInitiated else { return }

        activeTabID = tabID
        syncMarkdownViewModelToTab(
            tab,
            suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
        )
        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: .info,
            event: "content_tab_selection_commit",
            metadata: [
                "pane": AppDiagnostics.pathToken(id.uuidString),
                "tab": AppDiagnostics.pathToken(tabID)
            ]
        )

        // F021-R15: user reactivation intentionally republishes so project
        // focus can be repaired. Reconciliation only enters when selection
        // changes, preventing observer recursion and duplicate commits.
        NotificationCenter.default.post(
            name: .contentViewerTabActivated,
            object: nil,
            userInfo: [AppCommandUserInfoKey.tab: tab]
        )
    }

    /// Activates the first visible tab when the current selection is outside the visible scope.
    /// An empty visible set preserves a hidden active selection so changing scope can restore it.
    func reconcileActiveSelection(visibleTabIDs: [String]) {
        if let activeTabID, visibleTabIDs.contains(activeTabID) {
            return
        }
        guard let fallbackTabID = visibleTabIDs.first else { return }
        activateTab(fallbackTabID, mode: .reconciliation)
    }

    func updateTabTitle(_ tabID: String, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].customTitle = title
    }

    @discardableResult
    func closeTab(
        _ tabID: String,
        discardUnsavedChanges: Bool = false
    ) -> Task<Error?, Never>? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        if previewTabID == tabID { previewTabID = nil }
        let wasActive = activeTabID == tabID
        let closingKind = tabs[index].kind

        tabs.remove(at: index)
        backNavigationTabIDs.removeAll(where: { $0 == tabID })
        forwardNavigationTabIDs.removeAll(where: { $0 == tabID })

        var flushTask: Task<Error?, Never>?
        if case .file(let reference) = closingKind {
            let closingProvider = fileContentProviderByTabID.removeValue(forKey: tabID)
            gitPresentationByTabID.removeValue(forKey: tabID)
            flushTask = markdownViewModel.closeEditorTab(
                withID: reference.documentIdentity,
                writer: discardUnsavedChanges ? nil : markdownViewModel.makeBufferWriter(
                    fileContentProvider: closingProvider
                ),
                discardUnsavedChanges: discardUnsavedChanges
            )
        }

        guard wasActive else { return flushTask }
        if tabs.isEmpty {
            activeTabID = nil
            markdownViewModel.fileContentProvider = nil
            markdownViewModel.clearCurrentDocument()
        } else {
            let fallbackIndex = min(index, tabs.count - 1)
            activateTab(tabs[fallbackIndex].id, mode: .lifecycleFallback)
        }
        return flushTask
    }

    func closeAllTabsForTeardown() -> [Task<Error?, Never>] {
        tabs.map(\.id).reversed().compactMap { closeTab($0) }
    }

    func retargetFileSystemLocation(from oldURL: URL, to newURL: URL) {
        let normalizedOld = oldURL.standardizedFileURL
        let normalizedNew = newURL.standardizedFileURL
        let previousProviders = fileContentProviderByTabID
        let previousGitPresentations = gitPresentationByTabID
        let previousTabs = tabs

        tabs = previousTabs.map { tab in
            guard case .file(let reference) = tab.kind,
                  let mapped = Self.mapURL(reference.url, from: normalizedOld, to: normalizedNew) else {
                return tab
            }
            return .file(reference: reference.replacingURL(mapped))
        }
        let remappedTabIDs = zip(previousTabs, tabs).reduce(into: [String: String]()) { result, pair in
            result[pair.0.id] = pair.1.id
        }
        backNavigationTabIDs = backNavigationTabIDs.map { remappedTabIDs[$0] ?? $0 }
        forwardNavigationTabIDs = forwardNavigationTabIDs.map { remappedTabIDs[$0] ?? $0 }

        fileContentProviderByTabID = [:]
        gitPresentationByTabID = [:]
        for (previousTab, updatedTab) in zip(previousTabs, tabs) {
            if let provider = previousProviders[previousTab.id] {
                fileContentProviderByTabID[updatedTab.id] = provider
            }
            if let presentation = previousGitPresentations[previousTab.id] {
                gitPresentationByTabID[updatedTab.id] = presentation
            }
        }

        if let currentActiveTabID = activeTabID,
           let activeIndex = previousTabs.firstIndex(where: { $0.id == currentActiveTabID }),
           tabs.indices.contains(activeIndex) {
            activeTabID = tabs[activeIndex].id
        }

        markdownViewModel.retargetOpenDocuments(from: normalizedOld, to: normalizedNew)
    }

    /// F052: flush unsaved edits for `url` to disk via the markdown view model.
    func flushUnsavedEdits(forFileURL url: URL) {
        markdownViewModel.flushUnsavedEdits(forFileURL: url)
    }

    func closeFileTabs(at url: URL, includeDescendants: Bool = false) {
        let normalizedURL = url.standardizedFileURL
        let rootPath = normalizedURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let matchingTabIDs = tabs.compactMap { tab -> String? in
            guard case .file(let reference) = tab.kind else { return nil }
            let candidatePath = reference.url.standardizedFileURL.path
            guard candidatePath == rootPath
                    || (includeDescendants && candidatePath.hasPrefix(prefix)) else {
                return nil
            }
            return tab.id
        }

        for tabID in matchingTabIDs.reversed() {
            closeTab(tabID, discardUnsavedChanges: true)
        }
    }

    // MARK: - Private

    private func navigateAcrossFiles(_ direction: MarkdownNavigationDirection) {
        let validTabIDs = Set(tabs.map(\.id))
        let destinationTabID: String?
        switch direction {
        case .back:
            destinationTabID = Self.popValidDestination(
                from: &backNavigationTabIDs,
                activeTabID: activeTabID,
                validTabIDs: validTabIDs
            )
        case .forward:
            destinationTabID = Self.popValidDestination(
                from: &forwardNavigationTabIDs,
                activeTabID: activeTabID,
                validTabIDs: validTabIDs
            )
        }
        guard let destinationTabID else { return }

        if let activeTabID {
            switch direction {
            case .back:
                Self.append(activeTabID, to: &forwardNavigationTabIDs)
            case .forward:
                Self.append(activeTabID, to: &backNavigationTabIDs)
            }
        }
        activateTab(destinationTabID)
    }

    private static func popValidDestination(
        from history: inout [String],
        activeTabID: String?,
        validTabIDs: Set<String>
    ) -> String? {
        while let candidate = history.popLast() {
            if candidate != activeTabID, validTabIDs.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func hasTab(withID tabID: String) -> Bool {
        tabs.contains(where: { $0.id == tabID })
    }

    private func activateOrInsertTab(_ tab: ContentViewerTab, setActive: Bool) {
        if !tabs.contains(where: { $0.id == tab.id }) {
            tabs.append(tab)
        }
        if setActive { activeTabID = tab.id }
    }

    private static func append(_ tabID: String, to history: inout [String]) {
        history.append(tabID)
        if history.count > navigationHistoryLimit {
            history.removeFirst(history.count - navigationHistoryLimit)
        }
    }

    var backNavigationTabIDsSnapshot: [String] { backNavigationTabIDs }
    var forwardNavigationTabIDsSnapshot: [String] { forwardNavigationTabIDs }

    private func syncMarkdownViewModelToTab(
        _ tab: ContentViewerTab,
        suppressConnectionReadinessErrors: Bool = false
    ) {
        if case .file(let reference) = tab.kind {
            if let gitPresentation = gitPresentationByTabID[tab.id] {
                markdownViewModel.fileContentProvider = nil
                switch gitPresentation {
                case let .diff(rootURL, relativePath, statusCode):
                    markdownViewModel.previewGitDiff(
                        rootURL: rootURL,
                        fileURL: reference.url,
                        relativePath: relativePath,
                        statusCode: statusCode,
                        documentReference: reference
                    )
                case let .preloadedDiff(content, relativePath, statusCode):
                    markdownViewModel.previewGitDiffContent(
                        content,
                        fileURL: reference.url,
                        relativePath: relativePath,
                        statusCode: statusCode,
                        documentReference: reference
                    )
                case let .historicalContent(rootURL, relativePath, titleSuffix):
                    markdownViewModel.previewGitFileContent(
                        rootURL: rootURL,
                        fileURL: reference.url,
                        relativePath: relativePath,
                        titleSuffix: titleSuffix,
                        documentReference: reference
                    )
                }
                return
            }
            markdownViewModel.fileContentProvider = fileContentProviderForFileTab(tab)
            markdownViewModel.openFileIfNeeded(
                at: reference.url,
                documentReference: reference,
                suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
            )
        }
    }

    func fileContentProvider(for tabID: String) -> (any FileContentProviding)? {
        fileContentProviderByTabID[tabID]
    }

    private func fileContentProviderForFileTab(
        _ tab: ContentViewerTab
    ) -> (any FileContentProviding)? {
        fileContentProviderByTabID[tab.id]
    }

    private func applyFileContentProvider(
        _ provider: (any FileContentProviding)?,
        for tabID: String
    ) {
        if let provider {
            fileContentProviderByTabID[tabID] = provider
        } else {
            fileContentProviderByTabID.removeValue(forKey: tabID)
        }
    }

    private func fileURL(forTabID tabID: String) -> URL? {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              case .file(let reference) = tab.kind else {
            return nil
        }
        return reference.url
    }

    private static func mapURL(_ candidate: URL, from oldURL: URL, to newURL: URL) -> URL? {
        let c = candidate.standardizedFileURL
        if c == oldURL { return newURL }
        let prefix = oldURL.path.hasSuffix("/") ? oldURL.path : oldURL.path + "/"
        guard c.path.hasPrefix(prefix) else { return nil }
        return newURL.appendingPathComponent(String(c.path.dropFirst(prefix.count)))
    }
}
