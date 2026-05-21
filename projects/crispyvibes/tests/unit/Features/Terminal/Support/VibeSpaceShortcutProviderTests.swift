import XCTest
@testable import CrispyVibes

@MainActor
private func waitForExpectation(
    timeout: TimeInterval = 1.0,
    condition: @escaping @MainActor () -> Bool
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertTrue(condition())
}

final class VibeSpaceShortcutProviderTests: XCTestCase {

    @MainActor
    private func makeProviderHarness() throws -> (
        provider: VibeSpaceShortcutProvider,
        service: VibeSpaceManagementService,
        vibespaceID: UUID,
        tempDirectory: URL,
        projectURL: URL
    ) {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispyvibes-vibespace-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let projectURL = tempDirectory.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempDirectory)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)
        let vibespace = service.createVibeSpace(name: "VibeSpace", projectURLs: [projectURL])
        let provider = VibeSpaceShortcutProvider(vibespaceManagement: service)
        return (provider, service, vibespace.id, tempDirectory, projectURL)
    }

    @MainActor
    func testEmptyProviderReturnsNoShortcuts() {
        let provider = VibeSpaceShortcutProvider()
        XCTAssertTrue(provider.mergedShortcuts.isEmpty)
        XCTAssertTrue(provider.vibespaceShortcuts.isEmpty)
        XCTAssertTrue(provider.projectShortcuts.isEmpty)
    }

    @MainActor
    func testUpdateWithNilVibeSpaceIDClearsShortcuts() {
        let provider = VibeSpaceShortcutProvider()
        provider.update(vibespaceID: nil, focusedProjectPath: nil)
        XCTAssertTrue(provider.mergedShortcuts.isEmpty)
    }

    @MainActor
    func testUpdateLoadsVibeSpaceAndFocusedProjectShortcuts() throws {
        let harness = try makeProviderHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectory) }

        let vibespaceShortcut = TerminalShortcutDefinition(name: "Root", command: "pwd")
        let projectShortcut = TerminalShortcutDefinition(name: "Build", command: "npm run build")
        harness.service.setVibeSpaceShortcuts([vibespaceShortcut], vibespaceID: harness.vibespaceID)
        harness.service.setProjectShortcuts([projectShortcut], vibespaceID: harness.vibespaceID, projectPath: harness.projectURL.path)

        harness.provider.update(
            vibespaceID: harness.vibespaceID,
            focusedProjectPath: harness.projectURL.path
        )

        XCTAssertEqual(harness.provider.vibespaceShortcuts, [vibespaceShortcut])
        XCTAssertEqual(harness.provider.projectShortcuts, [projectShortcut])
        XCTAssertEqual(harness.provider.mergedShortcuts, [vibespaceShortcut, projectShortcut])
    }

    @MainActor
    func testProviderReloadsWhenVibeSpaceShortcutsChangeNotificationFires() throws {
        let harness = try makeProviderHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectory) }

        harness.provider.update(
            vibespaceID: harness.vibespaceID,
            focusedProjectPath: harness.projectURL.path
        )
        XCTAssertTrue(harness.provider.mergedShortcuts.isEmpty)

        let vibespaceShortcut = TerminalShortcutDefinition(name: "Serve", command: "npm run dev")
        harness.service.setVibeSpaceShortcuts([vibespaceShortcut], vibespaceID: harness.vibespaceID)

        waitForExpectation {
            harness.provider.vibespaceShortcuts == [vibespaceShortcut]
        }

        XCTAssertEqual(harness.provider.mergedShortcuts, [vibespaceShortcut])
    }
}

final class SpotlightComposeInlineTriggerTests: XCTestCase {
    func testParsesUniversalTriggerAndQuery() {
        let parsed = SpotlightComposeInlineTrigger.parse("`build api", triggerToken: "`")

        guard case let .universal(query, prefixText)? = parsed else {
            return XCTFail("Expected universal trigger")
        }
        XCTAssertEqual(query, "build api")
        XCTAssertEqual(prefixText, "")
    }

