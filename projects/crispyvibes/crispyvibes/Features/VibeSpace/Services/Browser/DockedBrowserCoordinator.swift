import Combine
import Combine
import Foundation

@MainActor
final class DockedBrowserCoordinator: ObservableObject {
    private var groups: [UUID: BrowserPanelViewModel] = [:]
    private var detailedViewGroups: [UUID: BrowserPanelViewModel] = [:]
    private var detailedViewSessionSnapshots: [UUID: BrowserSessionSnapshot] = [:]
    private var detailedViewReferences: [UUID: BrowserTabReference] = [:]
    private(set) var previewViewModel: BrowserPanelViewModel?
    @Published var previewURL: URL?
    private(set) var previewSessionSnapshot: BrowserSessionSnapshot?
    private(set) var previewProjectPath: String?
    var historyStore: BrowserHistoryStore?
    var agentAPIFactory: ((BrowserPanelViewModel) -> BrowserAgentAPI)?

    /// Set by ContentView to handle new-tab requests from any browser VM.
    var onOpenNewBrowser: ((URL, String?) -> Void)?
    /// Fired when a pinned browser tile's session state changes (URL navigation, zoom,
    /// history). Consumers (e.g., `VibeSpaceTerminalBoardStore`) subscribe to this to
    /// re-persist the current board state with fresh browser snapshots captured via
    /// `snapshotBrowserSessions(for:)` / `currentURLs(for:)`.
    let browserSessionDidChange = PassthroughSubject<Void, Never>()
    /// Fired when a detailed (editor-pane) browser's session state changes. Used by the
    /// composition root to trigger editor-session state persistence.
    var onDetailedSessionStateChanged: (() -> Void)?
    /// Provides projectPath for a given tile ID. Set at composition root.
    var projectPathForTile: ((UUID) -> String?)?

    private func makePersistentViewModel(initialURL: URL? = nil) -> BrowserPanelViewModel {
        BrowserPanelViewModel(initialURL: initialURL)
    }

    private func makePreviewViewModel(initialURL: URL? = nil) -> BrowserPanelViewModel {
        BrowserPanelViewModel(initialURL: initialURL, usesEphemeralDataStore: true)
    }

    private func wireNewBrowserCallback(
        _ vm: BrowserPanelViewModel,
        tileID: UUID? = nil,
        detailedBrowserID: UUID? = nil
    ) {
        vm.historyStore = historyStore
        vm.onOpenNewBrowser = { [weak self] url in
            let projectPath =
                tileID.flatMap { self?.projectPathForTile?($0) }
                ?? detailedBrowserID.flatMap { self?.detailedViewReferences[$0]?.projectPath }
                ?? self?.previewProjectPath
            self?.onOpenNewBrowser?(url, projectPath)
        }
        vm.onSessionStateChanged = { [weak self, weak vm] in
            guard let self else { return }
            if tileID != nil {
                self.browserSessionDidChange.send()
            } else if let detailedBrowserID, let vm {
                self.captureDetailedSnapshot(from: vm, browserID: detailedBrowserID)
                if self.detailedViewReferences[detailedBrowserID]?.linkedTileID != nil {
                    self.browserSessionDidChange.send()
                }
                self.onDetailedSessionStateChanged?()
            } else if let vm {
                self.capturePreviewSnapshot(from: vm)
            }
        }
    }

    private func capturePreviewSnapshot(
        from viewModel: BrowserPanelViewModel,
        fallbackURL: URL? = nil
    ) {
        var snapshot = viewModel.sessionSnapshot()
        if snapshot.urlString == nil {
            snapshot.urlString = fallbackURL?.absoluteString
        }
        previewSessionSnapshot = snapshot
        publishPreviewURL(snapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL)
    }

    private func publishPreviewURL(_ url: URL?) {
        if previewURL == url { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.previewURL != url {
                self.previewURL = url
            }
        }
    }

    private func captureDetailedSnapshot(
        from viewModel: BrowserPanelViewModel,
        browserID: UUID,
        fallbackURL: URL? = nil
    ) {
        var snapshot = viewModel.sessionSnapshot()
        if snapshot.urlString == nil {
            snapshot.urlString = fallbackURL?.absoluteString
        }
        detailedViewSessionSnapshots[browserID] = snapshot
    }

    /// Remove all VMs not in the given set of tile IDs. Called on vibespace switch.
    func pruneViewModels(keeping activeTileIDs: Set<UUID>) {
        for key in groups.keys where !activeTileIDs.contains(key) {
            groups.removeValue(forKey: key)
        }
    }

    /// Remove all VMs and preview. Called on vibespace close.
    func removeAll() {
        groups.removeAll()
        detailedViewGroups.removeAll()
        detailedViewSessionSnapshots.removeAll()
        detailedViewReferences.removeAll()
        dismissPreview()
    }

    // MARK: - Detailed View (string-keyed)

