import Foundation
import OSLog

struct VibeLoopPersistedState: Codable, Equatable, Sendable {
    var definitions: [VibeLoopDefinition]
    var runtimeStates: [VibeLoopRuntimeState]
    var runRecords: [VibeLoopRunRecord]

    static let empty = VibeLoopPersistedState(
        definitions: [],
        runtimeStates: [],
        runRecords: []
    )
}

@MainActor
protocol VibeLoopPersisting: AnyObject {
    func loadPersistedState() async throws -> VibeLoopPersistedState
    func persistState(_ state: VibeLoopPersistedState) async throws
}

/// Synchronous stores are retained for focused tests and legacy migration.
protocol VibeLoopStoring: VibeLoopPersisting {
    func loadState() throws -> VibeLoopPersistedState
    func saveState(_ state: VibeLoopPersistedState) throws

    // Compatibility projections used by focused tests and legacy callers.
    func loadDefinitions() -> [VibeLoopDefinition]
    func saveDefinitions(_ definitions: [VibeLoopDefinition])
    func loadRuntimeStates() -> [VibeLoopRuntimeState]
    func saveRuntimeStates(_ states: [VibeLoopRuntimeState])
    func loadRunRecords() -> [VibeLoopRunRecord]
    func saveRunRecords(_ records: [VibeLoopRunRecord])
}

extension VibeLoopStoring {
    func loadPersistedState() async throws -> VibeLoopPersistedState {
        try loadState()
    }

    func persistState(_ state: VibeLoopPersistedState) async throws {
        try saveState(state)
    }
}

final class InMemoryVibeLoopStore: VibeLoopStoring {
    private var definitions: [VibeLoopDefinition]
    private var runtimeStates: [VibeLoopRuntimeState]
    private var runRecords: [VibeLoopRunRecord]
    var shouldFailSaves = false
    var shouldFailLoads = false

    init(
        definitions: [VibeLoopDefinition] = [],
        runtimeStates: [VibeLoopRuntimeState] = [],
        runRecords: [VibeLoopRunRecord] = []
    ) {
        self.definitions = definitions
        self.runtimeStates = runtimeStates
        self.runRecords = runRecords
    }

    func loadState() throws -> VibeLoopPersistedState {
        if shouldFailLoads {
            throw CocoaError(.fileReadUnknown)
        }
        return VibeLoopPersistedState(
            definitions: definitions,
            runtimeStates: runtimeStates,
            runRecords: runRecords
        )
    }

    func saveState(_ state: VibeLoopPersistedState) throws {
        if shouldFailSaves {
            throw CocoaError(.fileWriteUnknown)
        }
        definitions = state.definitions
        runtimeStates = state.runtimeStates
        runRecords = state.runRecords
    }

    func loadDefinitions() -> [VibeLoopDefinition] { definitions }
    func saveDefinitions(_ definitions: [VibeLoopDefinition]) { self.definitions = definitions }
    func loadRuntimeStates() -> [VibeLoopRuntimeState] { runtimeStates }
    func saveRuntimeStates(_ states: [VibeLoopRuntimeState]) { runtimeStates = states }
    func loadRunRecords() -> [VibeLoopRunRecord] { runRecords }
    func saveRunRecords(_ records: [VibeLoopRunRecord]) { runRecords = records }
}

final class FileVibeLoopStore: VibeLoopStoring {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
        category: "loops"
    )

    init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var definitionsURL: URL { directory.appendingPathComponent("definitions.json") }
    private var runtimeURL: URL { directory.appendingPathComponent("runtime.json") }
    private var runsURL: URL { directory.appendingPathComponent("runs.json") }

    func loadState() throws -> VibeLoopPersistedState {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            return try loadRequired(VibeLoopPersistedState.self, from: stateURL)
        }

        let state = VibeLoopPersistedState(
            definitions: try loadLegacy([VibeLoopDefinition].self, from: definitionsURL) ?? [],
            runtimeStates: try loadLegacy([VibeLoopRuntimeState].self, from: runtimeURL) ?? [],
            runRecords: try loadLegacy([VibeLoopRunRecord].self, from: runsURL) ?? []
        )
        try saveState(state)
        return state
    }

    func saveState(_ state: VibeLoopPersistedState) throws {
        let data = try encoder.encode(state)
        let temporary = stateURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: temporary)
        try data.write(to: temporary, options: .atomic)
        do {
            if FileManager.default.fileExists(atPath: stateURL.path) {
                _ = try FileManager.default.replaceItemAt(stateURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: stateURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func loadDefinitions() -> [VibeLoopDefinition] {
        (try? loadState().definitions) ?? []
    }

    func saveDefinitions(_ definitions: [VibeLoopDefinition]) {
        mutateState { $0.definitions = definitions }
    }

    func loadRuntimeStates() -> [VibeLoopRuntimeState] {
        (try? loadState().runtimeStates) ?? []
    }

    func saveRuntimeStates(_ states: [VibeLoopRuntimeState]) {
        mutateState { $0.runtimeStates = states }
    }

    func loadRunRecords() -> [VibeLoopRunRecord] {
        (try? loadState().runRecords) ?? []
    }

    func saveRunRecords(_ records: [VibeLoopRunRecord]) {
        mutateState { $0.runRecords = records }
    }

    private func loadLegacy<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try loadRequired(type, from: url)
    }

    private func loadRequired<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Could not decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func mutateState(_ mutation: (inout VibeLoopPersistedState) -> Void) {
        do {
            var state = try loadState()
            mutation(&state)
            try saveState(state)
        } catch {
            logger.error("Could not persist state.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
