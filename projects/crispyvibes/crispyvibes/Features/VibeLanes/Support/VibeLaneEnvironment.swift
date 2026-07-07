import SwiftUI

/// F059 — SwiftUI environment key exposing the Vibe Lanes task manager to the
/// content viewer, so the dashboard surface can be built without threading the
/// manager through every canvas layer (mirrors `vibespaceTodoStoreEnvironment`).
private struct VibeLaneTaskManagerKey: EnvironmentKey {
    static let defaultValue: VibeLaneTaskManager? = nil
}

private struct VibeLaneSurfaceNavigationKey: EnvironmentKey {
    static let defaultValue: VibeLaneSurfaceNavigationViewModel? = nil
}

extension EnvironmentValues {
    var vibeLaneTaskManagerEnvironment: VibeLaneTaskManager? {
        get { self[VibeLaneTaskManagerKey.self] }
        set { self[VibeLaneTaskManagerKey.self] = newValue }
    }

    var vibeLaneSurfaceNavigationEnvironment: VibeLaneSurfaceNavigationViewModel? {
        get { self[VibeLaneSurfaceNavigationKey.self] }
        set { self[VibeLaneSurfaceNavigationKey.self] = newValue }
    }
}
