import Combine
import Foundation

@MainActor
final class ACPDeveloperToolsService: ObservableObject {
    @Published var availableAgents: [ACPDiscoveredAgent] = []
    @Published var selectedAgentID = ""
    @Published var promptText = ""
    @Published var responseText = ""
    @Published var statusText = "Idle"
    @Published var isConnecting = false
    @Published var isSending = false
    @Published var autoAllowPermissions = false

    private let sessionManager: ACPSessionManager
    private let vibespaceContextStore: ACPVibeSpaceContextStore
    private var session: ACPSession?

    init(
        sessionManager: ACPSessionManager,
        vibespaceContextStore: ACPVibeSpaceContextStore
    ) {
        self.sessionManager = sessionManager
        self.vibespaceContextStore = vibespaceContextStore
        reloadAgents()
    }

    var focusedProjectDisplayName: String {
        vibespaceContextStore.focusedProjectDisplayName ?? "No focused project"
    }

    var focusedProjectPath: String? {
        vibespaceContextStore.focusedProjectRootPath
    }

    var isConnected: Bool {
        session?.isConnected == true
    }

    func reloadAgents() {
        availableAgents = ACPAgentRegistry.discoverInstalledAgents().filter {
            $0.isAvailable && $0.supportsACP
        }
        if selectedAgentID.isEmpty {
            selectedAgentID = availableAgents.first?.id ?? ""
        } else if !availableAgents.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = availableAgents.first?.id ?? ""
        }
    }

    func connect() async {
        guard !isConnecting else { return }
        guard let project = vibespaceContextStore.focusedProject else {
            statusText = "Focus a project before connecting ACP"
            return
        }
        guard let agent = availableAgents.first(where: { $0.id == selectedAgentID })?.agentDefinition else {
            statusText = "No ACP agent selected"
            return
        }

        isConnecting = true
        responseText = ""
        statusText = "Connecting…"

        do {
            let session = try await sessionManager.connect(
                project: project,
                agent: agent,
                autoAllowPermissions: autoAllowPermissions
            )
            self.session = session
            statusText = "Connected to \(agent.title)"
        } catch {
            statusText = "Connect failed: \(error.localizedDescription)"
        }

        isConnecting = false
        objectWillChange.send()
    }

    func disconnect() {
        guard let session else {
            statusText = "Disconnected"
            return
        }
        sessionManager.release(session)
        self.session = nil
        statusText = "Disconnected"
        objectWillChange.send()
    }

    func cancelPrompt() async {
        guard let session else { return }
        await session.cancel()
        isSending = false
        statusText = "Cancelled"
    }

    func sendPrompt() async {
        guard !isSending else { return }
        guard let session else {
            statusText = "Connect ACP to the focused project first"
            return
        }

        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isSending = true
        responseText = ""
        statusText = "Sending prompt…"

        for await update in session.prompt(prompt) {
            switch update {
            case .agentMessageChunk(.text(let text)):
                responseText += text
            case .thoughtChunk(.text(let text)):
                responseText += "\n[thought] \(text)"
            case .toolCall(let toolCall):
                responseText += "\n[tool] \(toolCall.title ?? toolCall.toolCallId)"
            case .toolCallUpdate(let update):
                responseText += "\n[tool-update] \(update.toolCallId): \(update.status.rawValue)"
            case .sessionInfoUpdate(let info):
                responseText += "\n[session-info] \(info)"
            case .availableCommandsUpdate(let commands):
                responseText += "\n[commands] \(commands.count)"
            case .currentModeUpdate(let mode):
                responseText += "\n[mode] \(mode)"
            case .configOptionUpdate(let config):
                responseText += "\n[config] \(config)"
            case .userMessageChunk:
                break
            case .turnCompleted:
                statusText = "Prompt complete"
            case .unknown(let kind):
                responseText += "\n[unknown] \(kind)"
            case .error(let message):
                responseText += "\n[error] \(message)"
            case .userInputRequest(let request):
                responseText += "\n[user-input-request] \(request.question) options=\(request.options.map(\.label))"
            }
        }

        isSending = false
        statusText = "Prompt complete"
    }
}
