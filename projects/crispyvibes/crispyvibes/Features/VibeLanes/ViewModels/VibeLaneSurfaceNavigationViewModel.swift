import Combine
import Foundation

@MainActor
final class VibeLaneSurfaceNavigationViewModel: ObservableObject {
    enum Screen: Equatable {
        case dashboard
        /// `laneID` preselects the lane when the user started from a lane card.
        case newTask(laneID: UUID?)
        case detail(UUID)
        case lanes
        case laneEditor(UUID)
        case vibes
        case vibeEditor(UUID, laneID: UUID?)
        /// A task's worker or reviewer chat, opened in place. The store is resolved
        /// by the host at render time, so the screen stays Equatable.
        case acp(target: VibeLaneACPChatTarget, taskID: UUID)
    }

    @Published private(set) var screen: Screen = .dashboard

    func show(_ screen: Screen) {
        self.screen = screen
    }

    func showDashboard() {
        screen = .dashboard
    }

    func showNewTask(laneID: UUID? = nil) {
        screen = .newTask(laneID: laneID)
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

    func showVibes() {
        screen = .vibes
    }

    func showVibeEditor(id: UUID, fromLaneID laneID: UUID? = nil) {
        screen = .vibeEditor(id, laneID: laneID)
    }

    func showACPSession(target: VibeLaneACPChatTarget, taskID: UUID) {
        screen = .acp(target: target, taskID: taskID)
    }

    func validateSelection(
        taskExists: (UUID) -> Bool,
        laneExists: (UUID) -> Bool,
        vibeExists: (UUID) -> Bool = { _ in true }
    ) {
        switch screen {
        case let .detail(id) where !taskExists(id):
            screen = .dashboard
        case let .laneEditor(id) where !laneExists(id):
            screen = .lanes
        case let .newTask(laneID) where laneID.map { !laneExists($0) } == true:
            screen = .newTask(laneID: nil)
        case let .vibeEditor(id, _) where !vibeExists(id):
            screen = .vibes
        case let .acp(_, taskID) where !taskExists(taskID):
            screen = .dashboard
        case .dashboard, .newTask, .detail, .lanes, .laneEditor, .vibes, .vibeEditor, .acp:
            break
        }
    }
}
