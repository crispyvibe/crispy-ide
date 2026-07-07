import AppKit
import Combine
import Foundation

@MainActor
final class ACPChatViewModel: ObservableObject {
    private static let maxTimelineEntries = 50_000
    static let restoredMessageLimit = 6
    private static let restoredMessageTextLimit = 3_000

    @Published var timeline: [ACPTimelineEntry] = []
    @Published var composeText = ""
    @Published var isStreaming = false
    /// Attached images for the next message (#5).
    @Published var composeImages: [NSImage] = []
    /// Context window usage — updated from sessionInfoUpdate events.
    @Published private(set) var contextWindowUsage: ACPContextWindowUsage?
    @Published var availableCommands: [ACPSlashCommand] = []
    /// Pending structured question from the agent (#4).
    @Published var pendingUserInputRequest: ACPUserInputRequest?

    private let sessionManager: ACPSessionManager
    private let conversationStore: AgentConversationStore
    private var activeProjectIdentifier: String?
    private var boundStandaloneSession: (any AgentSessionProtocol)?
    private var promptTask: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private let persistenceQueue = SerialTaskQueue()

    /// Persistence — thread context created on first send, reused for the conversation lifetime.
    private(set) var persistenceContext: PersistenceContext?
    private(set) var vibespaceID: String?
    private(set) var hasRestoredThread = false

    /// Called by the owning store after each completed turn to persist session metadata.
    var onTurnCompleted: (() -> Void)?

    struct PersistenceContext {
        let threadID: String
        let vibespaceID: String
        let projectPath: String
        let agentID: String
        let transportKind: String
        let model: String
        var title: String = ""
    }

