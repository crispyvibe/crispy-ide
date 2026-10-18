import Combine
import Foundation

@MainActor
final class DockedBrowserCoordinator: ObservableObject {
    private var groups: [UUID: BrowserPanelViewModel] = [:]
    private var detailedViewGroups: [UUID: BrowserPanelViewModel] = [:]
    private var detailedViewSessionSnapshots: [UUID: BrowserSessionSnapshot] = [:]
    private var detailedViewSnapshotRevisions: [UUID: UInt64] = [:]
    private var detailedViewReferences: [UUID: BrowserTabReference] = [:]
    private var nextDetailedSnapshotRevision: UInt64 = 0
    private var pendingLinkedTileSnapshots: [UUID: BrowserSessionSnapshot] = [:]
    private var linkedTileAuthorityBrowserIDs: [UUID: UUID] = [:]
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

    private func makePersistentViewModel(initialURL: URL? = nil, projectPath: String? = nil) -> BrowserPanelViewModel {
        BrowserPanelViewModel(initialURL: initialURL, projectPath: projectPath)
    }

    private func makePreviewViewModel(initialURL: URL? = nil, projectPath: String? = nil) -> BrowserPanelViewModel {
        BrowserPanelViewModel(initialURL: initialURL, usesEphemeralDataStore: true, projectPath: projectPath)
    }

