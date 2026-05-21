import Combine
import Foundation

enum ACPStderrDiagnostics {
    static func summary(for stderr: String) -> String? {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "stderrHash=\(AppDiagnostics.sha256Hex(trimmed).prefix(12)) stderrBytes=\(trimmed.utf8.count)"
    }
}

@MainActor
protocol AgentSessionProtocol: ObservableObject, Identifiable where ID == UUID {
    var isConnected: Bool { get }
    var agentName: String { get }
    /// Stable agent identifier for persistence and matching.
    var agentID: String { get }
    var projectPath: URL { get }
    var permissionHandler: ACPPermissionHandler? { get }
    var availableModes: [ACPModeInfo] { get }
    var currentModeID: String? { get }
    var availableModels: [ACPModelInfo] { get }
    var currentModelID: String? { get }

    /// Transport identifier — "acp", "claude_code_direct", "codex_direct".
    var transportKind: String { get }
    /// Provider-specific session or thread ID for resume.
    var providerSessionID: String? { get }
    /// Resume strategy — "native_resume", "transcript_replay", "none".
    var resumeStrategy: String { get }

    func connect() async throws
    func prompt(_ text: String, contentBlocks: [[String: Any]]?) -> AsyncStream<ACPUpdate>
    func cancel() async
    func disconnect()
    func setMode(_ modeID: String) async
    func setModel(_ modelID: String) async
    func installPermissionHandler(_ handler: ACPPermissionHandler)
}

extension AgentSessionProtocol {
    func prompt(_ text: String) -> AsyncStream<ACPUpdate> {
        prompt(text, contentBlocks: nil)
    }

    var availableModes: [ACPModeInfo] { [] }
    var currentModeID: String? { nil }
    var availableModels: [ACPModelInfo] { [] }
    var currentModelID: String? { nil }
    var transportKind: String { "unknown" }
    var providerSessionID: String? { nil }
    var resumeStrategy: String { "none" }

    func installPermissionHandler(_ handler: ACPPermissionHandler) {}

    func setMode(_ modeID: String) async {}
    func setModel(_ modelID: String) async {}
}
