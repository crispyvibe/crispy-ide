import Foundation

/// Captures all session identity and resume information in one place.
/// Computed once at session bind time, refreshed after each turn.
@MainActor
struct SessionMetadata: Sendable {
    let agentID: String
    let transportKind: String
    let resumeStrategy: String
    let providerSessionID: String?
    let resumeCursorJSON: String?

    /// Build metadata by reading protocol properties — single source of truth.
    static func from(session: any AgentSessionProtocol, agentID: String) -> SessionMetadata {
        let providerID = session.providerSessionID
        var cursorJSON: String?

        switch session.transportKind {
        case "claude_code_direct":
            if let id = providerID { cursorJSON = "{\"resume\":\"\(id)\"}" }
        case "codex_direct":
            if let id = providerID { cursorJSON = "{\"threadId\":\"\(id)\"}" }
        default:
            break
        }

        return SessionMetadata(
            agentID: agentID,
            transportKind: session.transportKind,
            resumeStrategy: session.resumeStrategy,
            providerSessionID: providerID,
            resumeCursorJSON: cursorJSON
        )
    }
}
