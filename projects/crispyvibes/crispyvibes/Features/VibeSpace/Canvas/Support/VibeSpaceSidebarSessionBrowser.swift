import Foundation

private struct VibeSpaceSidebarRemoteConnectionGroup {
    let connection: SSHConnection
    var projects: [AnyProjectSession]
}

@MainActor
struct VibeSpaceSidebarSessionBrowser {
    func buildVibeSpaceGroups(
        for vibespaces: [VibeSpaceState],
        activeVibeSpaceID: UUID?
    ) async -> [VibeSpaceSidebarTmuxVibeSpaceGroup] {
        let orderedVibeSpaces = orderedVibeSpaces(from: vibespaces, activeVibeSpaceID: activeVibeSpaceID)
        var displayedSessionIDs = Set<String>()
        var groups: [VibeSpaceSidebarTmuxVibeSpaceGroup] = []

        for vibespace in orderedVibeSpaces {
            let includeAvailabilityMessages = vibespace.id == activeVibeSpaceID
            let sections = await buildSections(
                for: vibespace.projects,
                includeAvailabilityMessages: includeAvailabilityMessages
            )
            let filteredSections = deduplicatedSections(
                from: sections,
                displayedSessionIDs: &displayedSessionIDs,
                keepAvailabilityMessages: includeAvailabilityMessages
            )

            guard includeAvailabilityMessages || !filteredSections.isEmpty else { continue }
            groups.append(
                VibeSpaceSidebarTmuxVibeSpaceGroup(
                    id: vibespace.id,
                    title: vibespace.name,
                    isCurrentVibeSpace: vibespace.id == activeVibeSpaceID,
                    sections: filteredSections
                )
            )
        }

        return groups
    }

    private func buildSections(
        for projects: [AnyProjectSession],
        includeAvailabilityMessages: Bool
    ) async -> [VibeSpaceSidebarTmuxSessionSection] {
        let localProjects = projects.filter { $0.metadata.hostLabel == nil }
        let remoteProjects = projects.filter { $0.metadata.hostLabel != nil }

        let localSessions = await loadLocalSessions()
        let localAssignments = assignLocalSessions(localSessions, to: localProjects)

        var sections: [VibeSpaceSidebarTmuxSessionSection] = localProjects.compactMap { project in
            let sessions = localAssignments[project.id] ?? []
            guard includeAvailabilityMessages || !sessions.isEmpty else { return nil }
            return VibeSpaceSidebarTmuxSessionSection(
                id: "local|\(project.id.uuidString)",
                projectID: project.id,
                title: project.title,
                subtitle: project.metadata.displayPath,
                iconName: "macwindow",
                sessions: sessions,
                availability: localAvailabilityMessage(project: project, sessions: sessions)
            )
        }

        if let unmatchedLocalSessions = localAssignments[nil], !unmatchedLocalSessions.isEmpty {
            sections.append(
                VibeSpaceSidebarTmuxSessionSection(
                    id: "local|unmatched",
                    projectID: nil,
                    title: AppStrings.Sidebar.Sessions.otherLocalTitle,
                    subtitle: nil,
                    iconName: "macwindow",
                    sessions: unmatchedLocalSessions,
                    availability: .ready
                )
            )
        }

        for group in makeRemoteConnectionGroups(from: remoteProjects) {
            let remoteSessions = await loadRemoteSessions(for: group.connection)
            let assignments = assignRemoteSessions(
                remoteSessions,
                connection: group.connection,
                to: group.projects
            )

            for project in group.projects {
                let sessions = assignments[project.id] ?? []
                guard includeAvailabilityMessages || !sessions.isEmpty else { continue }
                sections.append(
                    VibeSpaceSidebarTmuxSessionSection(
                        id: "remote|\(project.id.uuidString)",
                        projectID: project.id,
                        title: project.title,
                        subtitle: project.metadata.hostLabel ?? project.metadata.displayPath,
                        iconName: "server.rack",
                        sessions: sessions,
                        availability: remoteAvailabilityMessage(
                            project: project,
                            connection: group.connection,
                            sessions: sessions
                        )
                    )
                )
            }

            if let unmatchedRemoteSessions = assignments[nil], !unmatchedRemoteSessions.isEmpty {
                sections.append(
                    VibeSpaceSidebarTmuxSessionSection(
                        id: "remote|\(group.connection.profile.id.uuidString)|unmatched",
                        projectID: nil,
                        title: AppStrings.Sidebar.Sessions.otherRemoteTitle(group.connection.profile.displayName),
                        subtitle: group.connection.profile.connectionString,
                        iconName: "server.rack",
                        sessions: unmatchedRemoteSessions,
                        availability: .ready
                    )
                )
            }
        }

        return sections
    }

