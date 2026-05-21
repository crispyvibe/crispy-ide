import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class RemoteProjectSessionMemoryTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-remote-memory")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container = nil
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testRemoteTerminalSessionDeallocatesAfterCloseTab() throws {
        let session = makeSession()
        let terminal = try XCTUnwrap(session.terminal as? TerminalViewModel)
        let tab = try XCTUnwrap(terminal.activeTab)
        weak var weakSession = terminal.session(for: tab.id)

        XCTAssertNotNil(weakSession)

        terminal.closeTab(tab)

        XCTAssertNil(weakSession, "Remote TerminalSession should deallocate after tab close")
    }

    func testRemoteTerminalViewModelDeallocatesAfterShutdownAndRelease() {
        var session: RemoteProjectSession? = makeSession()
        weak var weakTerminalViewModel = session?.terminal as? TerminalViewModel

        session?.shutdown()
        session = nil

        XCTAssertNil(
            weakTerminalViewModel,
            "Remote TerminalViewModel should deallocate after shutdown and release"
        )
    }

    private func makeSession() -> RemoteProjectSession {
        RemoteProjectSession(
            connection: SSHConnection(profile: makeProfile()),
            remotePath: "/srv/app",
            terminalViewModelFactory: container.makeTerminalViewModel
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
}
