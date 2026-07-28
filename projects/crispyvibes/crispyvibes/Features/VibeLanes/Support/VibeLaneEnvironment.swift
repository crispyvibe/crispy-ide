import SwiftUI

enum VibeLaneVisualIdentity {
    static let symbolName = "flowchart"
}

/// F059 — SwiftUI environment key exposing the Vibe Lanes task manager to the
/// content viewer, so the dashboard surface can be built without threading the
/// manager through every canvas layer (mirrors `vibespaceTodoStoreEnvironment`).
private struct VibeLaneTaskManagerKey: EnvironmentKey {
    static let defaultValue: VibeLaneTaskManager? = nil
}

private struct VibeLaneSkillStoreKey: EnvironmentKey {
    static let defaultValue: VibeLaneSkillStore? = nil
}

private struct VibeLaneSurfaceNavigationKey: EnvironmentKey {
    static let defaultValue: VibeLaneSurfaceNavigationViewModel? = nil
}

/// Installed-agent display metadata for engine summaries. Resolved once outside
/// the render path (agent discovery resolves every catalog executable through
/// PATH) and read from the environment by the summary views, which render once
/// per checkpoint and per attempt.
private struct VibeLaneEngineDisplayCatalogKey: EnvironmentKey {
    static let defaultValue = VibeLaneEngineDisplayCatalog.unresolved
}

extension EnvironmentValues {
    var vibeLaneTaskManagerEnvironment: VibeLaneTaskManager? {
        get { self[VibeLaneTaskManagerKey.self] }
        set { self[VibeLaneTaskManagerKey.self] = newValue }
    }

    var vibeLaneSkillStoreEnvironment: VibeLaneSkillStore? {
        get { self[VibeLaneSkillStoreKey.self] }
        set { self[VibeLaneSkillStoreKey.self] = newValue }
    }

    var vibeLaneSurfaceNavigationEnvironment: VibeLaneSurfaceNavigationViewModel? {
        get { self[VibeLaneSurfaceNavigationKey.self] }
        set { self[VibeLaneSurfaceNavigationKey.self] = newValue }
    }

    var vibeLaneEngineDisplayCatalog: VibeLaneEngineDisplayCatalog {
        get { self[VibeLaneEngineDisplayCatalogKey.self] }
        set { self[VibeLaneEngineDisplayCatalogKey.self] = newValue }
    }
}
