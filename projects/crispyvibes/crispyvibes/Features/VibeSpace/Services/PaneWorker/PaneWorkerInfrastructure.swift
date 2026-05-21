import Foundation

protocol PaneWorkerExecuting: Sendable {
    func restart() async
    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String?
}

enum PaneWorkerExecutionMode: Equatable {
    case inProcess
    case subprocess

    static func resolve(
        from environment: [String: String],
        isPaneTaskProcess: Bool
    ) -> PaneWorkerExecutionMode {
        if isPaneTaskProcess {
            return .inProcess
        }

        // Default the app process to subprocess workers so expensive pane tasks can be isolated
        // unless a test or debugging session explicitly opts back into in-process execution.
        switch environment["CRISPYVIBES_PANE_WORKER_EXECUTION_MODE"]?.lowercased() {
        case "inprocess":
            return .inProcess
        case "subprocess", nil:
            return .subprocess
        default:
            return .subprocess
        }
    }
}

enum PaneWorkerKind: String, Codable {
    case explorer
    case sourceControl
    case editor
    case terminal
}

enum PaneWorkerMethod: String, Codable {
    case ping
    case listTree
    case gitDiscoverRepositories
    case gitDiscoverRepositoriesBatch
    case gitRepositorySnapshot
    case gitStatus
    case gitBranches
    case gitStage
    case gitUnstage
    case gitUnstageAll
    case gitStageAll
    case gitDiscard
    case gitDiscardAll
    case gitCommit
    case gitPush
    case gitPull
    case gitFetch
    case gitCheckoutBranch
    case gitCommitHistory
    case gitFileHistory
    case gitFileContent
    case gitCurrentBranch
    case gitHubCloneOptions
    case gitDiff
    case createFile
    case createFolder
    case renameItem
    case moveItem
    case copyItem
    case deleteItem
    case readFile
    case writeFile
    case gitCloneRepository
}

struct PaneWorkerRequest: Codable {
    let method: PaneWorkerMethod
    let arguments: [String: String]
}

struct PaneWorkerResponse: Codable {
    let success: Bool
    let value: String?
    let error: String?
}

struct PaneWorkerSessionRequestEnvelope: Codable {
    let requestID: UInt64
    let request: PaneWorkerRequest
}

struct PaneWorkerSessionResponseEnvelope: Codable {
    let requestID: UInt64
    let response: PaneWorkerResponse
}

struct WorkerFileNode: Codable {
    let path: String
    let isDirectory: Bool
    let isHidden: Bool
    let isGitIgnored: Bool
    let children: [WorkerFileNode]?
}

struct WorkerGitStatusNode: Codable {
    let code: String
    let indexStatus: String
    let workTreeStatus: String
    let path: String
    let relativePath: String
}

struct WorkerGitStatusPayload: Codable {
    let gitAvailable: Bool
    let repository: Bool
    let entries: [WorkerGitStatusNode]
    let message: String?
}

struct WorkerGitRepositoryNode: Codable {
    let repositoryRootPath: String
}

struct WorkerGitRepositoryDiscoveryPayload: Codable {
    let gitAvailable: Bool
    let repositories: [WorkerGitRepositoryNode]
    let message: String?
}

struct WorkerGitRepositoryDiscoveryBatchEntry: Codable {
    let projectRootPath: String
    let payload: WorkerGitRepositoryDiscoveryPayload
}

struct WorkerGitRepositoryDiscoveryBatchPayload: Codable {
    let results: [WorkerGitRepositoryDiscoveryBatchEntry]
}

struct WorkerGitBranchNode: Codable {
    let name: String
    let displayName: String
    let isCurrent: Bool
    let isRemote: Bool
}

struct WorkerGitBranchesPayload: Codable {
    let gitAvailable: Bool
    let repository: Bool
    let currentBranch: String?
    let branches: [WorkerGitBranchNode]
    let message: String?
}

