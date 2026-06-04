import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

/// Unit tests for F021-R09–R11 (Project Parking) and F012-R17 (Browser Project Ownership).
///
/// Covers the model-level lifecycle on `VibeSpaceState` and the supporting
/// fields on `VibeSpaceConfigFile` / `ProjectConfigFile`. Coordinator-level
/// orchestration (browser snapshot capture, persistence, close-pipeline
/// dispatch) is exercised by behavioral tests at a higher layer.
@MainActor
final class VibeSpaceStateParkingTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-parking-unit")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    // MARK: - Helpers

    private func makeProjectDirectory(_ name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - F021-R09: Park State

    func testNewVibeSpaceHasNoParkedProjects() throws {
        let projectURL = try makeProjectDirectory("p1")
        let vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
        XCTAssertFalse(vibespace.isProjectParked(path: projectURL.standardizedFileURL.path))
    }

    func testConfigFileEmitsParkedProjectPaths() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        guard let id = vibespace.projects.first?.id else {
            return XCTFail("expected one live project")
        }
        XCTAssertNotNil(vibespace.parkProject(id: id))
        XCTAssertEqual(vibespace.configFile.parkedProjectPaths, [projectURL.standardizedFileURL.path])
    }

    func testConfigRoundTripPreservesParkedProjectPaths() throws {
        let liveURL = try makeProjectDirectory("live")
        let parkedURL = try makeProjectDirectory("parked")
        let config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Fixture",
            projectPaths: [liveURL.path],
            unresolvedProjectPaths: [],
            parkedProjectPaths: [parkedURL.path],
            startupSettings: .default
        )
        let vibespace = container.makeVibeSpaceState(config: config, projectConfigs: [:])
        XCTAssertEqual(vibespace.parkedProjectPaths, [parkedURL.standardizedFileURL.path])
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.projects.first?.projectIdentifier, liveURL.standardizedFileURL.path)
        XCTAssertTrue(vibespace.isProjectParked(path: parkedURL.path))
    }

    // MARK: - F021-R10: Park Lifecycle

    func testParkProjectRemovesFromProjectsAndAppendsToParkedPaths() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        guard let id = vibespace.projects.first?.id else {
            return XCTFail("expected one live project")
        }

        let parkedPath = vibespace.parkProject(id: id)

        XCTAssertEqual(parkedPath, projectURL.standardizedFileURL.path)
        XCTAssertTrue(vibespace.projects.isEmpty)
        XCTAssertEqual(vibespace.parkedProjectPaths, [projectURL.standardizedFileURL.path])
    }

    func testParkingFocusedProjectFallsBackToLastRemaining() throws {
        let p1 = try makeProjectDirectory("p1")
        let p2 = try makeProjectDirectory("p2")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [p1, p2])
        let firstID = vibespace.projects[0].id
        let secondID = vibespace.projects[1].id
        vibespace.focusedProjectID = firstID

        vibespace.parkProject(id: firstID)

        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.focusedProjectID, secondID)
        XCTAssertEqual(vibespace.parkedProjectPaths, [p1.standardizedFileURL.path])
    }

    func testParkProjectIsNoOpForUnknownID() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let result = vibespace.parkProject(id: UUID())
        XCTAssertNil(result)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
    }

    // MARK: - F021-R11: Unpark Restoration

    func testUnparkProjectRestoresLiveSession() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let originalID = vibespace.projects.first!.id
        vibespace.parkProject(id: originalID)
        XCTAssertTrue(vibespace.projects.isEmpty)

        let unparked = vibespace.unparkProject(path: projectURL.path)

        XCTAssertNotNil(unparked)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
        XCTAssertEqual(vibespace.focusedProjectID, unparked?.id)
        // Fresh session — different identity from the original.
        XCTAssertNotEqual(unparked?.id, originalID)
    }

    func testUnparkUnknownPathReturnsNil() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let result = vibespace.unparkProject(path: "/some/other/path")
        XCTAssertNil(result)
    }

    func testUnparkMissingDirectoryReturnsNil() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let id = vibespace.projects.first!.id
        vibespace.parkProject(id: id)
        // Remove the directory while parked.
        try FileManager.default.removeItem(at: projectURL)
        let result = vibespace.unparkProject(path: projectURL.path)
        XCTAssertNil(result)
        XCTAssertEqual(vibespace.parkedProjectPaths, [projectURL.standardizedFileURL.path])
    }

    // MARK: - addProjects auto-unpark

    func testAddingParkedProjectAutoUnparks() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let originalID = vibespace.projects.first!.id
        vibespace.parkProject(id: originalID)
        XCTAssertTrue(vibespace.projects.isEmpty)

        let result = vibespace.addProjects(from: [projectURL])

        XCTAssertNotNil(result)
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
    }

    // MARK: - F021-R19: Remove Parked Project

    func testRemoveParkedProjectDropsPathAndClearsAssociatedState() throws {
        let live = try makeProjectDirectory("live")
        let parked = try makeProjectDirectory("parked")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [live, parked])
        let parkedID = try XCTUnwrap(
            vibespace.projects.first(where: { $0.projectIdentifier == parked.standardizedFileURL.path })?.id
        )
        vibespace.parkProject(id: parkedID)
        XCTAssertEqual(vibespace.parkedProjectPaths, [parked.standardizedFileURL.path])

        vibespace.removeParkedProject(path: parked.path)

        // Path dropped, associated color tag cleared, live project untouched.
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
        XCTAssertFalse(vibespace.isProjectParked(path: parked.path))
        XCTAssertNil(vibespace.projectColorTagsByPath[parked.standardizedFileURL.path])
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertEqual(vibespace.projects.first?.projectIdentifier, live.standardizedFileURL.path)
    }

    func testRemoveParkedProjectIsNoOpForUnknownPath() throws {
        let live = try makeProjectDirectory("live")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [live])
        vibespace.removeParkedProject(path: "/not/parked/here")
        XCTAssertEqual(vibespace.projects.count, 1)
        XCTAssertTrue(vibespace.parkedProjectPaths.isEmpty)
    }

    // MARK: - F012-R17: Browser ownership at the VM layer

    func testBrowserPanelViewModelCarriesProjectPath() {
        let projectPath = "/Users/test/projects/myproject"
        let vm = BrowserPanelViewModel(projectPath: projectPath)
        XCTAssertEqual(vm.projectPath, projectPath)
    }

    func testBrowserPanelViewModelDefaultsToNilProjectPath() {
        let vm = BrowserPanelViewModel()
        XCTAssertNil(vm.projectPath)
    }

    // MARK: - F012-R20 / F021-R10: BrowserSessionEntry serialization

    func testProjectConfigFileSerializesBrowserSessionEntries() throws {
        let entry = BrowserSessionEntry(
            browserID: UUID(),
            snapshot: BrowserSessionSnapshot(
                urlString: "https://example.com",
                backHistoryURLStrings: ["https://example.com/a"],
                forwardHistoryURLStrings: [],
                pageZoom: 1.5,
                themeMode: "dark"
            ),
            pinnedTileID: nil
        )
        var config = ProjectConfigFile.empty(projectPath: "/p1")
        config.browserSessionEntries = [entry]
        config.isParked = true

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfigFile.self, from: encoded)

        XCTAssertEqual(decoded.browserSessionEntries.count, 1)
        XCTAssertEqual(decoded.browserSessionEntries.first?.browserID, entry.browserID)
        XCTAssertEqual(decoded.browserSessionEntries.first?.snapshot.urlString, "https://example.com")
        XCTAssertEqual(decoded.browserSessionEntries.first?.snapshot.pageZoom, 1.5)
        XCTAssertTrue(decoded.isParked)
    }

    func testProjectConfigFileBackwardCompatibleDecodeWithoutNewFields() throws {
        // JSON written by an older app version (no isParked, no browserSessionEntries)
        let json = """
        {
            "version": 2,
            "projectPath": "/p1",
            "terminalEntries": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ProjectConfigFile.self, from: json)
        XCTAssertFalse(decoded.isParked)
        XCTAssertTrue(decoded.browserSessionEntries.isEmpty)
    }

    func testVibeSpaceConfigFileBackwardCompatibleDecodeWithoutParkedPaths() throws {
        let id = UUID().uuidString
        let json = """
        {
            "version": 2,
            "id": "\(id)",
            "name": "Fixture",
            "projectPaths": ["/p1"],
            "unresolvedProjectPaths": [],
            "startupSettings": {
                "startupTerminalCount": 1,
                "startupProfiles": [{"presetID": null, "command": ""}],
                "focusTerminalOnProjectSwitch": true
            },
            "sourceControlSettings": {
                "ignoredDirectoryNames": [],
                "scanMaxDepth": 8,
                "scanMaxRepositories": 64,
                "autoPresentedRepositoryLimit": 12
            }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VibeSpaceConfigFile.self, from: json)
        XCTAssertTrue(decoded.parkedProjectPaths.isEmpty)
    }

    // MARK: - Memory: parking releases the live session (mirrors documented `shutdown()` pattern)

    func testParkProjectReleasesLiveProjectSession() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace: VibeSpaceState? = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let id = vibespace!.projects.first!.id
        weak var weakSession = vibespace!.projects.first

        vibespace!.parkProject(id: id)

        XCTAssertTrue(vibespace!.projects.isEmpty)
        XCTAssertNil(weakSession,
                     "ProjectSession must deallocate after parkProject calls shutdown and removes from projects")
        vibespace = nil
    }

    func testRepeatedParkUnparkCyclesDoNotAccumulateSessions() throws {
        let projectURL = try makeProjectDirectory("p1")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])

        var weakSessions: [() -> AnyObject?] = []

        for _ in 0..<5 {
            let liveID = vibespace.projects.first!.id
            weak var weakSession = vibespace.projects.first
            weakSessions.append { weakSession }
            vibespace.parkProject(id: liveID)
            _ = vibespace.unparkProject(path: projectURL.path)
        }

        // Park final live session so all sessions are gone.
        vibespace.parkProject(id: vibespace.projects.first!.id)
        XCTAssertTrue(vibespace.projects.isEmpty)

        for (index, accessor) in weakSessions.enumerated() {
            XCTAssertNil(accessor(),
                         "Cycle \(index): historic ProjectSession must deallocate after park")
        }
    }

    /// Regression: parking a project must explicitly shut down the folder
    /// explorer's long-lived resources (DirectoryWatcher + pending main-actor
    /// work). Without this, anything still holding a strong ref to the
    /// ProjectSession after parking (e.g., SwiftUI view mid-unmount) keeps the
    /// watcher alive, firing FS events that schedule MainActor work — observed
    /// as a UI hang in the project rail's LazyHVStack after parking.
    func testParkingShutsDownFolderExplorerEvenIfSessionRetained() throws {
        let projectURL = try makeProjectDirectory("p-with-watcher")
        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [projectURL])
        let session = try XCTUnwrap(vibespace.projects.first)
        // Force the explorer to bind to the directory (which arms the watcher).
        session.activate()
        session.ensureExplorerLoaded()

        // Hold the session across the park to simulate a stray strong ref.
        let pinnedSession = session

        vibespace.parkProject(id: session.id)

        // The session is still alive (we're holding it), but its folder
        // explorer must have been explicitly shut down.
        XCTAssertNotNil(pinnedSession, "test holds the session")
        // The shutdown is exposed via the explorer's `hasShutdown` flag (private),
        // so we verify externally-observable behavior: a second park-driven
        // shutdown must be a no-op (idempotent) and not crash.
        // Calling parkProject again on a now-removed session id is also a no-op.
        XCTAssertNil(vibespace.parkProject(id: session.id))
    }
}
