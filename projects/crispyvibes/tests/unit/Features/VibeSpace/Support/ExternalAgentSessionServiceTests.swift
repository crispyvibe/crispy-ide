import Darwin
import XCTest
@testable import CrispyVibes

@MainActor
final class ExternalAgentSessionServiceTests: XCTestCase {
    func test_directoryDisclosure_loadsCollapsedAndExpandsForSearch() {
        XCTAssertFalse(
            ExternalSessionDirectoryDisclosureState.isExpanded(
                id: "/work/project",
                expandedGroups: [],
                searchText: ""
            )
        )
        XCTAssertTrue(
            ExternalSessionDirectoryDisclosureState.isExpanded(
                id: "/work/project",
                expandedGroups: ["/work/project"],
                searchText: ""
            )
        )
        XCTAssertTrue(
            ExternalSessionDirectoryDisclosureState.isExpanded(
                id: "/work/project",
                expandedGroups: [],
                searchText: "  auth failure  "
            )
        )
        XCTAssertFalse(
            ExternalSessionDirectoryDisclosureState.isExpanded(
                id: "/work/project",
                expandedGroups: [],
                searchText: "   "
            )
        )
    }

    func test_classicTranscriptMetadata_decodesHelperContract() throws {
        let data = Data(#"""
        {
          "session": {
            "provider": "kiro", "providerName": "Kiro CLI", "sessionId": "classic-1",
            "sessionSource": "classic", "title": "Classic", "projectPath": "/work",
            "sourcePath": "/tmp/data.sqlite3", "createdAt": "", "updatedAt": "",
            "modifiedAtEpoch": 0, "messageCount": 5, "hasToolActivity": true,
            "parseStatus": "ok", "parseErrors": [], "parentSessionId": null,
            "searchSnippet": null, "searchSnippets": [], "matchCount": 0
          },
          "entries": [
            {"role":"user","timestamp":"1","text":"Prompt","metadata":{}},
            {"role":"assistant","timestamp":"1","text":"Response","metadata":{}},
            {"role":"assistant","timestamp":"1","text":"ToolUse content","metadata":{}},
            {"role":"tool","timestamp":"1","text":"ToolUse","metadata":{"toolUses":[{"id":"call-1"}]}},
            {"role":"tool","timestamp":"1","text":"ToolUseResults","metadata":{"toolUseResults":[{"tool_use_id":"call-1"}]}},
            {"role":"user","timestamp":"1","text":"CancelledToolUses prompt","metadata":{}},
            {"role":"tool","timestamp":"1","text":"CancelledToolUses","metadata":{"toolUseResults":[{"status":"cancelled"}]}}
          ],
          "parseErrors": []
        }
        """#.utf8)

        let transcript = try JSONDecoder().decode(ExternalAgentTranscript.self, from: data)
        XCTAssertEqual(transcript.entries.count, 7)
        XCTAssertEqual(transcript.entries[0].metadata, [:])
        XCTAssertEqual(
            transcript.entries[3].metadata["toolUses"],
            JSONValue.array([.object(["id": .string("call-1")])])
        )
        XCTAssertEqual(
            transcript.entries[6].metadata["toolUseResults"],
            JSONValue.array([.object(["status": .string("cancelled")])])
        )
    }

    func test_cancellingRapidSearches_terminatesAndReapsEachHelper() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-session-cancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let helper = directory.appendingPathComponent("blocking-helper")
        let pidFile = directory.appendingPathComponent("helper.pid")
        try "#!/bin/sh\necho $$ > '\(pidFile.path)'\nwhile :; do :; done\n"
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let service = ExternalAgentSessionService(helperURL: helper)

        for index in 0..<3 {
            try? FileManager.default.removeItem(at: pidFile)
            let task = Task {
                try await service.search(query: "query-\(index)")
            }
            let pid = try await waitForPID(at: pidFile)
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Cancelled search unexpectedly completed")
            } catch is CancellationError {
                // Expected: cancellation owns helper termination and reaping.
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }
            try await waitForProcessExit(pid)
        }
    }

    private func waitForPID(at url: URL) async throws -> pid_t {
        for _ in 0..<200 {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw TestError.timeout("helper PID")
    }

    private func waitForProcessExit(_ pid: pid_t) async throws {
        for _ in 0..<200 {
            errno = 0
            if kill(pid, 0) == -1, errno == ESRCH { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw TestError.timeout("helper process \(pid) exit")
    }

    private enum TestError: Error {
        case timeout(String)
    }
}
