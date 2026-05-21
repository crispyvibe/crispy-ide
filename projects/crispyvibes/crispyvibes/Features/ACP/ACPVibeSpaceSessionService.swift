import Combine
import SwiftUI

@MainActor
final class ACPVibeSpaceSessionService: ObservableObject {
    @Published private(set) var focusedProject: AnyProjectSession?
    @Published private(set) var preferredAgentID: String?

    var hasConfiguredAgent: Bool {
        preferredAgentID != nil
    }

    var focusedProjectTitle: String? {
        focusedProject?.title
    }

    func sync(
        focusedProject: AnyProjectSession?,
        preferredAgentID: String?,
        vibespaceID: UUID? = nil
    ) {
        self.focusedProject = focusedProject
        self.preferredAgentID = preferredAgentID
    }
}
