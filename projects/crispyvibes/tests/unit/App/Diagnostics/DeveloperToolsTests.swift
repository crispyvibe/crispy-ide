import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

// MARK: - Mocks

private actor MockPaneWorker: PaneWorkerExecuting {
    var executeResult: String? = "mock-result"
    var executeCalled = false

    func restart() async {}

    func execute(_ method: PaneWorkerMethod, arguments: [String: String], timeout: TimeInterval) async throws -> String? {
        executeCalled = true
        return executeResult
    }
}

@MainActor
private final class StubTerminalEngine: TerminalSessionEngine {
    var sessionID: UUID?
    let hostedView: NSView = NSView(frame: .zero)
    var effectiveAppearance: NSAppearance { NSAppearance.current }
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var processIsRunning: Bool { false }
    var shellProcessID: Int32 { 0 }
    var debugIdentifier: String { "stub" }

    func configure(delegate: any TerminalSessionEngineDelegate, initialFont: NSFont, optionAsMetaKey: Bool, historySize: Int) {}
    func startProcess(executable: String, args: [String], environment: [String], currentDirectory: String) {}
    func terminate() {}
    func copySelection() {}
    func pasteFromClipboard() {}
    func send(text: String) {}
    func typeCharacters(_ text: String) {}
    func pressSubmitVariant(_ variant: TerminalSubmitVariant) {}
    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void) {}
    func currentDimensions() -> (cols: Int, rows: Int) { (80, 24) }
    func resize(cols: Int, rows: Int) {}
    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {}
    func applyThemePalette(_ palette: AppThemePalette) {}
}

