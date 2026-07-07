import Combine
import Foundation
import OSLog

struct ACPStandalonePaneSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    var selectedAgentID: String?
    var selectedModelID: String?
    var selectedProjectIdentifier: String?
    var trustMode: CLITrustMode
    var reasoningLevel: AgentReasoningLevel
    var shouldAutoConnect: Bool
    var threadId: String?
}

@MainActor
final class ACPStandaloneSessionStore: ObservableObject, Identifiable {
    let id: UUID
    let chatViewModel: ACPChatViewModel

    @Published var selectedAgentID: String?
    @Published var selectedModelID: String?
    @Published var selectedProjectIdentifier: String?
    @Published var trustMode: CLITrustMode = .standard {
        didSet { applyTrustModeToActivePermissionHandler() }
    }
    @Published var reasoningLevel: AgentReasoningLevel = .medium
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var shouldAutoConnect = true
    @Published private(set) var availableModels: [ACPModelInfo] = []
    /// When set, the user must confirm whether to start a fresh session after resume failed.
    @Published var pendingResumeFailure: String?
    @Published private(set) var isExternallyManaged = false
    /// The in-flight restore task, awaited by ensureConnected before connecting.
    private var restoreTask: Task<Void, Never>?

    private let sessionManager: ACPSessionManager
    private let conversationStore: AgentConversationStore
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "acpStandaloneSession")
    private let persistenceQueue = SerialTaskQueue()
    private var session: (any AgentSessionProtocol)?
    private var modelObservations = Set<AnyCancellable>()
    private var cachedModelsByAgentID: [String: [ACPModelInfo]] = [:]
    /// The remote session ID from the last ACP session, stored for resume across app restarts.
    private var storedProviderSessionId: String?
    /// The transport kind from the last session, stored for resume strategy decisions.
    private var storedTransportKind: String?

    init(
        id: UUID = UUID(),
        sessionManager: ACPSessionManager,
        conversationStore: AgentConversationStore,
        chatViewModel: ACPChatViewModel,
        vibespaceID: UUID? = nil
    ) {
        self.id = id
        self.sessionManager = sessionManager
        self.conversationStore = conversationStore
        self.chatViewModel = chatViewModel
        self.chatViewModel.updateVibeSpaceID(vibespaceID?.uuidString)
        self.chatViewModel.onTurnCompleted = { [weak self] in
            self?.persistSessionMetadata(status: "ready")
        }
    }

    var isConnected: Bool {
        session?.isConnected == true
    }

    var isDirectIntegration: Bool {
        selectedDefinition?.supportsDirectIntegration == true
    }

    var directIntegrationType: CLIToolDefinition.DirectIntegrationType? {
        selectedDefinition?.directIntegration
    }

    var selectedModelName: String? {
        guard let id = selectedModelID else { return nil }
        return availableModels.first(where: { $0.modelId == id })?.name
    }

    var agentTitle: String {
        if let session {
            return session.agentName
        }
        guard let selectedAgentID else { return AppStrings.ACP.agentContentTitle }
        return selectedDefinition?.title
            ?? ACPAgentRegistry.agentDefinition(id: selectedAgentID)?.title
            ?? selectedAgentID
    }

    var tabTitle: String {
        // Prefer conversation title from persistence
        if let title = chatViewModel.persistenceContext?.title, !title.isEmpty {
            return title
        }
        // Fall back to first user message prefix
        if let firstMessage = chatViewModel.timeline.first(where: {
            if case .userMessage = $0.kind { return true }
            if case .turn(let t) = $0.kind { return !t.userMessage.isEmpty }
            return false
        }) {
            switch firstMessage.kind {
            case .userMessage(let text):
                return String(text.prefix(40))
            case .turn(let turn):
                return String(turn.userMessage.prefix(40))
            default: break
            }
        }
        return agentTitle
    }

    var snapshot: ACPStandalonePaneSnapshot {
        ACPStandalonePaneSnapshot(
            id: id,
            selectedAgentID: selectedAgentID,
            selectedModelID: selectedModelID,
            selectedProjectIdentifier: selectedProjectIdentifier,
            trustMode: trustMode,
            reasoningLevel: reasoningLevel,
            shouldAutoConnect: shouldAutoConnect,
            threadId: chatViewModel.persistenceContext?.threadID
        )
    }

    private var selectedDefinition: CLIToolDefinition? {
        guard let selectedAgentID else { return nil }
        return CLIToolCatalog.agentDefinitions.first(where: { $0.id == selectedAgentID })
            ?? CLIToolCatalog.agentDefinitions.first(where: { $0.title == selectedAgentID })
    }

    func applyDefaults(
        focusedProject: AnyProjectSession?,
        preferredAgentID: String?
    ) {
        if selectedProjectIdentifier == nil {
            selectedProjectIdentifier = focusedProject?.projectIdentifier
        }
        if selectedAgentID == nil {
            selectedAgentID = preferredAgentID ?? AppPreferences.acpDefaultAgentID()
        }
        if let rawTrustMode = UserDefaults.standard.string(forKey: AppPreferences.acpDefaultTrustModeKey),
           let mode = CLITrustMode(rawValue: rawTrustMode) {
            trustMode = mode
        }
        let defaultModel = UserDefaults.standard.string(forKey: AppPreferences.acpDefaultModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let defaultModel, !defaultModel.isEmpty {
            selectedModelID = defaultModel
        }
        if let rawReasoning = UserDefaults.standard.string(forKey: AppPreferences.acpDefaultReasoningLevelKey),
           let level = AgentReasoningLevel(rawValue: rawReasoning) {
            reasoningLevel = level
        }
        syncAvailableModelsForSelection()
    }

    func restore(from snapshot: ACPStandalonePaneSnapshot) {
        selectedAgentID = snapshot.selectedAgentID
        selectedModelID = snapshot.selectedModelID
        selectedProjectIdentifier = snapshot.selectedProjectIdentifier
        trustMode = snapshot.trustMode
        reasoningLevel = snapshot.reasoningLevel
        shouldAutoConnect = snapshot.shouldAutoConnect
        syncAvailableModelsForSelection()

        // Coordinated restore: load messages, thread metadata, and session data in parallel
        guard let threadId = snapshot.threadId else { return }

        restoreTask = Task { [weak self] in
            guard let self else { return }
            async let messagesResult = self.conversationStore.listMessages(
                threadId: threadId,
                limit: ACPChatViewModel.restoredMessageLimit
            )
            async let sessionResult = self.conversationStore.getSession(threadId: threadId)
            async let threadResult = self.conversationStore.getThread(id: threadId)

            let messages = await messagesResult
            let sessionData = await sessionResult
            let threadData = await threadResult

            await MainActor.run {
                self.storedProviderSessionId = sessionData?["providerSessionId"] as? String
                self.storedTransportKind = sessionData?["transportKind"] as? String
                self.chatViewModel.applyRestoredData(
                    threadId: threadId, messages: messages, threadData: threadData
                )
                self.restoreTask = nil
            }
        }
    }

    func selectedProject(from projects: [AnyProjectSession]) -> AnyProjectSession? {
        guard let selectedProjectIdentifier else { return nil }
        return projects.first(where: { $0.projectIdentifier == selectedProjectIdentifier })
    }

    func setTrustMode(_ mode: CLITrustMode) {
        trustMode = mode
        connectionError = nil
    }

    func ensureConnected(projects: [AnyProjectSession]) {
        logger.info("[ensureConnected] shouldAutoConnect=\(self.shouldAutoConnect), isConnected=\(self.isConnected), isConnecting=\(self.isConnecting), restoring=\(self.restoreTask != nil), selectedAgentID=\(self.selectedAgentID ?? "nil", privacy: .public), selectedProject=\(self.selectedProjectIdentifier ?? "nil", privacy: .public)")
        guard shouldAutoConnect, !isConnected, !isConnecting else { return }
        Task { [weak self] in
            // If a restore is in flight, wait for it so we have resume data
            await self?.restoreTask?.value
            await self?.connect(projects: projects)
        }
    }

    func reconnectWithNewAgent(projects: [AnyProjectSession]) async {
        disconnect()
        await connect(projects: projects)
    }

    func connect(projects: [AnyProjectSession]) async {
        guard !isConnecting else { return }
        guard let selectedAgentID else {
            connectionError = "Choose a default agent in Settings > ACP."
            return
        }
        guard let project = selectedProject(from: projects) else {
            connectionError = "Choose a project to open ACP."
            return
        }

        // If we have a threadId but no provider session ID yet, load it from DB now
        if storedProviderSessionId == nil, let threadId = chatViewModel.persistenceContext?.threadID {
            let sessionData = await conversationStore.getSession(threadId: threadId)
            storedProviderSessionId = sessionData?["providerSessionId"] as? String
            storedTransportKind = sessionData?["transportKind"] as? String
            logger.info("[connect] Loaded from DB: providerSessionId=\(self.storedProviderSessionId ?? "nil", privacy: .public), transport=\(self.storedTransportKind ?? "nil", privacy: .public)")
        }

        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            if let directIntegrationType {
                logger.info("[Resume] Direct: type=\(String(describing: directIntegrationType)), storedId=\(self.storedProviderSessionId ?? "nil", privacy: .public), transport=\(self.storedTransportKind ?? "nil", privacy: .public)")
                let connectedSession = try await connectDirectSession(
                    integration: directIntegrationType,
                    definition: selectedDefinition,
                    project: project
                )
                bindDirectSession(connectedSession)
            } else {
                guard let agent = ACPAgentRegistry.agentDefinition(id: selectedAgentID) else {
                    throw ACPTransportError.agentError("Agent unavailable: \(selectedAgentID)")
                }
                let preferredModelID = selectedModelID
                let connectedSession = try await connectACPWithTimeout(project: project, agent: agent)

                // Attempt session resume if we have a stored provider session ID (R06)
                // Prefer session/resume (lightweight) over session/load (replays history)
                let canResume = connectedSession.supportsSessionResume
                let canLoadSession = connectedSession.agentCapabilities?.loadSession == true
                logger.info("[Resume] ACP: storedId=\(self.storedProviderSessionId ?? "nil", privacy: .public), canResume=\(canResume), canLoad=\(canLoadSession)")
                if let providerSessionId = storedProviderSessionId, (canResume || canLoadSession) {
                    do {
                        if canResume {
                            try await connectedSession.resumeSession(sessionId: providerSessionId)
                        } else {
                            try await connectedSession.loadSession(sessionId: providerSessionId)
                        }
                        bindACPSession(
                            connectedSession,
                            agentID: selectedAgentID,
                            preferredModelID: preferredModelID
                        )
                    } catch {
                        // Resume failed — don't silently start fresh. Disconnect and ask the user.
                        storedProviderSessionId = nil
                        connectedSession.disconnect()
                        let detail = error.localizedDescription
                        pendingResumeFailure = "Could not restore previous session: \(detail)"
                    }
                } else {
                    bindACPSession(
                        connectedSession,
                        agentID: selectedAgentID,
                        preferredModelID: preferredModelID
                    )
                }
            }
            connectionError = nil
        } catch {
            session = nil
            modelObservations.removeAll()
            syncAvailableModelsForSelection()
            chatViewModel.bindStandaloneSession(nil)
            connectionError = error.localizedDescription
        }
    }

    func reconnect(projects: [AnyProjectSession]) {
        Task { await connect(projects: projects) }
    }

    /// User confirmed starting a fresh session after resume failed.
    func confirmStartFreshSession(projects: [AnyProjectSession]) {
        pendingResumeFailure = nil
        storedProviderSessionId = nil
        Task { await connect(projects: projects) }
    }

    /// User dismissed the resume failure — stay disconnected.
    func dismissResumeFailure() {
        pendingResumeFailure = nil
    }

    /// Whether the agent/provider is locked because the thread already has conversation history.
    /// Once a thread has messages, switching providers would lose all agent context.
    var isProviderLocked: Bool {
        chatViewModel.persistenceContext != nil || chatViewModel.hasRestoredThread
    }

    func setSelectedAgentID(_ agentID: String?) {
        guard !isProviderLocked else { return }
        selectedAgentID = agentID
        syncAvailableModelsForSelection()
    }

    func setSelectedProjectIdentifier(_ projectIdentifier: String?) {
        selectedProjectIdentifier = projectIdentifier
    }

    func setSelectedModelID(_ modelID: String?) {
        selectedModelID = modelID
    }

    func disconnect() {
        modelObservations.removeAll()
        sessionManager.unregisterStandalone(id: id)
        session = nil
        syncAvailableModelsForSelection()
        chatViewModel.bindStandaloneSession(nil)
        persistSessionMetadata(status: "disconnected")
    }

    func teardown() {
        if isExternallyManaged {
            modelObservations.removeAll()
            chatViewModel.bindStandaloneSession(nil)
            session = nil
            return
        }
        disconnect()
    }

    func prepareExternalVibeLaneSession(agentID: String, projectPath: String) {
        isExternallyManaged = true
        selectedAgentID = agentID
        selectedProjectIdentifier = projectPath
        shouldAutoConnect = false
        connectionError = nil
        syncAvailableModelsForSelection()
    }

    func restoreThreadIfNeeded(_ threadID: String) {
        guard chatViewModel.persistenceContext?.threadID != threadID
            || chatViewModel.timeline.isEmpty else { return }
        chatViewModel.restoreThread(threadId: threadID)
    }

    func attachExistingHeadlessSession(
        _ connectedSession: ACPSession,
        agentID: String,
        preferredModelID: String? = nil
    ) {
        prepareExternalVibeLaneSession(agentID: agentID, projectPath: connectedSession.projectPath.path)
        bindACPSession(
            connectedSession,
            agentID: agentID,
            preferredModelID: preferredModelID
        )
    }

    private func persistSessionMetadata(status: String) {
        guard let threadId = chatViewModel.persistenceContext?.threadID,
              let session = session else { return }
        let metadata = SessionMetadata.from(session: session, agentID: selectedAgentID ?? "unknown")

        // Update stored values for resume
        storedProviderSessionId = metadata.providerSessionID
        storedTransportKind = metadata.transportKind

        persistenceQueue.enqueue { [conversationStore] in
            await conversationStore.updateSessionStatus(
                threadId: threadId, provider: metadata.agentID,
                transportKind: metadata.transportKind, status: status,
                resumeStrategy: metadata.resumeStrategy,
                providerSessionId: metadata.providerSessionID,
                resumeCursorJson: metadata.resumeCursorJSON
            )
        }
    }

    private func applyTrustModeToActivePermissionHandler() {
        session?.permissionHandler?.allowAll = trustMode == .fullTrust
    }

    private func connectACPWithTimeout(
        project: AnyProjectSession,
        agent: ACPAgentDefinition
    ) async throws -> ACPSession {
        let session = try await withThrowingTaskGroup(of: ACPSession.self) { group in
            group.addTask { @MainActor in
                try await self.sessionManager.connectStandalone(
                    id: self.id,
                    project: project,
                    agent: agent,
                    autoAllowPermissions: self.trustMode == .fullTrust
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                throw ACPTransportError.agentError("Timed out while connecting to \(agent.title).")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        return session
    }

    private func connectDirectSession(
        integration: CLIToolDefinition.DirectIntegrationType,
        definition: CLIToolDefinition?,
        project: AnyProjectSession
    ) async throws -> any AgentSessionProtocol {
        let session: any AgentSessionProtocol
        switch integration {
        case .claudeCode:
            session = ClaudeCodeSession(
                projectPath: project.rootURL,
                executable: definition?.terminalInvocation?.executable ?? "claude",
                agentName: definition?.title ?? "Claude Code",
                trustMode: trustMode,
                model: selectedModelID,
                reasoningLevel: reasoningLevel,
                resumeSessionId: storedTransportKind == "claude_code_direct" ? storedProviderSessionId : nil
            )
        case .codex:
            session = CodexSession(
                projectPath: project.rootURL,
                executable: definition?.terminalInvocation?.executable ?? "codex",
                agentName: definition?.title ?? "Codex",
                trustMode: trustMode,
                model: selectedModelID,
                reasoningLevel: reasoningLevel,
                resumeThreadID: storedTransportKind == "codex_direct" ? storedProviderSessionId : nil
            )
        }

        let permissionHandler = ACPPermissionHandler()
        if trustMode == .fullTrust {
            permissionHandler.allowAll = true
        }
        session.installPermissionHandler(permissionHandler)

        try await session.connect()
        return session
    }

    private func bindDirectSession(_ connectedSession: any AgentSessionProtocol) {
        modelObservations.removeAll()
        session = connectedSession
        sessionManager.registerStandalone(id: id, session: connectedSession)
        storedProviderSessionId = connectedSession.providerSessionID
        storedTransportKind = connectedSession.transportKind
        syncAvailableModelsForSelection()
        observeUnexpectedDisconnect(connectedSession)
        chatViewModel.bindStandaloneSession(connectedSession)
        persistSessionMetadata(status: "ready")
    }

    private func bindACPSession(
        _ connectedSession: ACPSession,
        agentID: String?,
        preferredModelID: String?
    ) {
        modelObservations.removeAll()
        session = connectedSession
        storedProviderSessionId = connectedSession.sessionID
        storedTransportKind = "acp"
        applyACPModelState(connectedSession.modelState, for: agentID)

        if let preferredModelID,
           connectedSession.modelState?.currentModelId != preferredModelID {
            selectedModelID = preferredModelID
            Task { await connectedSession.setModel(preferredModelID) }
        }

        connectedSession.$modelState
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.applyACPModelState(state, for: agentID)
                }
            }
            .store(in: &modelObservations)

        // Detect unexpected process exit
        connectedSession.$isConnected
            .dropFirst()
            .filter { !$0 }
            .first()
            .sink { [weak self, weak connectedSession] _ in
                Task { @MainActor in
                    guard let self, self.connectionError == nil else { return }
                    self.connectionError = connectedSession?.lastDisconnectReason
                        ?? "Agent disconnected unexpectedly."
                }
            }
            .store(in: &modelObservations)

        chatViewModel.bindStandaloneSession(connectedSession)
        persistSessionMetadata(status: "ready")
    }

    private func observeUnexpectedDisconnect<S: AgentSessionProtocol>(_ session: S) {
        session.objectWillChange
            .sink { [weak self, weak session] _ in
                Task { @MainActor in
                    guard let self, let session, !session.isConnected, self.connectionError == nil else { return }
                    self.connectionError = "Agent process exited unexpectedly."
                }
            }
            .store(in: &modelObservations)
    }

    private func applyACPModelState(_ state: ACPSessionModelState?, for agentID: String?) {
        if let agentID, let state {
            cachedModelsByAgentID[agentID] = state.availableModels
        }

        if let state {
            availableModels = state.availableModels
            selectedModelID = state.currentModelId
            return
        }

        syncAvailableModelsForSelection()
    }

    private func syncAvailableModelsForSelection() {
        if let directIntegrationType {
            availableModels = AgentModelCatalog.models(for: directIntegrationType).map {
                ACPModelInfo(modelId: $0.slug, name: $0.name, description: nil)
            }
            if let selectedModelID,
               availableModels.contains(where: { $0.modelId == selectedModelID }) {
                return
            }
            selectedModelID = availableModels.first?.modelId
                ?? AgentModelCatalog.defaultModel(for: directIntegrationType)
            return
        }

        availableModels = selectedAgentID.flatMap { cachedModelsByAgentID[$0] } ?? []
        guard !availableModels.isEmpty else {
            if session == nil {
                selectedModelID = nil
            }
            return
        }
        guard let selectedModelID,
              availableModels.contains(where: { $0.modelId == selectedModelID }) else {
            self.selectedModelID = availableModels.first?.modelId
            return
        }
    }
}
