import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ACPTransportPromptCompletionTests: XCTestCase {
    private struct TimeoutError: Error {}

    func testPromptResponseInjectsTurnCompletedAfterBufferedNotifications() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ACPTransportPromptCompletionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let executable = tempDirectory.appendingPathComponent("fake-acp-agent.sh")
        let script = """
        #!/bin/sh
        IFS= read -r line
        printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"one"}}}}'
        printf '%s\\n' '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"two"}}}}'
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn"}}'
        sleep 2
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let transport = ACPTransport(
            localSessionID: "test-session",
            agentID: "test-agent",
            projectToken: nil,
            origin: "test",
            observabilityStore: nil
        )

        do {
            try await transport.start(executable: executable.path, arguments: [], environment: nil)

            let stream = await transport.notifications()
            let collector = Task { () -> [JSONRPCNotification] in
                var notifications: [JSONRPCNotification] = []
                for await notification in stream {
                    notifications.append(notification)
                    if notifications.count == 3 {
                        break
                    }
                }
                return notifications
            }

            let response = try await transport.send(
                method: "session/prompt",
                params: [
                    "sessionId": "s",
                    "prompt": [["type": "text", "text": "hello"]],
                ]
            )
            let notifications = try await withTimeout(nanoseconds: 2_000_000_000) {
                await collector.value
            }
            collector.cancel()
            await transport.stop()

            XCTAssertTrue(response.isSuccess)
            XCTAssertEqual(notifications.compactMap(Self.sessionUpdateKind), [
                "agent_message_chunk",
                "agent_message_chunk",
                "turn_completed",
            ])
        } catch {
            await transport.stop()
            throw error
        }
    }

    private static func sessionUpdateKind(from notification: JSONRPCNotification) -> String? {
        guard notification.method == "session/update",
              let params = notification.params?.dictValue,
              let update = params["update"] as? [String: Any] else {
            return nil
        }
        return update["sessionUpdate"] as? String
    }

    private func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw TimeoutError()
            }

            let result = try await group.next()
            group.cancelAll()
            return try XCTUnwrap(result)
        }
    }
}