private actor MockACPTransport: ACPTransportProtocol {
    func start(executable: String, arguments: [String], environment: [String : String]?) async throws {}
    func send(method: String, params: [String : Any]?) async throws -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: .int(1), result: AnyCodable([:]), error: nil)
    }
    func sendNotification(method: String, params: [String : Any]?) async throws {}
    func setRequestHandler(_ handler: @escaping @Sendable (String, [String : Any]) async throws -> Any) async {}
    func setTerminationHandler(_ handler: @escaping @Sendable (_ reason: String) -> Void) async {}
    func stop() async {}
    var isRunning: Bool { true }
    var lastStderrOutput: String { "" }
    func notifications() async -> AsyncStream<JSONRPCNotification> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private func makeExecutableScript(in directory: URL, name: String, contents: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@MainActor
private final class MockAgentSession: ObservableObject, AgentSessionProtocol {
    let id = UUID()
    let projectPath: URL
    let agentName: String
    let agentID: String
    let permissionHandler: ACPPermissionHandler? = nil
    @Published var isConnected = true

    private var promptResponses: [[ACPUpdate]]

    init(
        projectPath: URL = URL(fileURLWithPath: "/tmp/mock-acp-project"),
        agentName: String = "Mock ACP",
        agentID: String = "mock-acp",
        promptResponses: [[ACPUpdate]]
    ) {
        self.projectPath = projectPath
        self.agentName = agentName
        self.agentID = agentID
        self.promptResponses = promptResponses
    }

    func connect() async throws {}

    func prompt(_ text: String, contentBlocks: [[String : Any]]?) -> AsyncStream<ACPUpdate> {
        let response = promptResponses.isEmpty ? [] : promptResponses.removeFirst()
        return AsyncStream { continuation in
            for update in response {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }

    func cancel() async {}
    func disconnect() { isConnected = false }
    func setMode(_ modeID: String) async {}
    func setModel(_ modelID: String) async {}
}

@MainActor
private final class TestACPSessionManager: ACPSessionManager {
    private(set) var connectedProjectIdentifiers: [String] = []
    private(set) var disconnectedProjectIdentifiers: [String] = []
    private var sessionsByProjectIdentifier: [String: ACPSession] = [:]

    override func connect(
        project: AnyProjectSession,
        agent: ACPAgentDefinition,
        autoAllowPermissions: Bool = true
    ) async throws -> ACPSession {
        connectedProjectIdentifiers.append(project.projectIdentifier)
        let session = ACPSession(
            projectPath: project.rootURL,
            agent: agent,
            observabilityStore: nil,
            transport: MockACPTransport()
        )
        session.sessionID = "session-\(connectedProjectIdentifiers.count)"
        session.isConnected = true
        sessionsByProjectIdentifier[project.projectIdentifier] = session
        objectWillChange.send()
        return session
    }

    override func session(for projectIdentifier: String) -> ACPSession? {
        sessionsByProjectIdentifier[projectIdentifier]
    }

    override func disconnect(projectIdentifier: String) {
        disconnectedProjectIdentifiers.append(projectIdentifier)
        sessionsByProjectIdentifier.removeValue(forKey: projectIdentifier)?.disconnect()
        objectWillChange.send()
    }
}

// MARK: - Tests

@MainActor
final class DeveloperToolsTests: XCTestCase {

    // MARK: REQ-021 – Decorator wraps without changing behavior

    func testMeasuredPaneWorkerForwardsResultAndRecordsMetric() async throws {
        let store = OperationMetricsStore(capacity: 100)
        let mock = MockPaneWorker()
        let measured = MeasuredPaneWorker(inner: mock, metricsStore: store, kind: .explorer)

        let result = try await measured.execute(.listTree, arguments: [:], timeout: 5)

        XCTAssertEqual(result, "mock-result")
        let called = await mock.executeCalled
        XCTAssertTrue(called)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.snapshot().first?.operationName, PaneWorkerMethod.listTree.rawValue)
    }

    // MARK: REQ-022 – Metrics store stays bounded

    func testMetricsStoreEvictsOldestWhenCapacityExceeded() {
        let store = OperationMetricsStore(capacity: 5)
        let base = Date()

        for i in 0..<10 {
            store.recordOperation(
                name: "op-\(i)",
                startTime: base.addingTimeInterval(Double(i))
            )
        }

        XCTAssertEqual(store.count, 5)
        let names = store.snapshot().map(\.operationName)
        XCTAssertEqual(names, ["op-5", "op-6", "op-7", "op-8", "op-9"])
    }

    // MARK: REQ-022 – Aggregation works

    func testAggregateByOperationComputesCorrectly() {
        let store = OperationMetricsStore(capacity: 100)
        let base = Date()

        // Two successful "read" ops, one failed "write" op
        store.recordOperation(name: "read", startTime: base, endTime: base.addingTimeInterval(1))
        store.recordOperation(name: "read", startTime: base, endTime: base.addingTimeInterval(3))
        store.recordOperation(name: "write", startTime: base, endTime: base.addingTimeInterval(2), succeeded: false, errorDescription: "timeout")

        let byOp = store.aggregateByOperation()
        let readAgg = try! XCTUnwrap(byOp["read"])
        XCTAssertEqual(readAgg.count, 2)
        XCTAssertEqual(readAgg.totalDuration, 4, accuracy: 0.01)
        XCTAssertEqual(readAgg.maxDuration, 3, accuracy: 0.01)
        XCTAssertEqual(readAgg.failureCount, 0)

        let writeAgg = try! XCTUnwrap(byOp["write"])
        XCTAssertEqual(writeAgg.count, 1)
        XCTAssertEqual(writeAgg.failureCount, 1)
    }

    func testAggregateByProjectGroupsCorrectly() {
        let store = OperationMetricsStore(capacity: 100)
        let base = Date()

        store.recordOperation(name: "op", projectContext: "projA", startTime: base, endTime: base.addingTimeInterval(1))
        store.recordOperation(name: "op", projectContext: "projA", startTime: base, endTime: base.addingTimeInterval(2))
        store.recordOperation(name: "op", projectContext: "projB", startTime: base, endTime: base.addingTimeInterval(5))

        let byProj = store.aggregateByProject()
        XCTAssertEqual(byProj["projA"]?.count, 2)
        XCTAssertEqual(byProj["projB"]?.count, 1)
        XCTAssertEqual(byProj["projB"]?.totalDuration ?? 0, 5, accuracy: 0.01)
    }

    // MARK: REQ-024 – Terminal startup milestones are distinct

    func testTerminalStartupMilestonesComputeDistinctDurations() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(0.5)
        let t2 = t1.addingTimeInterval(0.3)
        let t3 = t2.addingTimeInterval(0.2)

        var ms = TerminalStartupMilestones()
        ms.sessionCreated = t0
        ms.shellLaunched = t1
        ms.firstRenderObserved = t2
        ms.firstInteractivePromptObserved = t3

        XCTAssertNotNil(ms.shellLaunchDuration)
        XCTAssertNotNil(ms.renderLatency)
        XCTAssertNotNil(ms.interactiveLatency)

        XCTAssertEqual(ms.shellLaunchDuration!, 0.5, accuracy: 0.001)
        XCTAssertEqual(ms.renderLatency!, 0.3, accuracy: 0.001)
        XCTAssertEqual(ms.interactiveLatency!, 0.5, accuracy: 0.001)

        // All timestamps are distinct
        let timestamps = [t0, t1, t2, t3]
        XCTAssertEqual(Set(timestamps).count, 4)
    }

    func testTerminalDiagnosticsSnapshotRecordsMilestones() {
        let snapshot = TerminalDiagnosticsSnapshot()
        let sessionID = UUID()
        let engine = StubTerminalEngine()

        snapshot.register(sessionID: sessionID, sessionDebugID: 1, engine: engine)

        let t0 = Date()
        snapshot.recordStartupMilestone(sessionID: sessionID) { $0.sessionCreated = t0 }
        snapshot.recordStartupMilestone(sessionID: sessionID) { $0.shellLaunched = t0.addingTimeInterval(0.4) }
        snapshot.recordStartupMilestone(sessionID: sessionID) { $0.firstRenderObserved = t0.addingTimeInterval(0.6) }
        snapshot.recordStartupMilestone(sessionID: sessionID) { $0.firstInteractivePromptObserved = t0.addingTimeInterval(0.9) }

        let payload = snapshot.capture()
        XCTAssertEqual(payload.activeSessionCount, 1)
        XCTAssertEqual(payload.sessions.count, 1)

        let row = payload.sessions[0]
        XCTAssertNotNil(row.sessionCreated)
        XCTAssertNotNil(row.shellLaunched)
        XCTAssertNotNil(row.firstRenderObserved)
        XCTAssertNotNil(row.firstInteractivePromptObserved)
        XCTAssertNotNil(row.shellLaunchDuration)
        XCTAssertNotNil(row.renderLatency)
        XCTAssertNotNil(row.interactiveLatency)

        // Durations are distinct from each other
        let durations = [row.shellLaunchDuration!, row.renderLatency!, row.interactiveLatency!]
        XCTAssertEqual(Set(durations).count, 3)
    }

    // MARK: REQ-023 – Dashboard renders without blocking

    func testDeveloperToolsViewCanBeCreatedWithoutBlocking() {
        let store = OperationMetricsStore(capacity: 100)
        let snapshot = TerminalDiagnosticsSnapshot()
        let acpStore = ACPObservabilityStore()
        let defaults = UserDefaults(suiteName: "DeveloperToolsTests-\(UUID().uuidString)")!
        let experimentalFeatures = ExperimentalFeaturesService(defaults: defaults)
        let acpContextStore = ACPVibeSpaceContextStore()
        let acpSessionManager = ACPSessionManager(observabilityStore: acpStore)
        let acpDeveloperToolsService = ACPDeveloperToolsService(
            sessionManager: acpSessionManager,
            vibespaceContextStore: acpContextStore
        )
        store.recordOperation(name: "test.op", startTime: Date())
        let view = DeveloperToolsView(
            metricsStore: store,
            diagnosticsSnapshot: snapshot,
            acpObservabilityStore: acpStore,
            experimentalFeatures: experimentalFeatures,
            acpVibeSpaceContextStore: acpContextStore,
            acpDeveloperToolsService: acpDeveloperToolsService,
            contextSummaryObservabilityStore: ContextSummaryObservabilityStore()
        )
        XCTAssertNotNil(view)
    }

    // MARK: REQ-025 – Shell startup anomaly scenarios

    func testStartupMilestonesDetectPromptLaggingBehindRender() {
        var ms = TerminalStartupMilestones()
        let t0 = Date()
        ms.shellLaunched = t0
        ms.firstRenderObserved = t0.addingTimeInterval(0.1)
        ms.firstInteractivePromptObserved = t0.addingTimeInterval(2.0)

        XCTAssertNotNil(ms.renderLatency)
        XCTAssertNotNil(ms.interactiveLatency)
        XCTAssertTrue(ms.interactiveLatency! > ms.renderLatency! * 5)
    }

    func testStartupMilestonesDetectBannerSuppression() {
        var ms = TerminalStartupMilestones()
        ms.bannerSuppressionTriggered = Date()
        XCTAssertNotNil(ms.bannerSuppressionTriggered)
    }
}

@MainActor
final class ACPPreferencesAndSessionServiceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var userDefaults: UserDefaults!
    private var tempRoot: URL!
    private var container: AppContainer!

    override func setUpWithError() throws {
        defaultsSuiteName = "ACPPreferencesAndSessionServiceTests-\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-acp-tests")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            userDefaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        userDefaults = nil
        tempRoot = nil
        container = nil
    }

    func testACPDefaultAgentResolvesCustomInstalledAgent() {
        let customAgent = CustomACPAgent(
            id: "custom-acp",
            title: "Custom ACP",
            executable: "custom-acp",
            arguments: ["serve"]
        )
        AppPreferences.setCustomACPAgents([customAgent], userDefaults: userDefaults)
        AppPreferences.setACPDefaultAgentID(customAgent.id, userDefaults: userDefaults)

        let discovered = ACPAgentRegistry.discoverInstalledAgents(
            userDefaults: userDefaults,
            resolveExecutable: { executable in
                executable == "custom-acp" ? "/opt/bin/custom-acp" : nil
            }
        )
        let resolved = AppPreferences.resolvedACPDefaultAgent(
            userDefaults: userDefaults,
            resolveExecutable: { executable in
                executable == "custom-acp" ? "/opt/bin/custom-acp" : nil
            }
        )

        XCTAssertTrue(discovered.contains(where: { $0.id == customAgent.id && $0.isAvailable }))
        XCTAssertEqual(resolved?.id, customAgent.id)
        XCTAssertEqual(resolved?.title, customAgent.title)
        XCTAssertEqual(resolved?.executable, customAgent.executable)
        XCTAssertEqual(resolved?.arguments, customAgent.arguments)
    }

    func testACPVibeSpaceSessionServiceTracksFocusedProjectAndPreferredAgent() async throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [first, second])
        let firstProject = try XCTUnwrap(vibespace.projects.first)
        let secondProject = try XCTUnwrap(vibespace.projects.last)
        let service = ACPVibeSpaceSessionService()
        let agentID = "kiro"

        service.sync(focusedProject: firstProject, preferredAgentID: agentID)
        await settleMainActor()

        XCTAssertEqual(service.focusedProject?.id, firstProject.id)
        XCTAssertEqual(service.preferredAgentID, agentID)
        XCTAssertTrue(service.hasConfiguredAgent)

        service.sync(focusedProject: secondProject, preferredAgentID: agentID)
        await settleMainActor()

        XCTAssertEqual(service.focusedProject?.id, secondProject.id)
        XCTAssertEqual(service.preferredAgentID, agentID)

        service.sync(focusedProject: secondProject, preferredAgentID: nil)
        await settleMainActor()

        XCTAssertEqual(service.focusedProject?.id, secondProject.id)
        XCTAssertNil(service.preferredAgentID)
        XCTAssertFalse(service.hasConfiguredAgent)
    }

    private func settleMainActor(iterations: Int = 8) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }
}