    private func orderedVibeSpaces(
        from vibespaces: [VibeSpaceState],
        activeVibeSpaceID: UUID?
    ) -> [VibeSpaceState] {
        guard let activeVibeSpaceID else { return vibespaces }
        let active = vibespaces.filter { $0.id == activeVibeSpaceID }
        let others = vibespaces.filter { $0.id != activeVibeSpaceID }
        return active + others
    }

    private func deduplicatedSections(
        from sections: [VibeSpaceSidebarTmuxSessionSection],
        displayedSessionIDs: inout Set<String>,
        keepAvailabilityMessages: Bool
    ) -> [VibeSpaceSidebarTmuxSessionSection] {
        sections.compactMap { section in
            let visibleSessions = section.sessions.filter { session in
                displayedSessionIDs.insert(session.id).inserted
            }

            if !visibleSessions.isEmpty {
                return VibeSpaceSidebarTmuxSessionSection(
                    id: section.id,
                    projectID: section.projectID,
                    title: section.title,
                    subtitle: section.subtitle,
                    iconName: section.iconName,
                    sessions: visibleSessions,
                    availability: .ready
                )
            }

            guard keepAvailabilityMessages else { return nil }
            return VibeSpaceSidebarTmuxSessionSection(
                id: section.id,
                projectID: section.projectID,
                title: section.title,
                subtitle: section.subtitle,
                iconName: section.iconName,
                sessions: [],
                availability: section.availability
            )
        }
    }

    private func loadLocalSessions() async -> [TmuxService.SessionInfo] {
        guard TmuxService.isAvailable else { return [] }
        return await TmuxService.listSessionDetailsAsync()
    }

    private func assignLocalSessions(
        _ sessions: [TmuxService.SessionInfo],
        to projects: [AnyProjectSession]
    ) -> [UUID?: [VibeSpaceSidebarTmuxSession]] {
        Dictionary(grouping: sessions) { session in
            bestMatchingProject(
                forWorkingDirectory: session.workingDirectory,
                projects: projects
            )?.id
        }.mapValues { matches in
            matches.map { session in
                let owningProject = bestMatchingProject(
                    forWorkingDirectory: session.workingDirectory,
                    projects: projects
                )
                return VibeSpaceSidebarTmuxSession(
                    id: "local|\(session.name)|\(session.workingDirectory)",
                    source: .local,
                    launchContextProjectID: owningProject?.id ?? projects.first?.id,
                    owningProjectID: owningProject?.id,
                    connectionProfile: nil,
                    sessionName: session.name,
                    displayTitle: displayTitle(
                        for: session.name,
                        owningProject: owningProject
                    ),
                    workingDirectory: session.workingDirectory,
                    workingDirectoryURL: URL(fileURLWithPath: session.workingDirectory),
                    currentCommand: session.currentCommand,
                    lastActivity: session.lastActivity,
                    isAttached: session.isAttached
                )
            }
        }
    }

    private func makeRemoteConnectionGroups(
        from projects: [AnyProjectSession]
    ) -> [VibeSpaceSidebarRemoteConnectionGroup] {
        var grouped: [VibeSpaceSidebarRemoteConnectionGroup] = []
        var seen = Set<ObjectIdentifier>()

        for project in projects {
            guard let connection = project.sshConnection else { continue }
            let key = ObjectIdentifier(connection)
            if let existingIndex = grouped.firstIndex(where: { ObjectIdentifier($0.connection) == key }) {
                grouped[existingIndex].projects.append(project)
                continue
            }
            guard seen.insert(key).inserted else { continue }
            grouped.append(
                VibeSpaceSidebarRemoteConnectionGroup(
                    connection: connection,
                    projects: [project]
                )
            )
        }

        return grouped
    }