    func viewModel(for reference: BrowserTabReference) -> BrowserPanelViewModel {
        let browserID = reference.browserID
        detailedViewReferences[browserID] = reference
        if let existing = detailedViewGroups[browserID] { return existing }

        if let snapshot = detailedViewSessionSnapshots[browserID] {
            let vm = makePersistentViewModel()
            wireNewBrowserCallback(vm, detailedBrowserID: browserID)
            vm.restoreSession(snapshot)
            detailedViewGroups[browserID] = vm
            return vm
        }

        if let linkedTileID = reference.linkedTileID,
           let tileViewModel = groups[linkedTileID] {
            let snapshot = tileViewModel.sessionSnapshot()
            detailedViewSessionSnapshots[browserID] = snapshot
            let vm = makePersistentViewModel()
            wireNewBrowserCallback(vm, detailedBrowserID: browserID)
            vm.restoreSession(snapshot)
            detailedViewGroups[browserID] = vm
            return vm
        }

        let url = reference.seedURL ?? URL(string: "about:blank")!
        let vm = makePersistentViewModel(initialURL: url.absoluteString == "about:blank" ? nil : url)
        wireNewBrowserCallback(vm, detailedBrowserID: browserID)
        detailedViewGroups[browserID] = vm
        captureDetailedSnapshot(from: vm, browserID: browserID, fallbackURL: url)
        return vm
    }

    func restoreDetailedBrowser(
        reference: BrowserTabReference,
        snapshot: BrowserSessionSnapshot?
    ) {
        detailedViewReferences[reference.browserID] = reference
        if let snapshot {
            detailedViewSessionSnapshots[reference.browserID] = snapshot
            let vm = makePersistentViewModel()
            wireNewBrowserCallback(vm, detailedBrowserID: reference.browserID)
            vm.restoreSession(snapshot)
            detailedViewGroups[reference.browserID] = vm
            return
        }
        if let url = reference.seedURL {
            let vm = makePersistentViewModel(initialURL: url.absoluteString == "about:blank" ? nil : url)
            wireNewBrowserCallback(vm, detailedBrowserID: reference.browserID)
            detailedViewGroups[reference.browserID] = vm
            captureDetailedSnapshot(from: vm, browserID: reference.browserID, fallbackURL: url)
        }
    }

    func snapshotDetailedBrowser(for reference: BrowserTabReference) -> BrowserSessionSnapshot? {
        detailedViewReferences[reference.browserID] = reference
        if let vm = detailedViewGroups[reference.browserID] {
            captureDetailedSnapshot(
                from: vm,
                browserID: reference.browserID,
                fallbackURL: reference.seedURL
            )
            return detailedViewSessionSnapshots[reference.browserID]
        }
        if let snapshot = detailedViewSessionSnapshots[reference.browserID] {
            return snapshot
        }
        if let linkedTileID = reference.linkedTileID,
           let snapshot = groups[linkedTileID]?.sessionSnapshot() {
            detailedViewSessionSnapshots[reference.browserID] = snapshot
            return snapshot
        }
        guard let url = reference.seedURL else { return nil }
        let snapshot = BrowserSessionSnapshot(urlString: url.absoluteString)
        detailedViewSessionSnapshots[reference.browserID] = snapshot
        return snapshot
    }

    func removeDetailedBrowser(browserID: UUID) {
        detailedViewGroups.removeValue(forKey: browserID)
        detailedViewSessionSnapshots.removeValue(forKey: browserID)
        detailedViewReferences.removeValue(forKey: browserID)
    }

    // MARK: - Floating Preview

    func showPreview(for url: URL, projectPath: String? = nil) {
        let vm = makePreviewViewModel(initialURL: url.absoluteString == "about:blank" ? nil : url)
        setPreviewViewModel(vm, url: url, projectPath: projectPath)
    }

    func setPreviewViewModel(_ vm: BrowserPanelViewModel, url: URL, projectPath: String? = nil) {
        wireNewBrowserCallback(vm)
        previewViewModel = vm
        previewProjectPath = projectPath
        capturePreviewSnapshot(from: vm, fallbackURL: url)
    }

    func previewSnapshot(fallbackURL: URL? = nil) -> BrowserSessionSnapshot? {
        if let previewViewModel {
            capturePreviewSnapshot(from: previewViewModel, fallbackURL: fallbackURL)
            return previewSessionSnapshot
        }
        if var snapshot = previewSessionSnapshot {
            if snapshot.urlString == nil {
                snapshot.urlString = fallbackURL?.absoluteString
            }
            previewSessionSnapshot = snapshot
            publishPreviewURL(snapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL)
            return snapshot
        }
        guard let fallbackURL else { return nil }
        let snapshot = BrowserSessionSnapshot(urlString: fallbackURL.absoluteString)
        previewSessionSnapshot = snapshot
        publishPreviewURL(fallbackURL)
        return snapshot
    }

