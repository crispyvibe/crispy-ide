import Combine
import Foundation

@MainActor
final class SplitViewStore: ObservableObject {
    struct RestoredFileDocument {
        let reference: FileDocumentReference
        let fileContentProvider: (any FileContentProviding)?
    }

    @Published private(set) var root: SplitPaneNode
    @Published var activePaneID: UUID? { didSet { if activePaneID != oldValue { bindActiveGroup() } } }
    @Published var splitRatios: [UUID: CGFloat] = [:]

    private(set) var editorGroups: [UUID: EditorGroupStore] = [:]
    private var activeGroupSubscription: AnyCancellable?
    private let editorGroupFactory: @MainActor (UUID) -> EditorGroupStore
    var browserSessionSnapshotProvider: ((BrowserTabReference) -> BrowserSessionSnapshot?)?
    var browserTabRestoreHandler: ((BrowserTabReference, BrowserSessionSnapshot?) -> Void)?
    var browserTabCloseHandler: ((BrowserTabReference) -> Void)?
    var acpPaneCloseHandler: ((UUID) -> Void)?
    var acpPaneSnapshotProvider: ((UUID) -> ACPStandalonePaneSnapshot?)?
    var acpPaneRestoreHandler: ((ACPStandalonePaneSnapshot) -> Void)?

    var canSplit: Bool { root.leafCount < SplitPaneNode.maxPanes }
    var paneCount: Int { root.leafCount }
    var isSplit: Bool { root.leafCount > 1 }

    var activeGroup: EditorGroupStore {
        ensureGroup(for: activePaneID ?? root.id)
    }

    init(editorGroupFactory: @escaping @MainActor (UUID) -> EditorGroupStore) {
        self.editorGroupFactory = editorGroupFactory
        let node = SplitPaneNode.singleLeaf()
        self.root = node
        self.activePaneID = node.id
        _ = ensureGroup(for: node.id)
    }

    func group(for paneID: UUID) -> EditorGroupStore {
        ensureGroup(for: paneID)
    }

    // MARK: - Split

    /// Split the given pane. The new empty pane gets a fresh EditorGroupStore.
    /// Caller is responsible for opening content in the new group via the returned pane ID.
    @discardableResult
    func split(paneID: UUID, orientation: SplitOrientation) -> UUID? {
        guard let updated = SplitLayoutEngine.addSplit(to: root, at: paneID, orientation: orientation) else { return nil }
        let oldLeafIDs = Set(root.allLeafIDs)
        root = updated
        let newID = updated.allLeafIDs.first(where: { !oldLeafIDs.contains($0) })
        if let newID {
            _ = ensureGroup(for: newID)
            activePaneID = newID
        }
        pruneGroups()
        return newID
    }

    /// Split the active pane and move a tab into the new pane.
    func splitActiveWithTab(
        _ tab: ContentViewerTab,
        orientation: SplitOrientation,
        fileContentProvider: (any FileContentProviding)? = nil
    ) {
        guard let active = activePaneID else { return }
        let resolvedFileContentProvider =
            fileContentProvider
            ?? editorGroups[active]?.fileContentProvider(for: tab.id)
        // Remove from source group first (move, not copy)
        editorGroups[active]?.closeTab(tab.id)
        guard let newID = split(paneID: active, orientation: orientation) else {
            // Split failed (max panes) — reopen in source
            if let sourceGroup = editorGroups[active] {
                openTab(tab, fileContentProvider: resolvedFileContentProvider, in: sourceGroup)
            }
            return
        }
        openTab(tab, fileContentProvider: resolvedFileContentProvider, in: group(for: newID))
    }

    // MARK: - Close

    func closePane(paneID: UUID) {
        guard let updated = SplitLayoutEngine.removePane(from: root, paneID: paneID) else { return }
        if let group = editorGroups[paneID] {
            closeAllTabs(in: group)
        }
        let wasActive = activePaneID == paneID
        root = updated
        splitRatios = splitRatios.filter { updated.allLeafIDs.contains($0.key) }
        pruneGroups()
        if wasActive { activePaneID = updated.allLeafIDs.first }
    }

    // MARK: - Toggle Orientation

    func toggleOrientation(paneID: UUID) {
        guard let updated = SplitLayoutEngine.toggleOrientation(of: root, containing: paneID) else { return }
        root = updated
    }

    // MARK: - Ratio

    func ratioBinding(for splitID: UUID) -> CGFloat { splitRatios[splitID] ?? 0.5 }
    func setRatio(_ ratio: CGFloat, for splitID: UUID) { splitRatios[splitID] = ratio }

    // MARK: - Reset

    func reset() {
        for group in editorGroups.values {
            closeAllTabs(in: group)
        }
        let node = SplitPaneNode.singleLeaf()
        root = node
        activePaneID = node.id
        splitRatios.removeAll()
        editorGroups.removeAll()
        _ = ensureGroup(for: node.id)
        bindActiveGroup()
    }

