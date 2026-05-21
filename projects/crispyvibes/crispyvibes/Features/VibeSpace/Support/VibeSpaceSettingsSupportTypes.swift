import Foundation

struct VibeSpaceSettingsProjectItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let path: String
    let shortcutIndex: Int?
    let colorTag: ProjectColorTag?
}

enum VibeSpaceShortcutTargetScope: Equatable {
    case vibespace
    case project(String)

    var storageID: String {
        switch self {
        case .vibespace:
            return "vibespace"
        case let .project(path):
            return "project:\(path)"
        }
    }
}

struct VibeSpaceShortcutTargetOption: Identifiable, Equatable {
    let scope: VibeSpaceShortcutTargetScope
    let title: String

    var id: String { scope.storageID }
}

struct VibeSpaceShortcutPersistedRow: Equatable {
    let definition: TerminalShortcutDefinition
    let target: VibeSpaceShortcutTargetScope
}

struct VibeSpaceShortcutPersistencePlan: Equatable {
    let vibespaceShortcuts: [TerminalShortcutDefinition]
    let projectShortcutsByPath: [String: [TerminalShortcutDefinition]]
}

enum VibeSpaceShortcutSettingsSupport {
    static func targetOptions(
        vibespaceName: String,
        projects: [VibeSpaceSettingsProjectItem]
    ) -> [VibeSpaceShortcutTargetOption] {
        let sortedProjects = projects.sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }

        let trimmedVibeSpaceName = vibespaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseVibeSpaceTitle = trimmedVibeSpaceName.isEmpty
            ? AppStrings.VibeSpaceSettings.shortcutScopeVibeSpace
            : trimmedVibeSpaceName
        let hasVibeSpaceNameCollision = sortedProjects.contains {
            $0.title.localizedCaseInsensitiveCompare(baseVibeSpaceTitle) == .orderedSame
        }
        let vibespaceTitle = hasVibeSpaceNameCollision
            ? "\(baseVibeSpaceTitle) (vs)"
            : baseVibeSpaceTitle

        return [VibeSpaceShortcutTargetOption(scope: .vibespace, title: vibespaceTitle)]
            + sortedProjects.map {
                VibeSpaceShortcutTargetOption(scope: .project($0.path), title: $0.title)
            }
    }

    static func sanitizeRows(
        _ rows: [VibeSpaceShortcutPersistedRow],
        validProjectPaths: Set<String>
    ) -> [VibeSpaceShortcutPersistedRow] {
        rows.filter { row in
            switch row.target {
            case .vibespace:
                return true
            case let .project(path):
                return validProjectPaths.contains(path)
            }
        }
    }

    static func buildPersistencePlan(
        rows: [VibeSpaceShortcutPersistedRow],
        orderedProjectPaths: [String]
    ) -> VibeSpaceShortcutPersistencePlan {
        let validProjectPaths = Set(orderedProjectPaths)
        let sanitizedRows = sanitizeRows(rows, validProjectPaths: validProjectPaths)
        let vibespaceShortcuts = sanitizedRows
            .filter { $0.target == .vibespace }
            .map(\.definition)

        var projectShortcutsByPath: [String: [TerminalShortcutDefinition]] = [:]
        for projectPath in orderedProjectPaths {
            projectShortcutsByPath[projectPath] = sanitizedRows
                .compactMap { row in
                    guard case let .project(path) = row.target, path == projectPath else { return nil }
                    return row.definition
                }
        }

        return VibeSpaceShortcutPersistencePlan(
            vibespaceShortcuts: vibespaceShortcuts,
            projectShortcutsByPath: projectShortcutsByPath
        )
    }
}

enum StartupInputMode: String, CaseIterable, Identifiable {
    case none
    case preset
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .preset:
            return "Preset"
        case .command:
            return "Command"
        }
    }
}

enum TerminalShellSelectionContext {
    case appDefault
    case vibespaceDefault

    var inheritedTitle: String {
        switch self {
        case .appDefault:
            return "Use App Default"
        case .vibespaceDefault:
            return "Use VibeSpace Default"
        }
    }
}

enum ProjectStartupBehavior: String, CaseIterable, Identifiable {
    case inherited
    case override

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherited:
            return "Use VibeSpace Default"
        case .override:
            return "Custom Override"
        }
    }
}

enum TerminalShellSelection: String, CaseIterable, Identifiable {
    case inherited
    case zsh
    case bash

    var id: String { rawValue }

    func title(for context: TerminalShellSelectionContext) -> String {
        switch self {
        case .inherited:
            return context.inheritedTitle
        case .zsh:
            return "zsh"
        case .bash:
            return "bash"
        }
    }

    var shellPreference: TerminalShellPreference? {
        switch self {
        case .inherited:
            return nil
        case .zsh:
            return .zsh
        case .bash:
            return .bash
        }
    }

    init(shellPreference: TerminalShellPreference?) {
        switch shellPreference {
        case .zsh:
            self = .zsh
        case .bash:
            self = .bash
        case nil:
            self = .inherited
        }
    }
}

enum VibeSpaceSettingsCategory: String, CaseIterable, Identifiable {
    case vibespace
    case shortcuts
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibespace:
            return "VibeSpace Settings"
        case .projects:
            return "Projects"
        case .shortcuts:
            return AppStrings.VibeSpaceSettings.shortcutCommandsTitle
        }
    }

    var subtitle: String {
        switch self {
        case .vibespace:
            return "Startup defaults, naming, and maintenance"
        case .projects:
            return "Manage project order, colors, and overrides"
        case .shortcuts:
            return AppStrings.VibeSpaceSettings.shortcutCommandsSubtitle
        }
    }

    var iconSystemName: String {
        switch self {
        case .vibespace:
            return "slider.horizontal.3"
        case .projects:
            return "folder.badge.gearshape"
        case .shortcuts:
            return "terminal"
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