    init(sessionManager: ACPSessionManager, conversationStore: AgentConversationStore) {
        self.sessionManager = sessionManager
        self.conversationStore = conversationStore
        sessionManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebindSession()
                }
            }
            .store(in: &observations)
    }

    var activeSession: (any AgentSessionProtocol)? {
        if let boundStandaloneSession {
            return boundStandaloneSession
        }
        guard let activeProjectIdentifier else { return nil }
        return sessionManager.session(for: activeProjectIdentifier)
    }

    var agentName: String {
        activeSession?.agentName ?? "ACP Agent"
    }

    var agentID: String? {
        activeSession?.agentID ?? persistenceContext?.agentID
    }

    var isConnected: Bool {
        activeSession?.isConnected == true
    }

    var permissionHandler: ACPPermissionHandler? {
        activeSession?.permissionHandler
    }

    var availableModes: [ACPModeInfo] {
        activeSession?.availableModes ?? []
    }

    var currentModeID: String? {
        activeSession?.currentModeID
    }

    var availableModels: [ACPModelInfo] {
        activeSession?.availableModels ?? []
    }

    var currentModelID: String? {
        activeSession?.currentModelID
    }

    var filteredCommands: [ACPSlashCommand] {
        guard composeText.hasPrefix("/") else { return [] }
        let query = composeText.lowercased()
        return Array(availableCommands.filter { $0.name.lowercased().hasPrefix(query) }.prefix(5))
    }

    func setActiveProjectIdentifier(_ projectIdentifier: String?) {
        boundStandaloneSession = nil
        activeProjectIdentifier = projectIdentifier
        if projectIdentifier == nil {
            timeline.removeAll()
            availableCommands.removeAll()
            isStreaming = false
        }
        rebindSession()
    }

    func bindStandaloneSession(_ session: (any AgentSessionProtocol)?) {
        let didChangeSession = boundStandaloneSession?.id != session?.id
        boundStandaloneSession = session
        activeProjectIdentifier = nil
        if didChangeSession && !hasRestoredThread {
            timeline.removeAll()
            availableCommands.removeAll()
            isStreaming = false
        }
        rebindSession()
    }

    func setMode(_ modeID: String) {
        Task { await activeSession?.setMode(modeID) }
    }

    func setModel(_ modelID: String) {
        Task { await activeSession?.setModel(modelID) }
    }

    /// Called by the standalone pane to provide a connect-then-send path.
    var connectAndSend: ((String) -> Void)?

    struct ProgrammaticSendResult {
        var ok: Bool
        var responseText: String
        var errorText: String?
        var threadID: String?
    }

    func send() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        // Cancel any orphaned prompt task
        promptTask?.cancel()
        promptTask = nil

        // If no active session, trigger auto-connect and queue the message
        guard let session = activeSession else {
            if let connectAndSend {
                composeText = ""
                connectAndSend(text)
            }
            return
        }

        composeText = ""
        let images = composeImages
        composeImages = []
        isStreaming = true
        markStreamingEntriesComplete()

        // Create a new turn entry
        let turn = ACPTurnEntry(id: UUID(), timestamp: Date(), userMessage: text, attachedImageCount: images.count)
        appendTimelineEntry(.turn(turn))

        // Ensure thread exists for persistence
        if persistenceContext == nil {
            let agentID = session.agentID
            let transportKind = session.transportKind
            let model = session.currentModelID ?? ""
            let projectPath = session.projectPath.path
            let wsID = self.vibespaceID ?? UUID().uuidString
            ensureThread(
                vibespaceID: wsID, projectPath: projectPath,
                agentID: agentID, transportKind: transportKind, model: model
            )
        }

        // Persist user message
        let turnID = turn.id.uuidString
        persistUserMessage(text: text, turnID: turnID)

        promptTask = Task { [weak self] in
            // Build content blocks with text + images (#5)
            var contentBlocks: [[String: Any]]? = nil
            if !images.isEmpty {
                var blocks: [[String: Any]] = [["type": "text", "text": text]]
                for image in images {
                    if let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        let base64 = png.base64EncodedString()
                        blocks.append(["type": "image", "data": base64, "mediaType": "image/png"])
                    }
                }
                contentBlocks = blocks
            }

            for await update in session.prompt(text, contentBlocks: contentBlocks) {
                guard let self, !Task.isCancelled else { break }
                await MainActor.run {
                    self.applyUpdateToActiveTurn(update)
                }
            }

            if Task.isCancelled {
                await self?.activeSession?.cancel()
            }

            await MainActor.run {
                self?.finalizeStreaming()
            }
        }
    }

    /// Sends through the same chat/timeline/persistence path as the compose box,
    /// but awaits completion so headless orchestrators can make the next decision.
    func sendProgrammatic(_ text: String) async -> ProgrammaticSendResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ProgrammaticSendResult(ok: false, responseText: "", errorText: "empty prompt", threadID: persistenceContext?.threadID)
        }
        guard !isStreaming else {
            return ProgrammaticSendResult(ok: false, responseText: "", errorText: "session is already streaming", threadID: persistenceContext?.threadID)
        }
        guard let session = activeSession else {
            return ProgrammaticSendResult(ok: false, responseText: "", errorText: "no active ACP session", threadID: persistenceContext?.threadID)
        }

        promptTask?.cancel()
        promptTask = nil
        composeText = ""
        composeImages = []
        isStreaming = true
        markStreamingEntriesComplete()

        let turn = ACPTurnEntry(id: UUID(), timestamp: Date(), userMessage: trimmed)
        appendTimelineEntry(.turn(turn))

        if persistenceContext == nil {
            let wsID = self.vibespaceID ?? UUID().uuidString
            ensureThread(
                vibespaceID: wsID,
                projectPath: session.projectPath.path,
                agentID: session.agentID,
                transportKind: session.transportKind,
                model: session.currentModelID ?? ""
            )
        }

        let turnID = turn.id.uuidString
        persistUserMessage(text: trimmed, turnID: turnID)

        var streamEndedWithCompletion = false
        for await update in session.prompt(trimmed, contentBlocks: nil) {
            if Task.isCancelled {
                await session.cancel()
                break
            }
            applyUpdateToActiveTurn(update)
            if case .turnCompleted = update {
                streamEndedWithCompletion = true
                break
            }
        }

        finalizeStreaming()

        guard let lastTurn = timeline.last(where: {
            if case .turn = $0.kind { return true }
            return false
        }), case .turn(let completedTurn) = lastTurn.kind else {
            return ProgrammaticSendResult(
                ok: false,
                responseText: "",
                errorText: "no turn was recorded",
                threadID: persistenceContext?.threadID
            )
        }

        return ProgrammaticSendResult(
            ok: completedTurn.errorText == nil && (streamEndedWithCompletion || !completedTurn.responseText.isEmpty),
            responseText: completedTurn.responseText,
            errorText: completedTurn.errorText,
            threadID: persistenceContext?.threadID
        )
    }

    func cancelPrompt() {
        promptTask?.cancel()
        promptTask = nil
        isStreaming = false
        pendingUserInputRequest = nil
        Task { await activeSession?.cancel() }
    }

    /// Respond to a structured user input request (#4).
    func respondToUserInput(requestId: String, answer: String) {
        pendingUserInputRequest = nil
        // Send the answer as a regular message — the agent correlates by context
        composeText = answer
        send()
    }

    func resend(from entryID: UUID) {
        guard let index = timeline.firstIndex(where: { $0.id == entryID }),
              case .userMessage(let text) = timeline[index].kind else { return }
        timeline.removeSubrange(index...)
        composeText = text
    }

    private func rebindSession() {
        observations.removeAll()

        sessionManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebindSession()
                }
            }
            .store(in: &observations)

        if let activeSession {
            observeSession(activeSession)
        }

        activeSession?.permissionHandler?.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                // Record approval pause offset for message segmentation (#21)
                if let self, self.isStreaming,
                   self.activeSession?.permissionHandler?.pendingRequest != nil,
                   let turnIndex = self.timeline.lastIndex(where: { if case .turn = $0.kind { return true }; return false }),
                   case .turn(var turn) = self.timeline[turnIndex].kind {
                    let offset = turn.responseText.count
                    if offset > 0, turn.approvalPauseOffsets.last != offset {
                        turn.approvalPauseOffsets.append(offset)
                        self.timeline[turnIndex].kind = .turn(turn)
                    }
                }
            }
            .store(in: &observations)

        activeSession?.permissionHandler?.onDiffsReceived = { [weak self] toolCallID, content in
            self?.upsertToolCallContent(toolCallID: toolCallID, newContent: content)
        }
    }

    private func observeSession<S: AgentSessionProtocol>(_ session: S) {
        session.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &observations)
    }

    private func finalizeStreaming() {
        promptTask = nil
        isStreaming = false
        markStreamingEntriesComplete()
        persistCompletedTurn()
        onTurnCompleted?()
    }

    private func markStreamingEntriesComplete() {
        for index in timeline.indices {
            switch timeline[index].kind {
            case .assistantMessage(let text, true):
                timeline[index].kind = .assistantMessage(text: text, streaming: false)
                timeline[index].completedAt = Date()
            case .turn(var turn) where turn.isStreaming:
                turn.isStreaming = false
                turn.completedAt = Date()
                timeline[index].kind = .turn(turn)
                timeline[index].completedAt = Date()
            default:
                break
            }
        }
    }

    private func applyUpdateToActiveTurn(_ update: ACPUpdate) {
        guard let turnIndex = timeline.lastIndex(where: {
            if case .turn = $0.kind { return true }; return false
        }), case .turn(var turn) = timeline[turnIndex].kind else {
            applyUpdate(update)
            return
        }

        switch update {
        case .agentMessageChunk(.text(let text)):
            turn.responseText += text
        case .thoughtChunk(.text(let text)):
            turn.thinking += text
        case .toolCall(let toolCall):
            let state = ACPToolCallState(
                id: toolCall.toolCallId,
                title: toolCall.title ?? toolCall.toolCallId,
                kind: toolCall.kind,
                status: toolCall.status ?? .pending,
                content: toolCall.content,
                locations: toolCall.locations
            )
            if let i = turn.toolCalls.firstIndex(where: { $0.id == state.id }) {
                turn.toolCalls[i] = state
            } else {
                turn.toolCalls.append(state)
            }
        case .toolCallUpdate(let update):
            if let i = turn.toolCalls.firstIndex(where: { $0.id == update.toolCallId }) {
                turn.toolCalls[i].status = update.status
                if !update.content.isEmpty { turn.toolCalls[i].content = update.content }
            }
        case .error(let message):
            turn.errorText = message
        case .userInputRequest(let request):
            pendingUserInputRequest = request
        case .availableCommandsUpdate(let commands):
            availableCommands = commands.compactMap { command in
                guard let name = command["name"] as? String, !name.isEmpty else { return nil }
                return ACPSlashCommand(name: name, description: command["description"] as? String ?? "")
            }
        case .turnCompleted:
            break
        default:
            break
        }

        timeline[turnIndex].kind = .turn(turn)
    }

    private func applyUpdate(_ update: ACPUpdate) {
        switch update {
        case .agentMessageChunk(.text(let text)):
            appendAssistantChunk(text)
        case .thoughtChunk(.text(let text)):
            appendThoughtChunk(text)
        case .toolCall(let toolCall):
            upsertToolCall(toolCall)
        case .toolCallUpdate(let update):
            applyToolCallStatus(update)
        case .availableCommandsUpdate(let commands):
            availableCommands = commands.compactMap { command in
                guard let name = command["name"] as? String, !name.isEmpty else { return nil }
                return ACPSlashCommand(
                    name: name,
                    description: command["description"] as? String ?? ""
                )
            }
        case .currentModeUpdate, .configOptionUpdate, .unknown, .userMessageChunk, .error, .userInputRequest, .turnCompleted:
            break
        case .sessionInfoUpdate(let info):
            if let usage = ACPContextWindowUsage.parse(from: info) {
                contextWindowUsage = usage
            }
        }
    }

    private func appendAssistantChunk(_ text: String) {
        guard !text.isEmpty else { return }
        if let index = timeline.lastIndex(where: { entry in
            if case .assistantMessage(_, true) = entry.kind { return true }
            return false
        }) {
            if case .assistantMessage(let existing, _) = timeline[index].kind {
                timeline[index].kind = .assistantMessage(text: existing + text, streaming: true)
            }
            return
        }
        appendTimelineEntry(.assistant(text, streaming: true))
    }

    private func appendThoughtChunk(_ text: String) {
        guard !text.isEmpty else { return }
        if let index = timeline.lastIndex(where: { entry in
            if case .thought = entry.kind { return true }
            return false
        }), index == timeline.count - 1,
           case .thought(let existing) = timeline[index].kind {
            timeline[index].kind = .thought(existing + text)
            return
        }
        appendTimelineEntry(.thought(text))
    }

    private func upsertToolCall(_ toolCall: ACPToolCallUpdate) {
        let toolCallState = ACPToolCallState(
            id: toolCall.toolCallId,
            title: toolCall.title ?? toolCall.toolCallId,
            kind: toolCall.kind,
            status: toolCall.status ?? .pending,
            content: toolCall.content,
            locations: toolCall.locations
        )

        if let index = timeline.lastIndex(where: { entry in
            if case .toolCallGroup = entry.kind { return true }
            return false
        }), index == timeline.count - 1,
           case .toolCallGroup(var existingCalls) = timeline[index].kind {
            if let callIndex = existingCalls.firstIndex(where: { $0.id == toolCallState.id }) {
                existingCalls[callIndex] = toolCallState
            } else {
                existingCalls.append(toolCallState)
            }
            timeline[index].kind = .toolCallGroup(existingCalls)
            return
        }

        appendTimelineEntry(.toolCalls([toolCallState]))
    }

    private func applyToolCallStatus(_ update: ACPToolCallStatusUpdate) {
        guard let entryIndex = timeline.lastIndex(where: { entry in
            guard case .toolCallGroup(let calls) = entry.kind else { return false }
            return calls.contains(where: { $0.id == update.toolCallId })
        }), case .toolCallGroup(var calls) = timeline[entryIndex].kind,
           let callIndex = calls.firstIndex(where: { $0.id == update.toolCallId }) else {
            return
        }

        calls[callIndex].status = update.status
        if !update.content.isEmpty {
            calls[callIndex].content = update.content
        }
        timeline[entryIndex].kind = .toolCallGroup(calls)
    }

    private func upsertToolCallContent(toolCallID: String, newContent: [ACPToolCallContent]) {
        guard !newContent.isEmpty else { return }

        // Check turn entries first (new turn-based model)
        for entryIndex in timeline.indices.reversed() {
            if case .turn(var turn) = timeline[entryIndex].kind,
               let callIndex = turn.toolCalls.firstIndex(where: { $0.id == toolCallID }) {
                turn.toolCalls[callIndex].content = newContent
                timeline[entryIndex].kind = .turn(turn)
                return
            }
        }

        // Fallback: check flat toolCallGroup entries (legacy)
        guard let entryIndex = timeline.lastIndex(where: { entry in
            guard case .toolCallGroup(let calls) = entry.kind else { return false }
            return calls.contains(where: { $0.id == toolCallID })
        }), case .toolCallGroup(var calls) = timeline[entryIndex].kind,
           let callIndex = calls.firstIndex(where: { $0.id == toolCallID }) else {
            return
        }

        calls[callIndex].content = newContent
        timeline[entryIndex].kind = .toolCallGroup(calls)
    }

    private func appendTimelineEntry(_ entry: ACPTimelineEntry) {
        timeline.append(entry)
        trimTimelineIfNeeded()
    }

    private func trimTimelineIfNeeded() {
        guard timeline.count > Self.maxTimelineEntries else { return }
        timeline.removeFirst(timeline.count - Self.maxTimelineEntries)
    }

    // MARK: - Persistence Hooks

    private func persistUserMessage(text: String, turnID: String) {
        guard let ctx = persistenceContext else { return }
        let msgID = UUID().uuidString
        persistenceQueue.enqueue { [conversationStore, threadID = ctx.threadID] in
            await conversationStore.persistMessage(
                id: msgID, threadId: threadID, turnId: turnID,
                role: "user", text: text, isStreaming: false
            )
        }
    }

    private func persistCompletedTurn() {
        guard let ctx = persistenceContext else { return }
        guard let lastTurn = timeline.last(where: {
            if case .turn = $0.kind { return true }; return false
        }), case .turn(let turn) = lastTurn.kind else { return }

        let threadID = ctx.threadID
        let turnID = turn.id.uuidString
        let responseText = turn.responseText
        let thinking = turn.thinking
        let toolCalls = turn.toolCalls
        let userMessage = turn.userMessage
        let changedFiles = turn.changedFiles
        let isFirstTurn = timeline.count(where: {
            if case .turn = $0.kind { return true }; return false
        }) == 1

        persistenceQueue.enqueue { [conversationStore] in
            // Persist thinking as a system message
            if !thinking.isEmpty {
                await conversationStore.persistMessage(
                    id: UUID().uuidString, threadId: threadID, turnId: turnID,
                    role: "system", text: thinking, isStreaming: false
                )
            }

            // Persist assistant response
            if !responseText.isEmpty {
                await conversationStore.persistMessage(
                    id: UUID().uuidString, threadId: threadID, turnId: turnID,
                    role: "assistant", text: responseText, isStreaming: false
                )
            }

            // Persist tool calls as activities with file change content
            for toolCall in toolCalls {
                var payload: [String: Any] = [
                    "toolCallId": toolCall.id,
                    "kind": toolCall.kind ?? "unknown",
                    "status": toolCall.status.rawValue,
                    "itemType": ACPToolCallClassifier.classify(toolCall),
                ]
                // Include file paths and diff content
                var diffs: [[String: Any]] = []
                for content in toolCall.content {
                    if case .diff(let diff) = content {
                        var diffEntry: [String: Any] = ["path": diff.path]
                        if let oldText = diff.oldText { diffEntry["oldText"] = oldText }
                        diffEntry["newText"] = diff.newText
                        diffs.append(diffEntry)
                    }
                }
                if !diffs.isEmpty {
                    payload["filePaths"] = diffs.compactMap { $0["path"] as? String }
                    payload["diffs"] = diffs
                }

                await conversationStore.persistActivity(
                    id: UUID().uuidString, threadId: threadID, turnId: turnID,
                    kind: "tool_call", summary: toolCall.title,
                    payload: payload
                )
            }

            // Persist file change summary as activity
            if !changedFiles.isEmpty {
                let fileSummary = changedFiles.map { "\($0.diff.path) (+\($0.additions)/-\($0.deletions))" }
                await conversationStore.persistActivity(
                    id: UUID().uuidString, threadId: threadID, turnId: turnID,
                    kind: "file_change",
                    summary: "\(changedFiles.count) file(s) changed",
                    payload: ["files": fileSummary]
                )
            }

            // Auto-generate thread title — two-phase (R12)
            if isFirstTurn {
                // Phase 1: immediate seed from message prefix
                let seed = String(userMessage.prefix(60))
                await conversationStore.updateThreadTitle(id: threadID, title: seed)
                await MainActor.run { [weak self] in self?.persistenceContext?.title = seed }

                // Phase 2: LLM-generated title via text service CLI
                let llmTitle = TextGenerationService().generateThreadTitle(from: userMessage)
                let improved = llmTitle ?? ACPTitleGenerator.titleFromTurn(
                    userMessage: userMessage, responseText: responseText
                )
                if improved != seed {
                    await conversationStore.updateThreadTitle(id: threadID, title: improved)
                    await MainActor.run { [weak self] in self?.persistenceContext?.title = improved }
                }
            }
        }
    }

    func ensureThread(
        vibespaceID: String, projectPath: String,
        agentID: String, transportKind: String, model: String
    ) {
        guard persistenceContext == nil else { return }
        let threadID = UUID().uuidString
        persistenceContext = PersistenceContext(
            threadID: threadID, vibespaceID: vibespaceID,
            projectPath: projectPath, agentID: agentID,
            transportKind: transportKind, model: model
        )
        // Notify observers so the snapshot gets re-captured with the new threadId
        objectWillChange.send()
        persistenceQueue.enqueue { [conversationStore] in
            await conversationStore.createThread(
                id: threadID, vibespaceId: vibespaceID, projectPath: projectPath,
                title: "New conversation", agentId: agentID,
                transportKind: transportKind, model: model
            )
        }
    }

    func updateVibeSpaceID(_ id: String?) {
        vibespaceID = id
    }

    /// Restore a thread's conversation history from the persistence store.
    func restoreThread(threadId: String) {
        hasRestoredThread = true
        let messageLimit = Self.restoredMessageLimit
        Task { [conversationStore, vibespaceID] in
            async let messagesResult = conversationStore.listMessages(
                threadId: threadId,
                limit: messageLimit
            )
            async let threadResult = conversationStore.getThread(id: threadId)

            let messages = await messagesResult
            let threadData = await threadResult

            var restoredTimeline: [ACPTimelineEntry] = []
            for msg in messages {
                guard let role = msg["role"] as? String,
                      let rawText = msg["text"] as? String,
                      let id = msg["id"] as? String else { continue }
                let text = Self.restoredDisplayText(rawText)
                let ts = (msg["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                let entryID = UUID(uuidString: id) ?? UUID()

                switch role {
                case "user":
                    restoredTimeline.append(ACPTimelineEntry(id: entryID, timestamp: ts, kind: .userMessage(text)))
                case "assistant":
                    restoredTimeline.append(ACPTimelineEntry(id: entryID, timestamp: ts, kind: .assistantMessage(text: text, streaming: false), completedAt: ts))
                default:
                    break
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.persistenceContext = PersistenceContext(
                    threadID: threadId,
                    vibespaceID: threadData?["vibespaceId"] as? String ?? vibespaceID ?? "",
                    projectPath: threadData?["projectPath"] as? String ?? "",
                    agentID: threadData?["agentId"] as? String ?? "",
                    transportKind: threadData?["transportKind"] as? String ?? "",
                    model: threadData?["model"] as? String ?? "",
                    title: threadData?["title"] as? String ?? ""
                )
                self.timeline = restoredTimeline
            }
        }
    }

    /// Apply pre-loaded restore data (called by the owning store for coordinated restore).
    func applyRestoredData(threadId: String, messages: [[String: Any]], threadData: [String: Any]?) {
        hasRestoredThread = true
        var restoredTimeline: [ACPTimelineEntry] = []
        for msg in messages {
            guard let role = msg["role"] as? String,
                  let rawText = msg["text"] as? String,
                  let id = msg["id"] as? String else { continue }
            let text = Self.restoredDisplayText(rawText)
            let ts = (msg["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            let entryID = UUID(uuidString: id) ?? UUID()

            switch role {
            case "user":
                restoredTimeline.append(ACPTimelineEntry(id: entryID, timestamp: ts, kind: .userMessage(text)))
            case "assistant":
                restoredTimeline.append(ACPTimelineEntry(id: entryID, timestamp: ts, kind: .assistantMessage(text: text, streaming: false), completedAt: ts))
            default:
                break
            }
        }

        persistenceContext = PersistenceContext(
            threadID: threadId,
            vibespaceID: threadData?["vibespaceId"] as? String ?? vibespaceID ?? "",
            projectPath: threadData?["projectPath"] as? String ?? "",
            agentID: threadData?["agentId"] as? String ?? "",
            transportKind: threadData?["transportKind"] as? String ?? "",
            model: threadData?["model"] as? String ?? "",
            title: threadData?["title"] as? String ?? ""
        )
        timeline = restoredTimeline
    }

    private static func restoredDisplayText(_ text: String) -> String {
        guard text.count > restoredMessageTextLimit else { return text }
        let prefix = text.prefix(restoredMessageTextLimit)
        return "\(prefix)\n\n[Earlier restored message truncated for UI responsiveness. Full conversation remains stored.]"
    }
}
