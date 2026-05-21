import AppKit
import Combine
import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalViewModelTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!
    var viewModel: TerminalViewModel!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-terminal-vm")
        container = AppContainer.makeDefault()
        container.terminalViewModelDependencies.shortcutStore.save([])
        viewModel = container.makeTerminalViewModel()
    }

    override func tearDownWithError() throws {
        if let viewModel {
            for tab in viewModel.tabs {
                viewModel.closeTab(tab)
            }
        }
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container?.terminalViewModelDependencies.shortcutStore.save([])
        container = nil
    }

    func testCreateAndCloseTab() throws {
        viewModel.createTab(directoryURL: tempRoot, customName: "Custom", startImmediately: false)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTab?.customName, "Custom")
        XCTAssertEqual(viewModel.activeTab?.workingDirectory.path, tempRoot.standardizedFileURL.path)

        let tab = try XCTUnwrap(viewModel.activeTab)
        viewModel.closeTab(tab)
        XCTAssertTrue(viewModel.tabs.isEmpty)
        XCTAssertNil(viewModel.activeTabID)
    }

    func testCreateTabPublishesSingleViewInvalidation() {
        var changeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)

        XCTAssertEqual(changeCount, 1)
    }

    func testCloseTabRemovesSessionAndActivityState() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        let closingTab = try XCTUnwrap(viewModel.tabs.first)

        XCTAssertNotNil(viewModel.sessions[closingTab.id])
        XCTAssertNotNil(viewModel.tabActivityState(for: closingTab.id))

        viewModel.closeTab(closingTab)

        XCTAssertNil(viewModel.sessions[closingTab.id])
        XCTAssertNil(viewModel.tabActivityState(for: closingTab.id))
        XCTAssertEqual(viewModel.sessions.count, viewModel.tabs.count)
    }

    func testRestoreTabsPrunesPreviousSessionEntries() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        let previousTabIDs = Set(viewModel.tabs.map(\.id))

        viewModel.restoreTabs(
            directories: [tempRoot],
            activeDirectory: tempRoot,
            defaultDirectory: tempRoot
        )

        let currentTabIDs = Set(viewModel.tabs.map(\.id))
        XCTAssertEqual(viewModel.sessions.count, viewModel.tabs.count)
        XCTAssertEqual(viewModel.tabActivityStates.count, viewModel.tabs.count)

        for staleTabID in previousTabIDs.subtracting(currentTabIDs) {
            XCTAssertNil(viewModel.sessions[staleTabID])
            XCTAssertNil(viewModel.tabActivityState(for: staleTabID))
        }
    }

    func testRestoreTabsPublishesSingleViewInvalidationForBulkRestore() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)

        var changeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        viewModel.restoreTabs(
            directories: [first, second],
            activeDirectory: second,
            defaultDirectory: first
        )

        XCTAssertEqual(changeCount, 1)
    }

    func testShutdownClearsTabsSessionsAndActivityState() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        XCTAssertEqual(viewModel.sessions.count, 2)
        XCTAssertEqual(viewModel.tabActivityStates.count, 2)

        viewModel.shutdown()

        XCTAssertTrue(viewModel.tabs.isEmpty)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(viewModel.tabActivityStates.isEmpty)
        XCTAssertNil(viewModel.activeTabID)
    }

    func testCreateUserTabUsesProvidedDefaultDirectoryWhenNoActiveTabExists() {
        XCTAssertTrue(viewModel.tabs.isEmpty)

        let createdTabID = viewModel.createUserTab(defaultDirectory: tempRoot)

        XCTAssertNotNil(createdTabID)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTabID, createdTabID)
        XCTAssertEqual(viewModel.activeTab?.workingDirectory.path, tempRoot.standardizedFileURL.path)
    }

    func testCreateUserTabUsesActiveTabWorkingDirectory() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        viewModel.createTab(directoryURL: first, startImmediately: false)

        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let createdTabID = viewModel.createUserTab(defaultDirectory: second)

        XCTAssertNotNil(createdTabID)
        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertEqual(viewModel.activeTabID, createdTabID)
        XCTAssertEqual(viewModel.activeTab?.workingDirectory.path, first.standardizedFileURL.path)
    }

    func testOpenOrSelectTabAvoidsDuplicates() {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let originalTabID = viewModel.activeTabID

        viewModel.openOrSelectTab(for: tempRoot)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTabID, originalTabID)
    }

    func testMoveTabReordersTabsWithoutChangingActiveSelection() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        let third = tempRoot.appendingPathComponent("third", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, customName: "First", startImmediately: false)
        viewModel.createTab(directoryURL: second, customName: "Second", startImmediately: false)
        viewModel.createTab(directoryURL: third, customName: "Third", startImmediately: false)
        let activeTabID = try XCTUnwrap(viewModel.activeTabID)
        let firstTabID = try XCTUnwrap(viewModel.tabs.first(where: { $0.customName == "First" })?.id)
        let thirdTabID = try XCTUnwrap(viewModel.tabs.first(where: { $0.customName == "Third" })?.id)

        viewModel.moveTab(firstTabID, relativeTo: thirdTabID, placement: .after)

        XCTAssertEqual(viewModel.tabs.map(\.customName), ["Second", "Third", "First"])
        XCTAssertEqual(viewModel.activeTabID, activeTabID)

        let secondTabID = try XCTUnwrap(viewModel.tabs.first(where: { $0.customName == "Second" })?.id)
        viewModel.moveTab(firstTabID, relativeTo: secondTabID, placement: .before)

        XCTAssertEqual(viewModel.tabs.map(\.customName), ["First", "Second", "Third"])
        XCTAssertEqual(viewModel.activeTabID, activeTabID)
    }

    func testRestoreTabsDeduplicatesAndSelectsActiveDirectory() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.restoreTabs(
            directories: [first, first, second],
            activeDirectory: second,
            defaultDirectory: first
        )

        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertEqual(viewModel.activeTab?.workingDirectory.path, second.standardizedFileURL.path)
    }

    func testRestoreTabsFromEntriesPreservesMultipleTabsForSameDirectoryWhenTmuxSessionsDiffer() {
        let entries = [
            TerminalSessionEntry(
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: "Main",
                origin: .adHoc,
                tmuxSessionName: "crispyvibes-main"
            ),
            TerminalSessionEntry(
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: "Logs",
                origin: .adHoc,
                tmuxSessionName: "crispyvibes-logs"
            )
        ]

        viewModel.restoreTabsFromEntries(
            entries,
            activeDirectory: tempRoot,
            activeIdentity: nil,
            defaultDirectory: tempRoot
        )

        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertEqual(viewModel.tabs.map(\.customName), ["Main", "Logs"])
        XCTAssertEqual(
            viewModel.tabs.compactMap { viewModel.session(for: $0.id)?.tmuxSessionName },
            ["crispyvibes-main", "crispyvibes-logs"]
        )
    }

    func testRestoreTabsFromEntriesPreservesPersistedTabIDsForDuplicateEntries() {
        let firstID = UUID()
        let secondID = UUID()
        let entries = [
            TerminalSessionEntry(
                id: firstID,
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: nil,
                origin: .adHoc,
                tmuxSessionName: nil
            ),
            TerminalSessionEntry(
                id: secondID,
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: nil,
                origin: .adHoc,
                tmuxSessionName: nil
            )
        ]

        viewModel.restoreTabsFromEntries(
            entries,
            activeDirectory: tempRoot,
            activeIdentity: TerminalViewModel.persistenceIdentity(tabID: secondID),
            defaultDirectory: tempRoot
        )

        XCTAssertEqual(viewModel.tabs.map(\.id), [firstID, secondID])
        XCTAssertEqual(viewModel.activeTabID, secondID)
    }

    func testTerminalSessionSnapshotPersistsTabIDsAndActiveTabIdentity() throws {
        viewModel.createTab(directoryURL: tempRoot, customName: "First", startImmediately: false)
        let firstID = try XCTUnwrap(viewModel.activeTabID)
        viewModel.createTab(directoryURL: tempRoot, customName: "Second", startImmediately: false)
        let secondID = try XCTUnwrap(viewModel.activeTabID)

        viewModel.selectTab(try XCTUnwrap(viewModel.tabs.first(where: { $0.id == firstID })))

        let snapshot = ProjectTerminalSessionPersistence.snapshot(from: viewModel)

        XCTAssertEqual(snapshot.terminalEntries.map(\.id), [firstID, secondID])
        XCTAssertEqual(snapshot.activeTerminalIdentity, TerminalViewModel.persistenceIdentity(tabID: firstID))
    }

    func testRestoreTabsFromEntriesPrefersPersistedActiveIdentityOverDirectoryMatch() {
        let entries = [
            TerminalSessionEntry(
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: "Main",
                origin: .adHoc,
                tmuxSessionName: "crispyvibes-main"
            ),
            TerminalSessionEntry(
                workingDirectoryPath: tempRoot.standardizedFileURL.path,
                customName: "Logs",
                origin: .adHoc,
                tmuxSessionName: "crispyvibes-logs"
            )
        ]
        let activeIdentity = TerminalViewModel.persistenceIdentity(
            workingDirectoryPath: tempRoot.standardizedFileURL.path,
            customName: "Logs",
            origin: .adHoc,
            tmuxSessionName: "crispyvibes-logs"
        )

        viewModel.restoreTabsFromEntries(
            entries,
            activeDirectory: tempRoot,
            activeIdentity: activeIdentity,
            defaultDirectory: tempRoot
        )

        XCTAssertEqual(viewModel.activeTab?.customName, "Logs")
    }

    func testEnsureActiveTerminalCreatesDefaultTabWhenEmpty() {
        XCTAssertTrue(viewModel.tabs.isEmpty)
        viewModel.ensureActiveTerminal(defaultDirectory: tempRoot, transitionID: "unit-test")
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertNotNil(viewModel.activeTabID)
    }

    func testCreateTabLetsSessionConfiguratorSetTmuxNameBeforeDefaultGeneration() throws {
        try withUserDefaultsSnapshot(keys: [AppPreferences.experimentalTmuxIntegrationKey]) {
            UserDefaults.standard.set(true, forKey: AppPreferences.experimentalTmuxIntegrationKey)

            viewModel.sessionConfigurator = { session in
                session.tmuxSessionName = "remote-stable-session"
            }

            viewModel.createTab(directoryURL: tempRoot, startImmediately: false)

            let activeTab = try XCTUnwrap(viewModel.activeTab)
            XCTAssertEqual(
                viewModel.session(for: activeTab.id)?.tmuxSessionName,
                "remote-stable-session"
            )
        }
    }

    func testEnsureTerminalCountAddsTabsUpToRequestedMinimum() {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        viewModel.ensureTerminalCount(3, defaultDirectory: tempRoot)

        XCTAssertEqual(viewModel.tabs.count, 3)
        XCTAssertEqual(
            Set(viewModel.tabs.map { $0.workingDirectory.standardizedFileURL.path }),
            [tempRoot.standardizedFileURL.path]
        )
    }

    func testRunStartupCommandOnPrimaryTabSelectsPrimaryAndSetsCustomName() {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try? FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        let primaryTabID = viewModel.tabs.first?.id

        viewModel.runStartupCommandOnPrimaryTab(
            "echo boot",
            customName: "Kiro",
            defaultDirectory: tempRoot
        )

        XCTAssertEqual(viewModel.activeTabID, primaryTabID)
        XCTAssertEqual(viewModel.tabs.first?.customName, "Kiro")
    }

    func testRunStartupCommandOnTabTargetsSpecifiedTabWithoutStealingFocus() {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try? FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        let initialActiveTabID = viewModel.tabs.first?.id
        viewModel.activeTabID = initialActiveTabID

        viewModel.runStartupCommandOnTab(
            "echo worker",
            customName: "Worker",
            tabIndex: 1,
            defaultDirectory: tempRoot,
            activateTab: false
        )

        XCTAssertEqual(viewModel.activeTabID, initialActiveTabID)
        XCTAssertEqual(viewModel.tabs[1].customName, "Worker")
    }

    func testLaunchPresetRejectsUnsupportedFullTrustMode() {
        let preset = TerminalPresetDefinition(
            id: "simple",
            title: "Simple",
            shortLabel: "Simple",
            symbolName: "terminal",
            defaultCommand: "echo hello",
            fullTrustCommand: nil
        )

        viewModel.launchPreset(preset, mode: .fullTrust, directoryURL: tempRoot)
        XCTAssertEqual(viewModel.tabs.count, 0)
        XCTAssertTrue((viewModel.errorMessage ?? "").contains("does not define a full-trust launch mode"))
    }

    func testLaunchPresetSendsCommandToTerminalEvenWhenExecutableNotResolvableInGuiPath() throws {
        // Preset commands are dispatched to the user's interactive shell inside
        // the terminal. The GUI app's PATH does not source `.zshrc`/`.bash_profile`
        // and misses tools installed via Volta, Bun, npm-prefix, asdf, mise, nvm,
        // fnm, pnpm, cargo, etc. Crispy must not block dispatch on a PATH check
        // that doesn't reflect the shell's view of the world.
        let missingCommand = "definitely-not-installed-\(UUID().uuidString)"
        let preset = TerminalPresetDefinition(
            id: "missing",
            title: "Missing",
            shortLabel: "Missing",
            symbolName: "terminal",
            defaultCommand: missingCommand
        )

        viewModel.launchPreset(preset, mode: .standard, directoryURL: tempRoot)

        XCTAssertNil(viewModel.errorMessage, "Expected no preflight 'not available on PATH' error.")
        XCTAssertEqual(viewModel.tabs.count, 1, "Expected a tab to be created so the shell can attempt the command.")
        let session = try XCTUnwrap(viewModel.activeTab.flatMap { viewModel.session(for: $0.id) })
        XCTAssertEqual(session.pendingCommands.map(\.text), [missingCommand],
                       "Expected the raw preset command to be queued unchanged for the shell to resolve.")
    }

    func testCommandPathResolverIncludesFallbackInstallDirectories() {
        let paths = CommandPathResolver.searchPaths(
            environment: [:],
            homeDirectory: "/tmp/crispyvibes-home"
        )

        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains("/usr/bin"))
        XCTAssertTrue(paths.contains("/tmp/crispyvibes-home/.local/bin"))
        XCTAssertTrue(paths.contains("/tmp/crispyvibes-home/bin"))
    }

    func testCommandPathResolverDeduplicatesAndKeepsConfiguredPathFirst() {
        let paths = CommandPathResolver.searchPaths(
            environment: ["PATH": "/custom/bin:/usr/bin:/custom/bin:/bin"],
            homeDirectory: "/tmp/crispyvibes-home"
        )

        XCTAssertEqual(paths.first, "/custom/bin")
        XCTAssertEqual(paths.filter { $0 == "/custom/bin" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/bin" }.count, 1)
    }

    func testLaunchPresetSucceedsWhenExecutableExistsOnPath() throws {
        let binDirectory = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let executableURL = binDirectory.appendingPathComponent("fixturecmd")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPATH = ProcessInfo.processInfo.environment["PATH"]
        if let originalPATH {
            setenv("PATH", "\(binDirectory.path):\(originalPATH)", 1)
        } else {
            setenv("PATH", binDirectory.path, 1)
        }
        defer {
            if let originalPATH {
                setenv("PATH", originalPATH, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let preset = TerminalPresetDefinition(
            id: "fixture",
            title: "Fixture",
            shortLabel: "Fx",
            symbolName: "terminal",
            defaultCommand: "fixturecmd --arg"
        )

        viewModel.launchPreset(preset, mode: .standard, directoryURL: tempRoot)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTab?.customName, "Fx")
    }

    func testLaunchPresetSupportsAbsoluteExecutablePath() throws {
        let scriptURL = tempRoot.appendingPathComponent("absolute-tool")
        try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: scriptURL.path
        )

        let preset = TerminalPresetDefinition(
            id: "abs",
            title: "Absolute",
            shortLabel: "Abs",
            symbolName: "terminal",
            defaultCommand: "\(scriptURL.path) --check"
        )

        viewModel.launchPreset(preset, mode: .standard, directoryURL: tempRoot)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.activeTab?.customName, "Abs")
    }
}
