import SwiftUI

/// F060: SwiftUI environment key exposing the todo↔lane bridge to the Todos
/// surface, so the detail pane can offer "Send to Lane…" without threading the
/// bridge through canvas layers (mirrors `vibespaceTodoStoreEnvironment`).
/// nil = the pipeline is absent and Todos renders exactly as F053.
private struct TodoLanePipelineBridgeKey: EnvironmentKey {
    static let defaultValue: TodoLanePipelineBridge? = nil
}

extension EnvironmentValues {
    var todoLanePipelineBridgeEnvironment: TodoLanePipelineBridge? {
        get { self[TodoLanePipelineBridgeKey.self] }
        set { self[TodoLanePipelineBridgeKey.self] = newValue }
    }
}

/// F060: exposes the triage coordinator so todo views can render a live
/// "Triaging…" indicator from `activeTodoIDs`.
private struct TodoTriageCoordinatorKey: EnvironmentKey {
    static let defaultValue: TodoTriageCoordinator? = nil
}

extension EnvironmentValues {
    var todoTriageCoordinatorEnvironment: TodoTriageCoordinator? {
        get { self[TodoTriageCoordinatorKey.self] }
        set { self[TodoTriageCoordinatorKey.self] = newValue }
    }
}
