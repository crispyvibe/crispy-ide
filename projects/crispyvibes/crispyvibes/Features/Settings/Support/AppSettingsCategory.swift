import Foundation

enum AppSettingsCategory: String, CaseIterable, Identifiable {
    case account
    case general
    case shortcuts
    case layout
    case terminal
    case updates
    case services
    case acp
    case experimental
    case nerd
    case remoteSSH
    case reset

    static var sidebarCases: [AppSettingsCategory] {
        [
            .account,
            .general,
            .shortcuts,
            .terminal,
            .services,
            .acp,
            .updates,
            .experimental,
            .remoteSSH,
            .reset
        ]
    }

    var id: String { rawValue }

    var sidebarReplacement: AppSettingsCategory {
        switch self {
        case .layout:
            return .general
        case .nerd:
            return .terminal
        default:
            return self
        }
    }

    var title: String {
        switch self {
        case .account:
            return "Account"
        case .general:
            return "Appearance"
        case .shortcuts:
            return "Keyboard Shortcuts"
        case .layout:
            return AppSettingsCategory.general.title
        case .terminal:
            return "Terminal"
        case .updates:
            return "Updates"
        case .services:
            return "AI Services"
        case .acp:
            return "Agents"
        case .experimental:
            return AppStrings.Settings.Experimental.title
        case .nerd:
            return AppSettingsCategory.terminal.title
        case .remoteSSH:
            return "Connections"
        case .reset:
            return "Reset"
        }
    }

    var subtitle: String {
        switch self {
        case .account:
            return "Sign in to enable cloud-backed features"
        case .general:
            return "Theme, typography, borders, rail position, and app chrome"
        case .shortcuts:
            return "Customize app-wide shortcuts and terminal inline trigger"
        case .layout:
            return AppSettingsCategory.general.subtitle
        case .terminal:
            return "Shell defaults, rendering, and tmux integration"
        case .updates:
            return "Automatic checks and update feed configuration"
        case .services:
            return "CLI command defaults and reusable prompt templates"
        case .acp:
            return "Default agent selection and custom agent commands"
        case .experimental:
            return AppStrings.Settings.Experimental.subtitle
        case .nerd:
            return AppSettingsCategory.terminal.subtitle
        case .remoteSSH:
            return "Remote connection defaults and service configuration"
        case .reset:
            return "Clear local overrides and start from a fresh machine state"
        }
    }

    var iconSystemName: String {
        switch self {
        case .account:
            return "person.crop.circle"
        case .general:
            return "paintbrush"
        case .shortcuts:
            return "keyboard"
        case .layout:
            return AppSettingsCategory.general.iconSystemName
        case .terminal:
            return "terminal"
        case .updates:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .services:
            return "text.bubble"
        case .acp:
            return "sparkles"
        case .experimental:
            return "flask"
        case .nerd:
            return AppSettingsCategory.terminal.iconSystemName
        case .remoteSSH:
            return "network"
        case .reset:
            return "arrow.counterclockwise"
        }
    }

    var categoryItem: SettingsCategoryItem {
        SettingsCategoryItem(
            id: rawValue,
            title: title,
            subtitle: subtitle,
            iconSystemName: iconSystemName
        )
    }
}