struct WorkerGitRepositorySnapshotPayload: Codable {
    let gitAvailable: Bool
    let repository: Bool
    let entries: [WorkerGitStatusNode]
    let currentBranch: String?
    let branches: [WorkerGitBranchNode]
    let message: String?
}

struct WorkerGitHistoryEntry: Codable {
    let hash: String
    let shortHash: String
    let authorName: String
    let authoredDate: String
    let subject: String
}

struct WorkerGitHistoryPayload: Codable {
    let entries: [WorkerGitHistoryEntry]
}

struct WorkerGitHubRepositoryNode: Codable, Equatable, Identifiable {
    let nameWithOwner: String
    let cloneURL: String
    let description: String?
    let isPrivate: Bool
    let updatedAt: String?

    var id: String { cloneURL }
}

struct WorkerGitHubCloneOptionsPayload: Codable, Equatable {
    let cliAvailable: Bool
    let authenticated: Bool
    let repositories: [WorkerGitHubRepositoryNode]
    let message: String?
}

struct PaneWorkerStatus: Equatable {
    enum Level: String {
        case healthy
        case busy
        case unavailable
    }

    let level: Level
    let message: String

    static let ready = PaneWorkerStatus(level: .healthy, message: "Ready")

    static func busy(_ message: String = "Working") -> PaneWorkerStatus {
        PaneWorkerStatus(level: .busy, message: message)
    }

    static func unavailable(_ message: String) -> PaneWorkerStatus {
        PaneWorkerStatus(level: .unavailable, message: message)
    }
}

enum PaneWorkerError: LocalizedError {
    case executableNotFound
    case timeout(TimeInterval)
    case invalidResponse
    case workerFailure(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Unable to locate the worker executable."
        case let .timeout(seconds):
            return String(format: "Worker timed out after %.1f seconds.", seconds)
        case .invalidResponse:
            return "Worker returned an invalid response."
        case let .workerFailure(message):
            return message
        }
    }
}

