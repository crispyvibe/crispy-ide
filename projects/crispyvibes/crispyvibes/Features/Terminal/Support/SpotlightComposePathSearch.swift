import Foundation
import OSLog

struct SpotlightComposePathSearchMatch: Identifiable, Equatable {
    let rootPath: String
    let relativePath: String
    let absolutePath: String
    let isDirectory: Bool
    let indices: [Int]

    var id: String { absolutePath }

    var fileURL: URL {
        URL(fileURLWithPath: absolutePath).standardizedFileURL
    }

    func insertionText(currentDirectory: URL?) -> String? {
        TerminalFileDropSupport.shellEscapedRelativePath(
            for: fileURL,
            isDirectory: isDirectory,
            currentDirectory: currentDirectory
        )
    }
}

@MainActor
final class SpotlightComposePathSearchController: ObservableObject {
    @Published private(set) var matches: [SpotlightComposePathSearchMatch] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "spotlight.pathSearch")

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var activeSessionID = UUID().uuidString
    private var activeRoots: [URL] = []
    private var activeRootsSignature = ""
    private var latestQuery = ""
    private var stderrBuffer = ""

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func configure(searchRoots: [URL]) {
        let normalizedRoots = deduplicatedRoots(searchRoots)
        let newSignature = rootSignature(for: normalizedRoots)
        guard newSignature != activeRootsSignature else { return }

        activeRoots = normalizedRoots
        activeRootsSignature = newSignature

        if latestQuery.isEmpty {
            clearMatches()
            return
        }

        restart()
    }

    func updateQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery != latestQuery else { return }
        latestQuery = trimmedQuery
        errorMessage = nil

        guard !trimmedQuery.isEmpty else {
            stop()
            clearMatches()
            return
        }

        guard !activeRoots.isEmpty else {
            matches = []
            isSearching = false
            return
        }

        do {
            try startIfNeeded()
            isSearching = true
            try send(.update(.init(sessionID: activeSessionID, query: trimmedQuery)))
        } catch {
            logger.error("Spotlight path search update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            isSearching = false
            matches = []
            stopProcessOnly()
        }
    }

    func stop() {
        latestQuery = ""
        stopProcessOnly()
        clearMatches()
    }

    private func restart() {
        let query = latestQuery
        latestQuery = ""
        stopProcessOnly()
        clearMatches()
        if !query.isEmpty {
            updateQuery(query)
        }
    }

    private func clearMatches() {
        matches = []
        isSearching = false
        errorMessage = nil
    }

    private func startIfNeeded() throws {
        guard process == nil else { return }
        guard let helperURL = bundledHelperURL() else {
            throw SpotlightComposePathSearchError.helperMissing
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let controllerRef = WeakControllerRef(self)

        process.executableURL = helperURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleProcessTermination()
            }
        }

        try process.run()

        let sessionID = UUID().uuidString
        activeSessionID = sessionID
        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        stderrBuffer = ""

        stdoutTask = Task.detached(priority: .userInitiated) { [controllerRef, stdoutHandle = stdoutPipe.fileHandleForReading] in
            await Self.readStdoutLoop(stdoutHandle) { line in
                await MainActor.run {
                    controllerRef.value?.handleNotificationLine(line)
                }
            }
        }

        stderrTask = Task.detached(priority: .utility) { [controllerRef, stderrHandle = stderrPipe.fileHandleForReading] in
            await Self.readStderrLoop(stderrHandle) { text in
                await MainActor.run {
                    controllerRef.value?.appendStderr(text)
                }
            }
        }

        try send(
            .start(
                .init(
                    sessionID: sessionID,
                    roots: activeRoots.map(\.path)
                )
            )
        )
    }

    private func appendStderr(_ text: String) {
        stderrBuffer += text
        if stderrBuffer.count > 4096 {
            stderrBuffer = String(stderrBuffer.suffix(4096))
        }
    }

    private func bundledHelperURL() -> URL? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let helperURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("crispyvibes-path-search-helper", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: helperURL.path) ? helperURL : nil
    }

    private func stopProcessOnly() {
        if process?.isRunning == true, stdinHandle != nil {
            try? send(.stop(.init(sessionID: activeSessionID)))
        }

        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        stdinHandle?.closeFile()
        stdoutHandle?.closeFile()
        stderrHandle?.closeFile()
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
    }

    private func send(_ request: SpotlightComposePathSearchRequest) throws {
        guard let stdinHandle else {
            throw SpotlightComposePathSearchError.helperDisconnected
        }

        let encoder = JSONEncoder()
        var data = try encoder.encode(request)
        data.append(0x0A)
        try stdinHandle.write(contentsOf: data)
    }

    private static func readStdoutLoop(
        _ handle: FileHandle,
        onLine: @escaping @Sendable (Data) async -> Void
    ) async {
        var buffered = Data()

        for await chunk in chunkStream(
            from: handle,
            label: "com.crispyvibe.app.spotlight.pathSearch.stdout"
        ) {
            guard !Task.isCancelled else { break }
            buffered.append(chunk)

            while let newlineIndex = buffered.firstIndex(of: 0x0A) {
                let line = Data(buffered[..<newlineIndex])
                buffered.removeSubrange(...newlineIndex)
                guard !line.isEmpty else { continue }
                await onLine(line)
            }
        }
    }

    private static func readStderrLoop(
        _ handle: FileHandle,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async {
        for await chunk in chunkStream(
            from: handle,
            label: "com.crispyvibe.app.spotlight.pathSearch.stderr"
        ) {
            guard !Task.isCancelled else { break }
            if let text = String(data: chunk, encoding: .utf8) {
                await onChunk(text)
            }
        }
    }

    private static func chunkStream(
        from handle: FileHandle,
        label: String
    ) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: label)
            queue.async {
                while true {
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { break }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private final class WeakControllerRef: @unchecked Sendable {
        weak var value: SpotlightComposePathSearchController?

        init(_ value: SpotlightComposePathSearchController?) {
            self.value = value
        }
    }

    private func handleNotificationLine(_ data: Data) {
        do {
            let notification = try JSONDecoder().decode(SpotlightComposePathSearchNotification.self, from: data)
            apply(notification)
        } catch {
            logger.error("Spotlight path search decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ notification: SpotlightComposePathSearchNotification) {
        switch notification {
        case let .sessionUpdated(params):
            guard params.sessionID == activeSessionID, params.query == latestQuery else { return }
            matches = params.files.map {
                SpotlightComposePathSearchMatch(
                    rootPath: $0.root,
                    relativePath: $0.path,
                    absolutePath: URL(fileURLWithPath: $0.root).appendingPathComponent($0.path).standardizedFileURL.path,
                    isDirectory: $0.matchType == .directory,
                    indices: $0.indices ?? []
                )
            }
        case let .sessionCompleted(params):
            guard params.sessionID == activeSessionID, params.query == latestQuery else { return }
            isSearching = false
        }
    }

    private func handleProcessTermination() {
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        guard !latestQuery.isEmpty else { return }
        isSearching = false
        if !stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func deduplicatedRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private func rootSignature(for roots: [URL]) -> String {
        roots.map(\.path).joined(separator: "\n")
    }
}

private enum SpotlightComposePathSearchError: LocalizedError {
    case helperMissing
    case helperDisconnected

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "Bundled path search helper not found in the app executable directory."
        case .helperDisconnected:
            return "Bundled path search helper is not connected."
        }
    }
}

private enum SpotlightComposePathSearchRequest: Encodable {
    case start(SpotlightComposePathSearchStartParams)
    case update(SpotlightComposePathSearchUpdateParams)
    case stop(SpotlightComposePathSearchStopParams)

    enum CodingKeys: String, CodingKey {
        case method
        case params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .start(params):
            try container.encode("start", forKey: .method)
            try container.encode(params, forKey: .params)
        case let .update(params):
            try container.encode("update", forKey: .method)
            try container.encode(params, forKey: .params)
        case let .stop(params):
            try container.encode("stop", forKey: .method)
            try container.encode(params, forKey: .params)
        }
    }
}

private struct SpotlightComposePathSearchStartParams: Encodable {
    let sessionID: String
    let roots: [String]

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case roots
    }
}

