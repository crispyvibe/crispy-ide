import Combine
import Foundation

struct ACPHostContext {
    let projectRootURL: URL
    let projectIdentifier: String
    let projectDisplayName: String
    let fileContentProvider: any FileContentProviding
    let terminalProvider: AnyTerminalProvider?

    init(
        projectRootURL: URL,
        projectIdentifier: String,
        projectDisplayName: String,
        fileContentProvider: any FileContentProviding,
        terminalProvider: AnyTerminalProvider?
    ) {
        self.projectRootURL = projectRootURL.standardizedFileURL
        self.projectIdentifier = projectIdentifier
        self.projectDisplayName = projectDisplayName
        self.fileContentProvider = fileContentProvider
        self.terminalProvider = terminalProvider
    }

    @MainActor
    init(project: AnyProjectSession) {
        self.init(
            projectRootURL: project.rootURL,
            projectIdentifier: project.projectIdentifier,
            projectDisplayName: project.title,
            fileContentProvider: project.fileContent,
            terminalProvider: project.terminal
        )
    }

    static func background(workingDirectory: URL) -> ACPHostContext {
        ACPHostContext(
            projectRootURL: workingDirectory,
            projectIdentifier: workingDirectory.standardizedFileURL.path,
            projectDisplayName: workingDirectory.lastPathComponent,
            fileContentProvider: LocalFileContentProvider(),
            terminalProvider: nil
        )
    }
}

enum ACPHandlerError: LocalizedError {
    case missingParameter(String)
    case invalidEncoding(String)
    case outsideProjectBoundary(String)
    case unknownTerminal(String)

    var errorDescription: String? {
        switch self {
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidEncoding(let path):
            return "File is not valid UTF-8: \(path)"
        case .outsideProjectBoundary(let path):
            return "Path is outside project boundary: \(path)"
        case .unknownTerminal(let terminalId):
            return "Unknown terminal: \(terminalId)"
        }
    }
}

struct ACPFileSystemHandler: Sendable {
    let projectRootURL: URL
    let projectIdentifier: String
    let fileContentProvider: any FileContentProviding
    let observabilityStore: ACPObservabilityStore?
    let onFileWritten: @Sendable (URL) -> Void
    let onDiffGenerated: @Sendable (String, ACPDiff) -> Void

    init(
        hostContext: ACPHostContext,
        observabilityStore: ACPObservabilityStore? = nil,
        onFileWritten: @escaping @Sendable (URL) -> Void = { _ in },
        onDiffGenerated: @escaping @Sendable (String, ACPDiff) -> Void = { _, _ in }
    ) {
        self.projectRootURL = hostContext.projectRootURL
        self.projectIdentifier = hostContext.projectIdentifier
        self.fileContentProvider = hostContext.fileContentProvider
        self.observabilityStore = observabilityStore
        self.onFileWritten = onFileWritten
        self.onDiffGenerated = onDiffGenerated
    }

    func handleRead(params: [String: Any]) async throws -> [String: Any] {
        let startedAt = Date()
        let path = try resolvedPath(from: params)
        let data = try await fileContentProvider.readFile(at: path.path)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ACPHandlerError.invalidEncoding(path.path)
        }

        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.fs_read",
                projectToken: AppDiagnostics.pathToken(projectIdentifier),
                method: "fs/read_text_file",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: ["path": AppDiagnostics.pathToken(path.path)]
            )
        )

        if let startLine = params["line"] as? Int {
            let lines = content.components(separatedBy: "\n")
            let startIndex = max(startLine - 1, 0)
            guard startIndex < lines.count else { return ["content": ""] }
            let limit = params["limit"] as? Int ?? (lines.count - startIndex)
            let endIndex = min(startIndex + limit, lines.count)
            return ["content": lines[startIndex..<endIndex].joined(separator: "\n")]
        }

        return ["content": content]
    }

    func handleWrite(params: [String: Any]) async throws -> Any {
        let startedAt = Date()
        let path = try resolvedPath(from: params)
        guard let content = params["content"] as? String else {
            throw ACPHandlerError.missingParameter("content")
        }

        // Capture old content for diff generation
        let oldContent = try? await fileContentProvider.readFile(at: path.path)
        let oldText = oldContent.flatMap { String(data: $0, encoding: .utf8) }

        try await fileContentProvider.writeFile(at: path.path, contents: Data(content.utf8))
        onFileWritten(path)

        // Generate diff for UI
        let toolCallId = params["toolCallId"] as? String ?? params["_toolCallId"] as? String
        if let toolCallId {
            let diff = ACPDiff(path: path.lastPathComponent, oldText: oldText, newText: content)
            onDiffGenerated(toolCallId, diff)
        }
        onFileWritten(path)

        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.fs_write",
                projectToken: AppDiagnostics.pathToken(projectIdentifier),
                method: "fs/write_text_file",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: ["path": AppDiagnostics.pathToken(path.path)]
            )
        )
        return NSNull()
    }

    private func resolvedPath(from params: [String: Any]) throws -> URL {
        guard let pathString = params["path"] as? String else {
            throw ACPHandlerError.missingParameter("path")
        }
        let url = URL(fileURLWithPath: pathString).standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath()
        let resolvedRoot = projectRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedURL.path == resolvedRoot || resolvedURL.path.hasPrefix(resolvedRoot + "/") else {
            throw ACPHandlerError.outsideProjectBoundary(pathString)
        }
        return url
    }
}

