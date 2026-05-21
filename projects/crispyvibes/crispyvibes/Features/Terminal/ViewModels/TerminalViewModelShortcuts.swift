import Foundation

extension TerminalViewModel {
    @discardableResult
    func addShortcut(
        name: String,
        command: String,
        launchBehavior: TerminalShortcutLaunchBehavior = .currentTerminal
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else {
            return false
        }
        var updated = shortcutCommands
        updated.append(
            TerminalShortcutDefinition(
                name: trimmedName,
                command: trimmedCommand,
                launchBehavior: launchBehavior
            )
        )
        shortcutStore.save(updated)
        shortcutCommands = shortcutStore.load()
        return true
    }

    func removeShortcut(id: UUID) {
        shortcutStore.save(shortcutCommands.filter { $0.id != id })
        shortcutCommands = shortcutStore.load()
    }

    func runShortcut(_ shortcut: TerminalShortcutDefinition, defaultDirectory: URL) {
        let command = shortcut.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        switch shortcut.launchBehavior {
        case .currentTerminal, .newTemporaryTerminal:
            if tabs.isEmpty {
                createTab(directoryURL: defaultDirectory, startImmediately: true)
            } else if let activeTabID {
                session(for: activeTabID)?.startIfNeeded()
            }
        case .newPermanentTerminal:
            createTab(
                directoryURL: defaultDirectory,
                customName: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                startImmediately: true
            )
        }

        focusActiveTerminal()
        if let activeTabID, let session = session(for: activeTabID) {
            session.sendStartupCommand(command)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
