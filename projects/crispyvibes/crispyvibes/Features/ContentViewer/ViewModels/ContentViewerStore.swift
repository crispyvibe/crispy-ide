import Combine
import Foundation

enum ViewerScope: String, Codable, Equatable {
    case focusedProject
    case allProjects
}

/// VibeSpace-level coordinator for the content viewer.
/// Delegates all file/tab operations to the active EditorGroupStore via SplitViewStore.
@MainActor
final class ContentViewerStore: ObservableObject {
    let vibeCastStore = VibeCastStore()
    let sessionRegistry: ACPSessionRegistry

    weak var splitStore: SplitViewStore?

    @Published var viewerScope: ViewerScope = .allProjects

    var onActiveFileCleared: (() -> Void)?
    var browserTabCloseHandler: ((BrowserTabReference) -> Void)?
    /// Eagerly instantiates the browser view-model for a tab when `openWebPage` is
    /// called. Required so the Agent CLI can immediately reach `agentAPI(for:)` after
    /// `browser open` without racing the SwiftUI render cycle. Wired by
    /// `AppContainer.makeContentViewDependencies` to call
    /// `DockedBrowserCoordinator.viewModel(for:)` which inserts into
    /// `detailedViewGroups[browserID]`. Default is no-op.
    var browserTabEagerCreateHandler: ((BrowserTabReference) -> Void)?

    var activeGroup: EditorGroupStore { splitStore?.activeGroup ?? fallbackGroup }
    var markdownViewModel: MarkdownViewModel { activeGroup.markdownViewModel }
    var tabs: [ContentViewerTab] { activeGroup.tabs }
    var activeTabID: String? { activeGroup.activeTabID }
    var activeTab: ContentViewerTab? { activeGroup.activeTab }

    private let editorGroupFactory: @MainActor (UUID) -> EditorGroupStore
    private let conversationStore: AgentConversationStore
    private var registryObservation: AnyCancellable?
    private lazy var fallbackGroup = editorGroupFactory(UUID())

