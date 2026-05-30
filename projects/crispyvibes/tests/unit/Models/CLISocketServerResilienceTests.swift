import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

/// F044: regression coverage for Agent CLI socket resilience.
///
/// Reproduces the released-app failure where the socket file existed but no
/// process was listening (`connect()` -> ECONNREFUSED). Verifies the server
/// reclaims a confirmed-stale socket and refuses to clobber a live one.
@MainActor
final class CLISocketServerResilienceTests: XCTestCase {
    var container: AppContainer!
    var router: CLICommandRouter!
    var socketPath: URL!

    override func setUpWithError() throws {
        // Short /tmp path keeps us under the sockaddr_un.sun_path length limit.
        socketPath = URL(fileURLWithPath: "/tmp/cvs-\(UUID().uuidString.prefix(8)).sock")
        container = AppContainer.makeDefault()
        router = CLICommandRouter(shelfStore: container.shelfStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: socketPath)
        router = nil
        container?.terminalServices.focusCoordinator.unfocusCurrent()
        container = nil
    }

    /// A socket file left by an unclean exit (bound then closed, no listener)
    /// must be reclaimed: start() removes the stale file, rebinds, and serves.
    func test_start_recoversFromStaleSocketFile() throws {
        writeStaleSocketFile(at: socketPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath.path))
        XCTAssertFalse(
            CLISocketServer.isSocketAlive(at: socketPath),
            "precondition: a stale socket has no listener"
        )

        let server = CLISocketServer(socketPath: socketPath, router: router)
        defer { server.shutdown() }
        XCTAssertNoThrow(try server.start())

        XCTAssertTrue(
            CLISocketServer.isSocketAlive(at: socketPath),
            "server should accept connections after reclaiming the stale socket"
        )
    }

    /// A second server must not clobber a healthy listener on the same path.
    func test_start_doesNotClobberLiveListener() throws {
        let first = CLISocketServer(socketPath: socketPath, router: router)
        defer { first.shutdown() }
        try first.start()
        XCTAssertTrue(CLISocketServer.isSocketAlive(at: socketPath))

        let second = CLISocketServer(socketPath: socketPath, router: router)
        XCTAssertThrowsError(try second.start()) { error in
            guard case CLISocketServerError.alreadyServing = error else {
                return XCTFail("expected .alreadyServing, got \(error)")
            }
        }
        XCTAssertTrue(
            CLISocketServer.isSocketAlive(at: socketPath),
            "the original live listener must remain healthy"
        )
    }

    // MARK: - Helpers

    /// Creates a socket-type file with no active listener — the exact orphaned
    /// state observed in the released app.
    private func writeStaleSocketFile(at path: URL) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return XCTFail("could not create socket") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.path.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            bytes.withUnsafeBytes { src in dest.copyMemory(from: src) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, len)
            }
        }
        // Close without listen(): leaves the socket file behind, no listener.
        close(fd)
    }
}
