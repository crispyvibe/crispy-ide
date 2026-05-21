import Foundation

/// Owns the floating agent conversation preview in terminal board mode.
/// Gets stores from the shared ACPSessionRegistry — same store instance
/// as any tab showing the same thread.
@MainActor
final class DockedAgentPreviewCoordinator: ObservableObject {
    private let sessionRegistry: ACPSessionRegistry

    @Published var previewThreadId: String?
    @Published var previewTitle: String?
    private(set) var previewStore: ACPStandaloneSessionStore?

    init(sessionRegistry: ACPSessionRegistry) {
        self.sessionRegistry = sessionRegistry
    }

    // MARK: - Floating Preview

    func showPreview(
        threadId: String,
        title: String,
        agentId: String,
        projectIdentifier: String?,
        vibespaceID: UUID? = nil
    ) {
        previewThreadId = threadId
        previewTitle = title
        // Get from registry — if a tab already has this thread, we share the store
        previewStore = sessionRegistry.storeForThread(
            threadId,
            agentId: agentId,
            projectIdentifier: projectIdentifier,
            vibespaceID: vibespaceID
        )
    }

    func dismissPreview() {
        previewThreadId = nil
        previewTitle = nil
        previewStore = nil
        // Don't teardown — the registry owns the store lifecycle
    }

    /// Returns the preview store and clears the preview state so the board can
    /// adopt the live store into a permanent tile without reloading.
    func promotePreview() -> ACPStandaloneSessionStore? {
        let store = previewStore
        previewThreadId = nil
        previewTitle = nil
        previewStore = nil
        return store
    }
}