    // MARK: - Snapshot / Restore

    func snapshot(viewerScope: ViewerScope? = nil) -> EditorSessionState {
        let tree = snapshotNode(root)
        let panes: [EditorPaneSnapshot] = root.allLeafIDs.compactMap { paneID in
            guard let group = editorGroups[paneID] else { return nil }
            let openFiles = group.tabs.compactMap { tab -> FileDocumentReference? in
                guard case .file(let reference) = tab.kind else { return nil }
                return reference
            }
            let terminalRefs = group.tabs.compactMap { tab -> TerminalTabReference? in
                guard case .terminal(let projectID, let tabID) = tab.kind else { return nil }
                return TerminalTabReference(projectID: projectID, tabID: tabID)
            }
            let browserTabs = group.tabs.compactMap { tab -> BrowserPaneTabSnapshot? in
                guard case .webPage(let reference) = tab.kind else { return nil }
                return BrowserPaneTabSnapshot(
                    reference: reference,
                    sessionSnapshot: browserSessionSnapshotProvider?(reference),
                    customTitle: tab.customTitle
                )
            }
            let acpTabs = group.tabs.compactMap { tab -> ACPStandalonePaneSnapshot? in
                guard case .acpPane(let id) = tab.kind else { return nil }
                return acpPaneSnapshotProvider?(id)
            }
            guard !openFiles.isEmpty || !terminalRefs.isEmpty || !browserTabs.isEmpty || !acpTabs.isEmpty else { return nil }
            let activeFile: FileDocumentReference? = group.activeTab.flatMap {
                guard case .file(let reference) = $0.kind else { return nil }
                return reference
            }
            let activeTerminalID: String? = group.activeTab.flatMap {
                guard case .terminal = $0.kind else { return nil }
                return $0.id
            }
            let activeBrowserID: String? = group.activeTab.flatMap {
                guard case .webPage = $0.kind else { return nil }
                return $0.id
            }
            return EditorPaneSnapshot(
                paneID: paneID,
                openFiles: openFiles,
                activeFile: activeFile,
                terminalTabs: terminalRefs.isEmpty ? nil : terminalRefs,
                activeTerminalTabID: activeTerminalID,
                browserTabs: browserTabs.isEmpty ? nil : browserTabs,
                activeBrowserTabID: activeBrowserID,
                acpTabs: acpTabs.isEmpty ? nil : acpTabs,
                activeTabID: group.activeTabID
            )
        }
        let ratios = splitRatios.reduce(into: [String: Double]()) { $0[$1.key.uuidString] = Double($1.value) }
        return EditorSessionState(splitTree: tree, panes: panes, activePaneID: activePaneID, splitRatios: ratios, viewerScope: viewerScope)
    }

    func restore(
        from state: EditorSessionState,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileReferenceResolver: ((FileDocumentReference) -> RestoredFileDocument?)? = nil
    ) {
        // Release buffer references from existing groups before replacing them.
        // `editorGroups.removeAll()` alone drops the MarkdownViewModel without closing buffers,
        // leaving DocumentBufferStore refcounts inflated on every restore cycle.
        // Close file tabs explicitly so `MarkdownViewModel.closeEditorTab` calls
        // `bufferStore.closeBuffer` and the refcount decrements match the openBuffer calls
        // made when those tabs were originally opened.
        for group in editorGroups.values {
            let fileTabIDs = group.tabs.compactMap { tab -> String? in
                if case .file = tab.kind { return tab.id }
                return nil
            }
            for tabID in fileTabIDs {
                group.closeTab(tabID)
            }
        }

        let restoredRoot = restoreNode(from: state.splitTree)
        root = restoredRoot
        activePaneID = state.activePaneID ?? restoredRoot.allLeafIDs.first
        splitRatios = state.splitRatios.reduce(into: [UUID: CGFloat]()) { result, pair in
            guard let uuid = UUID(uuidString: pair.key) else { return }
            result[uuid] = CGFloat(pair.value)
        }
        editorGroups.removeAll()
        let panesByID = Dictionary(uniqueKeysWithValues: state.panes.map { ($0.paneID, $0) })
        for leafID in restoredRoot.allLeafIDs {
            let group = ensureGroup(for: leafID)
            guard let paneState = panesByID[leafID] else { continue }
            for reference in paneState.openFiles {
                if let restoredFile = fileReferenceResolver?(reference) {
                    group.openFileInTab(
                        at: restoredFile.reference.url,
                        documentReference: restoredFile.reference,
                        fileContentProvider: restoredFile.fileContentProvider,
                        suppressConnectionReadinessErrors: true
                    )
                    continue
                }

                let url = reference.url
                guard fileExists(url.path) else { continue }
                group.openFileInTab(
                    at: url,
                    documentReference: reference,
                    suppressConnectionReadinessErrors: true
                )
            }
            for ref in paneState.terminalTabs ?? [] {
                group.openTab(.terminal(projectID: ref.projectID, tabID: ref.tabID))
            }
            for browser in paneState.browserTabs ?? [] {
                browserTabRestoreHandler?(browser.reference, browser.sessionSnapshot)
                group.openTab(.webPage(reference: browser.reference, customTitle: browser.customTitle))
            }
            for snapshot in paneState.acpTabs ?? [] {
                acpPaneRestoreHandler?(snapshot)
                group.openTab(.acpPane(id: snapshot.id))
            }
            if let activeTabID = paneState.activeTabID {
                group.activateTab(activeTabID, suppressConnectionReadinessErrors: true)
            } else if let activeBrowserTabID = paneState.activeBrowserTabID {
                group.activateTab(activeBrowserTabID, suppressConnectionReadinessErrors: true)
            } else if let activeFile = paneState.activeFile {
                let tabID = ContentViewerTab.file(reference: activeFile).id
                group.activateTab(tabID, suppressConnectionReadinessErrors: true)
            } else if let activeTerminalID = paneState.activeTerminalTabID {
                group.activateTab(activeTerminalID, suppressConnectionReadinessErrors: true)
            }
        }
        // Collapse empty panes (all files deleted)
        for leafID in restoredRoot.allLeafIDs where root.leafCount > 1 {
            if let g = editorGroups[leafID], g.tabs.isEmpty {
                if let collapsed = SplitLayoutEngine.removePane(from: root, paneID: leafID) {
                    root = collapsed
                    editorGroups.removeValue(forKey: leafID)
                }
            }
        }
        if let first = root.allLeafIDs.first, activePaneID.flatMap({ editorGroups[$0] }) == nil {
            activePaneID = first
        }
        bindActiveGroup()
    }

