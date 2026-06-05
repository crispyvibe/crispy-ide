import Combine
import Foundation

/// Per-pane editor group — each split pane owns one of these.
/// Mirrors the file-related subset of ContentViewerStore but is fully independent.
@MainActor
final class EditorGroupStore: ObservableObject, Identifiable {
    private enum GitFileTabPresentation: Equatable {
        case diff(rootURL: URL, relativePath: String, statusCode: String)
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

    var activeTab: ContentViewerTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    init(
        id: UUID = UUID(),
        markdownViewModel: MarkdownViewModel,
        commentsPanel: CommentsPanelStore
    ) {
        self.id = id
        self.markdownViewModel = markdownViewModel
        self.commentsPanel = commentsPanel
    }

    // MARK: - File Operations

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
            case .vibeCast, .todos, .terminal, .acpPane:
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
        case .vibeCast, .todos, .webPage, .terminal, .acpPane:
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
        activateOrInsertTab(tab, setActive: true)
        previewTabID = tab.id
        markdownViewModel.fileContentProvider = fileContentProvider
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
        let reference = documentReference ?? FileDocumentReference(url: url, projectIdentifier: projectIdentifier)
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

    func activateTab(_ tabID: String, suppressConnectionReadinessErrors: Bool = false) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        if let tab = tabs.first(where: { $0.id == tabID }) {
            syncMarkdownViewModelToTab(
                tab,
                suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
            )
            // F021-R15: surface tab activation so the click-to-select listener can
            // resolve the tab's owning project and switch focus. Idempotent when
            // the resolved project is already focused.
            NotificationCenter.default.post(
                name: .contentViewerTabActivated,
                object: nil,
                userInfo: [AppCommandUserInfoKey.tab: tab]
            )
        }
    }

    func updateTabTitle(_ tabID: String, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].customTitle = title
    }

    func closeTab(_ tabID: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if previewTabID == tabID { previewTabID = nil }
        let wasActive = activeTabID == tabID
        let closingKind = tabs[index].kind

        tabs.remove(at: index)

        if case .file(let reference) = closingKind {
            fileContentProviderByTabID.removeValue(forKey: tabID)
            gitPresentationByTabID.removeValue(forKey: tabID)
            markdownViewModel.closeEditorTab(withID: reference.documentIdentity)
        }

        guard wasActive else { return }
        if tabs.isEmpty {
            activeTabID = nil
            markdownViewModel.fileContentProvider = nil
            markdownViewModel.clearCurrentDocument()
        } else {
            let fallbackIndex = min(index, tabs.count - 1)
            let fallbackTab = tabs[fallbackIndex]
            activeTabID = fallbackTab.id
            syncMarkdownViewModelToTab(fallbackTab)
        }
    }

    func retargetFileSystemLocation(from oldURL: URL, to newURL: URL) {
        let normalizedOld = oldURL.standardizedFileURL
        let normalizedNew = newURL.standardizedFileURL
        let previousProviders = fileContentProviderByTabID
        let previousGitPresentations = gitPresentationByTabID
        let previousTabs = tabs

        tabs = previousTabs.map { tab in
            guard case .file(let reference) = tab.kind,
                  let mapped = Self.mapURL(reference.url, from: normalizedOld, to: normalizedNew) else { return tab }
            return .file(reference: reference.replacingURL(mapped))
        }

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

    func closeFileTabs(at url: URL) {
        let normalizedURL = url.standardizedFileURL
        let matchingTabIDs = tabs.compactMap { tab -> String? in
            guard case .file(let reference) = tab.kind,
                  reference.url.standardizedFileURL == normalizedURL else {
                return nil
            }
            return tab.id
        }

        for tabID in matchingTabIDs.reversed() {
            closeTab(tabID)
        }
    }

    // MARK: - Private

    private func activateOrInsertTab(_ tab: ContentViewerTab, setActive: Bool) {
        if !tabs.contains(where: { $0.id == tab.id }) {
            tabs.append(tab)
        }
        if setActive { activeTabID = tab.id }
    }

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

    private func fileContentProviderForFileTab(_ tab: ContentViewerTab) -> (any FileContentProviding)? {
        fileContentProviderByTabID[tab.id]
    }

    private func applyFileContentProvider(_ provider: (any FileContentProviding)?, for tabID: String) {
        if let provider {
            fileContentProviderByTabID[tabID] = provider
        } else {
            fileContentProviderByTabID.removeValue(forKey: tabID)
        }
    }

    private func fileURL(forTabID tabID: String) -> URL? {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              case .file(let reference) = tab.kind else { return nil }
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