    @discardableResult
    func restorePreview(
        from snapshot: BrowserSessionSnapshot,
        projectPath: String? = nil
    ) -> BrowserPanelViewModel {
        if let existing = previewViewModel,
           existing.sessionSnapshot() == snapshot {
            previewProjectPath = projectPath
            capturePreviewSnapshot(from: existing)
            return existing
        }

        let vm = makePreviewViewModel()
        wireNewBrowserCallback(vm)
        vm.restoreSession(snapshot)
        previewViewModel = vm
        previewProjectPath = projectPath
        capturePreviewSnapshot(
            from: vm,
            fallbackURL: snapshot.urlString.flatMap(URL.init(string:))
        )
        return vm
    }

    func dismissPreview() {
        publishPreviewURL(nil)
        previewSessionSnapshot = nil
        previewProjectPath = nil
        previewViewModel = nil
    }

    func promotePreview(to tileID: UUID?) {
        guard let tileID else {
            dismissPreview()
            return
        }
        let snapshot: BrowserSessionSnapshot
        if let previewViewModel {
            snapshot = previewViewModel.sessionSnapshot()
        } else if let previewSessionSnapshot {
            snapshot = previewSessionSnapshot
        } else {
            dismissPreview()
            return
        }
        let vm = makePersistentViewModel()
        wireNewBrowserCallback(vm, tileID: tileID)
        vm.restoreSession(snapshot)
        groups[tileID] = vm
        publishPreviewURL(nil)
        previewSessionSnapshot = nil
        previewProjectPath = nil
        previewViewModel = nil
    }

    var hasPreview: Bool { previewViewModel != nil }

    // MARK: - Pinned Tile Groups

    func viewModel(for tileID: UUID, url: URL) -> BrowserPanelViewModel {
        if let existing = groups[tileID] { return existing }
        let vm = makePersistentViewModel(initialURL: url)
        wireNewBrowserCallback(vm, tileID: tileID)
        groups[tileID] = vm
        return vm
    }

    func restoreTile(id: UUID, snapshot: BrowserSessionSnapshot) {
        let vm = makePersistentViewModel()
        wireNewBrowserCallback(vm, tileID: id)
        vm.restoreSession(snapshot)
        groups[id] = vm
    }

    func removeViewModel(for tileID: UUID) {
        groups.removeValue(forKey: tileID)
    }

    func snapshotBrowserSessions(for tileIDs: [UUID]) -> [UUID: BrowserSessionSnapshot] {
        var result: [UUID: BrowserSessionSnapshot] = [:]
        for tileID in tileIDs {
            if let linkedSnapshot = detailedSnapshotLinked(to: tileID) {
                result[tileID] = linkedSnapshot
            } else if let vm = groups[tileID] {
                result[tileID] = vm.sessionSnapshot()
            }
        }
        return result
    }

    func currentURLs(for tileIDs: [UUID]) -> [UUID: URL] {
        var result: [UUID: URL] = [:]
        for tileID in tileIDs {
            if let linkedSnapshot = detailedSnapshotLinked(to: tileID),
               let urlString = linkedSnapshot.urlString,
               let url = URL(string: urlString) {
                result[tileID] = url
            } else if let url = groups[tileID]?.currentURL {
                result[tileID] = url
            }
        }
        return result
    }

    // MARK: - Tab Search (S41)

    struct BrowserTabInfo: Identifiable {
        let id: UUID
        let title: String
        let url: URL?
    }

    func agentAPI(for tileID: UUID) -> BrowserAgentAPI? {
        let vm = groups[tileID] ?? detailedViewGroups[tileID]
        guard let vm else { return nil }
        return agentAPIFactory?(vm)
    }

    func searchTabs(query: String) -> [BrowserTabInfo] {
        let q = query.lowercased()
        return groups.compactMap { id, vm in
            let title = vm.displayTitle
            let url = vm.currentURL
            if q.isEmpty || title.lowercased().contains(q) || (url?.absoluteString.lowercased().contains(q) == true) {
                return BrowserTabInfo(id: id, title: title, url: url)
            }
            return nil
        }
    }

    func searchDetailedTabs(query: String) -> [BrowserTabInfo] {
        let q = query.lowercased()
        return detailedViewGroups.compactMap { id, vm in
            let title = vm.displayTitle
            let url = vm.currentURL
            if q.isEmpty || title.lowercased().contains(q) || (url?.absoluteString.lowercased().contains(q) == true) {
                return BrowserTabInfo(id: id, title: title, url: url)
            }
            return nil
        }
    }

    private func detailedSnapshotLinked(to tileID: UUID) -> BrowserSessionSnapshot? {
        for (browserID, reference) in detailedViewReferences where reference.linkedTileID == tileID {
            if let vm = detailedViewGroups[browserID] {
                captureDetailedSnapshot(
                    from: vm,
                    browserID: browserID,
                    fallbackURL: reference.seedURL
                )
            }
            if let snapshot = detailedViewSessionSnapshots[browserID] {
                return snapshot
            }
        }
        return nil
    }
}
