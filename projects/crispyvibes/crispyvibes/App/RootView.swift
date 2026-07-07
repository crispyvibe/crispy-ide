import SwiftUI

struct RootView: View {
    let appContainer: AppContainer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(container: appContainer)
            .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
            .environment(\.vibespaceTodoStoreEnvironment, appContainer.vibespaceTodoStore)
            .environment(\.vibeLaneTaskManagerEnvironment, appContainer.vibeLaneTaskManager)
            .environment(\.jupyterServerService, appContainer.jupyterServerService)
            .onReceive(NotificationCenter.default.publisher(for: .openDeveloperTools)) { _ in
                openWindow(id: "developer-tools")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAllComments)) { _ in
                openWindow(id: "all-comments")
            }
    }
}
