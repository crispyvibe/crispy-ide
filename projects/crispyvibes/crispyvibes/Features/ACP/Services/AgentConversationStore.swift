import Foundation
import OSLog

/// Configuration for `AgentConversationStore`, extracted for testability.
struct AgentConversationStoreConfig: Sendable {
    let keychainService: String
    let databasePath: String
    let helperURL: URL?

    /// Resolves configuration from the running app bundle (production default).
    static func resolveFromBundle() -> AgentConversationStoreConfig {
        let keychainService: String = {
            let infoKey = "CrispyVibesAgentPersistKeychainService"
            if let service = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !service.isEmpty {
                return service
            }
            let bundleID = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
            return "\(bundleID).agent-persist"
        }()

        let dbPath: String = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let infoKey = "CrispyVibesAppSupportDirectoryName"
            let dirName: String = {
                if let name = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    return name
                }
                if let bundleName = (Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !bundleName.isEmpty {
                    return bundleName
                }
                return "Crispy"
            }()
            return appSupport.appendingPathComponent("\(dirName)/acp/conversations.db").path
        }()

        let helperURL: URL? = {
            guard let execURL = Bundle.main.executableURL else { return nil }
            let url = execURL.deletingLastPathComponent()
                .appendingPathComponent("crispyvibes-persistence-helper", isDirectory: false)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }()

        return AgentConversationStoreConfig(
            keychainService: keychainService,
            databasePath: dbPath,
            helperURL: helperURL
        )
    }
}

/// Manages the Rust persistence helper subprocess and provides async JSON-RPC
/// communication for durable agent conversation storage.
@MainActor
final class AgentConversationStore: ObservableObject {

    // MARK: - State

    enum PersistenceState: Equatable {
        case starting
        case ready(schemaVersion: Int)
        case ephemeral(reason: String)
    }

    @Published private(set) var state: PersistenceState = .starting
    @Published private(set) var threadChangeCounter: UInt64 = 0

