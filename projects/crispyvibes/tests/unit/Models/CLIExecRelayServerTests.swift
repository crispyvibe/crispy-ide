import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

/// F051: verifies the exec relay runs the configured executable with the
/// relayed argv and returns `"<exit>\n<output>"`.
@MainActor
final class CLIExecRelayServerTests: XCTestCase {
    var socketPath: URL!
    var server: CLIExecRelayServer!

    override func setUpWithError() throws {
        socketPath = URL(fileURLWithPath: "/tmp/cvr-\(UUID().uuidString.prefix(8)).sock")
    }

    override func tearDownWithError() throws {
        server?.shutdown()
        try? FileManager.default.removeItem(at: socketPath)
    }

    func test_relay_runsExecutableAndReturnsExitAndOutput() throws {
        server = CLIExecRelayServer(
            socketPath: socketPath,
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            crispySocketPath: URL(fileURLWithPath: "/tmp/unused.sock")
        )
        try server.start()

        // Request: cwd \0 projectPath \0 arg0 \0 arg1 \0
        let response = try roundTrip(fields: ["/work", "/proj", "hello", "world"])
        XCTAssertEqual(response, "0\nhello world\n")
    }

    // MARK: - Helper

    private func roundTrip(fields: [String]) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.path.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            bytes.withUnsafeBytes { src in dest.copyMemory(from: src) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        XCTAssertEqual(connectResult, 0, "connect failed")

        var rcv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcv, socklen_t(MemoryLayout<timeval>.size))

        var request = Data()
        for field in fields { request.append(Data(field.utf8)); request.append(0x00) }
        _ = request.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, request.count) }
        shutdown(fd, SHUT_WR)

        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
        }
        return String(data: out, encoding: .utf8) ?? ""
    }
}