@MainActor
final class ACPTerminalHandler {
    private var terminalMap: [String: UUID] = [:]
    private var exitContinuations: [String: [CheckedContinuation<Int32?, Never>]] = [:]
    private var outputBuffers: [String: String] = [:]
    private var nextID = 0

    let sessionIdentifier: String?
    var terminalProvider: AnyTerminalProvider?
    let observabilityStore: ACPObservabilityStore?

    init(
        sessionIdentifier: String? = nil,
        terminalProvider: AnyTerminalProvider? = nil,
        observabilityStore: ACPObservabilityStore? = nil
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.terminalProvider = terminalProvider
        self.observabilityStore = observabilityStore
    }

    func handleCreate(params: [String: Any]) -> [String: Any] {
        let startedAt = Date()
        nextID += 1
        let terminalID = "acp_term_\(nextID)"
        let command = params["command"] as? String ?? ""
        let args = params["args"] as? [String] ?? []
        let cwd = params["cwd"] as? String
        let fullCommand = ([command] + args).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let cwdURL = cwd.map(URL.init(fileURLWithPath:))

        if let terminalProvider {
            terminalProvider.createTab(
                directoryURL: cwdURL,
                customName: fullCommand.isEmpty ? "ACP Task" : fullCommand,
                origin: .acp(sessionID: sessionIdentifier ?? terminalID),
                tmuxSessionName: nil,
                startImmediately: true
            )
            if let tabID = terminalProvider.activeTabID {
                terminalMap[terminalID] = tabID
                if !fullCommand.isEmpty {
                    terminalProvider.session(for: tabID)?.sendCommand(fullCommand)
                }
                terminalProvider.session(for: tabID)?.onProcessTerminated = { [weak self] exitCode in
                    Task { @MainActor in
                        self?.handleExit(terminalID: terminalID, exitCode: exitCode)
                    }
                }
                terminalProvider.session(for: tabID)?.onOutputReceived = { [weak self] text in
                    Task { @MainActor in
                        var buf = self?.outputBuffers[terminalID] ?? ""
                        buf += text
                        if buf.count > 50000 { buf = String(buf.suffix(50000)) }
                        self?.outputBuffers[terminalID] = buf
                    }
                }
            }
        }

        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.terminal_create",
                method: "terminal/create",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: [
                    "terminalId": terminalID,
                    "commandHash": AppDiagnostics.sha256Hex(fullCommand).prefix(12).description,
                ]
            )
        )
        return ["terminalId": terminalID]
    }

    func handleOutput(params: [String: Any]) throws -> [String: Any] {
        let startedAt = Date()
        let terminalId = params["terminalId"] as? String ?? ""
        _ = try resolveTabID(params)
        let output = outputBuffers[terminalId] ?? ""
        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.terminal_output",
                method: "terminal/output",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true
            )
        )
        return ["output": output, "truncated": output.count >= 50000]
    }

    func handleWaitForExit(params: [String: Any]) async throws -> [String: Any] {
        let startedAt = Date()
        let terminalId = params["terminalId"] as? String ?? ""
        let tabID = try resolveTabID(params)
        if let exitCode = terminalProvider?.tabs.first(where: { $0.id == tabID })?.exitCode {
            return ["exitCode": exitCode, "signal": NSNull()]
        }

        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
            exitContinuations[terminalId, default: []].append(continuation)
        }

        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.terminal_wait",
                method: "terminal/wait_for_exit",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: ["terminalId": terminalId]
            )
        )
        return ["exitCode": exitCode as Any, "signal": NSNull()]
    }

    func handleKill(params: [String: Any]) throws -> [String: Any] {
        let startedAt = Date()
        let tabID = try resolveTabID(params)
        terminalProvider?.session(for: tabID)?.sendRawText("\u{3}")
        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.terminal_kill",
                method: "terminal/kill",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true
            )
        )
        return [:]
    }

    func handleRelease(params: [String: Any]) throws -> [String: Any] {
        let startedAt = Date()
        guard let terminalId = params["terminalId"] as? String else {
            throw ACPHandlerError.missingParameter("terminalId")
        }
        terminalMap.removeValue(forKey: terminalId)
        outputBuffers.removeValue(forKey: terminalId)
        if let continuations = exitContinuations.removeValue(forKey: terminalId) {
            for continuation in continuations {
                continuation.resume(returning: nil)
            }
        }
        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.terminal_release",
                method: "terminal/release",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: ["terminalId": terminalId]
            )
        )
        return [:]
    }

    private func handleExit(terminalID: String, exitCode: Int32?) {
        if let continuations = exitContinuations.removeValue(forKey: terminalID) {
            for continuation in continuations {
                continuation.resume(returning: exitCode)
            }
        }
    }

    private func resolveTabID(_ params: [String: Any]) throws -> UUID {
        guard let terminalId = params["terminalId"] as? String else {
            throw ACPHandlerError.missingParameter("terminalId")
        }
        guard let tabID = terminalMap[terminalId] else {
            throw ACPHandlerError.unknownTerminal(terminalId)
        }
        return tabID
    }

    func releasePendingExitWaits() {
        let continuations = exitContinuations.values.flatMap { $0 }
        exitContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }
}