actor PaneWorkerClient {
    private let pane: PaneWorkerKind
    private var activeSession: PaneWorkerPersistentSession?
    private var generation = 0
    private let executionMode: PaneWorkerExecutionMode
    private var nextRequestID: UInt64 = 0
    private var requestInFlight = false
    private var waitingRequestContinuations: [CheckedContinuation<Void, Never>] = []

    init(pane: PaneWorkerKind) {
        self.pane = pane
        self.executionMode = PaneWorkerExecutionMode.resolve(
            from: ProcessInfo.processInfo.environment,
            isPaneTaskProcess: PaneWorkerBootstrap.isPaneTaskProcess
        )
    }

    func restart() {
        generation += 1
        invalidatePersistentSession()
    }

    deinit { activeSession?.terminate() }

    func ping(timeout: TimeInterval = 3.0) async throws {
        _ = try await execute(.ping, arguments: [:], timeout: timeout)
    }

    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval = 8.0
    ) async throws -> String? {
        switch executionMode {
        case .inProcess:
            return try await executeInProcess(
                method,
                arguments: arguments,
                timeout: timeout
            )
        case .subprocess:
            return try await executeViaSubprocess(
                method,
                arguments: arguments,
                timeout: timeout
            )
        }
    }

    private func executeInProcess(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String? {
        let request = PaneWorkerRequest(method: method, arguments: arguments)
        let clampedTimeout = max(0, timeout)

        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { [pane] in
                let response = PaneWorkerExecutor.execute(pane: pane, request: request)
                if response.success {
                    return response.value
                }
                throw PaneWorkerError.workerFailure(response.error ?? "Worker reported an unknown error.")
            }

            group.addTask {
                if clampedTimeout > 0 {
                    let timeoutNanoseconds = UInt64(clampedTimeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                throw PaneWorkerError.timeout(clampedTimeout)
            }

            guard let firstResult = try await group.next() else {
                throw PaneWorkerError.invalidResponse
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func executeViaSubprocess(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String? {
        await acquireRequestSlot()
        defer { releaseRequestSlot() }

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        let expectedGeneration = generation
        var shouldRetryTransportFailure = true

        while true {
            do {
                return try await performPersistentSessionRequest(
                    method,
                    arguments: arguments,
                    timeout: timeout,
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard shouldRetryTransportFailure,
                      shouldResetPersistentSession(for: error) else {
                    throw mapPersistentSessionError(error)
                }
                shouldRetryTransportFailure = false
                invalidatePersistentSessionIfNeeded(expectedGeneration: expectedGeneration)
            }
        }
    }

    private func performPersistentSessionRequest(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval,
        expectedGeneration: Int
    ) async throws -> String? {
        let session = try ensurePersistentSession(expectedGeneration: expectedGeneration)
        let requestID = nextRequestID
        nextRequestID &+= 1
        let envelope = PaneWorkerSessionRequestEnvelope(
            requestID: requestID,
            request: PaneWorkerRequest(method: method, arguments: arguments)
        )

        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let responseEnvelope = try await session.execute(envelope)
                guard responseEnvelope.requestID == requestID else {
                    throw PaneWorkerError.invalidResponse
                }
                if responseEnvelope.response.success {
                    return responseEnvelope.response.value
                }
                throw PaneWorkerError.workerFailure(
                    responseEnvelope.response.error ?? "Worker reported an unknown error."
                )
            }

            group.addTask { [self] in
                if timeout > 0 {
                    let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                await invalidatePersistentSessionIfNeeded(expectedGeneration: expectedGeneration)
                throw PaneWorkerError.timeout(timeout)
            }

            guard let firstResult = try await group.next() else {
                throw PaneWorkerError.invalidResponse
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func shouldResetPersistentSession(for error: Error) -> Bool {
        if let persistentError = error as? PaneWorkerPersistentSessionError {
            switch persistentError {
            case .workerFailure, .invalidResponse:
                return true
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EBADF) || nsError.code == Int(EPIPE) {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        return description.contains("bad file descriptor")
            || description.contains("broken pipe")
    }

    private func mapPersistentSessionError(_ error: Error) -> Error {
        if let paneWorkerError = error as? PaneWorkerError {
            return paneWorkerError
        }

        if let persistentError = error as? PaneWorkerPersistentSessionError {
            switch persistentError {
            case let .workerFailure(message):
                return PaneWorkerError.workerFailure(message)
            case .invalidResponse:
                return PaneWorkerError.invalidResponse
            }
        }

        return PaneWorkerError.workerFailure(error.localizedDescription)
    }

    private func ensurePersistentSession(expectedGeneration: Int) throws -> PaneWorkerPersistentSession {
        if let activeSession, activeSession.isRunning {
            return activeSession
        }

        let executableURL = try locateExecutableURL()
        let session = try PaneWorkerPersistentSession(executableURL: executableURL, pane: pane)
        guard generation == expectedGeneration else {
            session.terminate()
            throw PaneWorkerError.workerFailure("Worker restarted before the request could begin.")
        }
        activeSession = session
        return session
    }

    private func invalidatePersistentSession() {
        activeSession?.terminate()
        activeSession = nil
    }

    private func invalidatePersistentSessionIfNeeded(expectedGeneration: Int) {
        guard generation == expectedGeneration else { return }
        invalidatePersistentSession()
    }

    private func acquireRequestSlot() async {
        guard requestInFlight else {
            requestInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            waitingRequestContinuations.append(continuation)
        }
    }

    private func releaseRequestSlot() {
        if let continuation = waitingRequestContinuations.first {
            waitingRequestContinuations.removeFirst()
            continuation.resume()
        } else {
            requestInFlight = false
        }
    }

    private func locateExecutableURL() throws -> URL {
        if let bundleURL = Bundle.main.executableURL {
            return bundleURL
        }
        if let argv0 = ProcessInfo.processInfo.arguments.first {
            return URL(fileURLWithPath: argv0)
        }
        throw PaneWorkerError.executableNotFound
    }
}

extension PaneWorkerClient: PaneWorkerExecuting {}

enum PaneWorkerBootstrap {
    static var isPaneTaskProcess: Bool {
        let args = CommandLine.arguments
        guard args.count >= 3 else { return false }
        switch args[1] {
        case "--pane-task", "--pane-task-session":
            return PaneWorkerKind(rawValue: args[2]) != nil
        default:
            return false
        }
    }

    static func runIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard args.count >= 3,
              let pane = PaneWorkerKind(rawValue: args[2]) else {
            return false
        }

        switch args[1] {
        case "--pane-task":
            applyWorkerProcessName(pane: pane)
            runSingleRequestWorker(pane: pane)
            return true
        case "--pane-task-session":
            applyWorkerProcessName(pane: pane)
            runPersistentSessionWorker(pane: pane)
            return true
        default:
            return false
        }
    }

    private static func applyWorkerProcessName(pane: PaneWorkerKind) {
        let base = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "Crispy"
        ProcessInfo.processInfo.processName = "\(base) (\(pane.rawValue) worker)"
    }

    private static func runSingleRequestWorker(pane: PaneWorkerKind) {
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        let response: PaneWorkerResponse = autoreleasepool {
            do {
                let request = try JSONDecoder().decode(PaneWorkerRequest.self, from: inputData)
                return PaneWorkerExecutor.execute(pane: pane, request: request)
            } catch {
                return PaneWorkerResponse(
                    success: false,
                    value: nil,
                    error: "Invalid worker request: \(error.localizedDescription)"
                )
            }
        }

        writeSingleResponse(response)
    }

    private static func runPersistentSessionWorker(pane: PaneWorkerKind) {
        let inputHandle = FileHandle.standardInput
        var inputBuffer = Data()

        while let requestData = readDelimitedMessage(from: inputHandle, buffer: &inputBuffer) {
            autoreleasepool {
                let responseEnvelope: PaneWorkerSessionResponseEnvelope
                do {
                    let envelope = try JSONDecoder().decode(
                        PaneWorkerSessionRequestEnvelope.self,
                        from: requestData
                    )
                    let response = PaneWorkerExecutor.execute(pane: pane, request: envelope.request)
                    responseEnvelope = PaneWorkerSessionResponseEnvelope(
                        requestID: envelope.requestID,
                        response: response
                    )
                } catch {
                    responseEnvelope = PaneWorkerSessionResponseEnvelope(
                        requestID: 0,
                        response: PaneWorkerResponse(
                            success: false,
                            value: nil,
                            error: "Invalid worker request: \(error.localizedDescription)"
                        )
                    )
                }

                do {
                    var outputData = try JSONEncoder().encode(responseEnvelope)
                    outputData.append(0x0A)
                    FileHandle.standardOutput.write(outputData)
                } catch {
                    let fallback = "{\"requestID\":0,\"response\":{\"success\":false,\"error\":\"Failed to encode worker response.\"}}\n"
                    if let data = fallback.data(using: .utf8) {
                        FileHandle.standardOutput.write(data)
                    }
                }
            }
        }
    }

    private static func writeSingleResponse(_ response: PaneWorkerResponse) {
        do {
            let outputData = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(outputData)
        } catch {
            let fallback = "{\"success\":false,\"error\":\"Failed to encode worker response.\"}"
            if let data = fallback.data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        }
    }

    private static func readDelimitedMessage(
        from handle: FileHandle,
        buffer: inout Data
    ) -> Data? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let message = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return Data(message)
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                guard !buffer.isEmpty else { return nil }
                let remaining = buffer
                buffer.removeAll(keepingCapacity: false)
                return remaining
            }
            buffer.append(chunk)
        }
    }
}

/// Mutable box for transferring values across concurrency boundaries where
/// access is serialized externally (e.g. via DispatchGroup).
///
/// - Warning: Callers **must** provide external synchronization. Reading
///   `value` before the writing thread has completed (e.g. before
///   `DispatchGroup.wait()` returns) is a data race.
final class UnsafeMutableTransferBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private enum PaneWorkerPersistentSessionError: Error {
    case workerFailure(String)
    case invalidResponse
}

private final class PaneWorkerPersistentSession: @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let stderrStore = PaneWorkerSessionLogStore()
    private let ioQueue: DispatchQueue
    private var stdoutBuffer = Data()

    var isRunning: Bool {
        process.isRunning
    }

    init(executableURL: URL, pane: PaneWorkerKind) throws {
        self.process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        self.stdinHandle = inputPipe.fileHandleForWriting
        self.stdoutHandle = outputPipe.fileHandleForReading
        self.stderrHandle = errorPipe.fileHandleForReading
        self.ioQueue = DispatchQueue(label: "com.crispyvibe.app.worker.session.\(pane.rawValue)")

        process.executableURL = Self.workerExecutableURL(for: pane, mainExecutable: executableURL)
        process.arguments = ["--pane-task-session", pane.rawValue]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        stderrHandle.readabilityHandler = { [stderrStore] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stderrStore.append(data)
        }

        try process.run()
    }

    deinit {
        terminate()
    }

    func terminate() {
        ioQueue.sync {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            stdinHandle.closeFile()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()
        }
    }

    func execute(
        _ envelope: PaneWorkerSessionRequestEnvelope
    ) async throws -> PaneWorkerSessionResponseEnvelope {
        final class CompletionGate: @unchecked Sendable {
            private let lock = NSLock()
            private var didComplete = false

            func markIfNeeded() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !didComplete else { return false }
                didComplete = true
                return true
            }
        }

        var requestData = try JSONEncoder().encode(envelope)
        requestData.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            let completionGate = CompletionGate()

            func complete(_ result: Result<PaneWorkerSessionResponseEnvelope, Error>) {
                guard completionGate.markIfNeeded() else { return }
                continuation.resume(with: result)
            }

            ioQueue.async { [self] in
                do {
                    try stdinHandle.write(contentsOf: requestData)
                    let responseData = try readNextResponseLine()
                    let response = try JSONDecoder().decode(
                        PaneWorkerSessionResponseEnvelope.self,
                        from: responseData
                    )
                    complete(.success(response))
                } catch {
                    complete(.failure(error))
                }
            }
        }
    }

    private func readNextResponseLine() throws -> Data {
        while true {
            if let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = stdoutBuffer.prefix(upTo: newlineIndex)
                stdoutBuffer.removeSubrange(...newlineIndex)
                return Data(line)
            }

            let chunk = stdoutHandle.availableData
            guard !chunk.isEmpty else {
                let detail = stderrStore.text ?? "Worker process exited unexpectedly."
                throw PaneWorkerPersistentSessionError.workerFailure(detail)
            }
            stdoutBuffer.append(chunk)
        }
    }

    /// Returns a symlink to the main executable with a pane-specific name so
    /// Activity Monitor shows distinct entries per worker kind.
    private static func workerExecutableURL(
        for pane: PaneWorkerKind,
        mainExecutable: URL
    ) -> URL {
        let appName = mainExecutable.deletingPathExtension().lastPathComponent
        let symlinkName = "\(appName)-\(pane.rawValue)-worker"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.crispyvibe.app.workers", isDirectory: true)
        let symlinkURL = directory.appendingPathComponent(symlinkName)

        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Recreate if target changed (e.g. rebuild)
        if let existing = try? fm.destinationOfSymbolicLink(atPath: symlinkURL.path),
           existing == mainExecutable.path {
            return symlinkURL
        }
        try? fm.removeItem(at: symlinkURL)
        do {
            try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: mainExecutable)
            return symlinkURL
        } catch {
            return mainExecutable
        }
    }
}

private final class PaneWorkerSessionLogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maxBytes = 16 * 1024

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
        if data.count > maxBytes {
            data.removeFirst(data.count - maxBytes)
        }
    }

    var text: String? {
        lock.lock()
        defer { lock.unlock() }
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
