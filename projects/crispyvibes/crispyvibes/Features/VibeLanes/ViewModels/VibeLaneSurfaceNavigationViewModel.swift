import Combine
import Foundation

@MainActor
final class VibeLaneSurfaceNavigationViewModel: ObservableObject {
    enum Screen: Equatable {
        case dashboard
        case newTask
        case detail(UUID)
        case lanes
        case laneEditor(UUID)
    }

    @Published private(set) var screen: Screen = .dashboard

    func show(_ screen: Screen) {
        self.screen = screen
    }

    func showDashboard() {
        screen = .dashboard
    }

    func showNewTask() {
        screen = .newTask
    }

    func showTask(_ task: VibeLaneTask) {
        screen = .detail(task.id)
    }

    func showTask(id: UUID) {
        screen = .detail(id)
    }

    func showLanes() {
        screen = .lanes
    }

    func showLaneEditor(id: UUID) {
        screen = .laneEditor(id)
    }

    func validateSelection(taskExists: (UUID) -> Bool, laneExists: (UUID) -> Bool) {
        switch screen {
        case let .detail(id) where !taskExists(id):
            screen = .dashboard
        case let .laneEditor(id) where !laneExists(id):
            screen = .lanes
        case .dashboard, .newTask, .detail, .lanes, .laneEditor:
            break
        }
    }
}
