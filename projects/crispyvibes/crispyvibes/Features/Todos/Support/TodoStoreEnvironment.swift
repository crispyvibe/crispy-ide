import SwiftUI

/// F053: SwiftUI environment key exposing the vibespace todo store to the
/// content viewer, so the dockable Todos surface can be built without threading
/// the store through every canvas layer (mirrors `vibespaceCommentStoreEnvironment`).
private struct VibeSpaceTodoStoreKey: EnvironmentKey {
    static let defaultValue: VibeSpaceTodoStore? = nil
}

extension EnvironmentValues {
    var vibespaceTodoStoreEnvironment: VibeSpaceTodoStore? {
        get { self[VibeSpaceTodoStoreKey.self] }
        set { self[VibeSpaceTodoStoreKey.self] = newValue }
    }
}
