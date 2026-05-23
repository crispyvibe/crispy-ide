import Foundation
import XCTest
@testable import CrispyVibes

/// F044-R04: verifies `ProjectSession` stamps its vibespace ID onto every
/// terminal session its `TerminalViewModel` creates, so spawned shells get
/// `CRISPY_VIBESPACE=vibespace.<uuid>` in their env. The previous
/// implementation declared the env var in the F044 spec and exposed it on
/// `CLIChannelClientEnv` / the Rust client, but the Swift launch path never
/// set it — so `_env.vibespace` was always nil.
@MainActor
final class TerminalSessionVibeSpaceIDInjectionTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-vibespace-env")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testProjectSessionStampsVibeSpaceIDOnNewTerminalSessions() throws {
        let projectURL = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let vibespaceID = UUID()
        let layoutPersistence = container.layoutPersistence
        var dependencies = ProjectSessionDependencies(
            layoutPersistence: layoutPersistence,
            vibespaceManagement: container.vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: container.detachedWindowManager
        )
        dependencies.vibespaceID = vibespaceID
        let project = ProjectSession(rootURL: projectURL, dependencies: dependencies)

        // Activate to trigger wireViewModels which installs the configurator.
        project.activateIfNeeded()

        // Drive a terminal session creation through the view model — its
        // `sessionConfigurator` should stamp the vibespace ID on the session.
        project.terminalViewModel.createTab(directoryURL: projectURL, startImmediately: false)
        let session = try XCTUnwrap(project.terminalViewModel.activeTab.flatMap {
            project.terminalViewModel.session(for: $0.id)
        }) as? TerminalSession

        XCTAssertEqual(session?.vibespaceID, vibespaceID,
                       "ProjectSession must stamp its vibespace ID on terminal sessions")

        project.shutdown()
    }

    func testTerminalSessionWithoutVibeSpaceIDIsNil() throws {
        // A standalone session not owned by a ProjectSession should have nil
        // vibespaceID — the env var is omitted in startProcessAsync.
        let viewModel = container.makeTerminalViewModel()
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let session = try XCTUnwrap(viewModel.activeTab.flatMap {
            viewModel.session(for: $0.id)
        }) as? TerminalSession
        XCTAssertNil(session?.vibespaceID)
        viewModel.shutdown()
    }

    func testProjectSessionConfiguratorComposesWithExisting() throws {
        // If callers attach their own `sessionConfigurator` BEFORE wireViewModels
        // runs (rare, but possible), our wiring must compose, not overwrite.
        let projectURL = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let vibespaceID = UUID()
        var dependencies = ProjectSessionDependencies(
            layoutPersistence: container.layoutPersistence,
            vibespaceManagement: container.vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: container.detachedWindowManager
        )
        dependencies.vibespaceID = vibespaceID
        let project = ProjectSession(rootURL: projectURL, dependencies: dependencies)

        // Pre-install a configurator that records the session's tmux name.
        var preConfiguratorCalled = false
        project.terminalViewModel.sessionConfigurator = { session in
            preConfiguratorCalled = true
            session.tmuxSessionName = "preset-tmux"
        }

        project.activateIfNeeded()
        project.terminalViewModel.createTab(directoryURL: projectURL, startImmediately: false)
        let session = try XCTUnwrap(project.terminalViewModel.activeTab.flatMap {
            project.terminalViewModel.session(for: $0.id)
        }) as? TerminalSession

        XCTAssertTrue(preConfiguratorCalled, "pre-existing configurator must still run")
        XCTAssertEqual(session?.vibespaceID, vibespaceID,
                       "vibespace ID must be set even when composing with another configurator")
        XCTAssertEqual(session?.tmuxSessionName, "preset-tmux",
                       "pre-existing configurator's mutations must survive composition")

        project.shutdown()
    }
}
