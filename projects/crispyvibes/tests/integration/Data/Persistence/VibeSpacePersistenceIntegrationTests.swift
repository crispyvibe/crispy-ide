import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpacePersistenceIntegrationTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempRoot = base.appendingPathComponent("crispyvibes-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testWorkerEditorFlowForVibeSpaceFile() throws {
        let project = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [project])
        XCTAssertEqual(vibespace.projects.count, 1)

        let markdownFile = project.appendingPathComponent("notes.md")
        let writeResponse = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(
                method: .writeFile,
                arguments: [
                    "filePath": markdownFile.path,
                    "content": "# Notes\nHello"
                ]
            )
        )
        XCTAssertTrue(writeResponse.success)

        let readResponse = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(
                method: .readFile,
                arguments: ["filePath": markdownFile.path]
            )
        )
        XCTAssertTrue(readResponse.success)
        XCTAssertEqual(readResponse.value, "# Notes\nHello")
        XCTAssertTrue(MarkdownViewModel.isSupportedMarkdownFile(markdownFile))

        vibespace.reconcileProjectAvailability()
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.unresolvedProjectPaths.isEmpty)
    }

    func testVibeSpaceConfigHydrationPerformance() throws {
        let vibespaceCount = 4
        let projectsPerVibeSpace = 4
        var configs: [VibeSpaceConfigFile] = []

        for vibespaceIndex in 0..<vibespaceCount {
            var projectPaths: [String] = []
            for projectIndex in 0..<projectsPerVibeSpace {
                let projectURL = tempRoot
                    .appendingPathComponent("vibespace-\(vibespaceIndex)", isDirectory: true)
                    .appendingPathComponent("project-\(projectIndex)", isDirectory: true)
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
                projectPaths.append(projectURL.path)
            }
            configs.append(VibeSpaceConfigFile(
                id: UUID(),
                name: "Benchmark \(vibespaceIndex + 1)",
                projectPaths: projectPaths,
                unresolvedProjectPaths: [],
                focusedProjectPath: projectPaths.first,
                startupSettings: .default,
                defaultTerminalShell: nil
            ))
        }

        let encoded = try JSONEncoder().encode(configs)

        measure(metrics: [XCTClockMetric()]) {
            do {
                let decoded = try JSONDecoder().decode([VibeSpaceConfigFile].self, from: encoded)
                let hydrated = decoded.map { self.container.makeVibeSpaceState(config: $0) }
                XCTAssertEqual(hydrated.count, vibespaceCount)
                XCTAssertEqual(hydrated.reduce(0) { $0 + $1.projects.count }, vibespaceCount * projectsPerVibeSpace)
            } catch {
                XCTFail("Failed to decode: \(error)")
            }
        }
    }

    func testTerminalTabSwitchLatencyPerformance() throws {
        let projectRoot = tempRoot.appendingPathComponent("terminal", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        var directories: [URL] = []
        for index in 0..<6 {
            let directory = projectRoot.appendingPathComponent("project-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            directories.append(directory)
        }

        let defaultsSuite = "crispyvibes.integration.terminal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let dependencies = TerminalViewModelDependencies(
            presetDiagnostics: TerminalPresetAvailabilityDiagnostics(defaults: defaults),
            shortcutStore: TerminalShortcutStore(defaults: defaults),
            terminalServices: TerminalServices()
        )
        let viewModel = TerminalViewModel(
            dependencies: dependencies,
            worker: container.makePaneWorker(pane: .terminal)
        )
        viewModel.restoreTabs(
            directories: directories,
            activeDirectory: directories.first,
            defaultDirectory: projectRoot
        )
        let tabs = viewModel.tabs
        XCTAssertEqual(tabs.count, directories.count)

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<120 {
                for tab in tabs {
                    viewModel.selectTab(tab)
                }
            }
            XCTAssertEqual(viewModel.activeTabID, tabs.last?.id)
        }
    }

    func testVibeSpaceSteadyStateMemoryPerformance() throws {
        let vibespaceCount = 5
        let projectsPerVibeSpace = 5
        var configs: [VibeSpaceConfigFile] = []

        for vibespaceIndex in 0..<vibespaceCount {
            var projectPaths: [String] = []
            for projectIndex in 0..<projectsPerVibeSpace {
                let projectURL = tempRoot
                    .appendingPathComponent("memory-vibespace-\(vibespaceIndex)", isDirectory: true)
                    .appendingPathComponent("project-\(projectIndex)", isDirectory: true)
                try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
                projectPaths.append(projectURL.path)
            }
            configs.append(VibeSpaceConfigFile(
                id: UUID(),
                name: "Memory \(vibespaceIndex + 1)",
                projectPaths: projectPaths,
                unresolvedProjectPaths: [],
                focusedProjectPath: projectPaths.first,
                startupSettings: .default,
                defaultTerminalShell: nil
            ))
        }

        let encoded = try JSONEncoder().encode(configs)

        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            autoreleasepool {
                do {
                    let decoded = try JSONDecoder().decode([VibeSpaceConfigFile].self, from: encoded)
                    let hydrated = decoded.map { self.container.makeVibeSpaceState(config: $0) }
                    XCTAssertEqual(hydrated.count, vibespaceCount)
                    XCTAssertEqual(
                        hydrated.reduce(0) { $0 + $1.projects.count },
                        vibespaceCount * projectsPerVibeSpace
                    )
                } catch {
                    XCTFail("Failed to decode: \(error)")
                }
            }
        }
    }

    func testVibeSpaceHydrationRunsStartupCommandsForBackgroundProjects() async throws {
        let firstProject = tempRoot.appendingPathComponent("focused-project", isDirectory: true)
        let secondProject = tempRoot.appendingPathComponent("background-project", isDirectory: true)
        try FileManager.default.createDirectory(at: firstProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)

        let startupSettings = VibeSpaceStartupSettings(
            startupTerminalCount: 1,
            startupProfiles: [
                VibeSpaceTerminalStartupProfile(
                    presetID: nil,
                    command: "echo vibespace-startup"
                )
            ],
            focusTerminalOnProjectSwitch: true
        )
        let config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Hydration Fixture",
            projectPaths: [
                firstProject.standardizedFileURL.path,
                secondProject.standardizedFileURL.path
            ],
            unresolvedProjectPaths: [],
            focusedProjectPath: firstProject.standardizedFileURL.path,
            startupSettings: startupSettings,
            defaultTerminalShell: nil
        )
        let vibespace = container.makeVibeSpaceState(config: config)
        let dependencies = container.makeContentViewDependencies()
        dependencies.vibespaceCatalogStore.replaceDisplayedVibeSpace(with: vibespace)
        dependencies.appShellStore.showVibeSpace(vibespace.id)
        dependencies.vibespaceHydrationCoordinator.resetStartupExecutionFlags()

        dependencies.vibespaceHydrationCoordinator.scheduleVibeSpaceTerminalHydration(for: vibespace.id)

        let startupAppliedToAllProjects = await waitForCondition(timeout: 4) {
            guard let projects = dependencies.vibespaceCatalogStore.vibespaceValue(for: vibespace.id, { $0.projects }) else {
                return false
            }
            guard projects.count == 2 else { return false }
            return projects.allSatisfy { project in
                project.terminalViewModel.tabs.contains { tab in
                    if case let .preset(_, command) = tab.origin {
                        return command == "echo vibespace-startup"
                    }
                    return false
                }
            }
        }

        XCTAssertTrue(startupAppliedToAllProjects)
    }
}

@MainActor
private func waitForCondition(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
    return condition()
}