    init(
        conversationStore: AgentConversationStore,
        editorGroupFactory: @escaping @MainActor (UUID) -> EditorGroupStore,
        sessionRegistry: ACPSessionRegistry
    ) {
        self.conversationStore = conversationStore
        self.editorGroupFactory = editorGroupFactory
        self.sessionRegistry = sessionRegistry
        self.registryObservation = sessionRegistry.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - File Operations

    func previewFile(
        at url: URL,
        projectIdentifier: String? = nil,
        fileContentProvider: (any FileContentProviding)? = nil
    ) {
        activeGroup.previewFile(
            at: url,
            projectIdentifier: projectIdentifier,
            fileContentProvider: fileContentProvider
        )
    }

    func openFileInTab(
        at url: URL,
        line: Int? = nil,
        column: Int? = nil,
        projectIdentifier: String? = nil,
        fileContentProvider: (any FileContentProviding)? = nil
    ) {
        activeGroup.openFileInTab(
            at: url,
            line: line,
            column: column,
            projectIdentifier: projectIdentifier,
            fileContentProvider: fileContentProvider
        )
    }

    func previewGitDiff(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        statusCode: String,
        projectIdentifier: String? = nil
    ) {
        let group = activeGroup
        group.previewGitDiff(
            rootURL: rootURL,
            fileURL: fileURL,
            relativePath: relativePath,
            statusCode: statusCode,
            projectIdentifier: projectIdentifier
        )
    }

    func previewGitFileContent(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        titleSuffix: String,
        projectIdentifier: String? = nil
    ) {
        let group = activeGroup
        group.previewGitFileContent(
            rootURL: rootURL,
            fileURL: fileURL,
            relativePath: relativePath,
            titleSuffix: titleSuffix,
            projectIdentifier: projectIdentifier
        )
    }

    func openVibeCast() { activeGroup.openTab(.vibeCast) }
    func openTodos() { activeGroup.openTab(.todos) }
    func openVibeLanes() { activeGroup.openTab(.vibeLanes) }

    func makeACPStore(
        focusedProject: AnyProjectSession?,
        preferredAgentID: String?,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        sessionRegistry.newStore(
            focusedProject: focusedProject,
            preferredAgentID: preferredAgentID,
            vibespaceID: vibespaceID
        )
    }

    func openACPPane(
        focusedProject: AnyProjectSession?,
        preferredAgentID: String?,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        let store = makeACPStore(
            focusedProject: focusedProject,
            preferredAgentID: preferredAgentID,
            vibespaceID: vibespaceID
        )
        activeGroup.openTab(.acpPane(id: store.id))
        return store
    }

    /// Open an ACP pane pre-configured from a persisted thread's metadata.
    func openACPPaneForThread(
        agentId: String,
        projectPath: String,
        threadId: String,
        projects: [AnyProjectSession],
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        // Registry handles dedup — returns existing store if thread already open
        let project = projects.first(where: { $0.rootURL.standardizedFileURL.path == projectPath })
            ?? projects.first(where: { $0.projectIdentifier == projectPath })
            ?? projects.first

        let store = sessionRegistry.storeForThread(
            threadId,
            agentId: agentId,
            projectIdentifier: project?.projectIdentifier,
            vibespaceID: vibespaceID
        )
        activeGroup.openTab(.acpPane(id: store.id))
        return store
    }

    func restoreACPStore(
        from snapshot: ACPStandalonePaneSnapshot,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        sessionRegistry.restoreStore(from: snapshot, vibespaceID: vibespaceID)
    }

    func acpStore(for id: UUID) -> ACPStandaloneSessionStore? {
        sessionRegistry.store(forID: id)
    }

    func acpSnapshot(for id: UUID) -> ACPStandalonePaneSnapshot? {
        sessionRegistry.snapshot(forID: id)
    }

    func ensureACPPaneTab(id: UUID) {
        if splitStore?.activateExistingTab(matching: {
            guard case .acpPane(let existingID) = $0.kind else { return false }
            return existingID == id
        }) == true {
            return
        }
        activeGroup.openTab(.acpPane(id: id))
    }

    func openExistingACPPane(id: UUID) {
        guard sessionRegistry.store(forID: id) != nil else { return }
        ensureACPPaneTab(id: id)
    }

    func openVibeLaneACPPane(
        target: VibeLaneACPChatTarget,
        projects: [AnyProjectSession],
        vibespaceID: UUID? = nil
    ) {
        if let store = resolveVibeLaneACPStore(target: target, vibespaceID: vibespaceID) {
            ensureACPPaneTab(id: store.id)
            return
        }

        let threadID = target.threadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validThreadID = threadID?.isEmpty == false ? threadID : nil
        guard let validThreadID else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let thread = await self.conversationStore.getThread(id: validThreadID)
            let agentID = (thread?["agentId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? AppPreferences.acpDefaultAgentID()
                ?? "codex"
            let storedProjectPath = (thread?["projectPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedProjectPath = storedProjectPath?.isEmpty == false ? storedProjectPath! : target.projectPath
            _ = self.openACPPaneForThread(
                agentId: agentID.isEmpty ? "codex" : agentID,
                projectPath: resolvedProjectPath,
                threadId: validThreadID,
                projects: projects,
                vibespaceID: vibespaceID
            )
        }
    }

    func resolveVibeLaneACPStore(
        target: VibeLaneACPChatTarget,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore? {
        guard let sessionID = target.sessionID else { return nil }
        let store = sessionRegistry.store(forID: sessionID)
            ?? sessionRegistry.storeForVibeLaneSession(
                id: sessionID,
                agentID: AppPreferences.acpDefaultAgentID() ?? "codex",
                projectPath: target.projectPath,
                vibespaceID: vibespaceID
            )
        let threadID = target.threadID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let threadID, !threadID.isEmpty {
            store.restoreThreadIfNeeded(threadID)
        }
        return store
    }

    func removeACPStore(id: UUID) {
        closeACPPaneTabs(id: id)
        sessionRegistry.removeStore(id: id)
    }

    func teardownStandaloneACPStores() {
        sessionRegistry.removeAll()
    }

    func openWebPage(
        url: URL,
        projectPath: String? = nil,
        linkedTileID: UUID? = nil,
        browserID: UUID? = nil
    ) {
        let reference = BrowserTabReference(
            browserID: browserID ?? linkedTileID ?? UUID(),
            url: url,
            projectPath: projectPath,
            linkedTileID: linkedTileID
        )
        activeGroup.openTab(.webPage(reference: reference))
        // Eagerly create the BrowserPanelViewModel at the service layer so it exists
        // before any view renders. Required for the Agent CLI handoff: subsequent
        // commands like `crispy browser <id> snapshot` must succeed without racing
        // SwiftUI's render cycle.
        browserTabEagerCreateHandler?(reference)
    }

    // MARK: - Tab Management

    func activateTab(_ tabID: String) { activeGroup.activateTab(tabID) }

    func closeTab(_ tab: ContentViewerTab) {
        if case .webPage(let reference) = tab.kind {
            browserTabCloseHandler?(reference)
        }
        if case .acpPane(let storeID) = tab.kind {
            removeACPStore(id: storeID)
        }
        let group = activeGroup
        group.closeTab(tab.id)
        if group.tabs.isEmpty { onActiveFileCleared?() }
    }

    func closeTab(_ tabID: String) {
        let group = activeGroup
        guard let tab = group.tabs.first(where: { $0.id == tabID }) else { return }
        closeTab(tab)
    }

    // MARK: - Retarget

    func retargetFileSystemLocation(from oldURL: URL, to newURL: URL) {
        if let splitStore {
            for group in splitStore.editorGroups.values {
                group.retargetFileSystemLocation(from: oldURL, to: newURL)
            }
        } else {
            fallbackGroup.retargetFileSystemLocation(from: oldURL, to: newURL)
        }
    }

    /// F052: synchronously flush any unsaved edits for `url` to disk before a
    /// move/rename so buffered content isn't lost when the file relocates.
    func flushUnsavedEdits(forFileURL url: URL) {
        if let splitStore {
            for group in splitStore.editorGroups.values {
                group.flushUnsavedEdits(forFileURL: url)
            }
        } else {
            fallbackGroup.flushUnsavedEdits(forFileURL: url)
        }
    }

    func closeFileTabs(at url: URL) {
        if let splitStore {
            for group in splitStore.editorGroups.values {
                group.closeFileTabs(at: url)
            }
        } else {
            fallbackGroup.closeFileTabs(at: url)
        }

        if activeGroup.tabs.isEmpty {
            onActiveFileCleared?()
        }
    }

    private func closeACPPaneTabs(id: UUID) {
        let targetTabID = ContentViewerTab.acpPane(id: id).id

        if let splitStore {
            let paneIDs = Array(splitStore.editorGroups.keys)
            for paneID in paneIDs {
                guard let group = splitStore.editorGroups[paneID],
                      group.tabs.contains(where: { $0.id == targetTabID }) else {
                    continue
                }
                group.closeTab(targetTabID)
                if group.tabs.isEmpty, splitStore.isSplit {
                    splitStore.closePane(paneID: paneID)
                }
            }
        } else {
            fallbackGroup.closeTab(targetTabID)
        }

        if activeGroup.tabs.isEmpty {
            onActiveFileCleared?()
        }
    }
}
