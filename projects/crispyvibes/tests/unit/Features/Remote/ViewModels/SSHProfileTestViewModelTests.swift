import XCTest
@testable import CrispyVibes

@MainActor
final class SSHProfileTestViewModelTests: XCTestCase {
    func testUnknownHostDuringSettingsTestPromptsForAcceptance() async throws {
        let profile = makeProfile()
        let connection = StubSSHProfileTestingConnection()
        connection.connectError = HostKeyUnknownError(host: profile.host)

        let viewModel = SSHProfileTestViewModel()
        viewModel.makeConnection = { _ in connection }
        viewModel.fetchFingerprint = { _, _ in "SHA256:test-fingerprint" }

        viewModel.testConnection(for: profile)

        try await waitUntil {
            viewModel.pendingHostKeyProfile?.id == profile.id
        }

        XCTAssertEqual(viewModel.pendingHostKeyFingerprint, "SHA256:test-fingerprint")
        XCTAssertEqual(viewModel.testStatuses[profile.id], .idle)
        XCTAssertEqual(connection.connectCallCount, 1)
    }

    func testAcceptHostKeyRetriesAndMarksConnectionSuccessful() async throws {
        let profile = makeProfile()
        let connection = StubSSHProfileTestingConnection()
        connection.connectError = HostKeyUnknownError(host: profile.host)

        let viewModel = SSHProfileTestViewModel()
        viewModel.makeConnection = { _ in connection }
        viewModel.fetchFingerprint = { _, _ in "SHA256:test-fingerprint" }

        viewModel.testConnection(for: profile)
        try await waitUntil {
            viewModel.pendingHostKeyProfile?.id == profile.id
        }

        viewModel.acceptHostKeyAndContinue()

        try await waitUntil {
            viewModel.testStatuses[profile.id] == .success
        }

        XCTAssertNil(viewModel.pendingHostKeyProfile)
        XCTAssertNil(viewModel.pendingHostKeyFingerprint)
        XCTAssertEqual(connection.acceptCallCount, 1)
        XCTAssertGreaterThanOrEqual(connection.disconnectCallCount, 1)
    }

    func testRejectHostKeyClearsPendingPromptState() async throws {
        let profile = makeProfile()
        let connection = StubSSHProfileTestingConnection()
        connection.connectError = HostKeyUnknownError(host: profile.host)

        let viewModel = SSHProfileTestViewModel()
        viewModel.makeConnection = { _ in connection }
        viewModel.fetchFingerprint = { _, _ in "SHA256:test-fingerprint" }

        viewModel.testConnection(for: profile)
        try await waitUntil {
            viewModel.pendingHostKeyProfile?.id == profile.id
        }

        viewModel.rejectHostKey()

        XCTAssertNil(viewModel.pendingHostKeyProfile)
        XCTAssertNil(viewModel.pendingHostKeyFingerprint)
        XCTAssertEqual(viewModel.testStatuses[profile.id], .idle)
    }

    private func makeProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            id: UUID(),
            displayName: "Test Host",
            host: "example.com",
            port: 22,
            user: "testuser",
            authMethod: .agent,
            importedFromConfig: false
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

@MainActor
private final class StubSSHProfileTestingConnection: SSHProfileTestingConnection {
    var connectError: Error?
    private(set) var connectCallCount = 0
    private(set) var acceptCallCount = 0
    private(set) var disconnectCallCount = 0

    func connect() async throws {
        connectCallCount += 1
        if let connectError {
            throw connectError
        }
    }

    func acceptAndConnect() async throws {
        acceptCallCount += 1
    }

    func disconnect() async {
        disconnectCallCount += 1
    }
}
