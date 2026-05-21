import Foundation
import os.signpost

enum TerminalTabMovePlacement: Equatable {
    case before
    case after
}

extension TerminalViewModel {
    func shutdown() {
        if TmuxService.isEnabled && TmuxService.sessionBehavior == .terminate {
            for session in sessions.values {
                if let tmuxName = session.tmuxSessionName {
                    TmuxService.killSessionAsync(tmuxName)
                }
            }
        }
        terminateAllSessions(skipTmuxCleanup: true)
        withStateUpdates {
            tabs.removeAll()
            activeTabID = nil
            errorMessage = nil
        }
        clearTabActivityStates()
    }

    func terminateAllSessions(skipTmuxCleanup: Bool = false) {
        let tabIDs = Array(sessions.keys)
        for tabID in tabIDs {
            removeSession(for: tabID, skipTmuxCleanup: skipTmuxCleanup)
        }
    }

    func pruneOrphanedSessionState() {
        let validTabIDs = Set(tabs.map(\.id))
        let orphanedSessionIDs = sessions.keys.filter { !validTabIDs.contains($0) }
        for tabID in orphanedSessionIDs {
            removeSession(for: tabID)
        }

        let orphanedActivityIDs = tabActivityStates.keys.filter { !validTabIDs.contains($0) }
        for tabID in orphanedActivityIDs {
            removeTabActivityState(for: tabID)
        }

        if let activeTabID, !validTabIDs.contains(activeTabID) {
            self.activeTabID = nil
        }
    }

    func restartPane() {
        let restartDirectory = activeTab?.workingDirectory ?? tabs.first?.workingDirectory
        Task { [weak self] in
            guard let self else { return }
            await self.worker.restart()
            self.workerStatus = .ready
        }

        shutdown()
        if let restartDirectory {
            createTab(directoryURL: restartDirectory)
        } else {
            errorMessage = "Select a project or terminal directory before restarting the pane."
        }
    }

    func restartTab(_ tabID: UUID, activateTab: Bool = true) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        let existingTab = tabs[tabIndex]
        let workingDirectory = existingTab.workingDirectory.standardizedFileURL
        let existingTmuxSessionName = sessions[tabID]?.tmuxSessionName
        let replacementTab = TerminalTab(
            id: tabID,
            workingDirectory: workingDirectory,
            customName: existingTab.customName,
            origin: existingTab.origin
        )

        removeSession(for: tabID)
        removeTabActivityState(for: tabID)

        withStateUpdates {
            tabs[tabIndex] = replacementTab
            if activeTabID == tabID || activateTab {
                activeTabID = tabID
            }
        }

        tabActivityStates[tabID] = TerminalTabActivityState(id: tabID)

