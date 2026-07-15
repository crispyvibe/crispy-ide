import Foundation
import XCTest
@testable import CrispyVibes

/// F060 test double: container construction needs a triage runner; tests here
/// never trigger triage, so it just returns nil.
@MainActor
private final class NoopTriageRunner: TodoTriageRunning {
    func runTriage(prompt: String, projectPath: String) async -> String? { nil }
}

@MainActor
final class RemoteProjectSessionTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!
    private var vibespaceManagement: VibeSpaceManagementService!
    private let vibespaceID = UUID()

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-remote-project-session")
        container = makeContainer(appDirectoryURL: tempRoot)
        vibespaceManagement = container.vibespaceManagement
    }

    override func tearDownWithError() throws {
        container = nil
        vibespaceManagement = nil
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testInitRestoresPersistedRemoteTerminalEntriesFromRemoteIdentifier() throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let remoteIdentifier = "\(profile.sshURI)\(remotePath)"
        let restoredEntries = [
            TerminalSessionEntry(
                workingDirectoryPath: remotePath,
                customName: "Main",
                origin: .adHoc,
                tmuxSessionName: "restore-main"
            ),
            TerminalSessionEntry(
                workingDirectoryPath: "\(remotePath)/logs",
                customName: "Logs",
                origin: .preset(profileIndex: 0, command: "tail -f logs"),
                tmuxSessionName: "restore-logs"
            )
        ]
        vibespaceManagement.saveProjectSession(
            entries: restoredEntries,
            activeDirectory: "\(remotePath)/logs",
            activeIdentity: TerminalViewModel.persistenceIdentity(
                workingDirectoryPath: "\(remotePath)/logs",
                customName: "Logs",
                origin: .preset(profileIndex: 0, command: "tail -f logs"),
                tmuxSessionName: "restore-logs"
            ),
            forProject: remoteIdentifier,
            in: vibespaceID
        )

        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        XCTAssertEqual(session.metadata.identifier, remoteIdentifier)
        XCTAssertEqual(terminal.tabs.count, 2)
        XCTAssertEqual(terminal.tabs.map(\.customName), ["Main", "Logs"])
        XCTAssertEqual(
            terminal.activeTab?.workingDirectory.standardizedFileURL.path,
            "\(remotePath)/logs"
        )
        XCTAssertEqual(
            terminal.tabs.compactMap { terminal.session(for: $0.id)?.tmuxSessionName },
            ["restore-main", "restore-logs"]
        )
    }

    func testInitRestoresMultipleRemoteTerminalEntriesForSameDirectoryWhenTmuxSessionsDiffer() throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let remoteIdentifier = "\(profile.sshURI)\(remotePath)"
        let restoredEntries = [
            TerminalSessionEntry(
                workingDirectoryPath: remotePath,
                customName: "Main",
                origin: .adHoc,
                tmuxSessionName: "restore-main"
            ),
            TerminalSessionEntry(
                workingDirectoryPath: remotePath,
                customName: "Logs",
                origin: .adHoc,
                tmuxSessionName: "restore-logs"
            )
        ]
        vibespaceManagement.saveProjectSession(
            entries: restoredEntries,
            activeDirectory: remotePath,
            activeIdentity: TerminalViewModel.persistenceIdentity(
                workingDirectoryPath: remotePath,
                customName: "Logs",
                origin: .adHoc,
                tmuxSessionName: "restore-logs"
            ),
            forProject: remoteIdentifier,
            in: vibespaceID
        )

        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        XCTAssertEqual(terminal.tabs.count, 2)
        XCTAssertEqual(terminal.tabs.map(\.customName), ["Main", "Logs"])
        XCTAssertEqual(terminal.activeTab?.customName, "Logs")
        XCTAssertEqual(
            terminal.tabs.compactMap { terminal.session(for: $0.id)?.tmuxSessionName },
            ["restore-main", "restore-logs"]
        )
    }

    func testInitPrefersRemoteIdentifierPersistenceOverPlainRemotePath() throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let remoteIdentifier = "\(profile.sshURI)\(remotePath)"

        vibespaceManagement.saveProjectSession(
            entries: [
                TerminalSessionEntry(
                    workingDirectoryPath: remotePath,
                    customName: "Wrong",
                    origin: .adHoc,
                    tmuxSessionName: "wrong-session"
                )
            ],
            activeDirectory: remotePath,
            activeIdentity: "wrong-active",
            forProject: remotePath,
            in: vibespaceID
        )
        vibespaceManagement.saveProjectSession(
            entries: [
                TerminalSessionEntry(
                    workingDirectoryPath: "\(remotePath)/correct",
                    customName: "Correct",
                    origin: .adHoc,
                    tmuxSessionName: "correct-session"
                )
            ],
            activeDirectory: "\(remotePath)/correct",
            activeIdentity: "correct-active",
            forProject: remoteIdentifier,
            in: vibespaceID
        )

        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        XCTAssertEqual(terminal.tabs.count, 1)
        XCTAssertEqual(terminal.tabs.first?.customName, "Correct")
        XCTAssertEqual(
            terminal.tabs.first?.workingDirectory.standardizedFileURL.path,
            "\(remotePath)/correct"
        )
        XCTAssertEqual(
            terminal.tabs.first.flatMap { terminal.session(for: $0.id)?.tmuxSessionName },
            "correct-session"
        )
    }

    func testInitFallsBackToLegacyNormalizedRemoteIdentifierPersistence() throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let remoteIdentifier = "\(profile.sshURI)\(remotePath)"
        let legacyIdentifier = URL(fileURLWithPath: remoteIdentifier).standardizedFileURL.path

        vibespaceManagement.saveProjectSession(
            entries: [
                TerminalSessionEntry(
                    workingDirectoryPath: remotePath,
                    customName: "Legacy",
                    origin: .adHoc,
                    tmuxSessionName: "legacy-session"
                )
            ],
            activeDirectory: remotePath,
            activeIdentity: TerminalViewModel.persistenceIdentity(
                workingDirectoryPath: remotePath,
                customName: "Legacy",
                origin: .adHoc,
                tmuxSessionName: "legacy-session"
            ),
            forProject: legacyIdentifier,
            in: vibespaceID
        )

        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        XCTAssertEqual(terminal.tabs.count, 1)
        XCTAssertEqual(terminal.tabs.first?.customName, "Legacy")
        XCTAssertEqual(
            terminal.tabs.first.flatMap { terminal.session(for: $0.id)?.tmuxSessionName },
            "legacy-session"
        )
    }

    func testAppContainerRemoteIdentifierSessionRestoresVibeSpaceBoundRemoteStateForMultipleProjects() throws {
        let firstProfile = makeProfile()
        let secondProfile = SSHConnectionProfile(
            id: UUID(),
            displayName: "Analytics Box",
            host: "analytics.example.com",
            port: 22,
            user: "testuser",
            authMethod: .agent,
            importedFromConfig: false
        )
        let firstPath = "/srv/app"
        let secondPath = "/srv/analytics"
        let firstIdentifier = "\(firstProfile.sshURI)\(firstPath)"
        let secondIdentifier = "\(secondProfile.sshURI)\(secondPath)"

        vibespaceManagement.saveProjectSession(
            entries: [
                TerminalSessionEntry(
                    workingDirectoryPath: firstPath,
                    customName: "App",
                    origin: .adHoc,
                    tmuxSessionName: "restore-app"
                )
            ],
            activeDirectory: firstPath,
            activeIdentity: TerminalViewModel.persistenceIdentity(
                workingDirectoryPath: firstPath,
                customName: "App",
                origin: .adHoc,
                tmuxSessionName: "restore-app"
            ),
            forProject: firstIdentifier,
            in: vibespaceID
        )
        vibespaceManagement.saveProjectSession(
            entries: [
                TerminalSessionEntry(
                    workingDirectoryPath: secondPath,
                    customName: "Analytics",
                    origin: .adHoc,
                    tmuxSessionName: "restore-analytics"
                )
            ],
            activeDirectory: secondPath,
            activeIdentity: TerminalViewModel.persistenceIdentity(
                workingDirectoryPath: secondPath,
                customName: "Analytics",
                origin: .adHoc,
                tmuxSessionName: "restore-analytics"
            ),
            forProject: secondIdentifier,
            in: vibespaceID
        )

        let firstProject = container.makeProjectSessionFromIdentifier(firstIdentifier, vibespaceID: vibespaceID)
        let secondProject = container.makeProjectSessionFromIdentifier(secondIdentifier, vibespaceID: vibespaceID)
        let firstRemote = try XCTUnwrap(firstProject._wrapped as? RemoteProjectSession)
        let secondRemote = try XCTUnwrap(secondProject._wrapped as? RemoteProjectSession)
        let firstTerminal = try XCTUnwrap(firstRemote.terminal as? TerminalViewModel)
        let secondTerminal = try XCTUnwrap(secondRemote.terminal as? TerminalViewModel)

        XCTAssertEqual(firstTerminal.tabs.count, 1)
        XCTAssertEqual(firstTerminal.tabs.first?.customName, "App")
        XCTAssertEqual(
            firstTerminal.tabs.first.flatMap { firstTerminal.session(for: $0.id)?.tmuxSessionName },
            "restore-app"
        )

        XCTAssertEqual(secondTerminal.tabs.count, 1)
        XCTAssertEqual(secondTerminal.tabs.first?.customName, "Analytics")
        XCTAssertEqual(
            secondTerminal.tabs.first.flatMap { secondTerminal.session(for: $0.id)?.tmuxSessionName },
            "restore-analytics"
        )
    }

    func testAdditionalRemoteTerminalPersistsDistinctTmuxSessionName() async throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let stableTmuxName = "crispyvibes-\(RemoteProjectSession.stableHash("\(profile.sshURI)\(remotePath)"))"
        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)
        let workerDirectory = URL(fileURLWithPath: "\(remotePath)/worker")

        terminal.createTab(directoryURL: workerDirectory, customName: "Worker", startImmediately: false)
        let liveTab = try XCTUnwrap(terminal.activeTab)
        let liveTmuxName = try XCTUnwrap(terminal.session(for: liveTab.id)?.tmuxSessionName)
        XCTAssertTrue(liveTmuxName.hasPrefix("crispyvibes-"))
        XCTAssertNotEqual(liveTmuxName, stableTmuxName)

        let persisted = await waitForCondition(timeout: 2) {
            guard let stored = self.vibespaceManagement.loadProjectSession(
                forProject: session.metadata.identifier,
                in: self.vibespaceID
            ) else {
                return false
            }
            guard stored.activeDirectory == workerDirectory.standardizedFileURL.path else {
                return false
            }
            guard stored.entries.count == 2 else {
                return false
            }
            guard let workerEntry = stored.entries.first(where: {
                $0.workingDirectoryPath == workerDirectory.standardizedFileURL.path && $0.customName == "Worker"
            }) else {
                return false
            }
            guard let rootEntry = stored.entries.first(where: {
                $0.workingDirectoryPath == remotePath && $0.customName == nil
            }) else {
                return false
            }
            return workerEntry.tmuxSessionName == liveTmuxName
                && rootEntry.tmuxSessionName == stableTmuxName
        }

        XCTAssertTrue(persisted)
        XCTAssertEqual(terminal.session(for: liveTab.id)?.tmuxSessionName, liveTmuxName)
    }

    func testTerminalChangesPersistMultipleRemoteTabsForSameDirectory() async throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        terminal.createTab(directoryURL: URL(fileURLWithPath: remotePath), customName: "Logs", startImmediately: false)

        let persisted = await waitForCondition(timeout: 2) {
            guard let stored = self.vibespaceManagement.loadProjectSession(
                forProject: session.metadata.identifier,
                in: self.vibespaceID
            ) else {
                return false
            }
            guard stored.entries.count == 2 else { return false }
            let tmuxNames = stored.entries.compactMap(\.tmuxSessionName)
            return stored.entries.allSatisfy { $0.workingDirectoryPath == remotePath }
                && stored.entries.map(\.customName) == [nil, "Logs"]
                && Set(tmuxNames).count == 2
        }

        XCTAssertTrue(persisted)
    }

    func testShutdownPersistsMultipleRemoteTabsImmediately() throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        terminal.createTab(directoryURL: URL(fileURLWithPath: remotePath), customName: "Logs", startImmediately: false)
        session.shutdown()

        let stored = try XCTUnwrap(
            vibespaceManagement.loadProjectSession(
                forProject: session.metadata.identifier,
                in: vibespaceID
            )
        )
        XCTAssertEqual(stored.entries.count, 2)
        XCTAssertEqual(stored.entries.map(\.customName), [nil, "Logs"])
        XCTAssertEqual(Set(stored.entries.compactMap(\.tmuxSessionName)).count, 2)
    }

    func testMakeSSHLaunchInvocationPrefersTmuxWhenSessionNameExistsBeforeProbeCompletes() {
        let profile = makeProfile()

        let invocation = RemoteProjectSession.makeSSHLaunchInvocation(
            profile: profile,
            workingDirectory: "/srv/app",
            hasTmux: false,
            tmuxSessionName: "crispyvibes-abcd1234"
        )

        XCTAssertEqual(invocation.0, "/usr/bin/ssh")
        XCTAssertTrue(invocation.1.contains("\(profile.user)@\(profile.host)"))
        XCTAssertTrue(
            invocation.1.contains(where: { argument in
                argument.contains("tmux has-session -t crispyvibes-abcd1234")
                    && argument.contains("tmux new-session -s crispyvibes-abcd1234")
            })
        )
    }

    func testMakeSSHLaunchInvocationForwardsColorTermSendEnv() {
        let profile = makeProfile()

        let invocation = RemoteProjectSession.makeSSHLaunchInvocation(
            profile: profile,
            workingDirectory: "/srv/app",
            hasTmux: false,
            tmuxSessionName: nil
        )

        let args = invocation.1
        guard let sendEnvFlagIndex = args.firstIndex(of: "-o") else {
            XCTFail("Expected SSH invocation to include -o SendEnv flag for COLORTERM forwarding")
            return
        }
        XCTAssertTrue(
            args.indices.contains(sendEnvFlagIndex + 1),
            "Expected SSH invocation to include a value after -o"
        )
        XCTAssertEqual(
            args[sendEnvFlagIndex + 1],
            "SendEnv=COLORTERM",
            "Expected SSH to forward COLORTERM so remote programs can detect truecolor support"
        )
    }

    func testRemoteTmuxLaunchCommandExportsTruecolorAndEnablesRgbPassthrough() {
        let command = RemoteProjectSession.remoteTmuxLaunchCommand(
            workingDirectory: "/srv/app",
            sessionName: "crispyvibes-rendertest"
        )

        XCTAssertTrue(
            command.contains("export COLORTERM=truecolor"),
            "Remote launch should export COLORTERM=truecolor so non-tmux programs detect truecolor"
        )
        XCTAssertTrue(
            command.contains("terminal-overrides") && command.contains("*:RGB"),
            "Remote launch should enable RGB passthrough so tmux forwards 24-bit color sequences"
        )
    }

    func testRemoteTmuxLaunchCommandPicksBestAvailableTerminfoWithSafeFallback() {
        let command = RemoteProjectSession.remoteTmuxLaunchCommand(
            workingDirectory: "/srv/app",
            sessionName: "crispyvibes-rendertest"
        )

        XCTAssertTrue(
            command.contains("infocmp tmux-256color"),
            "Remote launch should prefer tmux-256color when the terminfo entry exists"
        )
        XCTAssertTrue(
            command.contains("infocmp screen-256color"),
            "Remote launch should fall back to screen-256color when tmux-256color is missing"
        )
        XCTAssertTrue(
            command.contains("echo screen"),
            "Remote launch should fall back to bare 'screen' when no 256-color terminfo is installed"
        )
        XCTAssertTrue(
            command.contains("default-terminal"),
            "Remote launch should set tmux's default-terminal to the picked terminfo"
        )
        XCTAssertTrue(
            command.contains("show-option -gqv default-terminal"),
            "Remote launch should only override default-terminal when the user has not configured it"
        )
    }

    func testResolveRemoteTmuxSessionNameUsesStableNameForFirstRemoteTabAndUniqueNameAfterThat() {
        let stableSessionName = "crispyvibes-stable1234"

        XCTAssertEqual(
            RemoteProjectSession.resolveRemoteTmuxSessionName(
                persistedSessionName: nil,
                existingSessionNames: [],
                stableSessionName: stableSessionName
            ),
            stableSessionName
        )

        let additionalSessionName = RemoteProjectSession.resolveRemoteTmuxSessionName(
            persistedSessionName: nil,
            existingSessionNames: [stableSessionName],
            stableSessionName: stableSessionName
        )

        XCTAssertTrue(additionalSessionName.hasPrefix("crispyvibes-"))
        XCTAssertNotEqual(additionalSessionName, stableSessionName)
        XCTAssertEqual(
            RemoteProjectSession.resolveRemoteTmuxSessionName(
                persistedSessionName: "restore-logs",
                existingSessionNames: [stableSessionName],
                stableSessionName: stableSessionName
            ),
            "restore-logs"
        )
    }

    func testInitSeedsStableRemoteTmuxSessionAndPersistsItWhenNoEntriesExist() async throws {
        let profile = makeProfile()
        let remotePath = "/srv/app"
        let expectedTmuxName = "crispyvibes-\(RemoteProjectSession.stableHash("\(profile.sshURI)\(remotePath)"))"

        let session = makeSession(profile: profile, remotePath: remotePath)
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)

        let liveTab = try XCTUnwrap(terminal.activeTab)
        XCTAssertEqual(terminal.session(for: liveTab.id)?.tmuxSessionName, expectedTmuxName)

        let persisted = await waitForCondition(timeout: 2) {
            guard let stored = self.vibespaceManagement.loadProjectSession(
                forProject: session.metadata.identifier,
                in: self.vibespaceID
            ) else {
                return false
            }
            guard stored.entries.count == 1 else { return false }
            let entry = stored.entries[0]
            return entry.workingDirectoryPath == remotePath
                && entry.tmuxSessionName == expectedTmuxName
                && stored.activeDirectory == remotePath
        }

        XCTAssertTrue(persisted)
    }

    func testReconnectRestartPlanRestartsAllTabsAndPreservesActiveSelection() {
        let activeExitedID = UUID()
        let inactiveID = UUID()
        let runningID = UUID()

        let plan = RemoteProjectSession.reconnectRestartPlan(
            tabs: [
                TerminalTab(id: activeExitedID, workingDirectory: URL(fileURLWithPath: "/srv/app"), exitCode: 255),
                TerminalTab(id: inactiveID, workingDirectory: URL(fileURLWithPath: "/srv/app/logs"), exitCode: nil),
                TerminalTab(id: runningID, workingDirectory: URL(fileURLWithPath: "/srv/app/worker"), exitCode: nil)
            ],
            activeTabID: activeExitedID
        )

        XCTAssertEqual(
            plan,
            [
                RemoteProjectSession.ReconnectRestart(tabID: activeExitedID, activate: true),
                RemoteProjectSession.ReconnectRestart(tabID: inactiveID, activate: false),
                RemoteProjectSession.ReconnectRestart(tabID: runningID, activate: false)
            ]
        )
    }

    func testConnectionTransitionDecisionLatchesReconnectAcrossConnectingState() {
        let disconnected = RemoteProjectSession.connectionTransitionDecision(
            for: .disconnected,
            shouldReviveOnNextConnect: false
        )
        XCTAssertEqual(
            disconnected,
            RemoteProjectSession.ConnectionTransitionDecision(
                shouldReviveOnNextConnect: true,
                shouldPresentConnectedSession: false,
                afterReconnect: false,
                shouldStopWatching: true
            )
        )

        let connecting = RemoteProjectSession.connectionTransitionDecision(
            for: .connecting,
            shouldReviveOnNextConnect: disconnected.shouldReviveOnNextConnect
        )
        XCTAssertEqual(
            connecting,
            RemoteProjectSession.ConnectionTransitionDecision(
                shouldReviveOnNextConnect: true,
                shouldPresentConnectedSession: false,
                afterReconnect: false,
                shouldStopWatching: false
            )
        )

        let connected = RemoteProjectSession.connectionTransitionDecision(
            for: .connected,
            shouldReviveOnNextConnect: connecting.shouldReviveOnNextConnect
        )
        XCTAssertEqual(
            connected,
            RemoteProjectSession.ConnectionTransitionDecision(
                shouldReviveOnNextConnect: false,
                shouldPresentConnectedSession: true,
                afterReconnect: true,
                shouldStopWatching: false
            )
        )
    }

    func testConnectionTransitionDecisionDoesNotMarkFreshConnectedStateAsReconnect() {
        let connected = RemoteProjectSession.connectionTransitionDecision(
            for: .connected,
            shouldReviveOnNextConnect: false
        )

        XCTAssertEqual(
            connected,
            RemoteProjectSession.ConnectionTransitionDecision(
                shouldReviveOnNextConnect: false,
                shouldPresentConnectedSession: true,
                afterReconnect: false,
                shouldStopWatching: false
            )
        )
    }

    func testConnectionTransitionDecisionTreatsFailedStateAsReconnectBoundary() {
        let failed = RemoteProjectSession.connectionTransitionDecision(
            for: .failed("network"),
            shouldReviveOnNextConnect: false
        )

        XCTAssertEqual(
            failed,
            RemoteProjectSession.ConnectionTransitionDecision(
                shouldReviveOnNextConnect: true,
                shouldPresentConnectedSession: false,
                afterReconnect: false,
                shouldStopWatching: true
            )
        )
    }

    private func makeSession(
        profile: SSHConnectionProfile,
        remotePath: String
    ) -> RemoteProjectSession {
        RemoteProjectSession(
            connection: SSHConnection(profile: profile),
            remotePath: remotePath,
            terminalViewModelFactory: container.makeTerminalViewModel,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID
        )
    }

    private func makeProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            id: UUID(),
            displayName: "Dev Box",
            host: "example.com",
            port: 22,
            user: "testuser",
            authMethod: .agent,
            importedFromConfig: false
        )
    }

    private func makeContainer(appDirectoryURL: URL) -> AppContainer {
        let paneWorkerFactory: PaneWorkerFactory = { pane in
            PaneWorkerClient(pane: pane)
        }
        let operationMetricsStore = OperationMetricsStore()
        let measuredPaneWorkerFactory: PaneWorkerFactory = { pane in
            MeasuredPaneWorker(
                inner: paneWorkerFactory(pane),
                metricsStore: operationMetricsStore,
                kind: pane
            )
        }
        let appPersistenceStore = AppPersistenceDataStore(
            fileManager: .default,
            appDirectoryURL: appDirectoryURL
        )
        let vibespacePersistenceStore = VibeSpacePersistenceStore(store: appPersistenceStore)
        let vibespaceManagement = VibeSpaceManagementService(persistenceStore: vibespacePersistenceStore)
        let layoutPersistence = LayoutPersistenceService(persistenceStore: appPersistenceStore)
        let vibespaceInteraction = VibeSpaceInteractionService()
        let terminalServices = TerminalServices(
            focusCoordinator: TerminalFocusCoordinator(),
            diagnosticsSnapshot: TerminalDiagnosticsSnapshot(),
            hostOwnershipCoordinator: TerminalHostOwnershipCoordinator(),
            vibespaceInteraction: vibespaceInteraction
        )
        let terminalViewModelDependencies = TerminalViewModelDependencies(
            presetDiagnostics: TerminalPresetAvailabilityDiagnostics(),
            shortcutStore: TerminalShortcutStore(),
            terminalServices: terminalServices,
            operationMetricsStore: operationMetricsStore
        )
        let makeMarkdownViewModel: @MainActor () -> MarkdownViewModel = {
            MarkdownViewModel(worker: measuredPaneWorkerFactory(.editor), bufferStore: DocumentBufferStore())
        }
        let makeTerminalViewModel: @MainActor () -> TerminalViewModel = {
            TerminalViewModel(
                dependencies: terminalViewModelDependencies,
                worker: measuredPaneWorkerFactory(.terminal)
            )
        }
        let terminalBoardStandaloneRegistry = VibeSpaceTerminalBoardStandaloneRegistry(
            makeTerminalViewModel: makeTerminalViewModel
        )
        let terminalBoardDetachedWindowManager = VibeSpaceTerminalBoardDetachedWindowManager()
        let detachedWindowManager = EditorDetachedWindowManager(
            markdownViewModelFactory: makeMarkdownViewModel
        )
        let experimentalFeatures = ExperimentalFeaturesService()
        let acpObservabilityStore = ACPObservabilityStore()
        let acpSessionManager = ACPSessionManager(observabilityStore: acpObservabilityStore)
        let acpVibeSpaceContextStore = ACPVibeSpaceContextStore()
        let agentConversationStore = AgentConversationStore()
        let makeACPStandaloneStore: @MainActor (UUID, UUID?) -> ACPStandaloneSessionStore = { id, vibespaceID in
            let chatViewModel = ACPChatViewModel(
                sessionManager: acpSessionManager,
                conversationStore: agentConversationStore
            )
            return ACPStandaloneSessionStore(
                id: id,
                sessionManager: acpSessionManager,
                conversationStore: agentConversationStore,
                chatViewModel: chatViewModel,
                vibespaceID: vibespaceID
            )
        }
        let acpSessionRegistry = ACPSessionRegistry(storeFactory: makeACPStandaloneStore)
        let acpVibeSpaceSessionService = ACPVibeSpaceSessionService()
        let acpDeveloperToolsService = ACPDeveloperToolsService(
            sessionManager: acpSessionManager,
            vibespaceContextStore: acpVibeSpaceContextStore
        )
        layoutPersistence.setVibeSpacePersistenceStore(vibespacePersistenceStore)
        let shelfStore = ShelfStore(persistenceStore: appPersistenceStore)
        let cliCommandRouter = CLICommandRouter(shelfStore: shelfStore)
        let cliSocketServer = CLISocketServer(router: cliCommandRouter)
        return AppContainer(
            appPersistenceStore: appPersistenceStore,
            vibespacePersistenceStore: vibespacePersistenceStore,
            terminalBoardStandaloneRegistry: terminalBoardStandaloneRegistry,
            terminalBoardDetachedWindowManager: terminalBoardDetachedWindowManager,
            layoutPersistence: layoutPersistence,
            shelfStore: shelfStore,
            detachedWindowManager: detachedWindowManager,
            vibespaceManagement: vibespaceManagement,
            themeManager: CrispyVibesThemeManager(),
            experimentalFeatures: experimentalFeatures,
            vibespaceInteraction: vibespaceInteraction,
            terminalServices: terminalServices,
            terminalViewModelDependencies: terminalViewModelDependencies,
            operationMetricsStore: operationMetricsStore,
            acpObservabilityStore: acpObservabilityStore,
            acpSessionManager: acpSessionManager,
            acpVibeSpaceContextStore: acpVibeSpaceContextStore,
            acpVibeSpaceSessionService: acpVibeSpaceSessionService,
            acpDeveloperToolsService: acpDeveloperToolsService,
            agentConversationStore: agentConversationStore,
            vibespaceCommentStore: VibeSpaceCommentStore(conversationStore: agentConversationStore),
            vibespaceTodoStore: VibeSpaceTodoStore(conversationStore: agentConversationStore),
            vibeLaneTaskManager: VibeLaneTaskManager(store: InMemoryVibeLaneStore(lanes: VibeLaneCatalog.starterLanes), worker: VibeLaneUnimplementedWorkRunner()),
            todoLanePipelineBridge: TodoLanePipelineBridge(
                todoStore: VibeSpaceTodoStore(conversationStore: agentConversationStore),
                laneManager: VibeLaneTaskManager(store: InMemoryVibeLaneStore(lanes: []), worker: VibeLaneUnimplementedWorkRunner())
            ),
            todoTriageCoordinator: TodoTriageCoordinator(
                todoStore: VibeSpaceTodoStore(conversationStore: agentConversationStore),
                laneManager: VibeLaneTaskManager(store: InMemoryVibeLaneStore(lanes: []), worker: VibeLaneUnimplementedWorkRunner()),
                runner: NoopTriageRunner()
            ),
            vibeLaneSurfaceNavigationViewModel: VibeLaneSurfaceNavigationViewModel(),
            commentLifecycleCoordinator: CommentLifecycleCoordinator(store: VibeSpaceCommentStore(conversationStore: agentConversationStore)),
            externalAgentSessionService: ExternalAgentSessionService(),
            acpSessionRegistry: acpSessionRegistry,
            dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator(sessionRegistry: acpSessionRegistry),
            paneWorkerFactory: measuredPaneWorkerFactory,
            browserHistoryStore: BrowserHistoryStore(),
            composeHistoryStore: ComposeHistoryStore(),
            contextSummaryObservabilityStore: ContextSummaryObservabilityStore(),
            sshConnectionManager: SSHConnectionManager(),
            cliCommandRouter: cliCommandRouter,
            cliSocketServer: cliSocketServer,
            jupyterServerService: JupyterServerService()
        )
    }
}
