import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpaceSidebarSessionBrowserTests: XCTestCase {
    private func makeProfile(
        displayName: String = "Prod",
        host: String = "example.com",
        port: UInt16 = 22,
        user: String = "alice",
        authMethod: SSHConnectionProfile.SSHAuthMethod = .agent,
        importedFromConfig: Bool = false
    ) -> SSHConnectionProfile {
        SSHConnectionProfile(
            id: UUID(),
            displayName: displayName,
            host: host,
            port: port,
            user: user,
            authMethod: authMethod,
            importedFromConfig: importedFromConfig
        )
    }

    func testParsePaneCommandsPrefersActivePaneCommandForSession() {
        let output = """
        build\t0\tnpm run dev
        build\t1\tvite
        shell\t0\tzsh
        """

        let commands = VibeSpaceSidebarSessionBrowser.parsePaneCommands(output)

        XCTAssertEqual(commands["build"], "vite")
        XCTAssertEqual(commands["shell"], "zsh")
    }

    func testParseFallbackRemoteSessionsReturnsVisibleRemoteSessions() {
        let profile = makeProfile()
        let output = """
        build\t1
        shell\t0
        """

        let sessions = VibeSpaceSidebarSessionBrowser.parseFallbackRemoteSessions(output, profile: profile)

        XCTAssertEqual(sessions.map(\.sessionName), ["build", "shell"])
        XCTAssertEqual(sessions.map(\.source), [.remote, .remote])
        XCTAssertEqual(sessions.map(\.isAttached), [true, false])
        XCTAssertEqual(
            sessions.map(\.id),
            [
                "remote|\(profile.id.uuidString)|build|fallback",
                "remote|\(profile.id.uuidString)|shell|fallback"
            ]
        )
    }

    func testParseFallbackRemoteSessionsIgnoresMalformedRows() {
        let output = """
        missing-columns
        valid\t1
        """

        let sessions = VibeSpaceSidebarSessionBrowser.parseFallbackRemoteSessions(output, profile: makeProfile())

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionName, "valid")
    }

    func testParseDetailedRemoteSessionsReturnsRichRemoteMetadata() {
        let profile = makeProfile()
        let output = """
        build\t/srv/app\t10\t20\t1
        shell\t/srv/app/logs\t30\t40\t0
        """

        let sessions = VibeSpaceSidebarSessionBrowser.parseDetailedRemoteSessions(
            output,
            paneCommands: [
                "build": "vite",
                "shell": "tail"
            ],
            profile: profile
        )

        XCTAssertEqual(sessions.map(\.sessionName), ["build", "shell"])
        XCTAssertEqual(sessions.map(\.workingDirectory), ["/srv/app", "/srv/app/logs"])
        XCTAssertEqual(sessions.map(\.currentCommand), ["vite", "tail"])
        XCTAssertEqual(sessions.map(\.isAttached), [true, false])
        XCTAssertEqual(
            sessions.map(\.id),
            [
                "remote|\(profile.id.uuidString)|build|/srv/app",
                "remote|\(profile.id.uuidString)|shell|/srv/app/logs"
            ]
        )
    }

    func testParseDetailedRemoteSessionsIgnoresMalformedRows() {
        let output = """
        too-short
        build\t/srv/app\t10\t20\t1
        """

        let sessions = VibeSpaceSidebarSessionBrowser.parseDetailedRemoteSessions(
            output,
            paneCommands: [:],
            profile: makeProfile()
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionName, "build")
    }

    func testResolveDisplayTitlePrefersMatchingTabTitle() {
        let title = VibeSpaceSidebarSessionBrowser.resolveDisplayTitle(
            sessionName: "crispyvibes-abc123",
            owningProjectTitle: "API",
            matchingTabTitle: "Dev Server"
        )

        XCTAssertEqual(title, "Dev Server")
    }

    func testResolveDisplayTitleUsesOwningProjectForCrispyVibesSessionWithoutMatchingTab() {
        let title = VibeSpaceSidebarSessionBrowser.resolveDisplayTitle(
            sessionName: "crispyvibes-abc123",
            owningProjectTitle: "API",
            matchingTabTitle: nil
        )

        XCTAssertEqual(title, "API")
    }

    func testResolveDisplayTitleUsesGenericProjectTerminalForUnownedCrispyVibesSession() {
        let title = VibeSpaceSidebarSessionBrowser.resolveDisplayTitle(
            sessionName: "crispyvibes-abc123",
            owningProjectTitle: nil,
            matchingTabTitle: nil
        )

        XCTAssertEqual(title, AppStrings.Sidebar.Sessions.projectTerminal)
    }

    func testResolveDisplayTitleDoesNotBorrowProjectNameForNonCrispyVibesSession() {
        let title = VibeSpaceSidebarSessionBrowser.resolveDisplayTitle(
            sessionName: "build-shell",
            owningProjectTitle: "API",
            matchingTabTitle: nil
        )

        XCTAssertEqual(title, "build-shell")
    }

    func testLocalSessionAttachCommandUsesTmuxAttach() {
        let session = VibeSpaceSidebarTmuxSession(
            id: "local|build|/tmp",
            source: .local,
            launchContextProjectID: nil,
            owningProjectID: nil,
            connectionProfile: nil,
            sessionName: "build session",
            displayTitle: "build session",
            workingDirectory: "/tmp",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            currentCommand: "vite",
            lastActivity: .distantPast,
            isAttached: true
        )

        XCTAssertEqual(session.attachCommand, "tmux attach-session -t 'build session'")
    }

    func testRemoteSessionAttachCommandIncludesSSHHostPortAndKey() {
        let session = VibeSpaceSidebarTmuxSession(
            id: "remote|prod|build|/srv/app",
            source: .remote,
            launchContextProjectID: nil,
            owningProjectID: nil,
            connectionProfile: makeProfile(
                port: 2201,
                authMethod: .keyFile("~/.ssh/id_ed25519")
            ),
            sessionName: "build session",
            displayTitle: "build session",
            workingDirectory: "/srv/app",
            workingDirectoryURL: URL(fileURLWithPath: "/srv/app"),
            currentCommand: "vite",
            lastActivity: .distantPast,
            isAttached: true
        )

        XCTAssertEqual(
            session.attachCommand,
            "'ssh' '-t' '-p' '2201' '-i' '\(NSHomeDirectory())/.ssh/id_ed25519' 'alice@example.com' 'tmux attach-session -t '\\''build session'\\'''"
        )
    }

    func testImportedRemoteSessionAttachCommandUsesSSHConfigAlias() {
        let session = VibeSpaceSidebarTmuxSession(
            id: "remote|prod|build|/srv/app",
            source: .remote,
            launchContextProjectID: nil,
            owningProjectID: nil,
            connectionProfile: makeProfile(
                displayName: "prod-alias",
                importedFromConfig: true
            ),
            sessionName: "build",
            displayTitle: "build",
            workingDirectory: "/srv/app",
            workingDirectoryURL: URL(fileURLWithPath: "/srv/app"),
            currentCommand: "vite",
            lastActivity: .distantPast,
            isAttached: true
        )

        XCTAssertEqual(
            session.attachCommand,
            "'ssh' '-t' 'prod-alias' 'tmux attach-session -t '\\''build'\\'''"
        )
    }
}
