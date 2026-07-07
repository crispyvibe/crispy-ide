import CryptoKit
import Foundation
import OSLog

// F059 — persistence for Vibe Lanes. The store is the durable shape of the
// schema (definitions + tasks). v1 ships a JSON-file store under Application
// Support so tasks survive a restart (R08); an `AgentConversationStore`-backed
// store can replace it later without touching the engine/UI (it only depends on
// this protocol).

/// Identifies one immutable lane content revision (a lane id at a specific
/// content `version`). Used to retain the exact revision a task pinned.
struct VibeLaneRevisionKey: Hashable, Sendable {
    let laneID: UUID
    let version: Int
}

protocol VibeLaneStoring: AnyObject {
    func loadLanes() -> [VibeLaneDefinition]
    func loadTasks() -> [VibeLaneTask]
    func saveTask(_ task: VibeLaneTask)
    func deleteTask(id: UUID)
    func saveLane(_ lane: VibeLaneDefinition)
    func deleteLane(id: UUID)

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
    func archiveLaneRevision(_ lane: VibeLaneDefinition)
    /// Drop retained revisions whose key is not in `keep` (e.g. after task deletes).
    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>)
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
    /// either its content still matches the fingerprint it was seeded with, or
    /// it is a legacy seed (no fingerprint) that was never version-bumped.
    static func isPristine(_ lane: VibeLaneDefinition) -> Bool {
        if let seeded = lane.seededFingerprint {
            return seeded == fingerprint(of: lane)
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
}

/// In-memory store for tests and previews.
final class InMemoryVibeLaneStore: VibeLaneStoring {
    private var lanes: [UUID: VibeLaneDefinition]
    private var tasks: [UUID: VibeLaneTask]
    private var revisions: [VibeLaneRevisionKey: VibeLaneDefinition] = [:]
    private let catalog: [VibeLaneDefinition]
    private var tombstones: Set<UUID> = []

    init(lanes: [VibeLaneDefinition] = [], tasks: [VibeLaneTask] = [], catalog: [VibeLaneDefinition] = []) {
        self.lanes = Dictionary(uniqueKeysWithValues: lanes.map { ($0.id, $0) })
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        self.catalog = catalog
    }

    func loadLanes() -> [VibeLaneDefinition] { Array(lanes.values) }
    func loadTasks() -> [VibeLaneTask] { Array(tasks.values) }
    func saveTask(_ task: VibeLaneTask) { tasks[task.id] = task }
    func deleteTask(id: UUID) { tasks[id] = nil }
    func saveLane(_ lane: VibeLaneDefinition) { lanes[lane.id] = lane }
    func deleteLane(id: UUID) {
        lanes[id] = nil
        if catalog.contains(where: { $0.id == id }) { tombstones.insert(id) }
    }

    func reconcileStarterLanes() {
        let outcome = VibeLaneStarterReconciler.reconcile(
            stored: Array(lanes.values),
            catalog: catalog,
            tombstones: tombstones
        )
        if outcome.changed {
            lanes = Dictionary(uniqueKeysWithValues: outcome.lanes.map { ($0.id, $0) })
        }
    }

    func restoreStarterLanes() {
        tombstones.removeAll()
        reconcileStarterLanes()
    }

    func laneRevision(id: UUID, version: Int) -> VibeLaneDefinition? {
        revisions[VibeLaneRevisionKey(laneID: id, version: version)]
    }
    func archiveLaneRevision(_ lane: VibeLaneDefinition) {
        revisions[VibeLaneRevisionKey(laneID: lane.id, version: lane.version)] = lane
    }
    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>) {
        revisions = revisions.filter { keep.contains($0.key) }
    }
}

/// JSON-file store. Lanes seed from the prebuilt catalog on first run and are
/// user-editable thereafter (`lanes.json`); tasks persist to `tasks.json` and
/// are written after every transition (small, atomic).
final class FileVibeLaneStore: VibeLaneStoring {
    private let directory: URL
    private let catalog: [VibeLaneDefinition]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app", category: "vibelanes")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL, catalog: [VibeLaneDefinition]) {
        self.directory = directory
        self.catalog = catalog
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
    private var tombstonesURL: URL { directory.appendingPathComponent("lane-tombstones.json") }

    func loadLanes() -> [VibeLaneDefinition] {
        // File missing → first run (reconcileStarterLanes seeds it); returning the
        // catalog keeps reads sane if a read races the seed.
        // File present (even if it decodes to an empty array) → the user's
        // intentional state wins; starter deletions stay durable via tombstones.
        guard let data = try? Data(contentsOf: lanesURL) else { return catalog }
        do {
            return try decoder.decode([VibeLaneDefinition].self, from: data)
        } catch {
            logger.warning("vibelane lanes decode failed: \(error.localizedDescription, privacy: .public)")
            return catalog
        }
    }

    func saveLane(_ lane: VibeLaneDefinition) {
        var all = loadLanes().filter { $0.id != lane.id }
        all.append(lane)
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
            persistLanes(seeded)
            return
        }
        let outcome = VibeLaneStarterReconciler.reconcile(
            stored: loadLanes(),
            catalog: catalog,
            tombstones: loadTombstones()
        )
        if outcome.changed {
            persistLanes(outcome.lanes)
        }
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
            let data = try encoder.encode(lanes)
            let tmp = lanesURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: lanesURL, with: tmp)
        } catch {
            logger.error("vibelane lanes persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadTasks() -> [VibeLaneTask] {
        guard let data = try? Data(contentsOf: tasksURL) else { return [] }
        do {
            return try decoder.decode([VibeLaneTask].self, from: data)
        } catch {
            logger.warning("vibelane tasks decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func saveTask(_ task: VibeLaneTask) {
        var all = loadTasks().filter { $0.id != task.id }
        all.append(task)
        persist(all)
    }

    func deleteTask(id: UUID) {
        let all = loadTasks().filter { $0.id != id }
        persist(all)
    }

    private func persist(_ tasks: [VibeLaneTask]) {
        do {
            let data = try encoder.encode(tasks)
            let tmp = tasksURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: tasksURL, with: tmp)
        } catch {
            logger.error("vibelane tasks persist failed: \(error.localizedDescription, privacy: .public)")
        }
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

    func archiveLaneRevision(_ lane: VibeLaneDefinition) {
        var all = loadRevisions().filter { !($0.id == lane.id && $0.version == lane.version) }
        all.append(lane)
        persistRevisions(all)
    }

    func pruneLaneRevisions(keep: Set<VibeLaneRevisionKey>) {
        let all = loadRevisions().filter { keep.contains(VibeLaneRevisionKey(laneID: $0.id, version: $0.version)) }
        persistRevisions(all)
    }

    private func persistRevisions(_ revisions: [VibeLaneDefinition]) {
        do {
            let data = try encoder.encode(revisions)
            let tmp = revisionsURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try replaceFile(at: revisionsURL, with: tmp)
        } catch {
            logger.error("vibelane revisions persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func replaceFile(at destination: URL, with temporary: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
