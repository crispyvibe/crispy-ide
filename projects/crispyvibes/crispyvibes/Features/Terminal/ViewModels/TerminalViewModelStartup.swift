import Foundation
import os.signpost

extension TerminalViewModel {
    func ensureTerminalCount(_ desiredCount: Int, defaultDirectory: URL) {
        let normalizedDefaultDirectory = defaultDirectory.standardizedFileURL
        let targetCount = Swift.max(
            VibeSpaceStartupSettings.minimumTerminalCount,
            Swift.min(desiredCount, VibeSpaceStartupSettings.maximumTerminalCount)
        )

        withStateUpdates {
            if tabs.isEmpty {
                createTab(directoryURL: normalizedDefaultDirectory)
            }

            while tabs.count < targetCount {
                createTab(directoryURL: normalizedDefaultDirectory)
            }
        }
    }

    func runStartupCommandOnPrimaryTab(
        _ command: String,
        customName: String? = nil,
        defaultDirectory: URL
    ) {
        runStartupCommandOnTab(
            command,
            customName: customName,
            tabIndex: 0,
            defaultDirectory: defaultDirectory,
            activateTab: true
        )
    }

    func runStartupCommandOnTab(
        _ command: String,
        customName: String? = nil,
        tabIndex: Int,
        origin: TerminalOrigin? = nil,
        defaultDirectory: URL,
        activateTab: Bool = true
    ) {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else { return }
        guard tabIndex >= 0 else { return }

        let normalizedDefaultDirectory = defaultDirectory.standardizedFileURL
        if tabs.isEmpty {
            createTab(directoryURL: normalizedDefaultDirectory)
        }

        while tabs.count <= tabIndex {
            createTab(directoryURL: normalizedDefaultDirectory)
        }

        guard tabs.indices.contains(tabIndex) else { return }
        let targetTabID = tabs[tabIndex].id
        guard let session = session(for: targetTabID) else { return }
        let previousActiveTabID = activeTabID

        withStateUpdates {
            if let customName {
                updateTab(tabID: targetTabID) { tab in
                    tab.customName = customName
                }
            }
            if let origin {
                updateTab(tabID: targetTabID) { tab in
                    tab.origin = origin
                }
            }

            if activateTab {
                activeTabID = targetTabID
            }
        }
        let isTmuxReattach = session.tmuxSessionName != nil
            && TmuxService.isEnabled
            && TmuxService.isAvailable
            && TmuxService.sessionExists(session.tmuxSessionName!)
        session.startIfNeeded()
        if !isTmuxReattach {
            session.sendStartupCommand(normalizedCommand)
        }
        if !activateTab {
            withStateUpdates {
                if let previousActiveTabID,
                   tabs.contains(where: { $0.id == previousActiveTabID }) {
                    activeTabID = previousActiveTabID
                } else if activeTabID == nil {
                    activeTabID = tabs.first?.id
                }
            }
        }
    }

    func ensureActiveTerminal(
        defaultDirectory: URL,
        transitionID: String? = nil,
        startIfCreated: Bool = true
    ) {
        pruneOrphanedSessionState()
        let correlationID = transitionID ?? UUID().uuidString
        let signpostID = OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        os_signpost(
            .begin,
            log: AppDiagnostics.terminalSignpostLog,
            name: "EnsureActiveTerminal",
            signpostID: signpostID,
            "transition=%{public}@ tabs=%{public}d active=%{public}@",
            correlationID,
            tabs.count,
            activeTabID?.uuidString ?? "none"
        )

        if tabs.isEmpty {
            createTab(directoryURL: defaultDirectory, startImmediately: startIfCreated)
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .notice,
                event: "terminal_ensure_active_created_default",
                metadata: [
                    "transition": correlationID,
                    "default_dir": AppDiagnostics.pathToken(defaultDirectory.path)
                ]
            )
            os_signpost(
                .end,
                log: AppDiagnostics.terminalSignpostLog,
                name: "EnsureActiveTerminal",
                signpostID: signpostID,
                "transition=%{public}@ result=%{public}@",
                correlationID,
                "created_default"
            )
            return
        }

