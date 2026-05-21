import SwiftUI

struct RootView: View {
    let appContainer: AppContainer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(container: appContainer)
            .onReceive(NotificationCenter.default.publisher(for: .openDeveloperTools)) { _ in
                openWindow(id: "developer-tools")
            }
    }
}
