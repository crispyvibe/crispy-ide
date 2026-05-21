import Combine
import Foundation

@MainActor
final class ACPSession: ObservableObject, Identifiable, AgentSessionProtocol {
    private struct TurnTracker {
        let id: String
        let startedAt: Date
        var assistantChunkCount = 0
        var thoughtChunkCount = 0
        var toolCallCount = 0
        var planUpdateCount = 0
        var permissionRequestCount = 0
        var terminalRequestCount = 0
        var fileOperationCount = 0
    }

    let id = UUID()
    let projectPath: URL
    let agent: ACPAgentDefinition
    let origin: String
    let observabilityStore: ACPObservabilityStore?

    var agentName: String { agent.title }
    var agentID: String { agent.id }
    var permissionHandler: ACPPermissionHandler?
    var availableModes: [ACPModeInfo] { modeState?.availableModes ?? [] }
    var currentModeID: String? { modeState?.currentModeId }
    var availableModels: [ACPModelInfo] { modelState?.availableModels ?? [] }
    var currentModelID: String? { modelState?.currentModelId }

    var transportKind: String { "acp" }
    var providerSessionID: String? { sessionID }
    var resumeStrategy: String {
        if agentCapabilities?.sessionCapabilities?.supportsResume == true { return "native_resume" }
        if agentCapabilities?.loadSession == true { return "native_resume" }
        return "none"
    }
    /// Whether the agent supports `session/resume` (lightweight, no replay).
    var supportsSessionResume: Bool {
        agentCapabilities?.sessionCapabilities?.supportsResume == true
    }

    private let transport: any ACPTransportProtocol
    private var notificationTask: Task<Void, Never>?
    private var activePromptContinuation: AsyncStream<ACPUpdate>.Continuation?
    private var currentTurn: TurnTracker?
    private weak var terminalHandler: ACPTerminalHandler?

    @Published var sessionID: String?
    @Published var isConnected = false
    @Published var lastDisconnectReason: String?
    @Published var agentInfo: ACPAgentInfo?
    @Published var agentCapabilities: ACPAgentCapabilities?
    @Published var modelState: ACPSessionModelState?
    @Published var modeState: ACPSessionModeState?

    init(
        projectPath: URL,
        agent: ACPAgentDefinition,
        origin: String = "project",
        observabilityStore: ACPObservabilityStore? = nil,
        transport: (any ACPTransportProtocol)? = nil
    ) {
        self.projectPath = projectPath.standardizedFileURL
        self.agent = agent
        self.origin = origin
        self.observabilityStore = observabilityStore

        let localSessionID = UUID().uuidString
        self.transport = transport ?? ACPTransport(
            localSessionID: localSessionID,
            agentID: agent.id,
            projectToken: AppDiagnostics.pathToken(projectPath.path),
            origin: origin,
            observabilityStore: observabilityStore
        )
        upsertObservedSession(connectionState: "idle", lastErrorClass: nil)
    }

    func connect() async throws {
        upsertObservedSession(connectionState: "connecting", lastErrorClass: nil)
        do {
            try await transport.start(executable: agent.executable, arguments: agent.arguments, environment: nil)

            let initializeResponse = try await transport.send(
                method: "initialize",
                params: [
                    "protocolVersion": 1,
                    "clientCapabilities": [
                        "fs": ["readTextFile": true, "writeTextFile": true],
                        "terminal": true,
                    ],
                    "clientInfo": [
                        "name": ACPClientInfo.crispyvibes.name,
                        "title": ACPClientInfo.crispyvibes.title,
                        "version": ACPClientInfo.crispyvibes.version,
                    ],
                ]
            )
            guard initializeResponse.isSuccess else {
                throw ACPTransportError.agentError(initializeResponse.error?.message ?? "Initialize failed")
            }

            if let result = initializeResponse.result?.dictValue,
               let data = try? JSONSerialization.data(withJSONObject: result),
               let decoded = try? JSONDecoder().decode(ACPInitializeResult.self, from: data) {
                agentInfo = decoded.agentInfo
                agentCapabilities = decoded.agentCapabilities
            }

            let sessionResponse = try await transport.send(
                method: "session/new",
                params: [
                    "cwd": projectPath.path,
                    "mcpServers": [] as [Any],
                ]
            )
            guard sessionResponse.isSuccess,
                  let sessionId = sessionResponse.result?["sessionId"] as? String else {
                throw ACPTransportError.agentError(sessionResponse.error?.message ?? "session/new failed")
            }

            self.sessionID = sessionId
            isConnected = true

            if let result = sessionResponse.result?.dictValue {
                updateSessionCapabilities(from: result)
            }

            startNotificationRouter()
            await transport.setTerminationHandler { [weak self] reason in
                Task { @MainActor in
                    self?.terminalHandler?.releasePendingExitWaits()
                    self?.sessionID = nil
                    self?.isConnected = false
                    self?.lastDisconnectReason = reason
                    self?.finalizeTurn(stopReason: "process_exit", errorDetail: reason)
                    self?.upsertObservedSession(connectionState: "disconnected", lastErrorClass: "process_exit")
                }
            }
            upsertObservedSession(connectionState: "connected", lastErrorClass: nil)
        } catch {
            upsertObservedSession(connectionState: "error", lastErrorClass: "connect_failed")
            throw error
        }
    }

