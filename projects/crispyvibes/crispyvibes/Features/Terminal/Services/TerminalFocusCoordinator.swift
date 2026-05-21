import AppKit

extension Notification.Name {
    static let terminalFocusedSessionDidChange = Notification.Name("TerminalFocusCoordinator.focusedSessionDidChange")
}

enum TerminalFocusCoordinatorUserInfoKey {
    static let sessionID = "sessionID"
}

/// Single source of truth for which terminal surface has Ghostty focus.
/// All focus transitions go through this coordinator to guarantee
/// mutual exclusion: exactly zero or one surface is focused at any time.
@MainActor
final class TerminalFocusCoordinator {
    private weak var focusedEngine: (any TerminalSessionEngine)?
    private var focusedSessionID: UUID?

    init() {}

    /// The only way to grant focus. Unfocuses the previous surface first.
    func focus(engine: any TerminalSessionEngine, sessionID: UUID) {
        if focusedSessionID == sessionID { return }
        unfocusCurrent()
        focusedEngine = engine
        focusedSessionID = sessionID
        engine.setSurfaceFocus(true)
        postFocusedSessionDidChange(sessionID)
    }

    /// Explicitly remove focus from the current surface.
    func unfocusCurrent() {
        let previousSessionID = focusedSessionID
        focusedEngine?.setSurfaceFocus(false)
        focusedEngine = nil
        focusedSessionID = nil
        guard previousSessionID != nil else { return }
        postFocusedSessionDidChange(nil)
    }

    /// Called when a session is destroyed to avoid dangling references.
    func relinquish(sessionID: UUID) {
        guard focusedSessionID == sessionID else { return }
        unfocusCurrent()
    }

    var currentSessionID: UUID? { focusedSessionID }

    private func postFocusedSessionDidChange(_ sessionID: UUID?) {
        NotificationCenter.default.post(
            name: .terminalFocusedSessionDidChange,
            object: self,
            userInfo: [TerminalFocusCoordinatorUserInfoKey.sessionID: sessionID as Any]
        )
    }
}
