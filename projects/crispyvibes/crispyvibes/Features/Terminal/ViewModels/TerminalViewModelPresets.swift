import Foundation

extension TerminalViewModel {
    func launchPreset(
        _ preset: TerminalPresetDefinition,
        mode: TerminalPresetLaunchMode,
        directoryURL: URL? = nil
    ) {
        if mode == .fullTrust, !preset.supportsFullTrust {
            errorMessage = "\(preset.title) does not define a full-trust launch mode."
            return
        }

        guard let launchDirectory = (directoryURL ?? activeTab?.workingDirectory ?? tabs.first?.workingDirectory)?
            .standardizedFileURL else {
            errorMessage = "Select a project or terminal directory before launching \(preset.title)."
            return
        }
        let command = preset.command(for: mode)

        // The preset command is dispatched into the user's interactive shell inside
        // the terminal. The shell — not the GUI app — is responsible for resolving
        // the executable against PATH. The GUI's PATH is the launchd-inherited one
        // (no .zshrc / .bash_profile sourced), which misses tools installed through
        // version managers (Volta, Bun, npm-prefix, asdf, mise, nvm, fnm, pnpm,
        // cargo, etc.). Doing a preflight existence check here would surface a
        // false "not available on PATH" error for those installs even when the
        // command runs fine in the terminal.
        errorMessage = nil
        createTab(directoryURL: launchDirectory, customName: preset.shortLabel)

        guard let activeTabID,
              let session = session(for: activeTabID) else {
            return
        }

        session.requestKeyboardFocus()
        session.sendUICommand(command)
    }

    func executableName(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    func resolvedLaunchCommand(for command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let executableName = executableName(from: trimmed),
              let executablePath = resolvedExecutablePath(named: executableName) else {
            return nil
        }

        let suffix = String(trimmed.dropFirst(executableName.count))
        return "\(shellEscapeIfNeeded(executablePath))\(suffix)"
    }

    func resolvedExecutablePath(named executableName: String) -> String? {
        if executableName.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executableName)
                ? executableName
                : nil
        }

        let searchPaths = CommandPathResolver.searchPaths()

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path)
                .appendingPathComponent(executableName)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func shellEscapeIfNeeded(_ value: String) -> String {
        guard value.contains(" ") || value.contains("'") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