private struct SpotlightComposePathSearchUpdateParams: Encodable {
    let sessionID: String
    let query: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case query
    }
}

private struct SpotlightComposePathSearchStopParams: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
    }
}

private enum SpotlightComposePathSearchNotification: Decodable {
    case sessionUpdated(SpotlightComposePathSearchUpdatedNotification)
    case sessionCompleted(SpotlightComposePathSearchCompletedNotification)

    enum CodingKeys: String, CodingKey {
        case method
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        switch method {
        case "sessionUpdated":
            self = .sessionUpdated(try container.decode(SpotlightComposePathSearchUpdatedNotification.self, forKey: .params))
        case "sessionCompleted":
            self = .sessionCompleted(try container.decode(SpotlightComposePathSearchCompletedNotification.self, forKey: .params))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unsupported notification method \(method)"
            )
        }
    }
}

private struct SpotlightComposePathSearchUpdatedNotification: Decodable {
    let sessionID: String
    let query: String
    let files: [SpotlightComposePathSearchFile]

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case query
        case files
    }
}

private struct SpotlightComposePathSearchCompletedNotification: Decodable {
    let sessionID: String
    let query: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case query
    }
}

private struct SpotlightComposePathSearchFile: Decodable {
    let root: String
    let path: String
    let matchType: SpotlightComposePathSearchMatchType
    let indices: [Int]?

    enum CodingKeys: String, CodingKey {
        case root
        case path
        case matchType = "match_type"
        case indices
    }
}

private enum SpotlightComposePathSearchMatchType: String, Decodable {
    case file
    case directory
}
