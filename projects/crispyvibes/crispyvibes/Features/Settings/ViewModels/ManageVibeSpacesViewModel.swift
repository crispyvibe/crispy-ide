import Foundation

/// View model backing the VibeSpaces panel of the App Settings window.
///
/// Lists every vibespace currently on disk (recent + non-recent), supports
/// multi-select, bulk delete, search, and double-click-to-open. Heavy work
/// (loading each vibespace's config from disk) is batched with `Task.yield()`
/// between batches so the runloop has time to draw and stays responsive on
/// large libraries.
@MainActor
final class ManageVibeSpacesViewModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let name: String
        let projectPaths: [String]
        let isRecent: Bool
        let config: VibeSpaceConfigFile

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.id == rhs.id
                && lhs.name == rhs.name
                && lhs.projectPaths == rhs.projectPaths
                && lhs.isRecent == rhs.isRecent
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading: Bool = false
    @Published var selection: Set<UUID> = []
    @Published var searchQuery: String = ""

    /// Entries filtered by `searchQuery`. Empty query returns everything.
    var filteredEntries: [Entry] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { entry in
            if entry.name.localizedCaseInsensitiveContains(trimmed) { return true }
            for path in entry.projectPaths
            where path.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            return false
        }
    }

    /// Test hook: when `true`, `load()` runs synchronously without yielding
    /// (used by unit tests so they can observe the final state immediately).
    /// Production keeps `false`.
    var loadSynchronouslyForTesting: Bool = false

    private let vibespaceManagement: VibeSpaceManaging
    private let onOpenVibeSpace: (VibeSpaceConfigFile) -> Void
    private let onDeleteVibeSpaces: (Set<UUID>) -> Void
    private let batchSize: Int
    private var loadGeneration: Int = 0
    private var loadTask: Task<Void, Never>?

    init(
        vibespaceManagement: VibeSpaceManaging,
        onOpenVibeSpace: @escaping (VibeSpaceConfigFile) -> Void,
        onDeleteVibeSpaces: @escaping (Set<UUID>) -> Void,
        batchSize: Int = 25
    ) {
        self.vibespaceManagement = vibespaceManagement
        self.onOpenVibeSpace = onOpenVibeSpace
        self.onDeleteVibeSpaces = onDeleteVibeSpaces
        self.batchSize = batchSize
        load()
    }

    /// Loads (or reloads) the entry list.
    ///
    /// Reads of refs and recent IDs are cheap and synchronous; the per-vibespace
    /// config loads are batched with `Task.yield()` between batches so the
    /// runloop redraws between chunks rather than blocking until completion.
    func load() {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration

        let recentIDsOrdered = vibespaceManagement.recentVibeSpaceIDs()
        let recentOrder: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: recentIDsOrdered.enumerated().map { ($1, $0) }
        )

        let refs = vibespaceManagement.vibespaceRefs()
        let orderedIDs = refs
            .map(\.id)
            .sorted { lhs, rhs in
                switch (recentOrder[lhs], recentOrder[rhs]) {
                case let (lhsIndex?, rhsIndex?):
                    return lhsIndex < rhsIndex
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    let lhsName = refs.first(where: { $0.id == lhs })?.name ?? ""
                    let rhsName = refs.first(where: { $0.id == rhs })?.name ?? ""
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
            }

        entries = []
        isLoading = !orderedIDs.isEmpty

        guard !orderedIDs.isEmpty else { return }

        if loadSynchronouslyForTesting {
            populateSynchronously(orderedIDs: orderedIDs, recentOrder: recentOrder)
            isLoading = false
            return
        }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var index = 0
            while index < orderedIDs.count {
                if Task.isCancelled || generation != self.loadGeneration { return }
                let upper = min(index + self.batchSize, orderedIDs.count)
                let batch = Array(orderedIDs[index ..< upper])
                let loaded = self.loadEntries(for: batch, recentOrder: recentOrder)
                self.entries.append(contentsOf: loaded)
                index = upper
                if index < orderedIDs.count {
                    await Task.yield()
                }
            }
            if generation == self.loadGeneration {
                self.isLoading = false
            }
        }
    }

    private func populateSynchronously(orderedIDs: [UUID], recentOrder: [UUID: Int]) {
        entries = loadEntries(for: orderedIDs, recentOrder: recentOrder)
    }

    private func loadEntries(for ids: [UUID], recentOrder: [UUID: Int]) -> [Entry] {
        var result: [Entry] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            guard let load = vibespaceManagement.loadVibeSpace(id: id) else { continue }
            let config = load.config
            let allPaths = config.projectPaths + config.unresolvedProjectPaths
            result.append(
                Entry(
                    id: id,
                    name: config.name,
                    projectPaths: allPaths,
                    isRecent: recentOrder[id] != nil,
                    config: config
                )
            )
        }
        return result
    }

    func open(_ entry: Entry) {
        onOpenVibeSpace(entry.config)
    }

    func openSelected() {
        guard selection.count == 1,
              let id = selection.first,
              let entry = entries.first(where: { $0.id == id }) else { return }
        open(entry)
    }

    /// Deletes every selected vibespace via the coordinator hook and clears
    /// the selection. The hook is responsible for closing any active session
    /// that maps to a deleted ID.
    func deleteSelected() {
        deleteIDs(selection)
    }

    /// Bulk-delete arbitrary IDs via the coordinator hook. Removes any of
    /// those IDs from the current selection and reloads.
    func deleteIDs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        onDeleteVibeSpaces(ids)
        selection.subtract(ids)
        load()
    }
}