    func testParsesCustomTriggerAfterLeadingWhitespace() {
        let parsed = SpotlightComposeInlineTrigger.parse("   :om generate git status for app", triggerToken: ":om")

        guard case let .universal(input, prefixText)? = parsed else {
            return XCTFail("Expected universal trigger")
        }
        XCTAssertEqual(input, "generate git status for app")
        XCTAssertEqual(prefixText, "   ")
    }

    func testIgnoresNonTriggerInput() {
        XCTAssertNil(SpotlightComposeInlineTrigger.parse("git status", triggerToken: "`"))
    }

    func testNormalizesConfiguredTrigger() {
        XCTAssertEqual(AppPreferences.normalizedTerminalComposeInlineTrigger("  `  "), "`")
        XCTAssertEqual(AppPreferences.normalizedTerminalComposeInlineTrigger(""), "`")
    }

    func testGenerateCommandPromptIncludesContextAndRequest() {
        let context = SpotlightComposeInlinePromptContext(
            terminalTitle: "API Terminal",
            workingDirectoryPath: "/tmp/project"
        )

        let prompt = SpotlightComposeInlinePromptAction.generateCommand.buildPrompt(
            userInput: "list all swift files changed today",
            context: context
        )

        XCTAssertTrue(prompt.contains("API Terminal"))
        XCTAssertTrue(prompt.contains("/tmp/project"))
        XCTAssertTrue(prompt.contains("list all swift files changed today"))
    }

    func testOnlyGenerateCommandPromptActionIsAvailable() {
        XCTAssertEqual(SpotlightComposeInlinePromptAction.allCases, [.generateCommand])
    }

    func testInlineResultProviderReturnsShortcutsAndPromptOnly() {
        let shortcuts = [
            TerminalShortcutDefinition(name: "Build API", command: "npm run build:api"),
            TerminalShortcutDefinition(name: "Build Web", command: "npm run build:web"),
            TerminalShortcutDefinition(name: "Serve", command: "npm run dev")
        ]

        let results = SpotlightComposeInlineResultProvider.results(
            query: "build",
            pathMatches: [],
            shortcuts: shortcuts,
            promptActions: SpotlightComposeInlinePromptAction.allCases,
            isRunningPromptAction: false
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(
            results.compactMap { result -> String? in
                guard case let .shortcut(shortcut) = result else { return nil }
                return shortcut.name
            },
            ["Build API", "Build Web"]
        )
        XCTAssertEqual(
            results.compactMap { result -> SpotlightComposeInlinePromptAction? in
                guard case let .promptAction(action, _, _) = result else { return nil }
                return action
            },
            [.generateCommand]
        )
    }

    func testInlineResultProviderPrefersShortcutMatchesAheadOfPaths() {
        let pathMatch = SpotlightComposePathSearchMatch(
            rootPath: "/tmp/project",
            relativePath: "Sources/BuildFeature.swift",
            absolutePath: "/tmp/project/Sources/BuildFeature.swift",
            isDirectory: false,
            indices: [0, 1, 2]
        )
        let shortcut = TerminalShortcutDefinition(name: "Build", command: "swift build")

        let results = SpotlightComposeInlineResultProvider.results(
            query: "build",
            pathMatches: [pathMatch],
            shortcuts: [shortcut],
            promptActions: SpotlightComposeInlinePromptAction.allCases,
            isRunningPromptAction: false
        )

        guard case let .shortcut(resultShortcut)? = results.first else {
            return XCTFail("Expected shortcut result first")
        }
        XCTAssertEqual(resultShortcut, shortcut)
    }

    func testInlineResultProviderSurfacesUpToFiftyPathMatches() {
        let pathMatches = (0..<60).map { index in
            SpotlightComposePathSearchMatch(
                rootPath: "/tmp/project",
                relativePath: "Sources/File\(index).swift",
                absolutePath: "/tmp/project/Sources/File\(index).swift",
                isDirectory: false,
                indices: [0]
            )
        }

        let results = SpotlightComposeInlineResultProvider.results(
            query: "file",
            pathMatches: pathMatches,
            shortcuts: [],
            promptActions: [],
            isRunningPromptAction: false
        )

        XCTAssertEqual(results.count, 50)
        XCTAssertEqual(
            results.compactMap { result -> SpotlightComposePathSearchMatch? in
                guard case let .path(match) = result else { return nil }
                return match
            }.count,
            50
        )
    }
}
