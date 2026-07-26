import SwiftUI

struct RootView: View {
    let appContainer: AppContainer
    @Environment(\.openWindow) private var openWindow
    /// Resolved once on appear. Agent discovery probes PATH, so it must not run
    /// inside a view body — see `VibeLaneEngineDisplayCatalog`.
    @State private var vibeLaneEngineCatalog = VibeLaneEngineDisplayCatalog.unresolved

    var body: some View {
        ContentView(container: appContainer)
            .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
            .environment(\.vibespaceTodoStoreEnvironment, appContainer.vibespaceTodoStore)
            .environment(\.vibeLaneTaskManagerEnvironment, appContainer.vibeLaneTaskManager)
            .environment(\.vibeLaneSkillStoreEnvironment, appContainer.vibeLaneSkillStore)
            .environment(\.vibeLaneEngineDisplayCatalog, vibeLaneEngineCatalog)
            .task {
                vibeLaneEngineCatalog = VibeLaneEngineDisplayCatalog(
                    discovered: ACPAgentRegistry.discoverInstalledAgents()
                )
            }
            .environment(\.todoLanePipelineBridgeEnvironment, appContainer.todoLanePipelineBridge)
            .environment(\.todoTriageCoordinatorEnvironment, appContainer.todoTriageCoordinator)
            .environment(\.vibeLaneSurfaceNavigationEnvironment, appContainer.vibeLaneSurfaceNavigationViewModel)
            .environment(\.jupyterServerService, appContainer.jupyterServerService)
            .onReceive(NotificationCenter.default.publisher(for: .openDeveloperTools)) { _ in
                openWindow(id: "developer-tools")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAllComments)) { _ in
                openWindow(id: "all-comments")
            }
    }
}
