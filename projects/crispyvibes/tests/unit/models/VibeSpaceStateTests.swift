import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpaceStateTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-vibespace-unit")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testInitializationDeduplicatesAndTracksUnresolvedPaths() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing, existing, missing])
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [missing.standardizedFileURL.path])
        XCTAssertEqual(vibespace.focusedProjectID, vibespace.projects.first?.id)
        XCTAssertNotNil(vibespace.projectColorTagsByPath[existing.standardizedFileURL.path])
        XCTAssertNotNil(vibespace.projectColorTagsByPath[missing.standardizedFileURL.path])
    }

    func testConfigRoundTripRestoresFocusedProjectAndColorTags() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let vibespaceShortcut = TerminalShortcutDefinition(name: "Root", command: "pwd")
        let projectShortcut = TerminalShortcutDefinition(name: "Build", command: "npm run build")

        let config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Fixture",
            projectPaths: [existing.path],
            unresolvedProjectPaths: [missing.path],
            focusedProjectPath: existing.path,
            startupSettings: VibeSpaceStartupSettings(
                startupTerminalCount: 3,
                startupProfiles: [VibeSpaceTerminalStartupProfile(presetID: "claude", command: "")],
                focusTerminalOnProjectSwitch: false
            ),
            defaultTerminalShell: .bash,
            shortcuts: [vibespaceShortcut]
        )
        let projectConfigs: [String: ProjectConfigFile] = [
            existing.path: {
                var pc = ProjectConfigFile.empty(projectPath: existing.path)
                pc.colorTag = "#336699"
                pc.startupOverride = VibeSpaceProjectStartupOverride(
                    startupTerminalCount: 2,
                    startupProfiles: [
                        VibeSpaceTerminalStartupProfile(presetID: "kiro", command: ""),
                        VibeSpaceTerminalStartupProfile(presetID: nil, command: "npm run dev")
                    ]
                )
                pc.acpAgentOverrideID = "opencode"
                pc.terminalShellOverride = .zsh
                pc.shortcuts = [projectShortcut]
                return pc
            }(),
            missing.path: {
                var pc = ProjectConfigFile.empty(projectPath: missing.path)
                pc.colorTag = "#E5A01F"
                pc.startupOverride = VibeSpaceProjectStartupOverride(startupPresetID: nil, startupCommand: "npm run dev")
                pc.acpAgentOverrideID = "kiro"
                pc.terminalShellOverride = .bash
                return pc
            }()
        ]

        let vibespace = container.makeVibeSpaceState(config: config, projectConfigs: projectConfigs)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [missing.standardizedFileURL.path])
        XCTAssertEqual(vibespace.focusedProjectID, vibespace.projects.first?.id)
        XCTAssertNotNil(vibespace.projectColorTagsByPath[existing.standardizedFileURL.path])
        XCTAssertNotNil(vibespace.projectColorTagsByPath[missing.standardizedFileURL.path])
        XCTAssertNil(vibespace.projectColorTagsByPath["/bad/path"])
        XCTAssertEqual(vibespace.startupSettings.startupTerminalCount, 3)
        XCTAssertEqual(vibespace.startupSettings.profile(at: 0).presetID, "claude")
        XCTAssertFalse(vibespace.startupSettings.focusTerminalOnProjectSwitch)
        XCTAssertEqual(vibespace.startupOverride(for: existing.standardizedFileURL.path)?.startupPresetID, "kiro")
        XCTAssertEqual(vibespace.startupOverride(for: existing.standardizedFileURL.path)?.startupTerminalCount, 2)
        XCTAssertEqual(vibespace.startupOverride(for: existing.standardizedFileURL.path)?.profile(at: 1).command, "npm run dev")
        XCTAssertEqual(vibespace.startupOverride(for: missing.standardizedFileURL.path)?.startupCommand, "npm run dev")
        XCTAssertNil(vibespace.startupOverride(for: "/bad/path"))
        XCTAssertEqual(vibespace.acpAgentOverrideID(for: existing.standardizedFileURL.path), "opencode")
        XCTAssertEqual(vibespace.acpAgentOverrideID(for: missing.standardizedFileURL.path), "kiro")
        XCTAssertNil(vibespace.acpAgentOverrideID(for: "/bad/path"))
        XCTAssertEqual(vibespace.defaultTerminalShell, .bash)
        XCTAssertEqual(vibespace.terminalShellOverride(for: existing.standardizedFileURL.path), .zsh)
        XCTAssertEqual(vibespace.terminalShellOverride(for: missing.standardizedFileURL.path), .bash)
        XCTAssertNil(vibespace.terminalShellOverride(for: "/bad/path"))
        XCTAssertEqual(vibespace.vibespaceShortcuts, [vibespaceShortcut])
        XCTAssertEqual(vibespace.configFile.shortcuts, [vibespaceShortcut])
        XCTAssertEqual(vibespace.projectScopedShortcuts(forProjectPath: existing.path), [projectShortcut])
    }

    func testProjectScopedShortcutsNormalizePathsAndRemoveEmptyValues() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing])
        let shortcut = TerminalShortcutDefinition(name: "Build", command: "npm run build")
        let rawPath = existing.appendingPathComponent("..").appendingPathComponent("existing").path

        vibespace.setProjectScopedShortcuts([shortcut], forProjectPath: rawPath)

        XCTAssertEqual(vibespace.projectScopedShortcuts(forProjectPath: existing.path), [shortcut])
        XCTAssertEqual(vibespace.projectScopedShortcutsByPath[existing.standardizedFileURL.path], [shortcut])

        vibespace.setProjectScopedShortcuts([], forProjectPath: rawPath)

        XCTAssertTrue(vibespace.projectScopedShortcuts(forProjectPath: existing.path).isEmpty)
        XCTAssertNil(vibespace.projectScopedShortcutsByPath[existing.standardizedFileURL.path])
    }

    func testConfigWithoutStartupSettingsUsesDefaults() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [existing.path], unresolvedProjectPaths: [],
            focusedProjectPath: existing.path, startupSettings: .default, defaultTerminalShell: nil
        )
        let vibespace = container.makeVibeSpaceState(config: config)
        XCTAssertEqual(vibespace.startupSettings, .default)
    }

    func testEffectiveTerminalShellIgnoresPerProjectShellOverride() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing])
        vibespace.defaultTerminalShell = .bash
        vibespace.setTerminalShellOverride(.zsh, forProjectPath: existing.path)

        XCTAssertEqual(
            vibespace.effectiveTerminalShell(for: existing.standardizedFileURL.path, appDefault: .zsh),
            .bash
        )
    }

    func testConfigInitializerUsesProvidedExistingDirectorySet() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let excluded = tempRoot.appendingPathComponent("excluded", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)

        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [existing.path, excluded.path], unresolvedProjectPaths: [],
            focusedProjectPath: existing.path, startupSettings: .default, defaultTerminalShell: nil
        )
        let vibespace = container.makeVibeSpaceState(config: config, existingDirectoryPaths: [existing.standardizedFileURL.path])
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.projects.first?.rootURL.path, existing.standardizedFileURL.path)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [excluded.standardizedFileURL.path])
    }

    func testAddProjectsResolvesNewDirectoriesAndKeepsMissingPaths() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let recovered = tempRoot.appendingPathComponent("recovered", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing, missing])
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [missing.standardizedFileURL.path])

        let existingProjectID = try XCTUnwrap(vibespace.projects.first?.id)
        let customColor = ProjectColorTag(red: 0.24, green: 0.71, blue: 0.53)
        vibespace.setColorTag(customColor, for: existingProjectID)

        let matched = vibespace.addProjects(from: [existing])
        XCTAssertEqual(matched?.rootURL.path, existing.standardizedFileURL.path)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.projectColorTagsByPath[existing.standardizedFileURL.path], customColor)

        try FileManager.default.createDirectory(at: recovered, withIntermediateDirectories: true)
        let added = vibespace.addProjects(from: [recovered])
        XCTAssertEqual(added?.rootURL.path, recovered.standardizedFileURL.path)
        XCTAssertEqual(vibespace.projects.count, 2)
        XCTAssertNotNil(vibespace.projectColorTagsByPath[recovered.standardizedFileURL.path])

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        let recoveredSession = vibespace.addProjects(from: [missing])
        XCTAssertNil(recoveredSession)
        vibespace.reconcileProjectAvailability()
        XCTAssertEqual(vibespace.projects.count, 3)
        XCTAssertTrue(vibespace.unresolvedProjectPaths.isEmpty)
    }

    func testRemoveProjectUpdatesFocusAndPrunesColorTag() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [first, second])
        let firstID = vibespace.projects[0].id
        vibespace.setColorTag(ProjectColorTag(red: 0.2, green: 0.2, blue: 0.9), for: firstID)
        vibespace.setStartupOverride(
            VibeSpaceProjectStartupOverride(startupPresetID: "claude", startupCommand: ""),
            for: firstID
        )
        vibespace.setACPAgentOverrideID("kiro", forProjectPath: first.standardizedFileURL.path)
        let removedProject = vibespace.projects[0]
        removedProject.terminalViewModel.createTab(directoryURL: first, startImmediately: false)

        vibespace.removeProject(id: firstID)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.focusedProjectID, vibespace.projects.last?.id)
        XCTAssertNil(vibespace.projectColorTagsByPath[first.standardizedFileURL.path])
        XCTAssertNil(vibespace.startupOverride(for: first.standardizedFileURL.path))
        XCTAssertNil(vibespace.acpAgentOverrideID(for: first.standardizedFileURL.path))
        XCTAssertTrue(removedProject.terminalViewModel.tabs.isEmpty)
    }

    func testStackedProjectsExcludeFocusedProjectAndUpdateWithFocusChanges() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        let third = tempRoot.appendingPathComponent("third", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [first, second, third])

        XCTAssertEqual(vibespace.focusedProject?.rootURL.standardizedFileURL.path, first.standardizedFileURL.path)
        XCTAssertEqual(
            Set(vibespace.stackedProjects.map { $0.rootURL.standardizedFileURL.path }),
            Set([second.standardizedFileURL.path, third.standardizedFileURL.path])
        )

        vibespace.focusedProjectID = vibespace.projects[2].id

        XCTAssertEqual(vibespace.focusedProject?.rootURL.standardizedFileURL.path, third.standardizedFileURL.path)
        XCTAssertEqual(
            Set(vibespace.stackedProjects.map { $0.rootURL.standardizedFileURL.path }),
            Set([first.standardizedFileURL.path, second.standardizedFileURL.path])
        )
    }

    func testRemoveUnresolvedProjectPrunesAssociatedColorTag() throws {
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [], unresolvedProjectPaths: [missing.path],
            focusedProjectPath: nil, startupSettings: .default, defaultTerminalShell: nil
        )
        let projectConfigs: [String: ProjectConfigFile] = [
            missing.path: {
                var pc = ProjectConfigFile.empty(projectPath: missing.path)
                pc.colorTag = "#FF0000"
                pc.startupOverride = VibeSpaceProjectStartupOverride(startupPresetID: "kiro", startupCommand: "")
                return pc
            }()
        ]

        var vibespace = container.makeVibeSpaceState(config: config, projectConfigs: projectConfigs)
        XCTAssertNotNil(vibespace.projectColorTagsByPath[missing.standardizedFileURL.path])
        XCTAssertNotNil(vibespace.startupOverride(for: missing.standardizedFileURL.path))
        vibespace.removeUnresolvedProject(path: missing.path)
        XCTAssertTrue(vibespace.unresolvedProjectPaths.isEmpty)
        XCTAssertNil(vibespace.projectColorTagsByPath[missing.standardizedFileURL.path])
        XCTAssertNil(vibespace.startupOverride(for: missing.standardizedFileURL.path))
    }

    func testRelinkUnresolvedToExistingProjectMovesColorTag() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [existing.path], unresolvedProjectPaths: [missing.path],
            focusedProjectPath: nil, startupSettings: .default, defaultTerminalShell: nil
        )
        let projectConfigs: [String: ProjectConfigFile] = [
            missing.path: {
                var pc = ProjectConfigFile.empty(projectPath: missing.path)
                pc.colorTag = "#00AACC"
                pc.startupOverride = VibeSpaceProjectStartupOverride(startupPresetID: nil, startupCommand: "npm run worker")
                return pc
            }()
        ]

        var vibespace = container.makeVibeSpaceState(config: config, projectConfigs: projectConfigs)
        let linked = vibespace.relinkUnresolvedProject(path: missing.path, to: existing)

        XCTAssertNotNil(linked)
        XCTAssertTrue(vibespace.unresolvedProjectPaths.isEmpty)
        XCTAssertNotNil(vibespace.projectColorTagsByPath[existing.standardizedFileURL.path])
        XCTAssertNil(vibespace.projectColorTagsByPath[missing.standardizedFileURL.path])
        XCTAssertEqual(vibespace.startupOverride(for: existing.standardizedFileURL.path)?.startupCommand, "npm run worker")
    }

    func testRelinkUnresolvedToMissingReplacementUpdatesTrackedPath() {
        let oldMissing = tempRoot.appendingPathComponent("old-missing", isDirectory: true)
        let newMissing = tempRoot.appendingPathComponent("new-missing", isDirectory: true)
        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [], unresolvedProjectPaths: [oldMissing.path],
            focusedProjectPath: nil, startupSettings: .default, defaultTerminalShell: nil
        )

        var vibespace = container.makeVibeSpaceState(config: config)
        let linked = vibespace.relinkUnresolvedProject(path: oldMissing.path, to: newMissing)
        XCTAssertNil(linked)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [newMissing.standardizedFileURL.path])
    }
}
