import Foundation
import OSLog

@MainActor
final class CodexSession: ObservableObject, Identifiable, AgentSessionProtocol {
    private static let maxToolOutputBufferLength = 262_144
    private static let maxJSONTraversalDepth = 8

    let id = UUID()
    let projectPath: URL
    let agentName: String
    var agentID: String { "codex" }

    private let executable: String
    private let trustMode: CLITrustMode
    private let model: String?
    private let reasoningLevel: AgentReasoningLevel
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "codex.session")

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrBuffer = ""
    private var activePromptContinuation: AsyncStream<ACPUpdate>.Continuation?
    private var readTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var threadID: String?
    /// The Codex app-server thread ID — stored for resume across session restarts.
    var providerThreadID: String? { threadID }
    private var hasStartedThread = false
    private var pendingResponses: [Int: CheckedContinuation<[String: Any]?, Error>] = [:]
    private var pendingResponseTimeoutTasks: [Int: Task<Void, Never>] = [:]
    private var toolOutputBuffers: [String: String] = [:]
    private var toolBaseContent: [String: [ACPToolCallContent]] = [:]

    @Published var isConnected = false
    private(set) var permissionHandler: ACPPermissionHandler?
    private var currentInteractionMode: String = "default"

    var transportKind: String { "codex_direct" }
    var providerSessionID: String? { threadID }
    var resumeStrategy: String { threadID != nil ? "native_resume" : "none" }

    var availableModes: [ACPModeInfo] {
        [
            ACPModeInfo(modeId: "default", name: "Default", description: "Agent acts immediately"),
            ACPModeInfo(modeId: "plan", name: "Plan", description: "Agent proposes before acting"),
        ]
    }
    var currentModeID: String? { currentInteractionMode }

    var availableModels: [ACPModelInfo] {
        guard let model else { return [] }
        return [ACPModelInfo(modelId: model, name: model, description: nil)]
    }

    var currentModelID: String? {
        model
    }

    init(
        projectPath: URL,
        executable: String = "codex",
        agentName: String = "Codex",
        trustMode: CLITrustMode = .standard,
        model: String? = nil,
        reasoningLevel: AgentReasoningLevel = .medium,
        resumeThreadID: String? = nil
    ) {
        self.projectPath = projectPath
        self.executable = executable
        self.agentName = agentName
        self.trustMode = trustMode
        self.model = model
        self.reasoningLevel = reasoningLevel
        self.threadID = resumeThreadID
    }

    func connect() async throws {
        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [executable, "app-server"]
        proc.currentDirectoryURL = projectPath
        proc.environment = CommandPathResolver.environmentWithResolvedPath()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stderrBuffer += text
                if self.stderrBuffer.count > 2048 {
                    self.stderrBuffer = String(self.stderrBuffer.suffix(2048))
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.activePromptContinuation?.finish()
                self.activePromptContinuation = nil
                self.toolOutputBuffers.removeAll()
                self.toolBaseContent.removeAll()
                for (_, continuation) in self.pendingResponses {
                    continuation.resume(returning: nil)
                }
                self.pendingResponses.removeAll()
                for timeoutTask in self.pendingResponseTimeoutTasks.values {
                    timeoutTask.cancel()
                }
                self.pendingResponseTimeoutTasks.removeAll()
            }
        }

        do {
            try proc.run()
        } catch {
            throw ACPTransportError.agentError("Failed to start codex: \(error.localizedDescription)")
        }

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        startReadLoop(stdout: stdout)

        let initializeResult = try await sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": ACPClientInfo.crispyvibes.name,
                    "title": ACPClientInfo.crispyvibes.title,
                    "version": ACPClientInfo.crispyvibes.version,
                ],
                "capabilities": ["experimentalApi": true],
            ]
        )

        guard initializeResult != nil else {
            process?.terminate()
            let authError = Self.detectAuthError(stderrBuffer)
            logStderrForDiagnostics(prefix: "Codex initialize failed")
            throw ACPTransportError.agentError(
                authError ?? "Codex initialize failed. Check app logs for diagnostics."
            )
        }

        // Codex app-server blocks until it receives this notification.
        writeJSON(["jsonrpc": "2.0", "method": "initialized"])

        isConnected = true
        logger.info("Codex App Server connected for \(self.projectPath.lastPathComponent)")
    }

    func prompt(_ text: String, contentBlocks: [[String: Any]]? = nil) -> AsyncStream<ACPUpdate> {
        AsyncStream<ACPUpdate> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task { @MainActor in
                self.activePromptContinuation?.finish()
                self.activePromptContinuation = continuation
                self.toolOutputBuffers.removeAll()
                self.toolBaseContent.removeAll()
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.activePromptContinuation = nil }
                }

                do {
                    if self.threadID == nil {
                        var threadParams: [String: Any] = [
                            "cwd": self.projectPath.path,
                            "approvalPolicy": self.trustMode == .fullTrust ? "never" : "on-request",
                            "sandbox": self.trustMode == .fullTrust ? "danger-full-access" : "vibespace-write",
                        ]
                        if let model = self.model {
                            threadParams["model"] = model
                        }
                        let threadResult = try await self.sendRequest(method: "thread/start", params: threadParams)
                        self.threadID = (threadResult?["thread"] as? [String: Any])?["id"] as? String
                            ?? threadResult?["threadId"] as? String
                    } else if !self.hasStartedThread {
                        // Resume a thread from a previous session using the stored threadID
                        var resumeParams: [String: Any] = [
                            "threadId": self.threadID!,
                            "cwd": self.projectPath.path,
                            "approvalPolicy": self.trustMode == .fullTrust ? "never" : "on-request",
                            "sandbox": self.trustMode == .fullTrust ? "danger-full-access" : "vibespace-write",
                        ]
                        if let model = self.model {
                            resumeParams["model"] = model
                        }
                        let resumeResult = try? await self.sendRequest(method: "thread/resume", params: resumeParams)
                        if resumeResult == nil {
                            // Resume failed — fall back to fresh thread
                            self.threadID = nil
                            var threadParams: [String: Any] = [
                                "cwd": self.projectPath.path,
                                "approvalPolicy": self.trustMode == .fullTrust ? "never" : "on-request",
                                "sandbox": self.trustMode == .fullTrust ? "danger-full-access" : "vibespace-write",
                            ]
                            if let model = self.model {
                                threadParams["model"] = model
                            }
                            let threadResult = try await self.sendRequest(method: "thread/start", params: threadParams)
                            self.threadID = (threadResult?["thread"] as? [String: Any])?["id"] as? String
                                ?? threadResult?["threadId"] as? String
                        }
                    }
                    self.hasStartedThread = true

                    // Build input array with text + images in Codex format
                    var input: [[String: Any]] = [["type": "text", "text": text]]
                    if let blocks = contentBlocks {
                        for block in blocks {
                            if block["type"] as? String == "image",
                               let data = block["data"] as? String,
                               let mediaType = block["mediaType"] as? String {
                                // Codex format: { type: "image", url: "data:mime;base64,..." }
                                input.append([
                                    "type": "image",
                                    "url": "data:\(mediaType);base64,\(data)",
                                ])
                            }
                        }
                    }

                    var turnParams: [String: Any] = [
                        "threadId": self.threadID ?? "",
                        "input": input,
                    ]
                    if let model = self.model {
                        turnParams["model"] = model
                    }
                    turnParams["effort"] = self.reasoningLevel == .max ? "high" : self.reasoningLevel.rawValue
                    // Collaboration mode for plan vs default (#12)
                    let effort = self.reasoningLevel == .max ? "high" : self.reasoningLevel.rawValue
                    turnParams["collaborationMode"] = [
                        "mode": self.currentInteractionMode,
                        "settings": [
                            "model": self.model ?? "codex-mini-latest",
                            "reasoning_effort": effort,
                            "developer_instructions": self.currentInteractionMode == "plan"
                                ? Self.planModeDeveloperInstructions
                                : Self.defaultModeDeveloperInstructions,
                        ] as [String: Any],
                    ] as [String: Any]
                    _ = try await self.sendRequest(method: "turn/start", params: turnParams)
                } catch {
                    self.logger.error("Codex prompt failed: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    func cancel() async {
        permissionHandler?.resolve(.cancelled)
        guard let threadID else { return }
        _ = try? await sendRequest(method: "turn/interrupt", params: ["threadId": threadID])
    }

    func setMode(_ modeID: String) async {
        currentInteractionMode = modeID
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil
        activePromptContinuation?.finish()
        activePromptContinuation = nil

        for (_, continuation) in pendingResponses {
            continuation.resume(returning: nil)
        }
        pendingResponses.removeAll()
        for timeoutTask in pendingResponseTimeoutTasks.values {
            timeoutTask.cancel()
        }
        pendingResponseTimeoutTasks.removeAll()

        stdinPipe?.fileHandleForWriting.closeFile()
        stdinPipe = nil
        stdoutPipe = nil

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isConnected = false
        threadID = nil
        toolOutputBuffers.removeAll()
        toolBaseContent.removeAll()
    }

    func installPermissionHandler(_ handler: ACPPermissionHandler) {
        permissionHandler = handler
    }

    private static func detectAuthError(_ stderr: String) -> String? {
        let lower = stderr.lowercased()
        let patterns = ["not logged in", "authentication", "sign in", "login required", "unauthorized", "chatgpt"]
        guard patterns.contains(where: { lower.contains($0) }) else { return nil }
        return "Codex authentication required. Run 'codex' in a terminal to sign in with ChatGPT, then try again."
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        timeout: TimeInterval = 10
    ) async throws -> [String: Any]? {
        let requestID = nextRequestID
        nextRequestID += 1
        let noTimeout = method == "turn/start" || method == "thread/start"

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any]?, Error>) in
            pendingResponses[requestID] = continuation
            if !noTimeout {
                pendingResponseTimeoutTasks[requestID] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        return
                    }
                    await MainActor.run {
                        self?.failPendingResponse(
                            requestID,
                            error: ACPTransportError.agentError("Timed out waiting for \(method) (>\(Int(timeout))s)")
                        )
                    }
                }
            }
            writeJSON([
                "jsonrpc": "2.0",
                "method": method,
                "id": requestID,
                "params": params,
            ])
        }
    }

    private func sendResponse(id: Any, result: [String: Any]) {
        writeJSON(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func writeJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let line = String(data: data, encoding: .utf8),
              let stdinPipe,
              process?.isRunning == true else { return }
        stdinPipe.fileHandleForWriting.write(Data((line + "\n").utf8))
    }

    private func startReadLoop(stdout: Pipe) {
        readTask = Task.detached { [weak self] in
            let handle = stdout.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                ACPTransport.extractJSONMessages(from: &buffer) { messageData in
                    guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.handleMessage(json)
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.activePromptContinuation?.finish()
                self?.activePromptContinuation = nil
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        let hasMethod = json["method"] is String
        let hasID = json["id"] != nil

        if hasID, hasMethod, let method = json["method"] as? String {
            handleServerRequest(method: method, json: json)
            return
        }

        if hasMethod, !hasID, let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            switch method {
            case "thread/started":
                threadID = (params["thread"] as? [String: Any])?["id"] as? String ?? params["threadId"] as? String
            case "turn/started":
                break
            case "turn/completed":
                handleTurnCompleted(params)
            case "turn/aborted":
                toolOutputBuffers.removeAll()
                toolBaseContent.removeAll()
                activePromptContinuation?.finish()
                activePromptContinuation = nil
            case "turn/diff/updated":
                handleTurnDiffUpdated(params)
            case "item/started":
                handleItemStarted(params)
            case "item/completed":
                handleItemCompleted(params)
            case "item/agentMessage/delta":
                yieldTextDelta(params)
            case "item/plan/delta":
                yieldPlanDelta(params)
            case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
                if let delta = extractDelta(params) {
                    activePromptContinuation?.yield(.thoughtChunk(.text(delta)))
                }
            case "item/commandExecution/outputDelta", "item/fileChange/outputDelta":
                handleOutputDelta(params)
            case "thread/tokenUsage/updated":
                activePromptContinuation?.yield(.sessionInfoUpdate(["tokenUsage": params]))
            case "session/exited", "session/closed":
                isConnected = false
                toolOutputBuffers.removeAll()
                toolBaseContent.removeAll()
                activePromptContinuation?.finish()
                activePromptContinuation = nil
            case "error":
                let message = (params["error"] as? [String: Any])?["message"] as? String ?? "Runtime error"
                activePromptContinuation?.yield(.agentMessageChunk(.text("\nError: \(message)\n")))
            default:
                break
            }
            return
        }

        if hasID, !hasMethod, let id = json["id"] as? Int,
           let continuation = pendingResponses.removeValue(forKey: id) {
            pendingResponseTimeoutTasks.removeValue(forKey: id)?.cancel()
            continuation.resume(returning: json["result"] as? [String: Any])
        }
    }

    private func failPendingResponse(_ requestID: Int, error: Error) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else { return }
        pendingResponseTimeoutTasks.removeValue(forKey: requestID)?.cancel()
        continuation.resume(throwing: error)
    }

    private func handleServerRequest(method: String, json: [String: Any]) {
        switch method {
        case "item/commandExecution/requestApproval",
             "item/fileRead/requestApproval",
             "item/fileChange/requestApproval":
            handleApprovalRequest(json)
        default:
            if let requestID = json["id"] {
                writeJSON([
                    "jsonrpc": "2.0",
                    "id": requestID,
                    "error": ["code": -32601, "message": "Unsupported: \(method)"],
                ])
            }
        }
    }

    private func handleTurnCompleted(_ params: [String: Any]) {
        if let turn = params["turn"] as? [String: Any],
           let cost = turn["totalCostUsd"] as? Double {
            let usage = turn["usage"] as? [String: Any]
            let input = usage?["input_tokens"] as? Int ?? 0
            let output = usage?["output_tokens"] as? Int ?? 0
            let summary = String(format: "Cost: $%.4f | Tokens: %d in / %d out", cost, input, output)
            activePromptContinuation?.yield(.sessionInfoUpdate(["usage": summary]))
        }
        toolOutputBuffers.removeAll()
        toolBaseContent.removeAll()
        activePromptContinuation?.finish()
        activePromptContinuation = nil
    }

    private func handleItemStarted(_ params: [String: Any]) {
        let item = params["item"] as? [String: Any] ?? params
        guard let itemType = item["type"] as? String ?? item["kind"] as? String else { return }
        let toolCallID = item["id"] as? String ?? UUID().uuidString
        let title = item["name"] as? String
            ?? item["command"] as? String
            ?? item["title"] as? String
            ?? itemType
        let locations = parseLocations(from: item)
        let content = parseToolContent(from: item, fallbackPath: locations.first?.path)

        switch itemType {
        case "function_call", "command_execution", "file_change", "mcp_tool_call":
            toolBaseContent[toolCallID] = content
            activePromptContinuation?.yield(.toolCall(ACPToolCallUpdate(
                toolCallId: toolCallID,
                title: title,
                kind: itemType,
                status: .inProgress,
                content: content,
                locations: locations
            )))
        default:
            break
        }
    }

    private func handleItemCompleted(_ params: [String: Any]) {
        let item = params["item"] as? [String: Any] ?? params
        guard let itemType = item["type"] as? String ?? item["kind"] as? String else { return }
        let toolCallID = item["id"] as? String ?? ""

        switch itemType {
        case "function_call", "command_execution", "file_change", "mcp_tool_call":
            var content = toolBaseContent[toolCallID] ?? []
            mergeUnique(contents: &content, additions: parseToolContent(from: item, fallbackPath: parseLocations(from: item).first?.path))
            let output = item["output"] as? String
                ?? item["summary"] as? String
                ?? toolOutputBuffers[toolCallID]
                ?? ""
            if !output.isEmpty {
                appendUnique(.text(output), into: &content)
            }
            activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
                toolCallId: toolCallID,
                status: .completed,
                content: content
            )))
            toolOutputBuffers.removeValue(forKey: toolCallID)
            toolBaseContent.removeValue(forKey: toolCallID)
        default:
            break
        }
    }

    private func handleOutputDelta(_ params: [String: Any]) {
        guard let delta = extractDelta(params) else { return }
        let itemID = params["itemId"] as? String ?? ""
        guard !itemID.isEmpty else { return }

        let updatedBuffer = (toolOutputBuffers[itemID, default: ""] + delta).suffix(Self.maxToolOutputBufferLength)
        toolOutputBuffers[itemID] = String(updatedBuffer)
        var content = toolBaseContent[itemID] ?? []
        if let output = toolOutputBuffers[itemID], !output.isEmpty {
            content.append(.text(output))
        }
        activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
            toolCallId: itemID,
            status: .inProgress,
            content: content
        )))
    }

    private func handleApprovalRequest(_ json: [String: Any]) {
        let params = json["params"] as? [String: Any] ?? [:]
        let requestID = json["id"]
        let toolCallID = firstString(in: params, matching: ["itemId", "toolCallId", "id"])
        let target = params["command"] as? String
            ?? params["path"] as? String
            ?? params["file_path"] as? String
            ?? "action"
        let reason = params["reason"] as? String ?? "Requires approval"
        let diffs = extractDiffs(from: params, fallbackPath: firstString(in: params, matching: Self.pathKeys))

        guard let permissionHandler else {
            if let requestID {
                sendResponse(id: requestID, result: ["decision": "deny"])
            }
            return
        }

        Task {
            let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ACPPermissionOutcome, Never>) in
                permissionHandler.pendingRequest = ACPPermissionHandler.PendingRequest(
                    sessionId: "\(requestID ?? "unknown")",
                    toolCallId: toolCallID,
                    toolCallTitle: "\(target): \(reason)",
                    options: [
                        ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow_once"),
                        ACPPermissionOption(optionId: "reject", name: "Deny", kind: "reject_once"),
                    ],
                    diffs: diffs,
                    continuation: continuation
                )
            }
            permissionHandler.pendingRequest = nil
            let approved: Bool
            switch outcome {
            case .selected(let optionID):
                approved = optionID.contains("allow")
            case .cancelled:
                approved = false
            }
            if let requestID {
                self.sendResponse(id: requestID, result: ["decision": approved ? "allow" : "deny"])
            }
        }
    }

    private func yieldTextDelta(_ params: [String: Any]) {
        guard let delta = extractDelta(params) else { return }
        activePromptContinuation?.yield(.agentMessageChunk(.text(delta)))
    }

    private func yieldPlanDelta(_ params: [String: Any]) {
        guard let delta = extractDelta(params), !delta.isEmpty else { return }
        activePromptContinuation?.yield(.thoughtChunk(.text(delta)))
    }

    private func handleTurnDiffUpdated(_ params: [String: Any]) {
        let itemID = firstString(in: params, matching: ["itemId", "toolCallId", "id"]) ?? ""
        guard !itemID.isEmpty else { return }

        var content = toolBaseContent[itemID] ?? []
        mergeUnique(contents: &content, additions: parseToolContent(from: params, fallbackPath: firstString(in: params, matching: Self.pathKeys)))
        if let output = toolOutputBuffers[itemID], !output.isEmpty {
            content.append(.text(output))
        }
        guard !content.isEmpty else { return }
        activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
            toolCallId: itemID,
            status: .inProgress,
            content: content
        )))
    }

    private func extractDelta(_ params: [String: Any]) -> String? {
        params["delta"] as? String
            ?? (params["textDelta"] as? [String: Any])?["text"] as? String
            ?? (params["delta"] as? [String: Any])?["text"] as? String
            ?? params["text"] as? String
    }

    private func parseLocations(from item: [String: Any]) -> [ACPToolCallLocation] {
        guard let path = firstString(in: item, matching: Self.pathKeys) else { return [] }
        let line = firstInt(in: item, matching: ["line", "lineNumber", "startLine"])
        return [ACPToolCallLocation(path: path, line: line)]
    }

    private func parseToolContent(from item: [String: Any], fallbackPath: String?) -> [ACPToolCallContent] {
        var content: [ACPToolCallContent] = []
        let path = fallbackPath ?? firstString(in: item, matching: Self.pathKeys)

        if let command = firstString(in: item, matching: ["command", "cmd"]), !command.isEmpty {
            content.append(.text(command))
        }

        appendDiffs(from: item, fallbackPath: path, into: &content, depth: 0)
        return content
    }

    private func extractDiffs(from item: [String: Any], fallbackPath: String?) -> [ACPDiff] {
        parseToolContent(from: item, fallbackPath: fallbackPath).compactMap { content in
            if case .diff(let diff) = content {
                return diff
            }
            return nil
        }
    }

    private func appendDiffs(from value: Any, fallbackPath: String?, into content: inout [ACPToolCallContent], depth: Int) {
        guard depth < Self.maxJSONTraversalDepth else { return }
        if let dict = value as? [String: Any] {
            let path = fallbackPath ?? firstString(in: dict, matching: Self.pathKeys, depth: depth + 1)

            if let newText = firstString(in: dict, matching: ["new_string", "newText", "content"], depth: depth + 1),
               let path {
                let oldText = firstString(in: dict, matching: ["old_string", "oldText"], depth: depth + 1)
                appendUnique(.diff(ACPDiff(path: path, oldText: oldText, newText: newText)), into: &content)
            }

            if let patch = firstString(in: dict, matching: ["unifiedDiff", "diff", "patch"], depth: depth + 1) {
                appendUnique(.diff(ACPDiff(path: path ?? "changes", oldText: nil, newText: patch)), into: &content)
            }

            if let edits = dict["edits"] as? [[String: Any]] {
                for edit in edits {
                    appendDiffs(from: edit, fallbackPath: path, into: &content, depth: depth + 1)
                }
            }

            if let changes = dict["changes"] as? [[String: Any]] {
                for change in changes {
                    appendDiffs(from: change, fallbackPath: path, into: &content, depth: depth + 1)
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                appendDiffs(from: item, fallbackPath: fallbackPath, into: &content, depth: depth + 1)
            }
        }
    }

    private func mergeUnique(contents: inout [ACPToolCallContent], additions: [ACPToolCallContent]) {
        for item in additions {
            appendUnique(item, into: &contents)
        }
    }

    private func appendUnique(_ item: ACPToolCallContent, into content: inout [ACPToolCallContent]) {
        guard !content.contains(item) else { return }
        content.append(item)
    }

    private func firstString(in value: Any, matching keys: Set<String>, depth: Int = 0) -> String? {
        guard depth < Self.maxJSONTraversalDepth else { return nil }
        if let dict = value as? [String: Any] {
            for key in keys {
                if let string = dict[key] as? String, !string.isEmpty {
                    return string
                }
            }
            for nested in dict.values {
                if let match = firstString(in: nested, matching: keys, depth: depth + 1) {
                    return match
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let match = firstString(in: item, matching: keys, depth: depth + 1) {
                    return match
                }
            }
        }
        return nil
    }

    private func firstInt(in value: Any, matching keys: Set<String>, depth: Int = 0) -> Int? {
        guard depth < Self.maxJSONTraversalDepth else { return nil }
        if let dict = value as? [String: Any] {
            for key in keys {
                if let int = dict[key] as? Int {
                    return int
                }
            }
            for nested in dict.values {
                if let match = firstInt(in: nested, matching: keys, depth: depth + 1) {
                    return match
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let match = firstInt(in: item, matching: keys, depth: depth + 1) {
                    return match
                }
            }
        }
        return nil
    }

    private static let pathKeys: Set<String> = ["path", "file_path", "filePath", "absolutePath", "abs_path"]

    private func logStderrForDiagnostics(prefix: String) {
        guard let summary = ACPStderrDiagnostics.summary(for: stderrBuffer) else { return }
        logger.error("\(prefix, privacy: .public): \(summary, privacy: .public)")
    }

    // MARK: - Collaboration Mode Developer Instructions

    private static let planModeDeveloperInstructions = """
    <collaboration_mode># Plan Mode (Conversational)
    You work in 3 phases, and you should chat your way to a great plan before finalizing it.
    ## Mode rules (strict)
    You are in Plan Mode until a developer message explicitly ends it.
    Plan Mode is not changed by user intent, tone, or imperative language.
    ## Execution vs. mutation in Plan Mode
    You may explore and execute non-mutating actions that improve the plan. You must not perform mutating actions.
    ### Allowed (non-mutating): Reading files, searching, static analysis, dry-run commands, tests/builds that don't edit tracked files.
    ### Not allowed (mutating): Editing files, running formatters that rewrite files, applying patches/migrations/codegen.
    ## Finalization rule
    Only output the final plan when it is decision complete. Wrap it in a <proposed_plan> block using Markdown.
    </collaboration_mode>
    """

    private static let defaultModeDeveloperInstructions = """
    <collaboration_mode># Collaboration Mode: Default
    You are now in Default mode. Any previous instructions for other modes are no longer active.
    Strongly prefer making reasonable assumptions and executing the user's request rather than stopping to ask questions.
    </collaboration_mode>
    """
}
