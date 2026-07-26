import CryptoKit
import Foundation
import OSLog

// F059 — persistence contracts for Vibes, Vibe Lanes, and tasks. Production
// uses the encrypted Automation database. Synchronous stores remain only for
// deterministic tests and one-time legacy JSON migration.

/// Identifies one immutable lane content revision (a lane id at a specific
/// content `version`). Used to retain the exact revision a task pinned.
struct VibeLaneRevisionKey: Hashable, Sendable {
    let laneID: UUID
    let version: Int
}

struct VibeLanePersistenceSnapshot: Sendable {
    var lanes: [VibeLaneDefinition]
    var laneRevisions: [VibeLaneDefinition]
    var laneTombstones: Set<UUID>
    var vibes: [VibeDefinition]
    var vibeRevisions: [VibeDefinition]
    var tasks: [VibeLaneTask]
}

enum VibeLanePersistenceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): detail
        }
    }
}

@MainActor
protocol VibeLanePersisting: AnyObject {
    func loadPersistenceSnapshot() async throws -> VibeLanePersistenceSnapshot
    func reconcileStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot
    func restoreStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot
    func persistCurrentLane(_ lane: VibeLaneDefinition) async throws
    func removeCurrentLane(id: UUID, tombstone: Bool) async throws
    func persistCurrentVibe(_ vibe: VibeDefinition) async throws
    func removeCurrentVibe(id: UUID) async throws
    func persistTask(_ task: VibeLaneTask) async throws
    func removeTask(id: UUID) async throws
}

/// Synchronous stores are retained for deterministic unit tests and as strict
/// legacy JSON readers. Production composition uses `AutomationDatabaseStore`.
protocol VibeLaneStoring: VibeLanePersisting {
    func loadLanes() -> [VibeLaneDefinition]
    func loadVibes() -> [VibeDefinition]
    func loadTasks() -> [VibeLaneTask]
    @discardableResult func saveTask(_ task: VibeLaneTask) -> Bool
    func deleteTask(id: UUID)
    func saveLane(_ lane: VibeLaneDefinition)
    func deleteLane(id: UUID)
    func saveVibe(_ vibe: VibeDefinition)
    func deleteVibe(id: UUID)
    func vibeRevision(id: UUID, version: Int) -> VibeDefinition?
    @discardableResult func archiveVibeRevision(_ vibe: VibeDefinition) -> Bool

    /// Reconcile the shipped starter catalog with the stored lanes: seed on
    /// first run, auto-refresh pristine (never user-edited) starter lanes when
    /// the shipped content improves, add newly shipped starters, and honor
    /// user deletions via tombstones. User-owned lanes are never touched.
    func reconcileStarterLanes()
    /// Clear starter tombstones and re-add/refresh starters (explicit user
    /// action). User-edited copies of starter lanes are still never overwritten.
    func restoreStarterLanes()

    /// Fetch a retained historical lane revision by id + content version, or nil.
    /// Lets a task resolve the exact lane it pinned after that lane is edited/deleted.
    func laneRevision(id: UUID, version: Int) -> VibeLaneDefinition?
    /// Retain a lane revision so tasks pinned to it keep resolving after the lane
    /// is edited or deleted. Owned by the store — never copied onto the task.
    @discardableResult func archiveLaneRevision(_ lane: VibeLaneDefinition) -> Bool
    /// Drop retained revisions whose key is not in `keep` (e.g. after task deletes).
    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>)
}

extension VibeLaneStoring {
    func loadPersistenceSnapshot() async throws -> VibeLanePersistenceSnapshot {
        let lanes = loadLanes()
        let vibes = loadVibes()
        let tasks = loadTasks()
        let laneRevisions = tasks.compactMap {
            laneRevision(id: $0.laneID, version: $0.laneVersion)
        }
        let allLanes = lanes + laneRevisions
        let vibeRevisions = allLanes
            .flatMap(\.checkpoints)
            .compactMap { checkpoint -> VibeDefinition? in
                guard let id = checkpoint.vibeID, let version = checkpoint.vibeVersion else {
                    return nil
                }
                if vibes.contains(where: { $0.id == id && $0.version == version }) {
                    return nil
                }
                return vibeRevision(id: id, version: version)
            }
        return VibeLanePersistenceSnapshot(
            lanes: lanes,
            laneRevisions: uniqueLaneRevisions(laneRevisions),
            laneTombstones: [],
            vibes: vibes,
            vibeRevisions: uniqueVibeRevisions(vibeRevisions),
            tasks: tasks
        )
    }