        if let activeTabID,
           tabs.contains(where: { $0.id == activeTabID }) {
            if startIfCreated {
                session(for: activeTabID)?.startIfNeeded()
            }
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .debug,
                event: "terminal_ensure_active_kept_existing",
                metadata: [
                    "transition": correlationID,
                    "tab": activeTabID.uuidString
                ]
            )
            os_signpost(
                .end,
                log: AppDiagnostics.terminalSignpostLog,
                name: "EnsureActiveTerminal",
                signpostID: signpostID,
                "transition=%{public}@ result=%{public}@ tab=%{public}@",
                correlationID,
                "kept_existing",
                activeTabID.uuidString
            )
            return
        }

        let fallbackTabID = tabs[0].id
        withStateUpdates {
            activeTabID = fallbackTabID
        }
        if startIfCreated {
            session(for: fallbackTabID)?.startIfNeeded()
        }
        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .notice,
            event: "terminal_ensure_active_fallback",
            metadata: [
                "transition": correlationID,
                "tab": fallbackTabID.uuidString
            ]
        )
        os_signpost(
            .end,
            log: AppDiagnostics.terminalSignpostLog,
            name: "EnsureActiveTerminal",
            signpostID: signpostID,
            "transition=%{public}@ result=%{public}@ tab=%{public}@",
            correlationID,
            "fallback_first_tab",
            fallbackTabID.uuidString
        )
    }

    func restoreTabs(
        directories: [URL],
        activeDirectory: URL?,
        defaultDirectory: URL
    ) {
        terminateAllSessions()
        clearTabActivityStates()

        let normalizedDefault = defaultDirectory.standardizedFileURL
        var normalizedDirectories: [URL] = []
        var seenPaths = Set<String>()

        for directory in directories {
            let normalized = directory.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { continue }
            normalizedDirectories.append(normalized)
        }

        if normalizedDirectories.isEmpty {
            normalizedDirectories = [normalizedDefault]
        }

        withStateUpdates {
            tabs.removeAll()
            activeTabID = nil

            for directory in normalizedDirectories {
                createTab(directoryURL: directory, startImmediately: false)
            }

            var resolvedActiveTabID: UUID?
            if let activeDirectory {
                let normalizedActive = activeDirectory.standardizedFileURL.path
                if let matched = tabs.first(where: {
                    $0.workingDirectory.standardizedFileURL.path == normalizedActive
                }) {
                    resolvedActiveTabID = matched.id
                }
            }

            if resolvedActiveTabID == nil {
                resolvedActiveTabID = tabs.first?.id
            }

            activeTabID = resolvedActiveTabID
        }
        pruneOrphanedSessionState()
    }

    func restoreTabsFromEntries(
        _ entries: [TerminalSessionEntry],
        activeDirectory: URL?,
        activeIdentity: String?,
        defaultDirectory: URL
    ) {
        terminateAllSessions()
        clearTabActivityStates()

        let normalizedDefault = defaultDirectory.standardizedFileURL
        var seenEntries = Set<String>()
        var dedupedEntries: [TerminalSessionEntry] = []

        for entry in entries {
            let normalized = URL(fileURLWithPath: entry.workingDirectoryPath).standardizedFileURL.path
            let dedupeKey = entry.id.map(Self.persistenceIdentity(tabID:)) ?? Self.persistenceIdentity(
                workingDirectoryPath: normalized,
                customName: entry.customName,
                origin: entry.origin,
                tmuxSessionName: entry.tmuxSessionName
            )
            guard seenEntries.insert(dedupeKey).inserted else { continue }
            dedupedEntries.append(
                TerminalSessionEntry(
                    id: entry.id,
                    workingDirectoryPath: normalized,
                    customName: entry.customName,
                    origin: entry.origin,
                    tmuxSessionName: entry.tmuxSessionName
                )
            )
        }

        if dedupedEntries.isEmpty {
            dedupedEntries = [TerminalSessionEntry(
                workingDirectoryPath: normalizedDefault.path,
                customName: nil,
                origin: .adHoc
            )]
        }

        withStateUpdates {
            tabs.removeAll()
            activeTabID = nil

            for entry in dedupedEntries {
                let dir = URL(fileURLWithPath: entry.workingDirectoryPath).standardizedFileURL
                createTab(
                    id: entry.id ?? UUID(),
                    directoryURL: dir,
                    customName: entry.customName,
                    origin: entry.origin,
                    tmuxSessionName: entry.tmuxSessionName,
                    startImmediately: false
                )
            }

            var resolvedActiveTabID: UUID?
            if let activeIdentity {
                resolvedActiveTabID = tabs.first(where: { tab in
                    if Self.persistenceIdentity(tabID: tab.id) == activeIdentity {
                        return true
                    }
                    guard let session = sessions[tab.id] else { return false }
                    return Self.persistenceIdentity(
                        workingDirectoryPath: tab.workingDirectory.standardizedFileURL.path,
                        customName: tab.customName,
                        origin: tab.origin,
                        tmuxSessionName: session.tmuxSessionName
                    ) == activeIdentity
                })?.id
            }
            if resolvedActiveTabID == nil, let activeDirectory {
                let normalizedActive = activeDirectory.standardizedFileURL.path
                resolvedActiveTabID = tabs.first(where: {
                    $0.workingDirectory.standardizedFileURL.path == normalizedActive
                })?.id
            }
            activeTabID = resolvedActiveTabID ?? tabs.first?.id
        }
        pruneOrphanedSessionState()
    }

    private static func originPersistenceKey(_ origin: TerminalOrigin) -> String {
        switch origin {
        case .adHoc:
            return "adHoc"
        case let .acp(sessionID):
            return "acp:\(sessionID)"
        case let .preset(profileIndex, command):
            return "preset:\(profileIndex):\(command)"
        case let .agentCLI(callerTerminalID):
            return "agentCLI:\(callerTerminalID ?? "none")"
        }
    }

    static func persistenceIdentity(
        workingDirectoryPath: String,
        customName: String?,
        origin: TerminalOrigin,
        tmuxSessionName: String?
    ) -> String {
        [
            URL(fileURLWithPath: workingDirectoryPath).standardizedFileURL.path,
            customName ?? "",
            originPersistenceKey(origin),
            tmuxSessionName ?? ""
        ].joined(separator: "\u{1F}")
    }

    static func persistenceIdentity(tabID: UUID) -> String {
        "tab:\(tabID.uuidString)"
    }
}