    // MARK: - Authentication

    func authenticate(authMethod: String, credentials: [String: Any]) async throws {
        guard await transport.isRunning else { throw ACPTransportError.disconnected("Agent process not running.") }
        let response = try await transport.send(
            method: "authenticate",
            params: [
                "authMethod": authMethod,
                "credentials": credentials,
            ]
        )
        guard response.isSuccess else {
            throw ACPTransportError.agentError(response.error?.message ?? "Authentication failed")
        }
    }

    // MARK: - Session Load (Resume)

    func loadSession(sessionId: String) async throws {
        guard agentCapabilities?.loadSession == true else {
            throw ACPTransportError.agentError("Agent does not support session/load")
        }
        let response = try await transport.send(
            method: "session/load",
            params: [
                "sessionId": sessionId,
                "cwd": projectPath.path,
                "mcpServers": [] as [Any],
            ]
        )
        guard response.isSuccess else {
            throw ACPTransportError.agentError(response.error?.message ?? "session/load failed")
        }
        self.sessionID = sessionId
        isConnected = true

        if let result = response.result?.dictValue {
            updateSessionCapabilities(from: result)
        }

        startNotificationRouter()
        upsertObservedSession(connectionState: "connected", lastErrorClass: nil)
    }

    /// Lightweight resume — reconnects without replaying history (ACP `session/resume`).
    func resumeSession(sessionId: String) async throws {
        guard supportsSessionResume else {
            throw ACPTransportError.agentError("Agent does not support session/resume")
        }
        let response = try await transport.send(
            method: "session/resume",
            params: [
                "sessionId": sessionId,
                "cwd": projectPath.path,
                "mcpServers": [] as [Any],
            ]
        )
        guard response.isSuccess else {
            throw ACPTransportError.agentError(response.error?.message ?? "session/resume failed")
        }
        self.sessionID = sessionId
        isConnected = true

        if let result = response.result?.dictValue {
            updateSessionCapabilities(from: result)
        }

        startNotificationRouter()
        upsertObservedSession(connectionState: "connected", lastErrorClass: nil)
    }