    func reconcileStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot {
        reconcileStarterLanes()
        return try await loadPersistenceSnapshot()
    }

    func restoreStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot {
        restoreStarterLanes()
        return try await loadPersistenceSnapshot()
    }

    func persistCurrentLane(_ lane: VibeLaneDefinition) async throws {
        if let current = loadLanes().first(where: { $0.id == lane.id }),
           current.version != lane.version,
           !archiveLaneRevision(current) {
            throw VibeLanePersistenceError.unavailable("Could not retain the outgoing Vibe Lane revision.")
        }
        saveLane(lane)
    }

    func removeCurrentLane(id: UUID, tombstone: Bool) async throws {
        _ = tombstone
        deleteLane(id: id)
    }

    func persistCurrentVibe(_ vibe: VibeDefinition) async throws {
        if let current = loadVibes().first(where: { $0.id == vibe.id }),
           current.version != vibe.version,
           !archiveVibeRevision(current) {
            throw VibeLanePersistenceError.unavailable("Could not retain the outgoing Vibe revision.")
        }
        saveVibe(vibe)
    }

    func removeCurrentVibe(id: UUID) async throws {
        deleteVibe(id: id)
    }

    func persistTask(_ task: VibeLaneTask) async throws {
        guard saveTask(task) else {
            throw VibeLanePersistenceError.unavailable("Could not persist the Vibe Lane task.")
        }
    }

    func removeTask(id: UUID) async throws {
        deleteTask(id: id)
    }