    // MARK: - Private

    func openTab(
        _ tab: ContentViewerTab,
        fileContentProvider: (any FileContentProviding)? = nil,
        in group: EditorGroupStore
    ) {
        group.openTab(tab, fileContentProvider: fileContentProvider)
    }

    func closeTab(_ tab: ContentViewerTab, in group: EditorGroupStore) {
        if case .webPage(let reference) = tab.kind {
            browserTabCloseHandler?(reference)
        }
        if case .acpPane(let id) = tab.kind {
            acpPaneCloseHandler?(id)
        }
        group.closeTab(tab.id)
    }

    /// Move a tab to a target group, removing it from any other group that has it.
    func moveTab(_ tab: ContentViewerTab, to targetGroup: EditorGroupStore) {
        let sourceFileContentProvider = editorGroups.values
            .filter { $0.id != targetGroup.id }
            .compactMap { $0.fileContentProvider(for: tab.id) }
            .first
        for (_, group) in editorGroups where group.id != targetGroup.id {
            if group.tabs.contains(where: { $0.id == tab.id }) {
                group.closeTab(tab.id)
            }
        }
        targetGroup.openTab(tab, fileContentProvider: sourceFileContentProvider)
    }

    /// Find an existing tab across all panes. If found, activate that pane and tab.
    func activateExistingTab(matching predicate: (ContentViewerTab) -> Bool) -> Bool {
        for (paneID, group) in editorGroups {
            if let tab = group.tabs.first(where: predicate) {
                activePaneID = paneID
                group.activateTab(tab.id)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func ensureGroup(for paneID: UUID) -> EditorGroupStore {
        if let existing = editorGroups[paneID] { return existing }
        let group = editorGroupFactory(paneID)
        editorGroups[paneID] = group
        if paneID == activePaneID ?? root.id { bindActiveGroup() }
        return group
    }

    private func bindActiveGroup() {
        let group = activeGroup
        activeGroupSubscription = group.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func pruneGroups() {
        let liveIDs = Set(root.allLeafIDs)
        for key in editorGroups.keys where !liveIDs.contains(key) { editorGroups.removeValue(forKey: key) }
    }

    private func closeAllTabs(in group: EditorGroupStore) {
        for tab in group.tabs.reversed() {
            closeTab(tab, in: group)
        }
    }

    private func snapshotNode(_ node: SplitPaneNode) -> SplitNodeSnapshot {
        switch node {
        case .leaf(let id): return .leaf(id: id)
        case .split(let id, let o, let first, let second, let r):
            return .split(id: id, orientation: o, first: snapshotNode(first), second: snapshotNode(second), ratio: r)
        }
    }

    private func restoreNode(from snapshot: SplitNodeSnapshot) -> SplitPaneNode {
        switch snapshot {
        case .leaf(let id): return .leaf(id: id)
        case .split(let id, let o, let first, let second, let r):
            return .split(id: id, orientation: o, first: restoreNode(from: first), second: restoreNode(from: second), ratio: r)
        }
    }
}
