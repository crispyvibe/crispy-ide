import CryptoKit
import Foundation

struct AutomationSkillReferenceRecord: Codable, Hashable, Sendable {
    var reference: String
    var sourceKind: String
    var digest: String?

    init(reference: String, sourceKind: String = "linked", digest: String? = nil) {
        self.reference = reference
        self.sourceKind = sourceKind
        self.digest = digest
    }
}

struct AutomationHandoffRecord: Codable, Hashable, Sendable {
    var taskID: UUID
    var checkpointKey: String
    var filePath: String
    var contentDigest: String?
    var updatedAt: Date
}

enum AutomationDatabaseError: LocalizedError {
    case unavailable
    case requestFailed(String)
    case invalidResponse
    case invalidLegacyData(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The encrypted Crispy database is unavailable."
        case .requestFailed(let detail):
            detail
        case .invalidResponse:
            "The persistence helper returned an invalid Automation response."
        case .invalidLegacyData(let detail):
            "Legacy Automation data is invalid: \(detail)"
        }
    }
}

/// The single production persistence adapter for Vibes, Vibe Lanes, tasks, and
/// Loops. Skill packages and handoff Markdown remain portable files; all
/// resource identity, revisions, runtime state, and references live in libSQL.
@MainActor
final class AutomationDatabaseStore:
    VibeLanePersisting,
    VibeLoopPersisting,
    AutomationSkillReferencePersisting
{
    private let conversationStore: AgentConversationStore
    private let catalog: [VibeLaneDefinition]
    private let handoffRoot: URL
    private let legacyReader: LegacyAutomationReader
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        conversationStore: AgentConversationStore,
        catalog: [VibeLaneDefinition],
        vibeLanesDirectory: URL,
        loopsDirectory: URL,
        skillsDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.conversationStore = conversationStore
        self.catalog = catalog
        self.handoffRoot = vibeLanesDirectory.appendingPathComponent(
            "handoffs",
            isDirectory: true
        )
        self.legacyReader = LegacyAutomationReader(
            catalog: catalog,
            vibeLanesDirectory: vibeLanesDirectory,
            loopsDirectory: loopsDirectory,
            skillsDirectory: skillsDirectory,
            fileManager: fileManager
        )
        self.encoder = Self.makeEncoder()
        self.decoder = Self.makeDecoder()
    }

    /// Must complete before either manager bootstraps. The helper transaction
    /// makes the database authoritative; JSON is never dual-written.
    func prepareLegacyMigration() async throws {
        let status = try await request("automation.migration.status", params: [:])
        let complete = status["complete"] as? Bool ?? false
        if complete {
            try legacyReader.archiveImportedFilesIfPresent()
            return
        }

        let legacy = try legacyReader.read()
        let params: [String: Any] = [
            "vibes": try objects(legacy.vibes),
            "vibeRevisions": try objects(legacy.vibeRevisions),
            "lanes": try storedLaneObjects(legacy.lanes),
            "laneRevisions": try storedLaneObjects(legacy.laneRevisions),
            "laneTombstones": legacy.laneTombstones.map(\.uuidString),
            "tasks": try objects(legacy.tasks),
            "handoffs": try objects(legacy.handoffs),
            "loopDefinitions": try objects(legacy.loopState.definitions),
            "loopRuntimeStates": try objects(legacy.loopState.runtimeStates),
            "loopRunRecords": try objects(legacy.loopState.runRecords),
            "skillReferences": try objects(legacy.skillReferences),
            "sourceDigests": legacy.sourceDigests,
        ]
        let result = try await request("automation.migration.import", params: params)
        guard result["imported"] as? Bool == true || result["alreadyComplete"] as? Bool == true else {
            throw AutomationDatabaseError.invalidResponse
        }
        try legacyReader.archiveImportedFilesIfPresent()
    }

    func loadPersistenceSnapshot() async throws -> VibeLanePersistenceSnapshot {
        try await loadDatabaseSnapshot().laneState
    }

    func reconcileStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot {
        try await reconcileStarterLanes(clearTombstones: false)
    }

    func restoreStarterLanesPersisted() async throws -> VibeLanePersistenceSnapshot {
        try await reconcileStarterLanes(clearTombstones: true)
    }

    private func reconcileStarterLanes(
        clearTombstones: Bool
    ) async throws -> VibeLanePersistenceSnapshot {
        let snapshot = try await loadPersistenceSnapshot()
        let resolvedCatalog = VibeLaneReferenceResolver.resolve(
            lanes: catalog,
            vibes: []
        )
        let outcome = VibeLaneStarterReconciler.reconcile(
            stored: snapshot.lanes,
            catalog: resolvedCatalog.lanes,
            tombstones: clearTombstones ? [] : snapshot.laneTombstones
        )
        let knownVibes = Set(
            (snapshot.vibes + snapshot.vibeRevisions).map {
                VibeRevisionKey(vibeID: $0.id, version: $0.version)
            }
        )
        let missingVibes = resolvedCatalog.vibes.filter {
            !knownVibes.contains(VibeRevisionKey(vibeID: $0.id, version: $0.version))
        }
        let missingVibeRevisions = resolvedCatalog.revisions.filter {
            !knownVibes.contains(VibeRevisionKey(vibeID: $0.id, version: $0.version))
        }
        let currentLanes = Dictionary(uniqueKeysWithValues: snapshot.lanes.map { ($0.id, $0) })
        let changedLanes = outcome.lanes.filter { currentLanes[$0.id] != $0 }
        let supersededVibeIDs = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: snapshot.vibes,
            previousLanes: snapshot.lanes,
            currentLanes: outcome.lanes,
            laneRevisions: snapshot.laneRevisions,
            catalogLanes: resolvedCatalog.lanes,
            catalogVibes: resolvedCatalog.vibes
        )
        guard clearTombstones
                || !missingVibes.isEmpty
                || !missingVibeRevisions.isEmpty
                || !changedLanes.isEmpty
                || !supersededVibeIDs.isEmpty else {
            return snapshot
        }

        _ = try await request(
            "automation.starters.apply",
            params: [
                "vibes": try objects(missingVibes),
                "vibeRevisions": try objects(missingVibeRevisions),
                "lanes": try storedLaneObjects(changedLanes),
                "retireVibeIDs": supersededVibeIDs
                    .map(\.uuidString)
                    .sorted(),
                "clearTombstones": clearTombstones,
            ]
        )
        return try await loadPersistenceSnapshot()
    }

    func persistCurrentLane(_ lane: VibeLaneDefinition) async throws {
        guard let stored = StoredVibeLaneDefinition(lane) else {
            throw AutomationDatabaseError.invalidLegacyData(
                "Vibe Lane \(lane.id) contains an unresolved Vibe reference."
            )
        }
        _ = try await request(
            "automation.lane.save",
            params: ["lane": try object(stored)]
        )
    }

    func removeCurrentLane(id: UUID, tombstone: Bool) async throws {
        _ = try await request(
            "automation.lane.delete",
            params: ["id": id.uuidString, "tombstone": tombstone]
        )
    }

    func persistCurrentVibe(_ vibe: VibeDefinition) async throws {
        _ = try await request(
            "automation.vibe.save",
            params: ["vibe": try object(vibe)]
        )
    }

    func removeCurrentVibe(id: UUID) async throws {
        _ = try await request("automation.vibe.delete", params: ["id": id.uuidString])
    }

    func persistTask(_ task: VibeLaneTask) async throws {
        _ = try await request(
            "automation.task.save",
            params: [
                "task": try object(task),
                "handoffs": try objects(handoffRecords(for: task)),
            ]
        )
    }

    func removeTask(id: UUID) async throws {
        _ = try await request("automation.task.delete", params: ["id": id.uuidString])
    }

    func loadPersistedState() async throws -> VibeLoopPersistedState {
        try await loadDatabaseSnapshot().loopState
    }

    func persistState(_ state: VibeLoopPersistedState) async throws {
        _ = try await request(
            "automation.loops.replace",
            params: [
                "definitions": try objects(state.definitions),
                "runtimeStates": try objects(state.runtimeStates),
                "runRecords": try objects(state.runRecords),
            ]
        )
    }

    func loadSkillReferences() async throws -> [AutomationSkillReferenceRecord] {
        try await loadDatabaseSnapshot().skillReferences
    }

    func persistSkillReferences(_ records: [AutomationSkillReferenceRecord]) async throws {
        _ = try await request(
            "automation.skillReferences.replace",
            params: ["references": try objects(records)]
        )
    }

    private func loadDatabaseSnapshot() async throws -> DatabaseSnapshot {
        let value = try await request("automation.snapshot.load", params: [:])
        let vibes = try decode([VibeDefinition].self, from: value["vibes"])
        let vibeRevisions = try decode([VibeDefinition].self, from: value["vibeRevisions"])
        let storedLanes = try decode([StoredVibeLaneDefinition].self, from: value["lanes"])
        let storedLaneRevisions = try decode(
            [StoredVibeLaneDefinition].self,
            from: value["laneRevisions"]
        )
        let lanes = storedLanes.map { $0.resolved(current: vibes, revisions: vibeRevisions) }
        let laneRevisions = storedLaneRevisions.map {
            $0.resolved(current: vibes, revisions: vibeRevisions)
        }
        let tombstoneStrings = value["laneTombstones"] as? [String] ?? []
        guard tombstoneStrings.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw AutomationDatabaseError.invalidResponse
        }
        let tasks = try decode([VibeLaneTask].self, from: value["tasks"])
        let loopState = VibeLoopPersistedState(
            definitions: try decode([VibeLoopDefinition].self, from: value["loopDefinitions"]),
            runtimeStates: try decode(
                [VibeLoopRuntimeState].self,
                from: value["loopRuntimeStates"]
            ),
            runRecords: try decode([VibeLoopRunRecord].self, from: value["loopRunRecords"])
        )
        return DatabaseSnapshot(
            laneState: VibeLanePersistenceSnapshot(
                lanes: lanes,
                laneRevisions: laneRevisions,
                laneTombstones: Set(tombstoneStrings.compactMap(UUID.init(uuidString:))),
                vibes: vibes,
                vibeRevisions: vibeRevisions,
                tasks: tasks
            ),
            loopState: loopState,
            skillReferences: try decode(
                [AutomationSkillReferenceRecord].self,
                from: value["skillReferences"]
            )
        )
    }

    private func request(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        guard let result = await conversationStore.send(method: method, params: params) else {
            throw AutomationDatabaseError.unavailable
        }
        guard result.ok else {
            throw AutomationDatabaseError.requestFailed(
                result.errorMessage ?? "Automation persistence request failed."
            )
        }
        return result.value ?? [:]
    }

    private func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AutomationDatabaseError.invalidResponse
        }
        return object
    }

    private func objects<Value: Encodable>(_ values: [Value]) throws -> [[String: Any]] {
        try values.map(object)
    }

    private func storedLaneObjects(_ lanes: [VibeLaneDefinition]) throws -> [[String: Any]] {
        try lanes.map { lane in
            guard let stored = StoredVibeLaneDefinition(lane) else {
                throw AutomationDatabaseError.invalidLegacyData(
                    "Vibe Lane \(lane.id) contains an unresolved Vibe reference."
                )
            }
            return try object(stored)
        }
    }

    private func handoffRecords(for task: VibeLaneTask) -> [AutomationHandoffRecord] {
        task.checkpointRuns.compactMap { run in
            guard let summary = run.summary else { return nil }
            let fileURL = handoffRoot
                .appendingPathComponent(task.id.uuidString, isDirectory: true)
                .appendingPathComponent("\(run.checkpointKey).md")
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let digest = SHA256.hash(data: Data(summary.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return AutomationHandoffRecord(
                taskID: task.id,
                checkpointKey: run.checkpointKey,
                filePath: fileURL.path,
                contentDigest: digest,
                updatedAt: run.endedAt ?? task.updatedAt
            )
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from object: Any?) throws -> Value {
        guard let object,
              JSONSerialization.isValidJSONObject(object) else {
            throw AutomationDatabaseError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try decoder.decode(type, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct DatabaseSnapshot {
    var laneState: VibeLanePersistenceSnapshot
    var loopState: VibeLoopPersistedState
    var skillReferences: [AutomationSkillReferenceRecord]
}

@MainActor
final class AutomationBootstrapCoordinator: ObservableObject {
    enum State: Equatable {
        case waiting
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .waiting

    private let store: AutomationDatabaseStore
    private let laneManager: VibeLaneTaskManager
    private let loopManager: VibeLoopManager
    private let skillStore: VibeLaneSkillStore
    private let scheduler: VibeLoopScheduler
    private let resumeTasks: Bool
    private var bootstrapTask: Task<Void, Never>?

    init(
        store: AutomationDatabaseStore,
        laneManager: VibeLaneTaskManager,
        loopManager: VibeLoopManager,
        skillStore: VibeLaneSkillStore,
        scheduler: VibeLoopScheduler,
        resumeTasks: Bool
    ) {
        self.store = store
        self.laneManager = laneManager
        self.loopManager = loopManager
        self.skillStore = skillStore
        self.scheduler = scheduler
        self.resumeTasks = resumeTasks
    }

    func start() {
        guard bootstrapTask == nil else { return }
        state = .loading
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await store.prepareLegacyMigration()
                await laneManager.bootstrap(resumeRunning: resumeTasks)
                if let error = laneManager.persistenceError {
                    throw AutomationDatabaseError.requestFailed(error)
                }
                await skillStore.bootstrap()
                if let error = skillStore.persistenceError {
                    throw AutomationDatabaseError.requestFailed(error)
                }
                await loopManager.bootstrap()
                if let error = loopManager.persistenceError {
                    throw AutomationDatabaseError.requestFailed(error)
                }
                if resumeTasks {
                    scheduler.start()
                }
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func shutdown() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
    }
}

private struct LegacyAutomationSnapshot {
    var lanes: [VibeLaneDefinition]
    var laneRevisions: [VibeLaneDefinition]
    var laneTombstones: Set<UUID>
    var vibes: [VibeDefinition]
    var vibeRevisions: [VibeDefinition]
    var tasks: [VibeLaneTask]
    var handoffs: [AutomationHandoffRecord]
    var loopState: VibeLoopPersistedState
    var skillReferences: [AutomationSkillReferenceRecord]
    var sourceDigests: [String: String]
}

private final class LegacyAutomationReader {
    private struct LinkedSkillRecord: Decodable {
        var path: String
    }

    private let catalog: [VibeLaneDefinition]
    private let vibeLanesDirectory: URL
    private let loopsDirectory: URL
    private let skillsDirectory: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(
        catalog: [VibeLaneDefinition],
        vibeLanesDirectory: URL,
        loopsDirectory: URL,
        skillsDirectory: URL,
        fileManager: FileManager
    ) {
        self.catalog = catalog
        self.vibeLanesDirectory = vibeLanesDirectory
        self.loopsDirectory = loopsDirectory
        self.skillsDirectory = skillsDirectory
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func read() throws -> LegacyAutomationSnapshot {
        let catalogState = VibeLaneReferenceResolver.resolve(lanes: catalog, vibes: [])
        let vibes = try decodeIfPresent(
            [VibeDefinition].self,
            at: vibeLanesDirectory.appendingPathComponent("vibes.json")
        ) ?? catalogState.vibes
        let vibeRevisions = try decodeIfPresent(
            [VibeDefinition].self,
            at: vibeLanesDirectory.appendingPathComponent("vibe-revisions.json")
        ) ?? []
        let loopState = try readLoopState()
        let currentLanes = try readCurrentLanes(
            fallback: catalogState.lanes,
            vibes: vibes,
            revisions: vibeRevisions
        )
        let laneRevisions = try decodeIfPresent(
            [VibeLaneDefinition].self,
            at: vibeLanesDirectory.appendingPathComponent("lane-revisions.json")
        ) ?? []

        let loopSnapshots = loopState.definitions.map(\.laneSnapshot)
        let allLanes = currentLanes + laneRevisions + loopSnapshots
        let resolved = VibeLaneReferenceResolver.resolve(
            lanes: allLanes,
            vibes: vibes,
            revisions: vibeRevisions
        )
        let currentCount = currentLanes.count
        let revisionCount = laneRevisions.count
        let resolvedCurrent = Array(resolved.lanes.prefix(currentCount))
        var resolvedRevisions = Array(
            resolved.lanes.dropFirst(currentCount).prefix(revisionCount)
        )
        let resolvedLoopSnapshots = Array(
            resolved.lanes.dropFirst(currentCount + revisionCount)
        )
        var resolvedLoops = loopState.definitions
        for index in resolvedLoops.indices {
            resolvedLoops[index].laneSnapshot = resolvedLoopSnapshots[index]
            resolvedLoops[index].laneID = resolvedLoopSnapshots[index].id
            resolvedLoops[index].laneVersion = resolvedLoopSnapshots[index].version
            if !resolvedCurrent.contains(where: {
                $0.id == resolvedLoopSnapshots[index].id
                    && $0.version == resolvedLoopSnapshots[index].version
            }) {
                resolvedRevisions.append(resolvedLoopSnapshots[index])
            }
        }

        let tasks = try decodeIfPresent(
            [VibeLaneTask].self,
            at: vibeLanesDirectory.appendingPathComponent("tasks.json")
        ) ?? []
        let allResolvableLanes = resolvedCurrent + resolvedRevisions
        for task in tasks {
            guard let lane = allResolvableLanes.first(where: {
                $0.id == task.laneID && $0.version == task.laneVersion
            }), task.isConsistent(with: lane) else {
                throw AutomationDatabaseError.invalidLegacyData(
                    "task \(task.id) does not resolve to a consistent pinned Vibe Lane."
                )
            }
        }

        let currentLaneKeys = Set(
            resolvedCurrent.map { VibeLaneRevisionKey(laneID: $0.id, version: $0.version) }
        )
        let currentVibeKeys = Set(
            resolved.vibes.map { VibeRevisionKey(vibeID: $0.id, version: $0.version) }
        )
        return LegacyAutomationSnapshot(
            lanes: uniqueLanes(resolvedCurrent),
            laneRevisions: uniqueLanes(resolvedRevisions).filter {
                !currentLaneKeys.contains(
                    VibeLaneRevisionKey(laneID: $0.id, version: $0.version)
                )
            },
            laneTombstones: try decodeIfPresent(
                Set<UUID>.self,
                at: vibeLanesDirectory.appendingPathComponent("lane-tombstones.json")
            ) ?? [],
            vibes: uniqueVibes(resolved.vibes),
            vibeRevisions: uniqueVibes(resolved.revisions).filter {
                !currentVibeKeys.contains(
                    VibeRevisionKey(vibeID: $0.id, version: $0.version)
                )
            },
            tasks: tasks,
            handoffs: handoffRecords(for: tasks),
            loopState: VibeLoopPersistedState(
                definitions: resolvedLoops,
                runtimeStates: loopState.runtimeStates,
                runRecords: loopState.runRecords
            ),
            skillReferences: try readSkillReferences(),
            sourceDigests: try sourceDigests()
        )
    }

    func archiveImportedFilesIfPresent() throws {
        let sources = legacyFileURLs().filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !sources.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupRoot = vibeLanesDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Automation Legacy Backup \(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        for source in sources {
            let namespace = source.path.hasPrefix(loopsDirectory.path) ? "Loops" : "VibeLanes"
            let destinationDirectory = backupRoot.appendingPathComponent(namespace, isDirectory: true)
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func readCurrentLanes(
        fallback: [VibeLaneDefinition],
        vibes: [VibeDefinition],
        revisions: [VibeDefinition]
    ) throws -> [VibeLaneDefinition] {
        let url = vibeLanesDirectory.appendingPathComponent("lanes.json")
        guard fileManager.fileExists(atPath: url.path) else { return fallback }
        let data = try Data(contentsOf: url)
        if let stored = try? decoder.decode([StoredVibeLaneDefinition].self, from: data) {
            return stored.map { $0.resolved(current: vibes, revisions: revisions) }
        }
        return try decoder.decode([VibeLaneDefinition].self, from: data)
    }

    private func readLoopState() throws -> VibeLoopPersistedState {
        let stateURL = loopsDirectory.appendingPathComponent("state.json")
        if fileManager.fileExists(atPath: stateURL.path) {
            return try decode(VibeLoopPersistedState.self, at: stateURL)
        }
        return VibeLoopPersistedState(
            definitions: try decodeIfPresent(
                [VibeLoopDefinition].self,
                at: loopsDirectory.appendingPathComponent("definitions.json")
            ) ?? [],
            runtimeStates: try decodeIfPresent(
                [VibeLoopRuntimeState].self,
                at: loopsDirectory.appendingPathComponent("runtime.json")
            ) ?? [],
            runRecords: try decodeIfPresent(
                [VibeLoopRunRecord].self,
                at: loopsDirectory.appendingPathComponent("runs.json")
            ) ?? []
        )
    }

    private func readSkillReferences() throws -> [AutomationSkillReferenceRecord] {
        let url = skillsDirectory.appendingPathComponent("linked-skills.json")
        let records = try decodeIfPresent([LinkedSkillRecord].self, at: url) ?? []
        return records.map {
            AutomationSkillReferenceRecord(reference: $0.path)
        }
    }

    private func sourceDigests() throws -> [String: String] {
        var digests: [String: String] = [:]
        for url in legacyFileURLs() where fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            digests[url.path] = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return digests
    }

    private func handoffRecords(for tasks: [VibeLaneTask]) -> [AutomationHandoffRecord] {
        tasks.flatMap { task in
            task.checkpointRuns.compactMap { run in
                guard let summary = run.summary else { return nil }
                let fileURL = vibeLanesDirectory
                    .appendingPathComponent("handoffs", isDirectory: true)
                    .appendingPathComponent(task.id.uuidString, isDirectory: true)
                    .appendingPathComponent("\(run.checkpointKey).md")
                guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
                let digest = SHA256.hash(data: Data(summary.utf8))
                    .map { String(format: "%02x", $0) }
                    .joined()
                return AutomationHandoffRecord(
                    taskID: task.id,
                    checkpointKey: run.checkpointKey,
                    filePath: fileURL.path,
                    contentDigest: digest,
                    updatedAt: run.endedAt ?? task.updatedAt
                )
            }
        }
    }

    private func legacyFileURLs() -> [URL] {
        [
            "vibes.json",
            "vibe-revisions.json",
            "lanes.json",
            "lane-revisions.json",
            "lane-tombstones.json",
            "tasks.json",
        ].map { vibeLanesDirectory.appendingPathComponent($0) }
            + [
                "state.json",
                "definitions.json",
                "runtime.json",
                "runs.json",
            ].map { loopsDirectory.appendingPathComponent($0) }
            + [skillsDirectory.appendingPathComponent("linked-skills.json")]
    }

    private func decode<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value {
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            throw AutomationDatabaseError.invalidLegacyData(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func decodeIfPresent<Value: Decodable>(
        _ type: Value.Type,
        at url: URL
    ) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(type, at: url)
    }

    private func uniqueLanes(_ lanes: [VibeLaneDefinition]) -> [VibeLaneDefinition] {
        Array(Dictionary(
            lanes.map { (VibeLaneRevisionKey(laneID: $0.id, version: $0.version), $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values)
    }

    private func uniqueVibes(_ vibes: [VibeDefinition]) -> [VibeDefinition] {
        Array(Dictionary(
            vibes.map { (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values)
    }
}