    private func uniqueLaneRevisions(
        _ revisions: [VibeLaneDefinition]
    ) -> [VibeLaneDefinition] {
        Array(Dictionary(
            revisions.map { (VibeLaneRevisionKey(laneID: $0.id, version: $0.version), $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values)
    }

    private func uniqueVibeRevisions(
        _ revisions: [VibeDefinition]
    ) -> [VibeDefinition] {
        Array(Dictionary(
            revisions.map { (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values)
    }
}

// MARK: - Starter reconciliation

/// Pure reconciliation of the shipped starter catalog against stored lanes.
/// Kept side-effect free so both stores share it and tests can drive it directly.
enum VibeLaneStarterReconciler {

    /// Stable content fingerprint of a lane (version and seed marker excluded, so
    /// the same authored content always hashes identically).
    static func fingerprint(of lane: VibeLaneDefinition) -> String {
        var normalized = lane
        normalized.version = 0
        normalized.seededFingerprint = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A stored starter lane is pristine when the user never saved an edit:
    /// a seed marker is cleared on every authored save. Exact fingerprints are
    /// allowed to drift across representation-only migrations such as embedded
    /// checkpoints to Vibes, so marker presence remains the ownership signal.
    static func isPristine(_ lane: VibeLaneDefinition) -> Bool {
        if lane.seededFingerprint != nil {
            return true
        }
        return lane.version == 1
    }

    struct Outcome {
        var lanes: [VibeLaneDefinition]
        var changed: Bool
    }

    /// Merge `catalog` into `stored`. Pristine starters whose shipped content
    /// changed are replaced in place (version bumped so retained revisions stay
    /// distinct); missing starters are added unless tombstoned; user-owned lanes
    /// pass through untouched.
    static func reconcile(
        stored: [VibeLaneDefinition],
        catalog: [VibeLaneDefinition],
        tombstones: Set<UUID>
    ) -> Outcome {
        var lanes = stored
        var changed = false
        for shipped in catalog {
            let shippedFingerprint = fingerprint(of: shipped)
            if let idx = lanes.firstIndex(where: { $0.id == shipped.id }) {
                let existing = lanes[idx]
                guard isPristine(existing), fingerprint(of: existing) != shippedFingerprint else { continue }
                var refreshed = shipped
                refreshed.version = existing.version + 1
                refreshed.seededFingerprint = shippedFingerprint
                lanes[idx] = refreshed
                changed = true
            } else if !tombstones.contains(shipped.id) {
                var added = shipped
                added.seededFingerprint = shippedFingerprint
                lanes.append(added)
                changed = true
            }
        }
        return Outcome(lanes: lanes, changed: changed)
    }

    /// Finds current Vibes that only survive because an older starter revision
    /// referenced them. Active catalog Vibes and every Vibe used by a current
    /// lane are protected.
    static func supersededVibeIDs(
        currentVibes: [VibeDefinition],
        previousLanes: [VibeLaneDefinition],
        currentLanes: [VibeLaneDefinition],
        laneRevisions: [VibeLaneDefinition],
        catalogLanes: [VibeLaneDefinition],
        catalogVibes: [VibeDefinition]
    ) -> Set<UUID> {
        let catalogLaneIDs = Set(catalogLanes.map(\.id))
        let catalogVibeIDs = Set(catalogVibes.map(\.id))
        let currentLaneVibeIDs = Set(
            currentLanes.flatMap(\.checkpoints).compactMap(\.vibeID)
        )
        let currentStarterLanes = Dictionary(
            uniqueKeysWithValues: currentLanes
                .filter { catalogLaneIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let unusedCatalogCopies = Set(
            catalogLanes.flatMap { catalogLane in
                catalogLane.checkpoints.compactMap { checkpoint -> UUID? in
                    guard let catalogVibeID = checkpoint.vibeID,
                          let currentLane = currentStarterLanes[catalogLane.id],
                          !currentLaneVibeIDs.contains(catalogVibeID),
                          currentLane.checkpoints.contains(where: {
                              semanticKey($0) == semanticKey(checkpoint)
                          }) else {
                        return nil
                    }
                    return catalogVibeID
                }
            }
        )
        let protectedCatalogIDs = catalogVibeIDs.subtracting(unusedCatalogCopies)
        let protectedIDs = protectedCatalogIDs.union(currentLaneVibeIDs)
        let currentVibeIDs = Set(currentVibes.map(\.id))
        let currentLanesByID = Dictionary(
            uniqueKeysWithValues: currentLanes.map { ($0.id, $0) }
        )

        var candidates = Set<UUID>()
        for previous in previousLanes where catalogLaneIDs.contains(previous.id) {
            guard let current = currentLanesByID[previous.id], current != previous else {
                continue
            }
            candidates.formUnion(previous.checkpoints.compactMap(\.vibeID))
        }

        let historicalStarterVibes = Set(
            laneRevisions
                .filter { catalogLaneIDs.contains($0.id) }
                .flatMap(\.checkpoints)
                .compactMap { checkpoint -> VibeRevisionKey? in
                    guard let id = checkpoint.vibeID,
                          let version = checkpoint.vibeVersion else {
                        return nil
                    }
                    return VibeRevisionKey(vibeID: id, version: version)
                }
        )
        let activeSemantics = Set(catalogVibes.map(semanticKey))
        candidates.formUnion(
            currentVibes.compactMap { vibe -> UUID? in
                let revision = VibeRevisionKey(vibeID: vibe.id, version: vibe.version)
                guard historicalStarterVibes.contains(revision),
                      activeSemantics.contains(semanticKey(vibe)) else {
                    return nil
                }
                return vibe.id
            }
        )
        candidates.formUnion(
            currentVibes.compactMap { vibe in
                guard activeSemantics.contains(semanticKey(vibe)),
                      isStarterDerived(vibe, catalogLanes: catalogLanes) else {
                    return nil
                }
                return vibe.id
            }
        )

        return candidates
            .intersection(currentVibeIDs)
            .subtracting(protectedIDs)
    }

    private struct VibeSemanticKey: Hashable {
        var name: String
        var goal: String
    }

    private static func semanticKey(_ vibe: VibeDefinition) -> VibeSemanticKey {
        VibeSemanticKey(
            name: normalized(vibe.name),
            goal: normalized(vibe.work.goal)
        )
    }

    private static func semanticKey(_ checkpoint: VibeLaneCheckpoint) -> VibeSemanticKey {
        VibeSemanticKey(
            name: normalized(checkpoint.displayTitle),
            goal: normalized(checkpoint.work.goal)
        )
    }

    private static func isStarterDerived(
        _ vibe: VibeDefinition,
        catalogLanes: [VibeLaneDefinition]
    ) -> Bool {
        for lane in catalogLanes {
            for (index, checkpoint) in lane.checkpoints.enumerated()
            where semanticKey(checkpoint) == semanticKey(vibe) {
                var source = checkpoint
                source.vibeID = nil
                source.vibeVersion = nil
                source.title = vibe.name
                source.work = vibe.work
                source.verify = vibe.verify
                source.bounds = vibe.bounds
                source.engine = vibe.engine
                if VibeLaneReferenceResolver.migratedID(
                    lane: lane,
                    checkpoint: source,
                    index: index
                ) == vibe.id {
                    return true
                }
            }
        }
        return false
    }

    private static func normalized(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

/// In-memory store for tests and previews.
final class InMemoryVibeLaneStore: VibeLaneStoring {
    private var lanes: [UUID: VibeLaneDefinition]
    private var vibes: [UUID: VibeDefinition]
    private var vibeRevisions: [VibeRevisionKey: VibeDefinition]
    private var tasks: [UUID: VibeLaneTask]
    private var revisions: [VibeLaneRevisionKey: VibeLaneDefinition] = [:]
    private let catalog: [VibeLaneDefinition]
    private var tombstones: Set<UUID> = []
    var shouldFailTaskSaves = false
    var shouldFailTaskDeletes = false
    var shouldFailLaneSaves = false
    var shouldFailVibeSaves = false
    var shouldFailRevisionArchives = false
    var shouldFailVibeRevisionArchives = false

    init(
        lanes: [VibeLaneDefinition] = [],
        vibes: [VibeDefinition] = [],
        vibeRevisions: [VibeDefinition] = [],
        tasks: [VibeLaneTask] = [],
        catalog: [VibeLaneDefinition] = []
    ) {
        let state = VibeLaneReferenceResolver.resolve(
            lanes: lanes + catalog,
            vibes: vibes,
            revisions: vibeRevisions
        )
        let storedLanes = Array(state.lanes.prefix(lanes.count))
        let storedCatalog = Array(state.lanes.dropFirst(lanes.count))
        self.lanes = Dictionary(uniqueKeysWithValues: storedLanes.map { ($0.id, $0) })
        self.vibes = Dictionary(uniqueKeysWithValues: state.vibes.map { ($0.id, $0) })
        self.vibeRevisions = Dictionary(
            uniqueKeysWithValues: state.revisions.map {
                (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
            }
        )
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        self.catalog = storedCatalog
    }

    func loadLanes() -> [VibeLaneDefinition] {
        VibeLaneReferenceResolver.resolve(
            lanes: Array(lanes.values),
            vibes: Array(vibes.values),
            revisions: Array(vibeRevisions.values)
        ).lanes
    }
    func loadVibes() -> [VibeDefinition] { Array(vibes.values) }
    func loadTasks() -> [VibeLaneTask] { Array(tasks.values) }
    func saveTask(_ task: VibeLaneTask) -> Bool {
        guard !shouldFailTaskSaves else { return false }
        tasks[task.id] = task
        return true
    }

    func persistTask(_ task: VibeLaneTask) async throws {
        let key = VibeLaneRevisionKey(
            laneID: task.laneID,
            version: task.laneVersion
        )
        let hasExactLane = lanes.values.contains {
            $0.id == key.laneID && $0.version == key.version
        } || revisions[key] != nil
        guard hasExactLane, saveTask(task) else {
            throw VibeLanePersistenceError.unavailable(
                "Could not persist the Vibe Lane task and its exact Lane revision."
            )
        }
    }

    func deleteTask(id: UUID) { tasks[id] = nil }

    func removeTask(id: UUID) async throws {
        guard !shouldFailTaskDeletes else {
            throw VibeLanePersistenceError.unavailable("Could not delete the Vibe Lane task.")
        }
        deleteTask(id: id)
    }
    func saveLane(_ lane: VibeLaneDefinition) {
        let state = VibeLaneReferenceResolver.resolve(
            lanes: [lane],
            vibes: Array(vibes.values),
            revisions: Array(vibeRevisions.values)
        )
        lanes[lane.id] = state.lanes[0]
        vibes = Dictionary(uniqueKeysWithValues: state.vibes.map { ($0.id, $0) })
        vibeRevisions = Dictionary(
            uniqueKeysWithValues: state.revisions.map {
                (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
            }
        )
    }
    func deleteLane(id: UUID) {
        lanes[id] = nil
        if catalog.contains(where: { $0.id == id }) { tombstones.insert(id) }
    }
    func saveVibe(_ vibe: VibeDefinition) { vibes[vibe.id] = vibe }
    func deleteVibe(id: UUID) { vibes[id] = nil }
    func vibeRevision(id: UUID, version: Int) -> VibeDefinition? {
        vibeRevisions[VibeRevisionKey(vibeID: id, version: version)]
    }
    func archiveVibeRevision(_ vibe: VibeDefinition) -> Bool {
        guard !shouldFailVibeRevisionArchives else { return false }
        vibeRevisions[VibeRevisionKey(vibeID: vibe.id, version: vibe.version)] = vibe
        return true
    }

    func persistCurrentLane(_ lane: VibeLaneDefinition) async throws {
        guard !shouldFailLaneSaves else {
            throw VibeLanePersistenceError.unavailable(
                "Could not persist the Vibe Lane."
            )
        }
        if let current = loadLanes().first(where: { $0.id == lane.id }),
           current.version != lane.version,
           !archiveLaneRevision(current) {
            throw VibeLanePersistenceError.unavailable(
                "Could not retain the outgoing Vibe Lane revision."
            )
        }
        saveLane(lane)
    }

    func persistCurrentVibe(_ vibe: VibeDefinition) async throws {
        guard !shouldFailVibeSaves else {
            throw VibeLanePersistenceError.unavailable(
                "Could not persist the Vibe."
            )
        }
        if let current = loadVibes().first(where: { $0.id == vibe.id }),
           current.version != vibe.version,
           !archiveVibeRevision(current) {
            throw VibeLanePersistenceError.unavailable(
                "Could not retain the outgoing Vibe revision."
            )
        }
        saveVibe(vibe)
    }

    func reconcileStarterLanes() {
        let previousLanes = Array(lanes.values)
        let currentVibes = Array(vibes.values)
        let catalogState = VibeLaneReferenceResolver.resolve(lanes: catalog, vibes: [])
        let outcome = VibeLaneStarterReconciler.reconcile(
            stored: previousLanes,
            catalog: catalogState.lanes,
            tombstones: tombstones
        )
        let supersededVibeIDs = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: currentVibes,
            previousLanes: previousLanes,
            currentLanes: outcome.lanes,
            laneRevisions: Array(revisions.values),
            catalogLanes: catalogState.lanes,
            catalogVibes: catalogState.vibes
        )
        if outcome.changed {
            lanes = Dictionary(uniqueKeysWithValues: outcome.lanes.map { ($0.id, $0) })
        }
        for id in supersededVibeIDs {
            guard let vibe = vibes.removeValue(forKey: id) else { continue }
            vibeRevisions[VibeRevisionKey(vibeID: vibe.id, version: vibe.version)] = vibe
        }
    }

    func restoreStarterLanes() {
        tombstones.removeAll()
        reconcileStarterLanes()
    }

    func laneRevision(id: UUID, version: Int) -> VibeLaneDefinition? {
        revisions[VibeLaneRevisionKey(laneID: id, version: version)]
    }
    func archiveLaneRevision(_ lane: VibeLaneDefinition) -> Bool {
        guard !shouldFailRevisionArchives else { return false }
        revisions[VibeLaneRevisionKey(laneID: lane.id, version: lane.version)] = lane
        return true
    }
    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>) {
        revisions = revisions.filter { keep.contains($0.key) }
    }
}

/// Strict legacy JSON reader/writer used by migration tests and the one-time
/// importer. Production does not compose this store or dual-write these files.
final class FileVibeLaneStore: VibeLaneStoring {
    private let directory: URL
    private let catalog: [VibeLaneDefinition]
    private let catalogVibes: [VibeDefinition]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app", category: "vibelanes")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL, catalog: [VibeLaneDefinition]) {
        self.directory = directory
        let catalogState = VibeLaneReferenceResolver.resolve(lanes: catalog, vibes: [])
        self.catalog = catalogState.lanes
        self.catalogVibes = catalogState.vibes
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var tasksURL: URL { directory.appendingPathComponent("tasks.json") }
    private var lanesURL: URL { directory.appendingPathComponent("lanes.json") }
    private var revisionsURL: URL { directory.appendingPathComponent("lane-revisions.json") }
    private var vibesURL: URL { directory.appendingPathComponent("vibes.json") }
    private var vibeRevisionsURL: URL { directory.appendingPathComponent("vibe-revisions.json") }
    private var tombstonesURL: URL { directory.appendingPathComponent("lane-tombstones.json") }

    func loadLanes() -> [VibeLaneDefinition] {
        // File missing → first run (reconcileStarterLanes seeds it); returning the
        // catalog keeps reads sane if a read races the seed.
        // File present (even if it decodes to an empty array) → the user's
        // intentional state wins; starter deletions stay durable via tombstones.
        guard let data = try? Data(contentsOf: lanesURL) else { return catalog }
        do {
            let vibes = loadVibesFromDisk()
            let vibeRevisions = loadVibeRevisionsFromDisk()
            if let stored = try? decoder.decode([StoredVibeLaneDefinition].self, from: data) {
                return stored.map { $0.resolved(current: vibes, revisions: vibeRevisions) }
            }
            let legacy = try decoder.decode([VibeLaneDefinition].self, from: data)
            let state = VibeLaneReferenceResolver.resolve(
                lanes: legacy,
                vibes: vibes,
                revisions: vibeRevisions
            )
            persistVibes(state.vibes)
            _ = persistVibeRevisions(state.revisions)
            persistLanes(state.lanes)
            return state.lanes
        } catch {
            logger.warning("vibelane lanes decode failed: \(error.localizedDescription, privacy: .public)")
            return catalog
        }
    }

    func saveLane(_ lane: VibeLaneDefinition) {
        var all = loadLanes().filter { $0.id != lane.id }
        let state = VibeLaneReferenceResolver.resolve(
            lanes: [lane],
            vibes: loadVibesFromDisk(),
            revisions: loadVibeRevisionsFromDisk()
        )
        all.append(state.lanes[0])
        persistVibes(state.vibes)
        _ = persistVibeRevisions(state.revisions)
        persistLanes(all)
    }

    func deleteLane(id: UUID) {
        let all = loadLanes().filter { $0.id != id }
        persistLanes(all)
        if catalog.contains(where: { $0.id == id }) {
            var stones = loadTombstones()
            stones.insert(id)
            persistTombstones(stones)
        }
    }

    func reconcileStarterLanes() {
        guard FileManager.default.fileExists(atPath: lanesURL.path) else {
            // First run: seed the catalog with seed fingerprints so future
            // shipped improvements can tell pristine lanes from edited ones.
            let seeded = catalog.map { lane -> VibeLaneDefinition in
                var copy = lane
                copy.seededFingerprint = VibeLaneStarterReconciler.fingerprint(of: lane)
                return copy
            }
            persistVibes(catalogVibes)
            persistLanes(seeded)
            return
        }
        let previousLanes = loadLanes()
        let currentVibes = loadVibesFromDisk()
        let vibeRevisions = loadVibeRevisionsFromDisk()
        let outcome = VibeLaneStarterReconciler.reconcile(
            stored: previousLanes,
            catalog: catalog,
            tombstones: loadTombstones()
        )
        let state = VibeLaneReferenceResolver.resolve(
            lanes: outcome.lanes,
            vibes: uniqueCurrentVibes(currentVibes + catalogVibes),
            revisions: vibeRevisions
        )
        let supersededVibeIDs = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: currentVibes,
            previousLanes: previousLanes,
            currentLanes: state.lanes,
            laneRevisions: loadRevisions(),
            catalogLanes: catalog,
            catalogVibes: catalogVibes
        )
        guard outcome.changed || !supersededVibeIDs.isEmpty else { return }

        let supersededVibes = currentVibes.filter {
            supersededVibeIDs.contains($0.id)
        }
        persistVibes(uniqueCurrentVibes(state.vibes).filter {
            !supersededVibeIDs.contains($0.id)
        })
        _ = persistVibeRevisions(state.revisions + supersededVibes)
        persistLanes(state.lanes)
    }

    func restoreStarterLanes() {
        persistTombstones([])
        reconcileStarterLanes()
    }

    private func loadTombstones() -> Set<UUID> {
        guard let data = try? Data(contentsOf: tombstonesURL) else { return [] }
        return (try? decoder.decode(Set<UUID>.self, from: data)) ?? []
    }

    private func persistTombstones(_ stones: Set<UUID>) {
        do {
            let data = try encoder.encode(stones)
            let tmp = tombstonesURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: tombstonesURL, with: tmp)
        } catch {
            logger.error("vibelane tombstones persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistLanes(_ lanes: [VibeLaneDefinition]) {
        do {
            let stored = lanes.compactMap(StoredVibeLaneDefinition.init)
            guard stored.count == lanes.count else {
                logger.error("vibelane lane persist refused: unresolved Vibe reference")
                return
            }
            let data = try encoder.encode(stored)
            let tmp = lanesURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: lanesURL, with: tmp)
        } catch {
            logger.error("vibelane lanes persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Vibes

    func loadVibes() -> [VibeDefinition] {
        loadVibesFromDisk()
    }

    func saveVibe(_ vibe: VibeDefinition) {
        var all = loadVibesFromDisk().filter { $0.id != vibe.id }
        all.append(vibe)
        persistVibes(all)
    }

    func deleteVibe(id: UUID) {
        persistVibes(loadVibesFromDisk().filter { $0.id != id })
    }

    func vibeRevision(id: UUID, version: Int) -> VibeDefinition? {
        loadVibeRevisionsFromDisk().first { $0.id == id && $0.version == version }
    }

    func archiveVibeRevision(_ vibe: VibeDefinition) -> Bool {
        var all = loadVibeRevisionsFromDisk().filter {
            !($0.id == vibe.id && $0.version == vibe.version)
        }
        all.append(vibe)
        return persistVibeRevisions(all)
    }

    private func loadVibesFromDisk() -> [VibeDefinition] {
        guard let data = try? Data(contentsOf: vibesURL) else { return catalogVibes }
        do {
            let decoded = try decodeVibesAndCategoryPresence(from: data)
            var vibes = decoded.vibes
            if decoded.missingCategoryIndices.isEmpty {
                return vibes
            }
            let catalogByID = Dictionary(uniqueKeysWithValues: catalogVibes.map { ($0.id, $0) })
            for index in decoded.missingCategoryIndices {
                vibes[index].category = catalogByID[vibes[index].id]?.category ?? .general
            }
            persistVibes(vibes)
            return vibes
        } catch {
            logger.warning("vibelane vibes decode failed: \(error.localizedDescription, privacy: .public)")
            return catalogVibes
        }
    }

    private func persistVibes(_ vibes: [VibeDefinition]) {
        do {
            let data = try encoder.encode(uniqueCurrentVibes(vibes))
            let tmp = vibesURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: vibesURL, with: tmp)
        } catch {
            logger.error("vibelane vibes persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadVibeRevisionsFromDisk() -> [VibeDefinition] {
        guard let data = try? Data(contentsOf: vibeRevisionsURL) else { return [] }
        do {
            let decoded = try decodeVibesAndCategoryPresence(from: data)
            var revisions = decoded.vibes
            if decoded.missingCategoryIndices.isEmpty {
                return revisions
            }
            let catalogByID = Dictionary(uniqueKeysWithValues: catalogVibes.map { ($0.id, $0) })
            for index in decoded.missingCategoryIndices {
                revisions[index].category = catalogByID[revisions[index].id]?.category ?? .general
            }
            _ = persistVibeRevisions(revisions)
            return revisions
        } catch {
            logger.warning("vibelane vibe revisions decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func decodeVibesAndCategoryPresence(
        from data: Data
    ) throws -> (vibes: [VibeDefinition], missingCategoryIndices: [Int]) {
        struct CategoryPresence: Decodable {
            let category: String?
        }

        let vibes = try decoder.decode([VibeDefinition].self, from: data)
        let presence = try decoder.decode([CategoryPresence].self, from: data)
        guard vibes.count == presence.count else { return (vibes, []) }
        return (
            vibes,
            presence.indices.filter { presence[$0].category == nil }
        )
    }

    private func persistVibeRevisions(_ revisions: [VibeDefinition]) -> Bool {
        do {
            let unique = Dictionary(
                revisions.map {
                    (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let data = try encoder.encode(Array(unique.values))
            let tmp = vibeRevisionsURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: vibeRevisionsURL, with: tmp)
            return true
        } catch {
            logger.error("vibelane vibe revision persist failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func uniqueCurrentVibes(_ vibes: [VibeDefinition]) -> [VibeDefinition] {
        Array(
            Dictionary(vibes.map { ($0.id, $0) }, uniquingKeysWith: { current, candidate in
                candidate.version >= current.version ? candidate : current
            }).values
        )
    }

    func loadTasks() -> [VibeLaneTask] {
        do {
            return try loadTasksForMutation()
        } catch {
            logger.warning("vibelane tasks decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func saveTask(_ task: VibeLaneTask) -> Bool {
        do {
            var all = try loadTasksForMutation().filter { $0.id != task.id }
            all.append(task)
            return persist(all)
        } catch {
            logger.error("vibelane task save aborted: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func deleteTask(id: UUID) {
        let all = loadTasks().filter { $0.id != id }
        _ = persist(all)
    }

    private func persist(_ tasks: [VibeLaneTask]) -> Bool {
        do {
            let data = try encoder.encode(tasks)
            let tmp = tasksURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: tasksURL, with: tmp)
            return true
        } catch {
            logger.error("vibelane tasks persist failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func loadTasksForMutation() throws -> [VibeLaneTask] {
        guard FileManager.default.fileExists(atPath: tasksURL.path) else { return [] }
        let data = try Data(contentsOf: tasksURL)
        return try decoder.decode([VibeLaneTask].self, from: data)
    }

    // MARK: - Lane revisions (retained pins)

    private func loadRevisions() -> [VibeLaneDefinition] {
        guard let data = try? Data(contentsOf: revisionsURL) else { return [] }
        do {
            return try decoder.decode([VibeLaneDefinition].self, from: data)
        } catch {
            logger.warning("vibelane revisions decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func laneRevision(id: UUID, version: Int) -> VibeLaneDefinition? {
        loadRevisions().first { $0.id == id && $0.version == version }
    }

    func archiveLaneRevision(_ lane: VibeLaneDefinition) -> Bool {
        do {
            var all = try loadRevisionsForMutation().filter {
                !($0.id == lane.id && $0.version == lane.version)
            }
            all.append(lane)
            return persistRevisions(all)
        } catch {
            logger.error("vibelane revision save aborted: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>) {
        let all = loadRevisions().filter { keep.contains(VibeLaneRevisionKey(laneID: $0.id, version: $0.version)) }
        _ = persistRevisions(all)
    }

    private func persistRevisions(_ revisions: [VibeLaneDefinition]) -> Bool {
        do {
            let data = try encoder.encode(revisions)
            let tmp = revisionsURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: revisionsURL, with: tmp)
            return true
        } catch {
            logger.error("vibelane revisions persist failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func loadRevisionsForMutation() throws -> [VibeLaneDefinition] {
        guard FileManager.default.fileExists(atPath: revisionsURL.path) else { return [] }
        let data = try Data(contentsOf: revisionsURL)
        return try decoder.decode([VibeLaneDefinition].self, from: data)
    }

    private func replaceFile(at destination: URL, with temporary: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
