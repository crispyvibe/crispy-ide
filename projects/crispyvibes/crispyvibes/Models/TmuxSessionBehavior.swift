import Foundation

enum TmuxSessionBehavior: String, CaseIterable, Identifiable {
    case detach
    case terminate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .detach: return AppStrings.Settings.Experimental.tmuxBehaviorDetach
        case .terminate: return AppStrings.Settings.Experimental.tmuxBehaviorTerminate
        }
    }
}