    func prompt(_ text: String, contentBlocks: [[String: Any]]? = nil) -> AsyncStream<ACPUpdate> {
        AsyncStream { [weak self] continuation in
            guard self != nil else {
                continuation.finish()
                return
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.activePromptContinuation = nil
                }
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                guard self.sessionID != nil else {
                    let reason = await self.transport.isRunning
                        ? "Session ID is nil — agent may not have completed initialization."
                        : "Agent process is not running."
                    continuation.yield(.error(reason))
                    continuation.finish()
                    return
                }

                self.currentTurn = TurnTracker(id: UUID().uuidString, startedAt: Date())
                self.activePromptContinuation = continuation
                self.observabilityStore?.record(
                    ACPObservedEvent(
                        category: "turn.start",
                        sessionLocalID: self.id.uuidString,
                        agentID: self.agent.id,
                        projectToken: AppDiagnostics.pathToken(self.projectPath.path),
                        metadata: ["origin": self.origin]
                    )
                )

                let promptContent: [Any] = contentBlocks ?? [["type": "text", "text": text]]
                do {
                    _ = try await self.transport.send(
                        method: "session/prompt",
                        params: [
                            "sessionId": self.sessionID ?? "",
                            "prompt": promptContent,
                        ]
                    )
                    // RPC response received. The transport injects a synthetic turn_completed
                    // notification into the notification stream, which will finish the stream
                    // after all buffered notifications are consumed.
                } catch {
                    let message = error.localizedDescription
                    continuation.yield(.error(message))
                    self.finalizeTurn(stopReason: "error", errorDetail: message)
                    // If the transport is dead, update connection state immediately
                    if error is ACPTransportError {
                        self.sessionID = nil
                        self.isConnected = false
                    }
                    self.activePromptContinuation = nil
                    continuation.finish()
                }
            }
        }
    }

    func cancel() async {
        permissionHandler?.resolve(.cancelled)
        guard let sessionID else { return }
        try? await transport.sendNotification(method: "session/cancel", params: ["sessionId": sessionID])
        finalizeTurn(stopReason: "cancelled")
    }

    func disconnect() {
        notificationTask?.cancel()
        notificationTask = nil
        activePromptContinuation?.finish()
        activePromptContinuation = nil
        terminalHandler?.releasePendingExitWaits()
        finalizeTurn(stopReason: "disconnected")
        Task { await transport.stop() }
        sessionID = nil
        isConnected = false
        upsertObservedSession(connectionState: "disconnected", lastErrorClass: nil)
    }

    func setMode(_ modeId: String) async {
        guard let sessionID else { return }
        let response = try? await transport.send(
            method: "session/set_mode",
            params: ["sessionId": sessionID, "modeId": modeId]
        )
        if response?.isSuccess == true, let state = modeState {
            modeState = ACPSessionModeState(availableModes: state.availableModes, currentModeId: modeId)
            upsertObservedSession(connectionState: isConnected ? "connected" : "idle", lastErrorClass: nil)
        }
    }

    func setModel(_ modelId: String) async {
        guard let sessionID, modelState?.currentModelId != modelId else { return }
        let response = try? await transport.send(
            method: "session/set_model",
            params: ["sessionId": sessionID, "modelId": modelId]
        )
        guard response?.isSuccess == true else { return }

        if let result = response?.result?.dictValue {
            updateSessionCapabilities(from: result)
        } else if let state = modelState {
            modelState = ACPSessionModelState(
                availableModels: state.availableModels,
                currentModelId: modelId
            )
        }
        upsertObservedSession(connectionState: isConnected ? "connected" : "idle", lastErrorClass: nil)
    }

    func installHandlers(
        fileSystem: ACPFileSystemHandler,
        terminal: ACPTerminalHandler,
        permission: ACPPermissionHandler
    ) {
        terminalHandler = terminal
        permissionHandler = permission
        permission.onDiffsReceived = { _, _ in }

        Task {
            await transport.setRequestHandler { [weak self] method, params in
                guard let self else { throw ACPTransportError.disconnected("Session deallocated.") }
                switch method {
                case "fs/read_text_file":
                    await self.noteFileOperation()
                    return try await fileSystem.handleRead(params: params)
                case "fs/write_text_file":
                    await self.noteFileOperation()
                    return try await fileSystem.handleWrite(params: params)
                case "terminal/create":
                    await self.noteTerminalRequest()
                    return await MainActor.run { terminal.handleCreate(params: params) }
                case "terminal/output":
                    await self.noteTerminalRequest()
                    return try await MainActor.run { try terminal.handleOutput(params: params) }
                case "terminal/wait_for_exit":
                    await self.noteTerminalRequest()
                    return try await terminal.handleWaitForExit(params: params)
                case "terminal/kill":
                    await self.noteTerminalRequest()
                    return try await MainActor.run { try terminal.handleKill(params: params) }
                case "terminal/release":
                    await self.noteTerminalRequest()
                    return try await MainActor.run { try terminal.handleRelease(params: params) }
                case "session/request_permission":
                    await self.notePermissionRequest()
                    return await permission.handle(requestID: 0, params: params)
                default:
                    throw JSONRPCError(code: -32601, message: "Method not found: \(method)")
                }
            }
        }
    }

    private func startNotificationRouter() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.transport.notifications()
            for await notification in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.routeNotification(notification)
                }
            }
        }
    }

    private func routeNotification(_ notification: JSONRPCNotification) {
        guard notification.method == "session/update",
              let params = notification.params?.dictValue,
              let updatePayload = params["update"] as? [String: Any] else {
            return
        }

        let update = ACPUpdate.decode(from: updatePayload)
        incrementTurnCounters(for: update)

        if case .currentModeUpdate(let modeId) = update, let state = modeState {
            modeState = ACPSessionModeState(availableModes: state.availableModes, currentModeId: modeId)
        }

        // Handle turn completion signal (injected by transport after session/prompt response)
        if case .turnCompleted = update {
            activePromptContinuation?.yield(.turnCompleted)
            finalizeTurn(stopReason: "completed")
            activePromptContinuation?.finish()
            activePromptContinuation = nil
            upsertObservedSession(connectionState: isConnected ? "connected" : "idle", lastErrorClass: nil)
            return
        }

        activePromptContinuation?.yield(update)
        upsertObservedSession(connectionState: isConnected ? "connected" : "idle", lastErrorClass: nil)
    }

    private func updateSessionCapabilities(from result: [String: Any]) {
        if let modelState = result["models"] as? [String: Any] {
            self.modelState = ACPSessionModelState.parse(from: modelState)
        }
        if let modeState = result["modes"] as? [String: Any] {
            self.modeState = ACPSessionModeState.parse(from: modeState)
        }
    }

    private func incrementTurnCounters(for update: ACPUpdate) {
        guard currentTurn != nil else { return }
        switch update {
        case .agentMessageChunk:
            currentTurn?.assistantChunkCount += 1
        case .thoughtChunk:
            currentTurn?.thoughtChunkCount += 1
        case .toolCall, .toolCallUpdate:
            currentTurn?.toolCallCount += 1
        default:
            break
        }
    }

    private func notePermissionRequest() {
        currentTurn?.permissionRequestCount += 1
    }

    private func noteTerminalRequest() {
        currentTurn?.terminalRequestCount += 1
    }

    private func noteFileOperation() {
        currentTurn?.fileOperationCount += 1
    }

    private func finalizeTurn(stopReason: String, errorDetail: String? = nil) {
        guard let currentTurn else { return }
        observabilityStore?.recordTurn(
            ACPObservedTurnSummary(
                id: currentTurn.id,
                sessionLocalID: id.uuidString,
                agentID: agent.id,
                projectToken: AppDiagnostics.pathToken(projectPath.path),
                startedAt: AppDiagnostics.iso8601Timestamp(currentTurn.startedAt),
                endedAt: AppDiagnostics.iso8601Timestamp(Date()),
                stopReason: stopReason,
                counts: ACPObservedTurnCounts(
                    assistantChunkCount: currentTurn.assistantChunkCount,
                    thoughtChunkCount: currentTurn.thoughtChunkCount,
                    toolCallCount: currentTurn.toolCallCount,
                    planUpdateCount: currentTurn.planUpdateCount,
                    permissionRequestCount: currentTurn.permissionRequestCount,
                    terminalRequestCount: currentTurn.terminalRequestCount,
                    fileOperationCount: currentTurn.fileOperationCount
                )
            )
        )
        var metadata: [String: String] = ["origin": origin]
        if let errorDetail { metadata["errorDetail"] = errorDetail }
        observabilityStore?.record(
            ACPObservedEvent(
                category: "turn.finish",
                sessionLocalID: id.uuidString,
                agentID: agent.id,
                projectToken: AppDiagnostics.pathToken(projectPath.path),
                duration: Date().timeIntervalSince(currentTurn.startedAt),
                succeeded: stopReason == "completed",
                errorClass: stopReason == "completed" ? nil : stopReason,
                metadata: metadata
            )
        )
        self.currentTurn = nil
    }

    private func upsertObservedSession(connectionState: String, lastErrorClass: String?) {
        observabilityStore?.upsertSession(
            ACPObservedSessionSnapshot(
                id: id.uuidString,
                agentID: agent.id,
                projectToken: AppDiagnostics.pathToken(projectPath.path),
                transportKind: "acp",
                origin: origin,
                connectionState: connectionState,
                remoteSessionID: sessionID,
                currentMode: modeState?.currentModeId,
                currentModel: modelState?.currentModelId,
                lastActivityAt: AppDiagnostics.iso8601Timestamp(Date()),
                lastErrorClass: lastErrorClass
            )
        )
    }
}
