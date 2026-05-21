import Foundation
import XCTest
@testable import CrispyVibes

final class LocalCommandExecutorTests: XCTestCase {
    func testExecuteReturnsStdoutAndSupportsStdin() async throws {
        let executor = LocalCommandExecutor()

        let result = try await executor.execute(
            tool: "/bin/cat",
            arguments: [],
            stdinData: Data("hello\n".utf8),
            timeout: 1
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.stdoutData, encoding: .utf8), "hello\n")
        XCTAssertEqual(result.stderrData, Data())
    }

    func testExecuteReturnsAfterTimeoutWithoutHangingCaller() async throws {
        let executor = LocalCommandExecutor()
        let start = Date()

        let result = try await executor.execute(
            tool: "/bin/sh",
            arguments: ["-lc", "sleep 5"],
            stdinData: nil,
            timeout: 0.1
        )

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0)
        XCTAssertNotEqual(result.terminationStatus, 0)
    }

    func testExecuteDrainsLargeOutputWithoutDeadlock() async throws {
        let executor = LocalCommandExecutor()

        let result = try await executor.execute(
            tool: "/bin/sh",
            arguments: ["-lc", "yes x | head -n 50000"],
            stdinData: nil,
            timeout: 2
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertGreaterThan(result.stdoutData.count, 65_536)
    }
}
