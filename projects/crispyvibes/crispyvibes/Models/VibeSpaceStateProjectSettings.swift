import Foundation

@MainActor
extension VibeSpaceState {
    func colorTag(for project: AnyProjectSession) -> ProjectColorTag? {
        projectColorTagsByPath[project.projectIdentifier]
    }

    func colorTag(for projectPath: String) -> ProjectColorTag? {
        projectColorTagsByPath[Self.normalizedPath(from: projectPath)]
    }

    mutating func setColorTag(_ tag: ProjectColorTag?, for projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        if let tag {
            projectColorTagsByPath[project.projectIdentifier] = tag
        } else {
            projectColorTagsByPath.removeValue(forKey: project.projectIdentifier)
        }
    }

    mutating func setColorTag(_ tag: ProjectColorTag?, forProjectPath projectPath: String) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        guard projects.contains(where: { $0.projectIdentifier == normalizedPath }) ||
                unresolvedProjectPaths.contains(normalizedPath) else { return }
        if let tag {
            projectColorTagsByPath[normalizedPath] = tag
        } else {
            projectColorTagsByPath.removeValue(forKey: normalizedPath)
        }
    }

    func startupOverride(for project: AnyProjectSession) -> VibeSpaceProjectStartupOverride? {
        projectStartupOverridesByPath[project.projectIdentifier]
    }

    func startupOverride(for projectPath: String) -> VibeSpaceProjectStartupOverride? {
        projectStartupOverridesByPath[Self.normalizedPath(from: projectPath)]
    }

    mutating func setStartupOverride(_ startupOverride: VibeSpaceProjectStartupOverride?, for projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        setStartupOverride(startupOverride, forProjectPath: project.projectIdentifier)
    }

    mutating func setStartupOverride(_ startupOverride: VibeSpaceProjectStartupOverride?, forProjectPath projectPath: String) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        if let startupOverride {
            projectStartupOverridesByPath[normalizedPath] = startupOverride.normalized()
        } else {
            projectStartupOverridesByPath.removeValue(forKey: normalizedPath)
        }
    }

    func terminalShellOverride(for project: AnyProjectSession) -> TerminalShellPreference? {
        projectTerminalShellOverridesByPath[project.projectIdentifier]
    }

    func terminalShellOverride(for projectPath: String) -> TerminalShellPreference? {
        projectTerminalShellOverridesByPath[Self.normalizedPath(from: projectPath)]
    }

    func acpAgentOverrideID(for projectPath: String) -> String? {
        projectACPAgentOverrideIDsByPath[Self.normalizedPath(from: projectPath)]
    }

    func acpAgentOverrideID(for project: AnyProjectSession) -> String? {
        projectACPAgentOverrideIDsByPath[project.projectIdentifier]
    }

    func projectScopedShortcuts(forProjectPath projectPath: String) -> [TerminalShortcutDefinition] {
        projectScopedShortcutsByPath[Self.normalizedPath(from: projectPath)] ?? []
    }

    mutating func setProjectScopedShortcuts(
        _ shortcuts: [TerminalShortcutDefinition],
        forProjectPath projectPath: String
    ) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        if shortcuts.isEmpty {
            projectScopedShortcutsByPath.removeValue(forKey: normalizedPath)
        } else {
            projectScopedShortcutsByPath[normalizedPath] = shortcuts
        }
    }

    mutating func setACPAgentOverrideID(_ agentID: String?, forProjectPath projectPath: String) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        let trimmed = agentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            projectACPAgentOverrideIDsByPath[normalizedPath] = trimmed
        } else {
            projectACPAgentOverrideIDsByPath.removeValue(forKey: normalizedPath)
        }
    }

    mutating func setTerminalShellOverride(
        _ shellPreference: TerminalShellPreference?,
        for projectID: UUID
    ) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        setTerminalShellOverride(shellPreference, forProjectPath: project.projectIdentifier)
    }

    mutating func setTerminalShellOverride(
        _ shellPreference: TerminalShellPreference?,
        forProjectPath projectPath: String
    ) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        if let shellPreference {
            projectTerminalShellOverridesByPath[normalizedPath] = shellPreference
        } else {
            projectTerminalShellOverridesByPath.removeValue(forKey: normalizedPath)
        }
    }

    func effectiveTerminalShell(
        for projectPath: String,
        appDefault: TerminalShellPreference
    ) -> TerminalShellPreference {
        if let defaultTerminalShell {
            return defaultTerminalShell
        }
        return appDefault
    }

    func shortcutIndex(for projectPath: String) -> Int? {
        projectShortcutByPath[Self.normalizedPath(from: projectPath)]
    }

    func shortcutIndex(for project: AnyProjectSession) -> Int? {
        projectShortcutByPath[project.projectIdentifier]
    }

    func project(forShortcut index: Int) -> AnyProjectSession? {
        guard (1...9).contains(index) else { return nil }
        guard let mappedPath = projectShortcutByPath.first(where: { $0.value == index })?.key else {
            return nil
        }
        return projects.first(where: { $0.projectIdentifier == mappedPath })
    }

    mutating func setShortcut(_ shortcut: Int?, forProjectPath projectPath: String) {
        let normalizedPath = Self.normalizedPath(from: projectPath)
        guard projects.contains(where: { $0.projectIdentifier == normalizedPath }) else { return }

        if let shortcut {
            guard (1...9).contains(shortcut) else { return }
            if let existingPath = projectShortcutByPath.first(where: { $0.value == shortcut })?.key {
                projectShortcutByPath.removeValue(forKey: existingPath)
            }
            projectShortcutByPath[normalizedPath] = shortcut
        } else {
            projectShortcutByPath.removeValue(forKey: normalizedPath)
        }

        normalizeProjectShortcuts()
    }
}
