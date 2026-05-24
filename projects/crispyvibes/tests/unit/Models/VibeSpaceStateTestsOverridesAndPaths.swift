import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
extension VibeSpaceStateTests {
    func testRelinkUnresolvedRecoversProjectWhenPathReturns() throws {
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [], unresolvedProjectPaths: [missing.path],
            focusedProjectPath: nil, startupSettings: .default, defaultTerminalShell: nil
        )

        var vibespace = container.makeVibeSpaceState(config: config)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)

        let recovered = vibespace.relinkUnresolvedProject(path: missing.path, to: missing)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.rootURL.path, missing.standardizedFileURL.path)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.unresolvedProjectPaths.isEmpty)
    }

    func testReconcileProjectAvailabilityMovesMissingAndRecoversResolved() throws {
        let live = tempRoot.appendingPathComponent("live", isDirectory: true)
        let recovering = tempRoot.appendingPathComponent("recovering", isDirectory: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)

        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Fixture",
            projectPaths: [live.path, recovering.path], unresolvedProjectPaths: [],
            focusedProjectPath: live.path, startupSettings: .default, defaultTerminalShell: nil
        )
        var vibespace = container.makeVibeSpaceState(config: config)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.unresolvedProjectPaths, [recovering.standardizedFileURL.path])
        let removedProject = try XCTUnwrap(
            vibespace.projects.first(where: { $0.rootURL.path == live.standardizedFileURL.path })
        )
        removedProject.terminalViewModel.createTab(directoryURL: live, startImmediately: false)
        XCTAssertFalse(removedProject.terminalViewModel.sessions.isEmpty)

        try FileManager.default.createDirectory(at: recovering, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: live)

        vibespace.reconcileProjectAvailability()
        XCTAssertTrue(vibespace.projects.contains(where: { $0.rootURL.path == recovering.standardizedFileURL.path }))
        XCTAssertTrue(vibespace.unresolvedProjectPaths.contains(live.standardizedFileURL.path))
        XCTAssertTrue(removedProject.terminalViewModel.sessions.isEmpty)
        XCTAssertTrue(removedProject.terminalViewModel.tabs.isEmpty)
    }

    func testRenameTrimsWhitespaceAndRejectsEmptyValues() {
        var vibespace = container.makeVibeSpaceState(name: "Before", projectURLs: [])
        vibespace.rename("  After  ")
        XCTAssertEqual(vibespace.name, "After")

        vibespace.rename("   ")
        XCTAssertEqual(vibespace.name, "After")
    }

    func testSnapshotContainsProjectAndMissingPaths() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing, missing])
        let existingID = vibespace.projects[0].id
        vibespace.setColorTag(ProjectColorTag(red: 0.1, green: 0.2, blue: 0.3), for: existingID)
        vibespace.setStartupOverride(
            VibeSpaceProjectStartupOverride(
                startupPresetID: nil,
                startupCommand: "npm run dev"
            ),
            forProjectPath: missing.path
        )
        let config = vibespace.configFile

        XCTAssertEqual(config.projectPaths, [existing.standardizedFileURL.path])
        XCTAssertEqual(config.unresolvedProjectPaths, [missing.standardizedFileURL.path])
        XCTAssertEqual(config.name, "Fixture")
        XCTAssertNotNil(vibespace.projectColorTagsByPath[existing.standardizedFileURL.path])
        XCTAssertEqual(config.startupSettings, .default)
        XCTAssertEqual(
            vibespace.startupOverride(for: missing.standardizedFileURL.path)?.startupCommand,
            "npm run dev"
        )
    }

    func testProjectShortcutsAutoAssignAndPersist() throws {
        let alpha = tempRoot.appendingPathComponent("alpha", isDirectory: true)
        let beta = tempRoot.appendingPathComponent("beta", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)

        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [beta, alpha])
        XCTAssertEqual(vibespace.shortcutIndex(for: beta.path), 1)
        XCTAssertEqual(vibespace.shortcutIndex(for: alpha.path), 2)
    }

    func testMoveProjectsReordersVibeSpaceAndReindexesShortcutsByOrder() throws {
        let alpha = tempRoot.appendingPathComponent("alpha", isDirectory: true)
        let beta = tempRoot.appendingPathComponent("beta", isDirectory: true)
        let gamma = tempRoot.appendingPathComponent("gamma", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gamma, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [alpha, beta, gamma])
        vibespace.moveProjects(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(
            vibespace.projects.map { $0.rootURL.path },
            [gamma.standardizedFileURL.path, alpha.standardizedFileURL.path, beta.standardizedFileURL.path]
        )
        XCTAssertEqual(vibespace.shortcutIndex(for: gamma.path), 1)
        XCTAssertEqual(vibespace.shortcutIndex(for: alpha.path), 2)
        XCTAssertEqual(vibespace.shortcutIndex(for: beta.path), 3)
    }

    func testSetShortcutReassignsConflictingSlot() throws {
        let alpha = tempRoot.appendingPathComponent("alpha", isDirectory: true)
        let beta = tempRoot.appendingPathComponent("beta", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [alpha, beta])
        vibespace.setShortcut(2, forProjectPath: alpha.path)

        XCTAssertEqual(vibespace.shortcutIndex(for: alpha.path), 2)
        XCTAssertNotEqual(vibespace.shortcutIndex(for: beta.path), 2)
    }

    func testSetStartupOverrideByProjectPathStoresAndClearsEntry() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing])

        vibespace.setStartupOverride(
            VibeSpaceProjectStartupOverride(startupPresetID: "codex", startupCommand: ""),
            forProjectPath: existing.path
        )
        XCTAssertEqual(vibespace.startupOverride(for: existing.path)?.startupPresetID, "codex")

        vibespace.setStartupOverride(nil, forProjectPath: existing.path)
        XCTAssertNil(vibespace.startupOverride(for: existing.path))
    }

    func testSetTerminalShellOverrideByProjectPathStoresAndClearsEntry() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing])

        vibespace.setTerminalShellOverride(.bash, forProjectPath: existing.path)
        XCTAssertEqual(vibespace.terminalShellOverride(for: existing.path), .bash)

        vibespace.setTerminalShellOverride(nil, forProjectPath: existing.path)
        XCTAssertNil(vibespace.terminalShellOverride(for: existing.path))
    }

    func testEffectiveTerminalShellUsesVibeSpaceThenAppDefaults() throws {
        let existing = tempRoot.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [existing])
        let path = existing.standardizedFileURL.path

        XCTAssertEqual(vibespace.effectiveTerminalShell(for: path, appDefault: .zsh), .zsh)

        vibespace.defaultTerminalShell = .bash
        XCTAssertEqual(vibespace.effectiveTerminalShell(for: path, appDefault: .zsh), .bash)

        vibespace.setTerminalShellOverride(.zsh, forProjectPath: path)
        XCTAssertEqual(vibespace.effectiveTerminalShell(for: path, appDefault: .bash), .bash)
    }

    func testNormalizedPathHandlesEscapedSeparators() {
        let raw = "\(tempRoot.path)/alpha\\/beta/../gamma"
        let expected = URL(fileURLWithPath: "\(tempRoot.path)/alpha/beta/../gamma").standardizedFileURL.path
        XCTAssertEqual(VibeSpaceState.normalizedPath(from: raw), expected)
    }
}
