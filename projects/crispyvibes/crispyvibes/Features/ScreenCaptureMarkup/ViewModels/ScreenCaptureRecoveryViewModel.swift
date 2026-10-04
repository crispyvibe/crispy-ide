import Foundation

/// One localized recovery command displayed by the permission/error panel.
struct ScreenCaptureRecoveryCommand: Identifiable {
    let action: ScreenCaptureRecoveryAction
    let perform: () -> Void
    var id: String { action.rawValue }
}

/// Structured permission and recoverable-error presentation state.
@MainActor
final class ScreenCaptureRecoveryViewModel: ObservableObject {
    let title: String
    let message: String
    let commands: [ScreenCaptureRecoveryCommand]

    init(title: String, message: String, commands: [ScreenCaptureRecoveryCommand]) {
        self.title = title
        self.message = message
        self.commands = commands
    }

    func perform(_ command: ScreenCaptureRecoveryCommand) { command.perform() }

    func title(for action: ScreenCaptureRecoveryAction) -> String {
        switch action {
        case .retry: return AppStrings.ScreenCapture.tryAgain
        case .recheckPermission: return AppStrings.ScreenCapture.recheck
        case .openSystemSettings: return AppStrings.ScreenCapture.openSystemSettings
        case .relaunchApplication: return AppStrings.ScreenCapture.relaunchCrispy
        case .beginNewCapture: return AppStrings.ScreenCapture.newCapture
        case .cancel: return AppStrings.ScreenCapture.cancel
        }
    }
}
