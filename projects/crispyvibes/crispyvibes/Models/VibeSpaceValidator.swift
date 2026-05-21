import Foundation

/// Pure logic for enforcing vibespace invariants (INV-001 through INV-010).
/// No side effects, no persistence, no UI.
enum VibeSpaceValidator {

    static func validateVibeSpaceConfig(_ config: VibeSpaceConfigFile) -> VibeSpaceConfigFile {
        var c = config

        // INV-010: Name non-empty
        let trimmedName = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.name = trimmedName.isEmpty ? "Untitled VibeSpace" : trimmedName

        // INV-003: Normalize all paths
        c.projectPaths = c.projectPaths.map { normalizedPath($0) }
        c.unresolvedProjectPaths = c.unresolvedProjectPaths.map { normalizedPath($0) }
        if let fp = c.focusedProjectPath {
            let normalized = normalizedPath(fp)
            c.focusedProjectPath = c.projectPaths.contains(normalized) ? normalized : c.projectPaths.first
        }

        // INV-001: Clamp terminal count
        c.startupSettings = validateStartupSettings(c.startupSettings)
        c.sourceControlSettings = c.sourceControlSettings.normalized()

        return c
    }

    static func validateStartupSettings(_ settings: VibeSpaceStartupSettings) -> VibeSpaceStartupSettings {
        var s = settings

        // INV-001: Clamp to 1–8
        s.startupTerminalCount = max(1, min(s.startupTerminalCount, 8))

        // INV-002: Profile count matches terminal count
        while s.startupProfiles.count < s.startupTerminalCount {
            s.startupProfiles.append(.empty)
        }
        if s.startupProfiles.count > s.startupTerminalCount {
            s.startupProfiles = Array(s.startupProfiles.prefix(s.startupTerminalCount))
        }

        return s
    }

    static func validateProjectConfig(_ config: ProjectConfigFile, validProjectPaths: Set<String>) -> ProjectConfigFile {
        var c = config

        // INV-003: Normalize path
        c.projectPath = normalizedPath(c.projectPath)

        // INV-005: Shortcut in 1–9
        if let idx = c.shortcutIndex, !(1...9).contains(idx) {
            c.shortcutIndex = nil
        }

        return c
    }

    /// Ensures shortcut indices are unique across all project configs.
    /// Returns corrected configs with duplicates removed (first wins).
    static func deduplicateShortcuts(_ configs: [ProjectConfigFile]) -> [ProjectConfigFile] {
        var seen = Set<Int>()
        return configs.map { config in
            var c = config
            if let idx = c.shortcutIndex {
                if !seen.insert(idx).inserted {
                    c.shortcutIndex = nil
                }
            }
            return c
        }
    }

    static func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("ssh://") {
            return path
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