@MainActor
final class ACPPermissionHandler: ObservableObject {
    struct PendingRequest: Identifiable {
        let id = UUID()
        let sessionId: String
        let toolCallId: String?
        let toolCallTitle: String
        let options: [ACPPermissionOption]
        let diffs: [ACPDiff]
        let continuation: CheckedContinuation<ACPPermissionOutcome, Never>
    }

    @Published var pendingRequest: PendingRequest?
    @Published var allowAll = false

    let observabilityStore: ACPObservabilityStore?
    var onDiffsReceived: ((_ toolCallId: String, _ content: [ACPToolCallContent]) -> Void)?

    init(observabilityStore: ACPObservabilityStore? = nil) {
        self.observabilityStore = observabilityStore
    }

    func handle(requestID: Int, params: [String: Any]) async -> [String: Any] {
        let startedAt = Date()
        let sessionId = params["sessionId"] as? String ?? ""
        let toolCall = params["toolCall"] as? [String: Any]
        let toolCallTitle = toolCall?["title"] as? String ?? "Permission requested"
        let toolCallId = toolCall?["toolCallId"] as? String
        let parsedContent = ACPToolCallContentParser.parse(toolCall?["content"] as? [[String: Any]])
        let diffs = parsedContent.compactMap { content in
            if case .diff(let diff) = content { return diff }
            return nil
        }

        if let toolCallId, !parsedContent.isEmpty {
            onDiffsReceived?(toolCallId, parsedContent)
        }

        let options: [ACPPermissionOption]
        if let rawOptions = params["options"] as? [[String: Any]] {
            options = rawOptions.map {
                ACPPermissionOption(
                    optionId: $0["optionId"] as? String ?? "",
                    name: $0["name"] as? String ?? "",
                    kind: $0["kind"] as? String ?? "allow_once"
                )
            }
        } else {
            options = [
                ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow_once"),
                ACPPermissionOption(optionId: "reject", name: "Deny", kind: "reject_once"),
            ]
        }

        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.permission_request",
                method: "session/request_permission",
                metadata: [
                    "sessionId": sessionId,
                    "toolCallId": toolCallId ?? "",
                    "title": toolCallTitle,
                ]
            )
        )

        if allowAll, let allowOption = options.first(where: { $0.kind.contains("allow") }) {
            observabilityStore?.record(
                ACPObservedEvent(
                    category: "handler.permission_resolved",
                    method: "session/request_permission",
                    duration: Date().timeIntervalSince(startedAt),
                    succeeded: true,
                    metadata: ["outcome": allowOption.optionId]
                )
            )
            return ACPPermissionOutcome.selected(optionId: allowOption.optionId).responseDict
        }

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ACPPermissionOutcome, Never>) in
            pendingRequest = PendingRequest(
                sessionId: sessionId,
                toolCallId: toolCallId,
                toolCallTitle: toolCallTitle,
                options: options,
                diffs: diffs,
                continuation: continuation
            )
        }

        if case .selected(let optionId) = outcome,
           options.first(where: { $0.optionId == optionId })?.kind == "allow_always" {
            allowAll = true
        }

        pendingRequest = nil
        let outcomeLabel: String
        switch outcome {
        case .cancelled:
            outcomeLabel = "cancelled"
        case .selected(let optionId):
            outcomeLabel = optionId
        }
        observabilityStore?.record(
            ACPObservedEvent(
                category: "handler.permission_resolved",
                method: "session/request_permission",
                duration: Date().timeIntervalSince(startedAt),
                succeeded: true,
                metadata: ["outcome": outcomeLabel]
            )
        )
        return outcome.responseDict
    }

    func resolve(_ outcome: ACPPermissionOutcome) {
        let request = pendingRequest
        pendingRequest = nil
        request?.continuation.resume(returning: outcome)
    }

    func revokeAllowAll() {
        allowAll = false
    }
}