    // MARK: - Private

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "agentConversationStore")
    private let config: AgentConversationStoreConfig
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var cachedKey: Data?
    private var pendingRequests: [String: CheckedContinuation<RPCResult, Never>] = [:]
    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 5
    private var requestCounter: UInt64 = 0
    private var restartAttempts = 0
    private let maxRestartAttempts = 3

    // MARK: - Init

    init(config: AgentConversationStoreConfig = .resolveFromBundle()) {
        self.config = config
    }

    // MARK: - Lifecycle

    func shutdown() {
        teardownProcess()
        state = .ephemeral(reason: "shutdown")
    }

    // MARK: - Public API

    private var startTask: Task<Void, Never>?

    /// Start the helper eagerly. Called once at app launch.
    func start() {
        guard case .starting = state, startTask == nil else { return }
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try self.loadOrCreateEncryptionKey()
                self.cachedKey = key
                try await self.spawnHelper(key: key)
            } catch {
                self.logger.error("Persistence helper start failed: \(error.localizedDescription, privacy: .public)")
                self.state = .ephemeral(reason: error.localizedDescription)
            }
        }
    }

    /// Send an RPC request and return the result. Returns nil if in ephemeral mode.
    /// Waits for the helper to become ready if still starting.
    func send(method: String, params: [String: Any]) async -> RPCResult? {
        // Wait for the start task to complete if still in progress
        if case .starting = state {
            await startTask?.value
        }
        guard case .ready = state else { return nil }
        requestCounter += 1
        let reqID = "req-\(requestCounter)"
        return await sendRaw(id: reqID, method: method, params: params)
    }

    // MARK: - Typed Convenience API

    func createThread(
        id: String,
        vibespaceId: String,
        projectPath: String,
        title: String,
        agentId: String,
        transportKind: String,
        model: String
    ) async {
        let result = await send(method: "thread.create", params: ACPPersistenceEncoder.encodeThreadCreate(
            id: id, vibespaceId: vibespaceId, projectPath: projectPath,
            title: title, agentId: agentId, transportKind: transportKind, model: model
        ))
        if let error = result?.errorMessage {
            logger.warning("thread.create failed: \(error, privacy: .public)")
        }
        threadChangeCounter += 1
    }

    func persistMessage(
        id: String, threadId: String, turnId: String?,
        role: String, text: String, isStreaming: Bool
    ) async {
        let result = await send(method: "message.append", params: ACPPersistenceEncoder.encodeMessage(
            id: id, threadId: threadId, turnId: turnId,
            role: role, text: text, isStreaming: isStreaming
        ))
        if let error = result?.errorMessage {
            logger.warning("message.append failed (\(role, privacy: .public)): \(error, privacy: .public)")
        }
    }

    func persistActivity(
        id: String, threadId: String, turnId: String?,
        kind: String, summary: String, payload: [String: Any]? = nil
    ) async {
        let result = await send(method: "activity.append", params: ACPPersistenceEncoder.encodeActivity(
            id: id, threadId: threadId, turnId: turnId,
            kind: kind, summary: summary, payload: payload
        ))
        if let error = result?.errorMessage {
            logger.warning("activity.append failed (\(kind, privacy: .public)): \(error, privacy: .public)")
        }
    }

    func updateSessionStatus(
        threadId: String, provider: String, transportKind: String,
        status: String, resumeStrategy: String = "none",
        providerSessionId: String? = nil, resumeCursorJson: String? = nil,
        capabilities: String? = nil
    ) async {
        let result = await send(method: "session.upsert", params: ACPPersistenceEncoder.encodeSessionUpsert(
            threadId: threadId, provider: provider, transportKind: transportKind,
            status: status, resumeStrategy: resumeStrategy,
            capabilities: capabilities, providerSessionId: providerSessionId,
            resumeCursorJson: resumeCursorJson
        ))
        if let error = result?.errorMessage {
            logger.warning("session.upsert failed (\(status, privacy: .public)): \(error, privacy: .public)")
        }
    }

    func updateThreadTitle(id: String, title: String) async {
        _ = await send(method: "thread.update", params: ["id": id, "title": title])
        threadChangeCounter += 1
    }

    /// Reads stored session metadata for a thread (resume strategy, provider session ID, capabilities).
    func getSession(threadId: String) async -> [String: Any]? {
        let result = await send(method: "session.get", params: ["threadId": threadId])
        if let error = result?.errorMessage {
            logger.warning("session.get failed for thread \(threadId, privacy: .public): \(error, privacy: .public)")
        }
        return result?.value
    }

    func deleteThread(id: String) async -> Bool {
        let result = await send(method: "thread.delete", params: ["id": id])
        if result?.ok == true { threadChangeCounter += 1 }
        return result?.ok == true
    }

    func exportMarkdown(threadId: String) async -> String? {
        let result = await send(method: "export.markdown", params: ["threadId": threadId])
        return result?.value?["markdown"] as? String
    }

    func exportJSON(threadId: String) async -> String? {
        let result = await send(method: "export.json", params: ["threadId": threadId])
        guard let value = result?.value,
              let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func listMessages(threadId: String, limit: Int = 2000) async -> [[String: Any]] {
        let result = await send(method: "message.list", params: ["threadId": threadId, "limit": limit])
        return result?.value?["messages"] as? [[String: Any]] ?? []
    }

    /// Reads a thread's metadata (vibespaceId, projectPath, agentId, transportKind, model, etc.).
    func getThread(id: String) async -> [String: Any]? {
        let result = await send(method: "thread.get", params: ["id": id])
        if let error = result?.errorMessage {
            logger.warning("thread.get failed for \(id, privacy: .public): \(error, privacy: .public)")
        }
        return result?.value
    }

    // MARK: - RPC Types

    struct RPCResult {
        let ok: Bool
        let value: [String: Any]?
        let errorMessage: String?
    }

    // MARK: - Keychain

    private func loadOrCreateEncryptionKey() throws -> Data {
        let keychain = KeychainStore(service: config.keychainService)
        let account = "db-encryption-key"

        if let existing = try keychain.read(account: account) {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentConversationStoreError.keychainFailure
        }
        let key = Data(bytes)
        try keychain.write(key, account: account)
        return key
    }

    // MARK: - Process Lifecycle

    private func spawnHelper(key: Data) async throws {
        guard let helperURL = config.helperURL else {
            throw AgentConversationStoreError.helperMissing
        }

        let dbPath = config.databasePath
        let dbDir = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)

        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = helperURL
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        let weakSelf = Weak(self)
        proc.terminationHandler = { _ in
            Task { @MainActor in weakSelf.value?.handleProcessTermination() }
        }

        try proc.run()

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        startReadLoop(stdoutPipe.fileHandleForReading)
        startStderrLoop(stderrPipe.fileHandleForReading)

        // Send init
        let hexKey = key.map { String(format: "%02x", $0) }.joined()
        let result = await sendRaw(
            id: "init",
            method: "init",
            params: ["dbPath": dbPath, "hexKey": hexKey]
        )

        guard let result, result.ok,
              let schemaVersion = (result.value?["schemaVersion"] as? NSNumber)?.intValue else {
            let reason = result?.errorMessage ?? "init failed"
            teardownProcess()
            throw AgentConversationStoreError.initFailed(reason)
        }

        state = .ready(schemaVersion: schemaVersion)
        logger.info("Persistence helper ready, schema v\(schemaVersion)")
    }

    private func teardownProcess() {
        readTask?.cancel()
        stderrTask?.cancel()
        readTask = nil
        stderrTask = nil

        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        stderrHandle?.closeFile()
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(returning: RPCResult(ok: false, value: nil, errorMessage: "helper terminated"))
        }
        pendingRequests.removeAll()

        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }

    private func handleProcessTermination() {
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        // Fail pending
        for (_, continuation) in pendingRequests {
            continuation.resume(returning: RPCResult(ok: false, value: nil, errorMessage: "helper crashed"))
        }
        pendingRequests.removeAll()

        guard restartAttempts < maxRestartAttempts, let key = cachedKey else {
            state = .ephemeral(reason: "helper crashed, \(restartAttempts) restart attempts exhausted")
            return
        }

        restartAttempts += 1
        let delay = UInt64(pow(2.0, Double(restartAttempts - 1))) * 1_000_000_000
        state = .starting
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            do {
                try await self?.spawnHelper(key: key)
                self?.restartAttempts = 0
            } catch {
                self?.state = .ephemeral(reason: "restart failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - JSON-RPC I/O

    private func sendRaw(id: String, method: String, params: [String: Any]) async -> RPCResult? {
        guard let stdinHandle else { return nil }

        let message: [String: Any] = ["id": id, "method": method, "params": params]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              var payload = String(data: jsonData, encoding: .utf8) else { return nil }
        payload.append("\n")

        do {
            try stdinHandle.write(contentsOf: Data(payload.utf8))
        } catch {
            return RPCResult(ok: false, value: nil, errorMessage: "write failed: \(error.localizedDescription)")
        }

        return await withCheckedContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    private func handleResponseLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else { return }

        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }

        if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "unknown error"
            consecutiveErrors += 1
            if consecutiveErrors >= maxConsecutiveErrors, case .ready = state {
                state = .ephemeral(reason: "too many consecutive errors")
                teardownProcess()
            }
            continuation.resume(returning: RPCResult(ok: false, value: nil, errorMessage: msg))
        } else {
            consecutiveErrors = 0
            let result = json["result"] as? [String: Any]
            continuation.resume(returning: RPCResult(ok: true, value: result, errorMessage: nil))
        }
    }

    // MARK: - Read Loops

    private func startReadLoop(_ handle: FileHandle) {
        let weakSelf = Weak(self)
        readTask = Task.detached(priority: .userInitiated) {
            var buffer = Data()
            for await chunk in Self.chunkStream(from: handle, label: "com.crispyvibe.app.persistence.stdout") {
                guard !Task.isCancelled else { break }
                buffer.append(chunk)
                while let idx = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<idx])
                    buffer.removeSubrange(...idx)
                    guard !line.isEmpty else { continue }
                    await MainActor.run { weakSelf.value?.handleResponseLine(line) }
                }
            }
        }
    }

    private func startStderrLoop(_ handle: FileHandle) {
        let weakSelf = Weak(self)
        stderrTask = Task.detached(priority: .utility) {
            for await chunk in Self.chunkStream(from: handle, label: "com.crispyvibe.app.persistence.stderr") {
                guard !Task.isCancelled else { break }
                if let text = String(data: chunk, encoding: .utf8) {
                    await MainActor.run {
                        weakSelf.value?.logger.debug("persistence-helper stderr: \(text, privacy: .public)")
                    }
                }
            }
        }
    }

    private nonisolated static func chunkStream(from handle: FileHandle, label: String) -> AsyncStream<Data> {
        AsyncStream { continuation in
            DispatchQueue(label: label).async {
                while true {
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { break }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Helpers

    private final class Weak<T: AnyObject>: @unchecked Sendable {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
}

enum AgentConversationStoreError: LocalizedError {
    case helperMissing
    case keychainFailure
    case initFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: return "Persistence helper binary not found."
        case .keychainFailure: return "Failed to generate encryption key."
        case .initFailed(let reason): return "Persistence init failed: \(reason)"
        }
    }
}