@MainActor
final class ACPSecurityHardeningTests: XCTestCase {
    func testACPDeveloperToolsDefaultsToDenyPermissions() {
        let service = ACPDeveloperToolsService(
            sessionManager: ACPSessionManager(),
            vibespaceContextStore: ACPVibeSpaceContextStore()
        )

        XCTAssertFalse(service.autoAllowPermissions)
    }

    func testACPChatTimelineEvictsOldEntriesWhenCapacityExceeded() async {
        let responses = [[ACPUpdate]()]
        let session = MockAgentSession(promptResponses: responses)
        let conversationStore = AgentConversationStore()
        let viewModel = ACPChatViewModel(sessionManager: ACPSessionManager(), conversationStore: conversationStore)
        viewModel.bindStandaloneSession(session)
        viewModel.timeline = (0..<50_000).map { index in
            .user("prompt-\(index)")
        }

        viewModel.composeText = "prompt-50000"
        viewModel.send()
        for _ in 0..<4 {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.timeline.count, 50_000)
        guard case .userMessage(let firstText) = viewModel.timeline.first?.kind else {
            return XCTFail("Expected oldest retained timeline entry to be a user message")
        }
        XCTAssertEqual(firstText, "prompt-1")
    }

    func testACPStderrDiagnosticsSummaryRedactsRawContent() {
        let secret = "VERY_SECRET_TOKEN=super-secret-value"
        let summary = ACPStderrDiagnostics.summary(for: "  \(secret)\n")

        XCTAssertNotNil(summary)
        XCTAssertFalse(summary?.contains(secret) == true)
        XCTAssertTrue(summary?.contains("stderrHash=") == true)
        XCTAssertTrue(summary?.contains("stderrBytes=") == true)
    }