    private func wireNewBrowserCallback(_ vm: BrowserPanelViewModel) {
        vm.historyStore = historyStore
        vm.onOpenNewBrowser = { [weak self, weak vm] url in
            guard let self, let vm else { return }
            let tileID = self.groups.first(where: { $0.value === vm })?.key
            let detailedReference = self.detailedViewGroups
                .filter { $0.value === vm }
                .sorted { $0.key.uuidString < $1.key.uuidString }
                .compactMap { self.detailedViewReferences[$0.key] }
                .first
            let projectPath = tileID.flatMap { self.projectPathForTile?($0) }
                ?? detailedReference?.projectPath
                ?? (self.previewViewModel === vm ? self.previewProjectPath : nil)
                ?? vm.projectPath
            self.onOpenNewBrowser?(url, projectPath)
        }
        vm.onSessionStateChanged = { [weak self, weak vm] in
            guard let self, let vm else { return }
            let tileIDs = self.groups.compactMap { $0.value === vm ? $0.key : nil }
            let detailedIDs = self.detailedViewGroups.compactMap { $0.value === vm ? $0.key : nil }
            for browserID in detailedIDs {
                self.captureDetailedSnapshot(from: vm, browserID: browserID)
            }
            let changedLinkedTileIDs = Set(detailedIDs.compactMap {
                self.detailedViewReferences[$0]?.linkedTileID
            })
            for tileID in changedLinkedTileIDs {
                self.convergeLinkedTileAuthority(for: tileID)
            }
            if self.previewViewModel === vm {
                self.capturePreviewSnapshot(from: vm)
            }
            let hasLinkedDetail = detailedIDs.contains {
                self.detailedViewReferences[$0]?.linkedTileID != nil
            }
            if !tileIDs.isEmpty || hasLinkedDetail {
                self.browserSessionDidChange.send()
            }
            if !detailedIDs.isEmpty {
                self.onDetailedSessionStateChanged?()
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
        nextDetailedSnapshotRevision &+= 1
        detailedViewSnapshotRevisions[browserID] = nextDetailedSnapshotRevision
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
        detailedViewSnapshotRevisions.removeAll()
        detailedViewReferences.removeAll()
        pendingLinkedTileSnapshots.removeAll()
        linkedTileAuthorityBrowserIDs.removeAll()
        nextDetailedSnapshotRevision = 0
        dismissPreview()
    }

    // MARK: - Detailed View (string-keyed)

    func viewModel(for reference: BrowserTabReference) -> BrowserPanelViewModel {
        let browserID = reference.browserID
        detailedViewReferences[browserID] = reference

        if let linkedTileID = reference.linkedTileID,
           let tileViewModel = groups[linkedTileID] {
            detailedViewGroups[browserID] = tileViewModel
            captureDetailedSnapshot(
                from: tileViewModel,
                browserID: browserID,
                fallbackURL: reference.seedURL
            )
            return tileViewModel
        }
        if let existing = detailedViewGroups[browserID] { return existing }

        let restoreSnapshot = detailedViewSessionSnapshots[browserID]
            ?? reference.linkedTileID.flatMap { pendingLinkedTileSnapshots[$0] }
        if let restoreSnapshot {
            let vm = makePersistentViewModel(projectPath: reference.projectPath)
            wireNewBrowserCallback(vm)
            vm.restoreSession(restoreSnapshot)
            detailedViewGroups[browserID] = vm
            captureDetailedSnapshot(from: vm, browserID: browserID)
            transferPreviewPresentationIfMatching(
                snapshot: restoreSnapshot,
                projectPath: reference.projectPath,
                to: vm
            )
            return vm
        }

        let url = reference.seedURL ?? URL(string: "about:blank")!
        let vm = makePersistentViewModel(
            initialURL: url.absoluteString == "about:blank" ? nil : url,
            projectPath: reference.projectPath
        )
        wireNewBrowserCallback(vm)
        detailedViewGroups[browserID] = vm
        captureDetailedSnapshot(from: vm, browserID: browserID, fallbackURL: url)
        return vm
    }

    func restoreDetailedBrowser(
        reference: BrowserTabReference,
        snapshot: BrowserSessionSnapshot?
    ) {
        detailedViewReferences[reference.browserID] = reference
        if let linkedTileID = reference.linkedTileID,
           let tileViewModel = groups[linkedTileID] {
            detailedViewGroups[reference.browserID] = tileViewModel
            captureDetailedSnapshot(
                from: tileViewModel,
                browserID: reference.browserID,
                fallbackURL: reference.seedURL
            )
            return
        }
        if let existing = detailedViewGroups[reference.browserID] {
            if let snapshot {
                existing.restoreSession(snapshot)
                transferPreviewPresentationIfMatching(
                    snapshot: snapshot,
                    projectPath: reference.projectPath,
                    to: existing
                )
            }
            captureDetailedSnapshot(
                from: existing,
                browserID: reference.browserID,
                fallbackURL: reference.seedURL
            )
            return
        }
        if let snapshot {
            let vm = makePersistentViewModel(projectPath: reference.projectPath)
            wireNewBrowserCallback(vm)
            vm.restoreSession(snapshot)
            detailedViewGroups[reference.browserID] = vm
            captureDetailedSnapshot(from: vm, browserID: reference.browserID)
            transferPreviewPresentationIfMatching(
                snapshot: snapshot,
                projectPath: reference.projectPath,
                to: vm
            )
            return
        }
        if let url = reference.seedURL {
            let vm = makePersistentViewModel(
                initialURL: url.absoluteString == "about:blank" ? nil : url,
                projectPath: reference.projectPath
            )
            wireNewBrowserCallback(vm)
            detailedViewGroups[reference.browserID] = vm
            captureDetailedSnapshot(from: vm, browserID: reference.browserID, fallbackURL: url)
        }
    }

    func snapshotDetailedBrowser(for reference: BrowserTabReference) -> BrowserSessionSnapshot? {
        detailedViewReferences[reference.browserID] = reference
        if let linkedTileID = reference.linkedTileID,
           let tileViewModel = groups[linkedTileID] {
            captureDetailedSnapshot(
                from: tileViewModel,
                browserID: reference.browserID,
                fallbackURL: reference.seedURL
            )
            return detailedViewSessionSnapshots[reference.browserID]
        }
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
        guard let url = reference.seedURL else { return nil }
        let snapshot = BrowserSessionSnapshot(urlString: url.absoluteString)
        detailedViewSessionSnapshots[reference.browserID] = snapshot
        return snapshot
    }

    func removeDetailedBrowser(browserID: UUID) {
        let reference = detailedViewReferences[browserID]
        let detailedViewModel = detailedViewGroups[browserID]
        if let linkedTileID = reference?.linkedTileID,
           groups[linkedTileID] == nil,
           let detailedViewModel {
            let remainingAuthorityID = orderedLinkedDetailedBrowserIDs(to: linkedTileID)
                .first(where: { $0 != browserID })
            if let remainingAuthorityID,
               let remainingViewModel = detailedViewGroups[remainingAuthorityID] {
                pendingLinkedTileSnapshots[linkedTileID] = remainingViewModel.sessionSnapshot()
            } else {
                pendingLinkedTileSnapshots[linkedTileID] = detailedViewModel.sessionSnapshot()
            }
            browserSessionDidChange.send()
        }
        detailedViewGroups.removeValue(forKey: browserID)
        detailedViewSessionSnapshots.removeValue(forKey: browserID)
        detailedViewSnapshotRevisions.removeValue(forKey: browserID)
        detailedViewReferences.removeValue(forKey: browserID)
        if let linkedTileID = reference?.linkedTileID,
           linkedTileAuthorityBrowserIDs[linkedTileID] == browserID {
            linkedTileAuthorityBrowserIDs.removeValue(forKey: linkedTileID)
        }
    }

    private func transferPreviewPresentationIfMatching(
        snapshot: BrowserSessionSnapshot,
        projectPath: String?,
        to destination: BrowserPanelViewModel
    ) {
        guard previewProjectPath == projectPath,
              let previewViewModel,
              previewViewModel.projectPath == projectPath,
              previewViewModel.sessionSnapshot() == snapshot else { return }
        previewViewModel.commentsPanel.transferPresentationState(to: destination.commentsPanel)
    }

    // MARK: - Floating Preview

    func showPreview(for url: URL, projectPath: String? = nil) {
        let vm = makePreviewViewModel(
            initialURL: url.absoluteString == "about:blank" ? nil : url,
            projectPath: projectPath
        )
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
           previewProjectPath == projectPath,
           existing.projectPath == projectPath,
           existing.sessionSnapshot() == snapshot {
            capturePreviewSnapshot(from: existing)
            return existing
        }

        let vm = makePreviewViewModel(projectPath: projectPath)
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

    func promotePreview(
        to tileID: UUID?,
        snapshot authoritativeSnapshot: BrowserSessionSnapshot? = nil
    ) {
        guard let tileID else {
            dismissPreview()
            return
        }
        let snapshot: BrowserSessionSnapshot
        if let authoritativeSnapshot {
            snapshot = authoritativeSnapshot
        } else if let previewViewModel {
            snapshot = previewViewModel.sessionSnapshot()
        } else if let previewSessionSnapshot {
            snapshot = previewSessionSnapshot
        } else {
            return
        }
        let sourcePreviewViewModel = previewViewModel
        let resolvedProjectPath = previewProjectPath ?? projectPathForTile?(tileID)
        let vm = makePersistentViewModel(projectPath: resolvedProjectPath)
        wireNewBrowserCallback(vm)
        vm.restoreSession(snapshot)
        sourcePreviewViewModel?.commentsPanel.transferPresentationState(to: vm.commentsPanel)
        groups[tileID] = vm
        publishPreviewURL(nil)
        previewSessionSnapshot = nil
        previewProjectPath = nil
        previewViewModel = nil
        browserSessionDidChange.send()
    }

    var hasPreview: Bool { previewViewModel != nil }

    // MARK: - Pinned Tile Groups

    /// Returns an already-owned canonical browser without creating a hidden host.
    func existingViewModel(for tileID: UUID) -> BrowserPanelViewModel? {
        groups[tileID] ?? linkedDetailedViewModel(to: tileID)
    }

    func viewModel(
        for tileID: UUID,
        url: URL,
        snapshot: BrowserSessionSnapshot? = nil
    ) -> BrowserPanelViewModel {
        if let existing = groups[tileID] { return existing }
        if let linkedViewModel = linkedDetailedViewModel(to: tileID) {
            wireNewBrowserCallback(linkedViewModel)
            groups[tileID] = linkedViewModel
            return linkedViewModel
        }
        let projectPath = projectPathForTile?(tileID)
        let vm = makePersistentViewModel(projectPath: projectPath)
        wireNewBrowserCallback(vm)
        if let restoreSnapshot = pendingLinkedTileSnapshots.removeValue(forKey: tileID) ?? snapshot {
            vm.restoreSession(restoreSnapshot)
        } else if url.absoluteString != "about:blank" {
            vm.navigate(to: url)
        }
        groups[tileID] = vm
        return vm
    }

    func restoreTile(id: UUID, snapshot: BrowserSessionSnapshot) {
        if groups[id] != nil { return }
        if let linkedViewModel = linkedDetailedViewModel(to: id) {
            wireNewBrowserCallback(linkedViewModel)
            groups[id] = linkedViewModel
            return
        }
        let projectPath = projectPathForTile?(id)
        let vm = makePersistentViewModel(projectPath: projectPath)
        wireNewBrowserCallback(vm)
        vm.restoreSession(pendingLinkedTileSnapshots.removeValue(forKey: id) ?? snapshot)
        groups[id] = vm
    }

    func removeViewModel(for tileID: UUID) {
        groups.removeValue(forKey: tileID)
        linkedTileAuthorityBrowserIDs.removeValue(forKey: tileID)
    }

    func snapshotBrowserSessions(for tileIDs: [UUID]) -> [UUID: BrowserSessionSnapshot] {
        var result: [UUID: BrowserSessionSnapshot] = [:]
        for tileID in tileIDs {
            if let vm = groups[tileID] {
                result[tileID] = vm.sessionSnapshot()
            } else if let linkedSnapshot = detailedSnapshotLinked(to: tileID) {
                result[tileID] = linkedSnapshot
            }
        }
        return result
    }

    func currentURLs(for tileIDs: [UUID]) -> [UUID: URL] {
        var result: [UUID: URL] = [:]
        for tileID in tileIDs {
            if let vm = groups[tileID] {
                if let url = vm.currentURL {
                    result[tileID] = url
                }
                continue
            }
            if let linkedSnapshot = detailedSnapshotLinked(to: tileID),
               let urlString = linkedSnapshot.urlString,
               let url = URL(string: urlString) {
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
        /// F012-R17: normalized path of the owning project, or nil for browsers
        /// without project ownership (preview-only, pre-restore).
        let projectPath: String?
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
                return BrowserTabInfo(id: id, title: title, url: url, projectPath: vm.projectPath)
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
                return BrowserTabInfo(id: id, title: title, url: url, projectPath: vm.projectPath)
            }
            return nil
        }
    }

    private func linkedDetailedViewModel(to tileID: UUID) -> BrowserPanelViewModel? {
        guard let browserID = orderedLinkedDetailedBrowserIDs(to: tileID).first,
              let viewModel = detailedViewGroups[browserID] else { return nil }
        linkedTileAuthorityBrowserIDs[tileID] = browserID
        return viewModel
    }

    private func convergeLinkedTileAuthority(for tileID: UUID) {
        guard let browserID = orderedLinkedDetailedBrowserIDs(to: tileID).first,
              let latestViewModel = detailedViewGroups[browserID] else { return }
        if let currentViewModel = groups[tileID], currentViewModel !== latestViewModel {
            currentViewModel.commentsPanel.transferPresentationState(to: latestViewModel.commentsPanel)
        }
        groups[tileID] = latestViewModel
        linkedTileAuthorityBrowserIDs[tileID] = browserID
    }

    private func orderedLinkedDetailedBrowserIDs(to tileID: UUID) -> [UUID] {
        detailedViewReferences.compactMap { browserID, reference in
            reference.linkedTileID == tileID ? browserID : nil
        }.sorted { lhs, rhs in
            let lhsRevision = detailedViewSnapshotRevisions[lhs] ?? 0
            let rhsRevision = detailedViewSnapshotRevisions[rhs] ?? 0
            if lhsRevision != rhsRevision { return lhsRevision > rhsRevision }
            if lhs == tileID { return true }
            if rhs == tileID { return false }
            return lhs.uuidString < rhs.uuidString
        }
    }

    private func detailedSnapshotLinked(to tileID: UUID) -> BrowserSessionSnapshot? {
        for browserID in orderedLinkedDetailedBrowserIDs(to: tileID) {
            guard let reference = detailedViewReferences[browserID] else { continue }
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
        return pendingLinkedTileSnapshots[tileID]
    }

    // MARK: - F012-R17/R18/R20: Project-Aware Lifecycle

    /// Returns true if any browser instance — board tile or detailed-view tab —
    /// is currently associated with the given normalized project path.
    func hasBrowsers(forProjectPath path: String) -> Bool {
        if groups.values.contains(where: { $0.projectPath == path }) { return true }
        if detailedViewGroups.values.contains(where: { $0.projectPath == path }) { return true }
        if detailedViewReferences.values.contains(where: { $0.projectPath == path }) { return true }
        return false
    }

    /// F012-R20: capture browser session entries for all browsers owned by the
    /// given project path. Used by the parking flow to persist browser state
    /// before tearing down the project's browsers.
    func snapshotBrowserSessions(forProjectPath path: String) -> [BrowserSessionEntry] {
        var entries: [BrowserSessionEntry] = []
        var seenIDs = Set<UUID>()

        // Detailed-view browsers (live VMs)
        for (browserID, vm) in detailedViewGroups where vm.projectPath == path {
            guard seenIDs.insert(browserID).inserted else { continue }
            let reference = detailedViewReferences[browserID]
            let snapshot = reference?.linkedTileID.flatMap { groups[$0]?.sessionSnapshot() }
                ?? vm.sessionSnapshot()
            entries.append(BrowserSessionEntry(
                browserID: browserID,
                snapshot: snapshot,
                pinnedTileID: reference?.linkedTileID
            ))
        }

        // Detailed-view references whose VMs aren't materialized yet
        for (browserID, reference) in detailedViewReferences
        where reference.projectPath == path && !seenIDs.contains(browserID) {
            let snapshot = reference.linkedTileID.flatMap { groups[$0]?.sessionSnapshot() }
                ?? detailedViewSessionSnapshots[browserID]
            if let snapshot {
                entries.append(BrowserSessionEntry(
                    browserID: browserID,
                    snapshot: snapshot,
                    pinnedTileID: reference.linkedTileID
                ))
                seenIDs.insert(browserID)
            }
        }

        // Board tiles
        for (tileID, vm) in groups where vm.projectPath == path {
            guard seenIDs.insert(tileID).inserted else { continue }
            entries.append(BrowserSessionEntry(
                browserID: tileID,
                snapshot: vm.sessionSnapshot(),
                pinnedTileID: tileID
            ))
        }

        return entries
    }

    /// F012-R18: enumerate all browsers owned by the given project path and
    /// dispatch close requests via the standard `.closeBrowserRequested`
    /// notification. Used by project-remove and project-park flows so the
    /// existing close-handling pipeline (which removes both board tiles and
    /// content-viewer tabs) drives teardown consistently.
    ///
    /// - Parameter path: normalized project path
    /// - Returns: the count of browsers that were dispatched for close
    @discardableResult
    func closeBrowsers(forProjectPath path: String) -> Int {
        // Collect IDs first to avoid mutation during enumeration.
        var browserIDs: [UUID] = []

        for (tileID, vm) in groups where vm.projectPath == path {
            browserIDs.append(tileID)
        }
        for (browserID, vm) in detailedViewGroups
        where vm.projectPath == path && !browserIDs.contains(browserID) {
            browserIDs.append(browserID)
        }
        for (browserID, reference) in detailedViewReferences
        where reference.projectPath == path && !browserIDs.contains(browserID) {
            browserIDs.append(browserID)
        }

        for browserID in browserIDs {
            NotificationCenter.default.post(
                name: .closeBrowserRequested,
                object: nil,
                userInfo: ["browserID": browserID]
            )
        }
        return browserIDs.count
    }
}


@MainActor
struct BrowserGlobalTeardownResult: Equatable {
    let removedBoardPresentation: Bool
    let closedContentTabCount: Int
}

@MainActor
enum BrowserGlobalTeardownCoordinator {
    static func referenceMatches(_ reference: BrowserTabReference, requestedID: UUID) -> Bool {
        reference.browserID == requestedID || reference.linkedTileID == requestedID
    }

    static func matchingTabs(
        requestedID: UUID,
        editorGroups: [UUID: EditorGroupStore]
    ) -> [(group: EditorGroupStore, tab: ContentViewerTab)] {
        var seenTargets = Set<String>()
        return editorGroups
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap { _, group in
                group.tabs.compactMap { tab -> (EditorGroupStore, ContentViewerTab)? in
                    guard case let .webPage(reference) = tab.kind,
                          referenceMatches(reference, requestedID: requestedID) else {
                        return nil
                    }
                    let targetKey = "\(group.id.uuidString)|\(tab.id)"
                    guard seenTargets.insert(targetKey).inserted else { return nil }
                    return (group, tab)
                }
            }
    }

    @discardableResult
    static func teardown(
        requestedID: UUID,
        boardStore: VibeSpaceTerminalBoardStore,
        splitViewStore: SplitViewStore,
        dockedBrowserCoordinator: DockedBrowserCoordinator
    ) -> BrowserGlobalTeardownResult {
        let targets = matchingTabs(
            requestedID: requestedID,
            editorGroups: splitViewStore.editorGroups
        )

        var removedBoardPresentation = false
        if let surfaceID = boardStore.surfaceID(containing: requestedID) {
            boardStore.removeTile(requestedID, surfaceID: surfaceID)
            removedBoardPresentation = true
        }

        for target in targets {
            guard let currentTab = target.group.tabs.first(where: { $0.id == target.tab.id }),
                  currentTab == target.tab else { continue }
            splitViewStore.closeTab(currentTab, in: target.group)
        }

        dockedBrowserCoordinator.removeViewModel(for: requestedID)
        dockedBrowserCoordinator.removeDetailedBrowser(browserID: requestedID)
        return BrowserGlobalTeardownResult(
            removedBoardPresentation: removedBoardPresentation,
            closedContentTabCount: targets.count
        )
    }
}
