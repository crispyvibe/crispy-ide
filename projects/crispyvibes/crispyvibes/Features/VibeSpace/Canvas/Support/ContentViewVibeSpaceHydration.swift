import SwiftUI

extension ContentView {
    func scheduleVibeSpaceTerminalHydration(for vibespaceID: UUID) {
        vibespaceHydrationCoordinator.scheduleVibeSpaceTerminalHydration(for: vibespaceID)
    }

    func scheduleEditorSessionStateSave() {
        vibespaceHydrationCoordinator.scheduleEditorSessionStateSave()
    }

    func persistEditorSessionStateNow() {
        vibespaceHydrationCoordinator.persistEditorSessionStateNow()
    }

    func cancelVibeSpaceHydration() {
        vibespaceHydrationCoordinator.cancelVibeSpaceHydration()
    }

    func handleActiveVibeSpaceChange(from oldID: UUID?, to newID: UUID?) {
        vibespaceHydrationCoordinator.handleActiveVibeSpaceChange(from: oldID, to: newID)
    }

    func refreshTerminalShellResolutionContexts(for vibespaceID: UUID) {
        vibespaceHydrationCoordinator.refreshTerminalShellResolutionContexts(for: vibespaceID)
    }

    func applyTerminalShellResolutionContext(
        to project: AnyProjectSession,
        vibespaceID: UUID
    ) {
        vibespaceHydrationCoordinator.applyTerminalShellResolutionContext(to: project, vibespaceID: vibespaceID)
    }

    func requestTerminalFocusWithStabilization(for terminal: AnyTerminalProvider) {
        vibespaceHydrationCoordinator.requestTerminalFocusWithStabilization(for: terminal)
    }

    func markStartupExecuted(forProjectPath projectPath: String, in vibespaceID: UUID) {
        vibespaceHydrationCoordinator.markStartupExecuted(forProjectPath: projectPath, in: vibespaceID)
    }

    func clearStartupExecutionFlag(forProjectPath projectPath: String, in vibespaceID: UUID) {
        vibespaceHydrationCoordinator.clearStartupExecutionFlag(forProjectPath: projectPath, in: vibespaceID)
    }

    func clearStartupExecutionFlags(for vibespaceID: UUID) {
        vibespaceHydrationCoordinator.clearStartupExecutionFlags(for: vibespaceID)
    }

    func resetStartupExecutionFlags() {
        vibespaceHydrationCoordinator.resetStartupExecutionFlags()
    }
}