        let shellResolutionProviderStore = shellResolutionProviderStore
        let session = TerminalSession(
            id: tabID,
            workingDirectory: workingDirectory,
            terminalServices: terminalServices,
            shellResolutionProvider: { [shellResolutionProviderStore] in
                shellResolutionProviderStore.resolve()
            }
        )
        session.operationMetricsStore = operationMetricsStore
        session.tmuxSessionName = existingTmuxSessionName
        sessionConfigurator?(session)
        wireSessionCallbacks(session, tabID: tabID)
        sessions[tabID] = session
        session.startIfNeeded()
        pruneOrphanedSessionState()
        refreshGitBranch(for: tabID, directoryURL: workingDirectory)

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: "terminal_tab_restarted",
            metadata: [
                "tab": tabID.uuidString,
                "dir": AppDiagnostics.pathToken(workingDirectory.path)
            ]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalTabRestarted",
            "tab=%{public}@",
            tabID.uuidString
        )
    }

    func openOrSelectTab(for directoryURL: URL) {
        let normalizedDirectory = directoryURL.standardizedFileURL
        if let existingIndex = tabs.firstIndex(where: {
            $0.workingDirectory.standardizedFileURL.path == normalizedDirectory.path
        }) {
            let tabID = tabs[existingIndex].id
            activeTabID = tabID
            session(for: tabID)?.startIfNeeded()
            refreshGitBranch(for: tabID, directoryURL: normalizedDirectory)
            return
        }
        createTab(directoryURL: normalizedDirectory)
    }

    func createTab(
        directoryURL: URL? = nil,
        customName: String? = nil,
        origin: TerminalOrigin = .adHoc,
        tmuxSessionName: String? = nil,
        startImmediately: Bool = true
    ) {
        createTab(
            id: UUID(),
            directoryURL: directoryURL,
            customName: customName,
            origin: origin,
            tmuxSessionName: tmuxSessionName,
            startImmediately: startImmediately
        )
    }

    func createTab(
        id tabID: UUID,
        directoryURL: URL? = nil,
        customName: String? = nil,
        origin: TerminalOrigin = .adHoc,
        tmuxSessionName: String? = nil,
        startImmediately: Bool = true
    ) {
        let workingDirectory: URL
        if let directoryURL {
            workingDirectory = directoryURL.standardizedFileURL
        } else if let fallbackDirectory = activeTab?.workingDirectory ?? tabs.first?.workingDirectory {
            workingDirectory = fallbackDirectory.standardizedFileURL
        } else {
            errorMessage = "Select a project or terminal directory before creating a tab."
            return
        }
        let tab = TerminalTab(id: tabID, workingDirectory: workingDirectory, customName: customName, origin: origin)
        withStateUpdates {
            tabs.append(tab)
            activeTabID = tabID
        }
        tabActivityStates[tabID] = TerminalTabActivityState(id: tabID)

        let shellResolutionProviderStore = shellResolutionProviderStore
        let session = TerminalSession(
            id: tabID,
            workingDirectory: workingDirectory,
            terminalServices: terminalServices,
            shellResolutionProvider: { [shellResolutionProviderStore] in
                shellResolutionProviderStore.resolve()
            }
        )
        session.operationMetricsStore = operationMetricsStore
        session.tmuxSessionName = tmuxSessionName
        sessionConfigurator?(session)
        if session.tmuxSessionName == nil, TmuxService.isEnabled {
            session.tmuxSessionName = TmuxService.generateSessionName()
        }
        wireSessionCallbacks(session, tabID: tabID)
        sessions[tabID] = session
        if startImmediately {
            session.startIfNeeded()
        }
        pruneOrphanedSessionState()
        refreshGitBranch(for: tabID, directoryURL: workingDirectory)

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: "terminal_tab_created",
            metadata: [
                "tab": tabID.uuidString,
                "dir": AppDiagnostics.pathToken(workingDirectory.path),
                "custom_name": customName ?? "none",
                "started": startImmediately ? "yes" : "no"
            ]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalTabCreated",
            "tab=%{public}@ custom=%{public}@",
            tabID.uuidString,
            customName ?? "none"
        )
    }

    @discardableResult
    func createUserTab(defaultDirectory: URL) -> UUID? {
        let normalizedDefaultDirectory = defaultDirectory.standardizedFileURL
        let workingDirectory = activeTab?.workingDirectory ?? normalizedDefaultDirectory
        createTab(directoryURL: workingDirectory, startImmediately: true)
        return activeTabID
    }

    func closeTab(_ tab: TerminalTab) {
        removeSession(for: tab.id)

        removeTabActivityState(for: tab.id)

        withStateUpdates {
            tabs.removeAll(where: { $0.id == tab.id })
            if activeTabID == tab.id {
                activeTabID = tabs.last?.id
            }
        }
        pruneOrphanedSessionState()
        let nextActiveID = activeTabID?.uuidString ?? "none"

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: "terminal_tab_closed",
            metadata: [
                "tab": tab.id.uuidString,
                "next_active": nextActiveID
            ]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalTabClosed",
            "tab=%{public}@ next=%{public}@",
            tab.id.uuidString,
            nextActiveID
        )
    }

    func selectTab(_ tab: TerminalTab) {
        activeTabID = tab.id
        session(for: tab.id)?.startIfNeeded()

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .debug,
            event: "terminal_tab_selected",
            metadata: ["tab": tab.id.uuidString]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalTabSelected",
            "tab=%{public}@",
            tab.id.uuidString
        )
    }

    @discardableResult
    func moveTab(_ tabID: UUID, relativeTo targetTabID: UUID, placement: TerminalTabMovePlacement) -> Bool {
        guard tabID != targetTabID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == tabID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetTabID }) else {
            return false
        }

        var didChange = false
        withStateUpdates {
            var reorderedTabs = tabs
            let movedTab = reorderedTabs.remove(at: sourceIndex)
            let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            let insertionIndex = switch placement {
            case .before:
                adjustedTargetIndex
            case .after:
                adjustedTargetIndex + 1
            }
            reorderedTabs.insert(movedTab, at: max(0, min(insertionIndex, reorderedTabs.count)))
            didChange = reorderedTabs.map(\.id) != tabs.map(\.id)
            tabs = reorderedTabs
        }

        if didChange {
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .debug,
                event: "terminal_tab_reordered",
                metadata: [
                    "tab": tabID.uuidString,
                    "target": targetTabID.uuidString,
                    "placement": placement == .before ? "before" : "after"
                ]
            )
        }
        return true
    }

    func session(for tabID: UUID) -> TerminalSession? {
        sessions[tabID]
    }

    func copy(tabID: UUID) {
        session(for: tabID)?.copySelection()
    }

    func paste(tabID: UUID) {
        session(for: tabID)?.pasteFromClipboard()
    }

    func copyActiveTab() {
        guard let activeTabID else { return }
        copy(tabID: activeTabID)
    }

    func pasteActiveTab() {
        guard let activeTabID else { return }
        paste(tabID: activeTabID)
    }

    func focusActiveTerminal() {
        guard let activeTabID,
              let session = session(for: activeTabID) else {
            return
        }
        session.startIfNeeded()
        session.requestKeyboardFocus()
    }

    func wireSessionCallbacks(_ session: TerminalSession, tabID: UUID) {
        session.onTitleChanged = { [weak self] title in
            self?.updateTab(tabID: tabID) { tab in
                tab.sessionTitle = title
            }
        }

        session.onDirectoryChanged = { [weak self] directory in
            guard let directory else { return }
            self?.updateTab(tabID: tabID) { tab in
                tab.workingDirectory = directory
            }
            self?.refreshGitBranch(for: tabID, directoryURL: directory)
        }

        session.onProcessTerminated = { [weak self] exitCode in
            self?.updateTab(tabID: tabID) { tab in
                tab.exitCode = exitCode
            }
        }

        session.onActivityChanged = { [weak self] isActive in
            self?.setTabActivity(tabID: tabID, isActive: isActive)
        }
    }

    func updateTab(tabID: UUID, mutate: (inout TerminalTab) -> Void) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var updated = tabs[tabIndex]
        mutate(&updated)
        tabs[tabIndex] = updated
    }

    func renameTab(_ tabID: UUID, to name: String) {
        withStateUpdates {
            updateTab(tabID: tabID) { tab in
                tab.customName = name.isEmpty ? nil : name
            }
        }
    }

    func setTabActivity(tabID: UUID, isActive: Bool) {
        guard let state = tabActivityStates[tabID] else { return }
        guard state.update(isActive: isActive) else { return }
        activeTabActivityCount += isActive ? 1 : -1
        activeTabActivityCount = max(0, activeTabActivityCount)
        tabActivitySummary.update(hasAnyActivity: activeTabActivityCount > 0)
    }

    func removeTabActivityState(for tabID: UUID) {
        guard let removedState = tabActivityStates.removeValue(forKey: tabID) else { return }
        if removedState.isActive {
            activeTabActivityCount = max(0, activeTabActivityCount - 1)
            tabActivitySummary.update(hasAnyActivity: activeTabActivityCount > 0)
        }
    }

    func clearTabActivityStates() {
        tabActivityStates.removeAll()
        activeTabActivityCount = 0
        tabActivitySummary.update(hasAnyActivity: false)
    }

    private func removeSession(for tabID: UUID, skipTmuxCleanup: Bool = false) {
        teardownGitHeadWatcher(for: tabID)
        guard let session = sessions.removeValue(forKey: tabID) else { return }
        if !skipTmuxCleanup, let tmuxName = session.tmuxSessionName, TmuxService.tabCloseBehavior == .terminate {
            TmuxService.killSessionAsync(tmuxName)
        }
        session.processLaunchOverride = nil
        session.onTitleChanged = nil
        session.onDirectoryChanged = nil
        session.onProcessTerminated = nil
        session.onActivityChanged = nil
        session.terminate()
    }

    private func refreshGitBranch(for tabID: UUID, directoryURL: URL) {
        let normalizedDirectory = directoryURL.standardizedFileURL
        Task { [weak self] in
            guard let self else { return }
            let branchName = try? await worker.execute(
                .gitCurrentBranch,
                arguments: ["rootPath": normalizedDirectory.path],
                timeout: 4
            )
            guard !Task.isCancelled else { return }
            let normalizedBranchName = branchName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            updateTab(tabID: tabID) { tab in
                guard tab.workingDirectory.standardizedFileURL.path == normalizedDirectory.path else {
                    return
                }
                if let normalizedBranchName, !normalizedBranchName.isEmpty {
                    tab.gitBranchName = normalizedBranchName
                } else {
                    tab.gitBranchName = nil
                }
            }
            updateGitHeadWatcher(for: tabID, directoryURL: normalizedDirectory)
        }
    }

    // MARK: - .git/HEAD file watcher

    private static var gitHeadWatchersByTab: [UUID: GitHeadWatcher] = [:]

    private func updateGitHeadWatcher(for tabID: UUID, directoryURL: URL) {
        let gitHeadURL = Self.resolveGitHeadURL(for: directoryURL)
        let existingWatcher = Self.gitHeadWatchersByTab[tabID]

        if let gitHeadURL {
            if existingWatcher?.watchedPath == gitHeadURL.path { return }
            existingWatcher?.invalidate()
            let watcher = GitHeadWatcher(path: gitHeadURL.path) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          let tab = self.tabs.first(where: { $0.id == tabID }) else { return }
                    self.refreshGitBranch(for: tabID, directoryURL: tab.workingDirectory)
                }
            }
            Self.gitHeadWatchersByTab[tabID] = watcher
        } else {
            existingWatcher?.invalidate()
            Self.gitHeadWatchersByTab.removeValue(forKey: tabID)
        }
    }

    func teardownGitHeadWatcher(for tabID: UUID) {
        Self.gitHeadWatchersByTab.removeValue(forKey: tabID)?.invalidate()
    }

    private static func resolveGitHeadURL(for directoryURL: URL) -> URL? {
        var current = directoryURL.standardizedFileURL
        let root = URL(fileURLWithPath: "/")
        while current.path != root.path {
            let gitHead = current.appendingPathComponent(".git/HEAD")
            if FileManager.default.fileExists(atPath: gitHead.path) {
                return gitHead
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }
}