    func testACPFileSystemHandlerRejectsSymlinkEscapes() async throws {
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-acp-symlink")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let outsideRoot = tempRoot.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)

        let secretFile = outsideRoot.appendingPathComponent("secret.txt")
        try "secret".write(to: secretFile, atomically: true, encoding: .utf8)

        let symlinkPath = projectRoot.appendingPathComponent("linked-secret.txt")
        try FileManager.default.createSymbolicLink(atPath: symlinkPath.path, withDestinationPath: secretFile.path)

        let hostContext = ACPHostContext(
            projectRootURL: projectRoot,
            projectIdentifier: projectRoot.path,
            projectDisplayName: "Project",
            fileContentProvider: LocalFileContentProvider(),
            terminalProvider: nil
        )
        let handler = ACPFileSystemHandler(hostContext: hostContext)

        do {
            _ = try await handler.handleRead(params: ["path": symlinkPath.path])
            XCTFail("Expected symlink escape to be rejected")
        } catch let error as ACPHandlerError {
            guard case .outsideProjectBoundary(let path) = error else {
                return XCTFail("Unexpected ACP handler error: \(error)")
            }
            XCTAssertEqual(path, symlinkPath.path)
        }
    }

    func testACPTransportSendTimesOutWhenAgentStopsResponding() async throws {
        let transport = ACPTransport(
            localSessionID: UUID().uuidString,
            agentID: "test-agent",
            projectToken: nil,
            origin: "test",
            observabilityStore: nil,
            requestTimeout: .milliseconds(150)
        )
        try await transport.start(executable: "/bin/sh", arguments: ["-c", "sleep 5"], environment: nil)
        defer {
            Task {
                await transport.stop()
            }
        }

        do {
            _ = try await transport.send(method: "initialize", params: nil)
            XCTFail("Expected ACP transport request to time out")
        } catch let error as ACPTransportError {
            guard case .requestTimedOut(let method) = error else {
                return XCTFail("Unexpected ACP transport error: \(error)")
            }
            XCTAssertEqual(method, "initialize")
        }
    }

    func testClaudeCodeConnectDoesNotLeakRawStderrToUserFacingError() async throws {
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-acp-claude")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let secret = "VERY_SECRET_TOKEN=super-secret-value"
        let executable = try makeExecutableScript(
            in: tempRoot,
            name: "fake-claude.sh",
            contents: """
            #!/bin/sh
            echo "\(secret)" 1>&2
            exit 1
            """
        )

        let session = ClaudeCodeSession(projectPath: tempRoot, executable: executable.path)

        do {
            try await session.connect()
            XCTFail("Expected Claude Code session startup to fail")
        } catch {
            let message = error.localizedDescription
            XCTAssertEqual(message, "Claude Code exited unexpectedly. Check app logs for diagnostics.")
            XCTAssertFalse(message.contains(secret))
        }
    }
}