    private func loadRemoteSessions(for connection: SSHConnection) async -> [VibeSpaceSidebarTmuxSession] {
        guard connection.state == .connected else { return [] }

        do {
            let executor = RemoteCommandExecutor(connection: connection)
            let summary = try await executor.execute(
                tool: "tmux",
                arguments: ["list-sessions", "-F", "#{session_name}\t#{session_attached}"],
                stdinData: nil,
                timeout: 5
            )

            let summaryOutput = String(data: summary.stdoutData, encoding: .utf8) ?? ""
            let summaryError = String(data: summary.stderrData, encoding: .utf8) ?? ""
            let normalizedSummaryError = summaryError.lowercased()

            if summary.terminationStatus != 0 {
                if Self.tmuxNoServerMessages.contains(where: normalizedSummaryError.contains) {
                    connection.hasTmux = true
                    return []
                }

                if Self.tmuxUnavailableMessages.contains(where: normalizedSummaryError.contains) {
                    connection.hasTmux = false
                    return []
                }

                AppDiagnostics.record(
                    category: .terminalLifecycle,
                    level: .error,
                    event: "remote_tmux_list_failed",
                    metadata: [
                        "host": connection.profile.host,
                        "status": String(summary.terminationStatus),
                        "stderr": summaryError.trimmingCharacters(in: .whitespacesAndNewlines)
                    ]
                )
                return []
            }

            connection.hasTmux = true
            let fallbackSessions = Self.parseFallbackRemoteSessions(
                summaryOutput,
                profile: connection.profile
            )

            guard !fallbackSessions.isEmpty else { return [] }

            let detailed = await loadDetailedRemoteSessions(
                with: executor,
                connection: connection
            )
            return detailed.isEmpty ? fallbackSessions : detailed
        } catch {
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .error,
                event: "remote_tmux_probe_threw",
                metadata: [
                    "host": connection.profile.host,
                    "error": error.localizedDescription
                ]
            )
            return []
        }
    }

    private func loadDetailedRemoteSessions(
        with executor: RemoteCommandExecutor,
        connection: SSHConnection
    ) async -> [VibeSpaceSidebarTmuxSession] {
        do {
            async let sessionsResult = executor.execute(
                tool: "tmux",
                arguments: [
                    "list-sessions",
                    "-F",
                    "#{session_name}\t#{session_path}\t#{session_created}\t#{session_activity}\t#{session_attached}"
                ],
                stdinData: nil,
                timeout: 5
            )
            async let panesResult = executor.execute(
                tool: "tmux",
                arguments: [
                    "list-panes",
                    "-a",
                    "-F",
                    "#{session_name}\t#{pane_active}\t#{pane_current_command}"
                ],
                stdinData: nil,
                timeout: 5
            )

            let (sessions, panes) = try await (sessionsResult, panesResult)
            guard sessions.terminationStatus == 0 else { return [] }

            let sessionOutput = String(data: sessions.stdoutData, encoding: .utf8) ?? ""
            let paneOutput = String(data: panes.stdoutData, encoding: .utf8) ?? ""
            return Self.parseDetailedRemoteSessions(
                sessionOutput,
                paneCommands: parsePaneCommands(from: paneOutput),
                profile: connection.profile
            )
        } catch {
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .debug,
                event: "remote_tmux_detail_probe_failed",
                metadata: [
                    "host": connection.profile.host,
                    "error": error.localizedDescription
                ]
            )
            return []
        }
    }

    private func assignRemoteSessions(
        _ sessions: [VibeSpaceSidebarTmuxSession],
        connection: SSHConnection,
        to projects: [AnyProjectSession]
    ) -> [UUID?: [VibeSpaceSidebarTmuxSession]] {
        Dictionary(grouping: sessions) { session in
            bestMatchingProject(
                forWorkingDirectory: session.workingDirectory,
                projects: projects
            )?.id
        }.mapValues { matches in
            matches.map { session in
                let owningProject = bestMatchingProject(
                    forWorkingDirectory: session.workingDirectory,
                    projects: projects
                )
                let launchProject = owningProject ?? projects.first
                return VibeSpaceSidebarTmuxSession(
                    id: session.id,
                    source: .remote,
                    launchContextProjectID: launchProject?.id,
                    owningProjectID: owningProject?.id,
                    connectionProfile: session.connectionProfile ?? connection.profile,
                    sessionName: session.sessionName,
                    displayTitle: displayTitle(
                        for: session.sessionName,
                        owningProject: owningProject
                    ),
                    workingDirectory: session.workingDirectory,
                    workingDirectoryURL: session.workingDirectoryURL,
                    currentCommand: session.currentCommand,
                    lastActivity: session.lastActivity,
                    isAttached: session.isAttached
                )
            }
        }
    }

    private func localAvailabilityMessage(
        project: AnyProjectSession,
        sessions: [VibeSpaceSidebarTmuxSession]
    ) -> VibeSpaceSidebarTmuxSessionSection.Availability {
        if !sessions.isEmpty {
            return .ready
        }
        if !TmuxService.isAvailable {
            return .message(AppStrings.Sidebar.Sessions.localTmuxUnavailable)
        }
        if !TmuxService.isEnabled {
            return .message(AppStrings.Sidebar.Sessions.localEnableTmux)
        }
        return .message(AppStrings.Sidebar.Sessions.localNoSessions)
    }

    private func remoteAvailabilityMessage(
        project: AnyProjectSession,
        connection: SSHConnection,
        sessions: [VibeSpaceSidebarTmuxSession]
    ) -> VibeSpaceSidebarTmuxSessionSection.Availability {
        if !sessions.isEmpty {
            return .ready
        }

        switch connection.state {
        case .connecting:
            return .message(
                AppStrings.Sidebar.Sessions.remoteConnecting(project.metadata.hostLabel ?? project.title)
            )
        case .disconnected:
            return .message(AppStrings.Sidebar.Sessions.remoteReconnect)
        case .failed(let error):
            return .message(error)
        case .connected:
            if !connection.hasTmux {
                return .message(AppStrings.Sidebar.Sessions.remoteTmuxUnavailable)
            }
            return .message(AppStrings.Sidebar.Sessions.remoteNoSessions)
        }
    }

    private func bestMatchingProject(
        forWorkingDirectory workingDirectory: String,
        projects: [AnyProjectSession]
    ) -> AnyProjectSession? {
        projects
            .filter { project in
                path(workingDirectory, isWithin: project.rootURL.path)
            }
            .max { lhs, rhs in
                lhs.rootURL.path.count < rhs.rootURL.path.count
            }
    }

    private func path(_ path: String, isWithin rootPath: String) -> Bool {
        let normalizedPath = NSString(string: path).standardizingPath
        let normalizedRoot = NSString(string: rootPath).standardizingPath
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private func parsePaneCommands(from output: String) -> [String: String] {
        Self.parsePaneCommands(output)
    }

    private func parseFallbackRemoteSessions(
        from output: String,
        connection: SSHConnection
    ) -> [VibeSpaceSidebarTmuxSession] {
        Self.parseFallbackRemoteSessions(output, profile: connection.profile)
    }

    private func displayTitle(
        for sessionName: String,
        owningProject: AnyProjectSession?
    ) -> String {
        let matchingTabTitle = owningProject?.terminal.tabs.first(where: { tab in
            owningProject?.terminal.session(for: tab.id)?.tmuxSessionName == sessionName
        })?.title
        return Self.resolveDisplayTitle(
            sessionName: sessionName,
            owningProjectTitle: owningProject?.title,
            matchingTabTitle: matchingTabTitle
        )
    }

    static func parsePaneCommands(_ output: String) -> [String: String] {
        var commands: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { continue }
            let sessionName = parts[0]
            let isActive = parts[1] == "1"
            let command = parts[2]
            if commands[sessionName] == nil || isActive {
                commands[sessionName] = command
            }
        }
        return commands
    }

    static func parseFallbackRemoteSessions(
        _ output: String,
        profile: SSHConnectionProfile
    ) -> [VibeSpaceSidebarTmuxSession] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            let sessionName = parts[0]
            let isAttached = (Int(parts[1]) ?? 0) > 0
            return VibeSpaceSidebarTmuxSession(
                id: "remote|\(profile.id.uuidString)|\(sessionName)|fallback",
                source: .remote,
                launchContextProjectID: nil,
                owningProjectID: nil,
                connectionProfile: profile,
                sessionName: sessionName,
                displayTitle: sessionName,
                workingDirectory: "",
                workingDirectoryURL: URL(fileURLWithPath: "/"),
                currentCommand: "",
                lastActivity: .distantPast,
                isAttached: isAttached
            )
        }
    }

    static func parseDetailedRemoteSessions(
        _ output: String,
        paneCommands: [String: String],
        profile: SSHConnectionProfile
    ) -> [VibeSpaceSidebarTmuxSession] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { return nil }

            let sessionName = parts[0]
            let workingDirectory = parts[1]
            let created = TimeInterval(parts[2]) ?? 0
            let activity = TimeInterval(parts[3]) ?? created
            let isAttached = (Int(parts[4]) ?? 0) > 0

            return VibeSpaceSidebarTmuxSession(
                id: "remote|\(profile.id.uuidString)|\(sessionName)|\(workingDirectory)",
                source: .remote,
                launchContextProjectID: nil,
                owningProjectID: nil,
                connectionProfile: profile,
                sessionName: sessionName,
                displayTitle: sessionName,
                workingDirectory: workingDirectory,
                workingDirectoryURL: URL(fileURLWithPath: workingDirectory),
                currentCommand: paneCommands[sessionName] ?? "",
                lastActivity: Date(timeIntervalSince1970: activity),
                isAttached: isAttached
            )
        }
    }

    static func resolveDisplayTitle(
        sessionName: String,
        owningProjectTitle: String?,
        matchingTabTitle: String?
    ) -> String {
        if let matchingTabTitle, !matchingTabTitle.isEmpty {
            return matchingTabTitle
        }

        if sessionName.hasPrefix("crispyvibes-") {
            if let owningProjectTitle, !owningProjectTitle.isEmpty {
                return owningProjectTitle
            }
            return AppStrings.Sidebar.Sessions.projectTerminal
        }

        return sessionName
    }

    private static let tmuxNoServerMessages = [
        "failed to connect to server",
        "no server running"
    ]

    private static let tmuxUnavailableMessages = [
        "tmux: command not found",
        "not found",
        "unknown command: tmux"
    ]
}
