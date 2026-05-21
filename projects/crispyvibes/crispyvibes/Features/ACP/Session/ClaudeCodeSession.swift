import Foundation
import OSLog

@MainActor
final class ClaudeCodeSession: ObservableObject, Identifiable, AgentSessionProtocol {
    private static let maxStreamBlockStates = 128
    private static let maxSeenToolCallIDs = 512

    private enum StreamBlockKind {
        case text
        case thinking
    }

    private struct StreamBlockState {
        var kind: StreamBlockKind
        var fullText: String = ""
        var emittedLength = 0
    }

    let id = UUID()
    let projectPath: URL
    let agentName: String
    var agentID: String { "claudeCode" }

    private let executable: String
    private let trustMode: CLITrustMode
    private let model: String?
    private let reasoningLevel: AgentReasoningLevel
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "claude-code.session")
    /// The Claude session ID — generated on first connect, reused for resume.
    private(set) var claudeSessionId: String?
    /// A session ID from a previous session to resume via --resume.
    private let resumeSessionId: String?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrBuffer = ""
    private var activePromptContinuation: AsyncStream<ACPUpdate>.Continuation?
    private var readTask: Task<Void, Never>?
    private var streamBlockStates: [Int: StreamBlockState] = [:]
    private var seenToolCallIDs = Set<String>()
    private var seenToolCallOrder: [String] = []
    private var emittedAssistantTextThisTurn = false
    private var toolNamesByID: [String: String] = [:]

    @Published var isConnected = false
    private(set) var permissionHandler: ACPPermissionHandler?
    private var currentPermissionMode: String = "default"
    private var controlRequestCounter = 0

    var transportKind: String { "claude_code_direct" }
    var providerSessionID: String? { claudeSessionId }
    var resumeStrategy: String { claudeSessionId != nil ? "native_resume" : "none" }

    var availableModes: [ACPModeInfo] {
        [
            ACPModeInfo(modeId: "default", name: "Default", description: "Agent acts immediately"),
            ACPModeInfo(modeId: "plan", name: "Plan", description: "Agent proposes a plan first"),
        ]
    }
    var currentModeID: String? { currentPermissionMode }

    var availableModels: [ACPModelInfo] {
        guard let model else { return [] }
        return [ACPModelInfo(modelId: model, name: model, description: nil)]
    }

    var currentModelID: String? {
        model
    }

    init(
        projectPath: URL,
        executable: String = "claude",
        agentName: String = "Claude Code",
        trustMode: CLITrustMode = .standard,
        model: String? = nil,
        reasoningLevel: AgentReasoningLevel = .medium,
        resumeSessionId: String? = nil
    ) {
        self.projectPath = projectPath
        self.executable = executable
        self.agentName = agentName
        self.trustMode = trustMode
        self.model = model
        self.reasoningLevel = reasoningLevel
        self.resumeSessionId = resumeSessionId
    }

    func connect() async throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [
            executable,
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
        ]
        if trustMode == .fullTrust {
            arguments += ["--permission-mode", "bypassPermissions"]
        } else {
            arguments += ["--permission-mode", "default", "--permission-prompt-tool", "stdio"]
        }
        if let model {
            arguments += ["--model", model]
        }
        // Resume a previous session if we have a stored session ID
        if let resumeSessionId {
            arguments += ["--resume", resumeSessionId]
        } else {
            // Generate a new session ID so we can resume later
            let newId = UUID().uuidString
            claudeSessionId = newId
            arguments += ["--session-id", newId]
        }
        process.arguments = arguments
        process.currentDirectoryURL = projectPath
        process.environment = CommandPathResolver.environmentWithResolvedPath()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

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

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isConnected = false
                self?.activePromptContinuation?.finish()
                self?.activePromptContinuation = nil
                self?.streamBlockStates.removeAll()
                self?.seenToolCallIDs.removeAll()
                self?.seenToolCallOrder.removeAll()
                self?.emittedAssistantTextThisTurn = false
                self?.toolNamesByID.removeAll()
            }
        }

        do {
            try process.run()
        } catch {
            throw ACPTransportError.agentError("Failed to start claude: \(error.localizedDescription)")
        }

        self.process = process
        stdinPipe = stdin
        stdoutPipe = stdout
        startReadLoop(stdout: stdout)

        try await Task.sleep(for: .milliseconds(500))
        if !process.isRunning {
            let authError = Self.detectAuthError(stderrBuffer)
            logStderrForDiagnostics(prefix: "Claude Code exited unexpectedly")
            throw ACPTransportError.agentError(
                authError ?? "Claude Code exited unexpectedly. Check app logs for diagnostics."
            )
        }

        isConnected = true
        logger.info("Claude Code session started for \(self.projectPath.lastPathComponent)")
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
                self.streamBlockStates.removeAll()
                self.seenToolCallIDs.removeAll()
                self.seenToolCallOrder.removeAll()
                self.emittedAssistantTextThisTurn = false
                self.toolNamesByID.removeAll()
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.activePromptContinuation = nil }
                }

                let promptText: String
                switch self.reasoningLevel {
                case .low, .medium:
                    promptText = text
                case .high:
                    promptText = "think harder\n\n\(text)"
                case .max:
                    promptText = "ultrathink\n\n\(text)"
                }

                // Build content array in Claude Code SDK format
                var content: [[String: Any]] = [["type": "text", "text": promptText]]
                if let blocks = contentBlocks {
                    for block in blocks {
                        if block["type"] as? String == "image",
                           let data = block["data"] as? String,
                           let mediaType = block["mediaType"] as? String {
                            // Claude Code format: { type: "image", source: { type: "base64", media_type, data } }
                            content.append([
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": mediaType,
                                    "data": data,
                                ] as [String: Any],
                            ])
                        }
                    }
                }

                let message: [String: Any] = [
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": content,
                    ] as [String: Any],
                ]
                self.writeJSON(message)
            }
        }
    }

    func cancel() async {
        permissionHandler?.resolve(.cancelled)
        activePromptContinuation?.finish()
        activePromptContinuation = nil
        streamBlockStates.removeAll()
        seenToolCallIDs.removeAll()
        seenToolCallOrder.removeAll()
        emittedAssistantTextThisTurn = false
        toolNamesByID.removeAll()
    }

    func setMode(_ modeID: String) async {
        // Send control_request to set permission mode via Claude Code's stdin control protocol
        let permissionMode = modeID == "plan" ? "plan" : "default"
        controlRequestCounter += 1
        let requestId = "ctrl-\(controlRequestCounter)"
        let controlRequest: [String: Any] = [
            "type": "control_request",
            "request_id": requestId,
            "request": [
                "subtype": "set_permission_mode",
                "mode": permissionMode,
            ] as [String: Any],
        ]
        writeJSON(controlRequest)
        currentPermissionMode = modeID
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil
        activePromptContinuation?.finish()
        activePromptContinuation = nil
        stdinPipe?.fileHandleForWriting.closeFile()
        stdinPipe = nil
        stdoutPipe = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isConnected = false
        streamBlockStates.removeAll()
        seenToolCallIDs.removeAll()
        seenToolCallOrder.removeAll()
        emittedAssistantTextThisTurn = false
        toolNamesByID.removeAll()
    }

    func installPermissionHandler(_ handler: ACPPermissionHandler) {
        permissionHandler = handler
    }

    private static func detectAuthError(_ stderr: String) -> String? {
        let lower = stderr.lowercased()
        if lower.contains("bedrock") || lower.contains("aws") || lower.contains("aws_region") || lower.contains("sso") {
            return "Claude Code Bedrock configuration error. Verify GUI-launched Crispy inherits your AWS credentials, `CLAUDE_CODE_USE_BEDROCK=1`, and `AWS_REGION`."
        }
        let patterns = ["not logged in", "authentication", "sign in", "login required", "unauthorized", "api key", "no api_key"]
        guard patterns.contains(where: { lower.contains($0) }) else { return nil }
        return "Claude Code authentication required. Run 'claude' in a terminal to sign in, then try again."
    }

    private func logStderrForDiagnostics(prefix: String) {
        guard let summary = ACPStderrDiagnostics.summary(for: stderrBuffer) else { return }
        logger.error("\(prefix, privacy: .public): \(summary, privacy: .public)")
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
                    guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
                          let type = json["type"] as? String else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.handleEvent(type: type, json: json)
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.activePromptContinuation?.finish()
                self?.activePromptContinuation = nil
            }
        }
    }

    private func handleEvent(type: String, json: [String: Any]) {
        switch type {
        case "system":
            break
        case "user":
            handleUserEvent(json)
        case "assistant":
            handleAssistantEvent(json)
        case "stream_event":
            handleStreamEvent(json)
        case "result":
            handleResultEvent(json)
        case "control_request":
            handleControlRequest(json)
        default:
            break
        }
    }

    private func handleResultEvent(_ json: [String: Any]) {
        flushPendingStreamBlocks()
        if !emittedAssistantTextThisTurn,
           let result = json["result"] as? String,
           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activePromptContinuation?.yield(.agentMessageChunk(.text(result)))
        }
        streamBlockStates.removeAll()
        seenToolCallIDs.removeAll()
        seenToolCallOrder.removeAll()
        emittedAssistantTextThisTurn = false
        toolNamesByID.removeAll()
        if let cost = json["total_cost_usd"] as? Double {
            let inputTokens = json["input_tokens"] as? Int ?? 0
            let outputTokens = json["output_tokens"] as? Int ?? 0
            let summary = String(format: "Cost: $%.4f | Tokens: %d in / %d out", cost, inputTokens, outputTokens)
            activePromptContinuation?.yield(.sessionInfoUpdate(["usage": summary]))
        }
        activePromptContinuation?.finish()
        activePromptContinuation = nil
    }

    private func handleUserEvent(_ json: [String: Any]) {
        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else { return }

        for block in contentBlocks {
            guard let blockType = block["type"] as? String, blockType == "tool_result" else { continue }
            let toolCallID = block["tool_use_id"] as? String ?? ""
            activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
                toolCallId: toolCallID,
                status: (block["is_error"] as? Bool == true) ? .error : .completed,
                content: parseToolResultContent(block, toolName: toolNamesByID[toolCallID])
            )))
        }
    }

    private func handleAssistantEvent(_ json: [String: Any]) {
        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else { return }

        for (index, block) in contentBlocks.enumerated() {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                emitSnapshotText(block["text"] as? String, index: index, kind: .text)

            case "thinking":
                emitSnapshotText(block["thinking"] as? String ?? block["text"] as? String, index: index, kind: .thinking)

            case "tool_use":
                let toolCallID = block["id"] as? String ?? UUID().uuidString
                let toolName = block["name"] as? String ?? "tool"
                let input = block["input"] as? [String: Any]
                if recordSeenToolCallID(toolCallID) {
                    toolNamesByID[toolCallID] = toolName
                    activePromptContinuation?.yield(.toolCall(ACPToolCallUpdate(
                        toolCallId: toolCallID,
                        title: formatToolTitle(name: toolName, input: input),
                        kind: toolName,
                        status: .inProgress,
                        content: toolContent(name: toolName, input: input),
                        locations: toolLocations(input: input)
                    )))
                } else {
                    // Tool call already seen from content_block_start — update content
                    // now that the full input (with diff data) is available
                    let content = toolContent(name: toolName, input: input)
                    if !content.isEmpty {
                        activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
                            toolCallId: toolCallID,
                            status: .inProgress,
                            content: content
                        )))
                    }
                }

            case "tool_result":
                let toolCallID = block["tool_use_id"] as? String ?? ""
                activePromptContinuation?.yield(.toolCallUpdate(ACPToolCallStatusUpdate(
                    toolCallId: toolCallID,
                    status: (block["is_error"] as? Bool == true) ? .error : .completed,
                    content: parseToolResultContent(block, toolName: toolNamesByID[toolCallID])
                )))

            default:
                break
            }
        }
    }

    private func handleStreamEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String else { return }

        switch eventType {
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String,
                  let index = event["index"] as? Int else { return }

            switch blockType {
            case "text":
                recordStreamBlockStart(index: index, kind: .text, initialText: block["text"] as? String ?? "")
            case "thinking":
                recordStreamBlockStart(index: index, kind: .thinking, initialText: block["thinking"] as? String ?? block["text"] as? String ?? "")
            case "tool_use", "server_tool_use", "mcp_tool_use":
                let toolCallID = block["id"] as? String ?? UUID().uuidString
                let toolName = block["name"] as? String ?? "tool"
                let input = block["input"] as? [String: Any]
                guard recordSeenToolCallID(toolCallID) else { break }
                toolNamesByID[toolCallID] = toolName
                activePromptContinuation?.yield(.toolCall(ACPToolCallUpdate(
                    toolCallId: toolCallID,
                    title: formatToolTitle(name: toolName, input: input),
                    kind: toolName,
                    status: .inProgress,
                    content: toolContent(name: toolName, input: input),
                    locations: toolLocations(input: input)
                )))
            default:
                break
            }

        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String,
                  let index = event["index"] as? Int else { return }

            switch deltaType {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return }
                emitStreamDelta(text, index: index, kind: .text)
            case "thinking_delta":
                let text = delta["thinking"] as? String ?? delta["text"] as? String ?? ""
                guard !text.isEmpty else { return }
                emitStreamDelta(text, index: index, kind: .thinking)
            case "input_json_delta":
                break
            default:
                break
            }

        case "content_block_stop":
            guard let index = event["index"] as? Int else { return }
            flushPendingStreamBlock(index: index)

        default:
            break
        }
    }

    private func handleControlRequest(_ json: [String: Any]) {
        guard let requestID = json["request_id"] as? String,
              let request = json["request"] as? [String: Any],
              let subtype = request["subtype"] as? String,
              subtype == "can_use_tool" else { return }

        let toolName = request["tool_name"] as? String ?? "Unknown"
        let input = request["input"] as? [String: Any] ?? [:]
        let toolCallID = request["tool_use_id"] as? String ?? requestID
        let diffs = toolDiffs(name: toolName, input: input)

        guard let permissionHandler else {
            sendControlResponse(requestId: requestID, allow: false, input: input)
            return
        }

        Task {
            let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ACPPermissionOutcome, Never>) in
                permissionHandler.pendingRequest = ACPPermissionHandler.PendingRequest(
                    sessionId: requestID,
                    toolCallId: toolCallID,
                    toolCallTitle: "\(toolName): \(formatToolTitle(name: toolName, input: input))",
                    options: [
                        ACPPermissionOption(optionId: "allow", name: "Allow", kind: "allow_once"),
                        ACPPermissionOption(optionId: "reject", name: "Deny", kind: "reject_once"),
                    ],
                    diffs: diffs,
                    continuation: continuation
                )
            }
            permissionHandler.pendingRequest = nil

            switch outcome {
            case .selected(let optionID):
                self.sendControlResponse(requestId: requestID, allow: optionID.contains("allow"), input: input)
            case .cancelled:
                self.sendControlResponse(requestId: requestID, allow: false, input: input)
            }
        }
    }

    private func sendControlResponse(requestId: String, allow: Bool, input: [String: Any]) {
        let response: [String: Any]
        if allow {
            response = [
                "type": "control_response",
                "response": [
                    "subtype": "success",
                    "request_id": requestId,
                    "response": [
                        "behavior": "allow",
                        "updatedInput": input,
                    ] as [String: Any],
                ] as [String: Any],
            ]
        } else {
            response = [
                "type": "control_response",
                "response": [
                    "subtype": "success",
                    "request_id": requestId,
                    "response": [
                        "behavior": "deny",
                        "message": "User denied this action",
                    ] as [String: Any],
                ] as [String: Any],
            ]
        }
        writeJSON(response)
    }

    private func formatToolTitle(name: String, input: [String: Any]?) -> String {
        switch name {
        case "Bash":
            return input?["command"] as? String ?? "Run command"
        case "Read":
            return "Read \(input?["file_path"] as? String ?? "file")"
        case "Edit", "Write", "MultiEdit":
            return "\(name) \(input?["file_path"] as? String ?? "file")"
        default:
            return name
        }
    }

    private func toolContent(name: String, input: [String: Any]?) -> [ACPToolCallContent] {
        guard let input else { return [] }
        var content: [ACPToolCallContent] = []
        let path = input["file_path"] as? String ?? input["path"] as? String

        switch name {
        case "Bash":
            if let command = input["command"] as? String {
                content.append(.text(command))
            }
        case "Edit":
            if let path,
               let newText = input["new_string"] as? String {
                content.append(.diff(ACPDiff(
                    path: path,
                    oldText: input["old_string"] as? String,
                    newText: newText
                )))
            }
        case "Write":
            if let path,
               let newText = input["content"] as? String {
                content.append(.diff(ACPDiff(path: path, oldText: nil, newText: newText)))
            }
        case "MultiEdit":
            if let path,
               let edits = input["edits"] as? [[String: Any]] {
                for edit in edits {
                    if let newText = edit["new_string"] as? String {
                        content.append(.diff(ACPDiff(
                            path: path,
                            oldText: edit["old_string"] as? String,
                            newText: newText
                        )))
                    }
                }
            }
        case "Read":
            break
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: .prettyPrinted),
               let text = String(data: data, encoding: .utf8) {
                content.append(.text(text))
            }
        }

        if content.isEmpty, let path {
            content.append(.text(path))
        }
        return content
    }

    private func toolDiffs(name: String, input: [String: Any]?) -> [ACPDiff] {
        toolContent(name: name, input: input).compactMap { content in
            if case .diff(let diff) = content {
                return diff
            }
            return nil
        }
    }

    private func parseToolResultContent(_ block: [String: Any], toolName: String?) -> [ACPToolCallContent] {
        if toolName == "Read" {
            return []
        }
        if let content = block["content"] as? String {
            return [.text(content)]
        }
        if let contentBlocks = block["content"] as? [[String: Any]] {
            return contentBlocks.compactMap { item in
                if let text = item["text"] as? String {
                    return .text(text)
                }
                return nil
            }
        }
        return []
    }

    private func toolLocations(input: [String: Any]?) -> [ACPToolCallLocation] {
        guard let path = input?["file_path"] as? String ?? input?["path"] as? String else { return [] }
        let line = input?["line"] as? Int ?? input?["start_line"] as? Int
        return [ACPToolCallLocation(path: path, line: line)]
    }

    private func recordStreamBlockStart(index: Int, kind: StreamBlockKind, initialText: String) {
        var state = streamBlockStates[index] ?? StreamBlockState(kind: kind)
        state.kind = kind
        if initialText.count > state.fullText.count {
            state.fullText = initialText
        }
        streamBlockStates[index] = state
        trimStreamBlockStatesIfNeeded()
    }

    private func emitStreamDelta(_ text: String, index: Int, kind: StreamBlockKind) {
        var state = streamBlockStates[index] ?? StreamBlockState(kind: kind)
        state.kind = kind
        state.fullText += text
        state.emittedLength += text.count
        streamBlockStates[index] = state
        trimStreamBlockStatesIfNeeded()
        yield(text: text, kind: kind)
    }

    private func emitSnapshotText(_ fullText: String?, index: Int, kind: StreamBlockKind) {
        guard let fullText, !fullText.isEmpty else { return }
        var state = streamBlockStates[index] ?? StreamBlockState(kind: kind)
        state.kind = kind
        if fullText.count > state.fullText.count {
            state.fullText = fullText
        }
        if state.fullText.count > state.emittedLength {
            let delta = String(state.fullText.dropFirst(state.emittedLength))
            state.emittedLength = state.fullText.count
            streamBlockStates[index] = state
            trimStreamBlockStatesIfNeeded()
            yield(text: delta, kind: kind)
        } else {
            streamBlockStates[index] = state
            trimStreamBlockStatesIfNeeded()
        }
    }

    private func flushPendingStreamBlocks() {
        for index in streamBlockStates.keys.sorted() {
            flushPendingStreamBlock(index: index)
        }
    }

    private func flushPendingStreamBlock(index: Int) {
        guard var state = streamBlockStates[index] else { return }
        if state.fullText.count > state.emittedLength {
            let delta = String(state.fullText.dropFirst(state.emittedLength))
            state.emittedLength = state.fullText.count
            streamBlockStates[index] = state
            yield(text: delta, kind: state.kind)
        }
    }

    private func yield(text: String, kind: StreamBlockKind) {
        guard !text.isEmpty else { return }
        switch kind {
        case .text:
            emittedAssistantTextThisTurn = true
            activePromptContinuation?.yield(.agentMessageChunk(.text(text)))
        case .thinking:
            activePromptContinuation?.yield(.thoughtChunk(.text(text)))
        }
    }

    private func trimStreamBlockStatesIfNeeded() {
        guard streamBlockStates.count > Self.maxStreamBlockStates else { return }
        let overflow = streamBlockStates.count - Self.maxStreamBlockStates
        for key in streamBlockStates.keys.sorted().prefix(overflow) {
            streamBlockStates.removeValue(forKey: key)
        }
    }

    private func recordSeenToolCallID(_ toolCallID: String) -> Bool {
        guard seenToolCallIDs.insert(toolCallID).inserted else { return false }
        seenToolCallOrder.append(toolCallID)
        if seenToolCallOrder.count > Self.maxSeenToolCallIDs {
            let overflow = seenToolCallOrder.count - Self.maxSeenToolCallIDs
            for expiredID in seenToolCallOrder.prefix(overflow) {
                seenToolCallIDs.remove(expiredID)
                toolNamesByID.removeValue(forKey: expiredID)
            }
            seenToolCallOrder.removeFirst(overflow)
        }
        return true
    }
}
