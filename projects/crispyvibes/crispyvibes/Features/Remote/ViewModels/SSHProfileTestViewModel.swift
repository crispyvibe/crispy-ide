// SSHProfileTestViewModel.swift — SSH Remote Development
// Manages key validation and test connections for SSH profiles.

import Foundation

@MainActor
protocol SSHProfileTestingConnection: AnyObject {
    func connect() async throws
    func acceptAndConnect() async throws
    func disconnect() async
}

@MainActor
private final class SSHProfileTestingConnectionAdapter: SSHProfileTestingConnection {
    private let connection: SSHConnection
    init(profile: SSHConnectionProfile) { self.connection = SSHConnection(profile: profile) }
    func connect() async throws { try await connection.connect() }
    func acceptAndConnect() async throws { try await connection.acceptAndConnect() }
    func disconnect() async { await connection.disconnect() }
}

@MainActor
final class SSHProfileTestViewModel: ObservableObject {
    enum KeyStatus: Equatable {
        case unchecked, checking
        case valid(String)
        case rsaIncompatible
        case passphrase
        case invalid(String)
    }

    enum TestStatus: Equatable {
        case idle, testing(String), success
        case failed(String)
    }

    @Published var keyStatuses: [UUID: KeyStatus] = [:]
    @Published var testStatuses: [UUID: TestStatus] = [:]
    @Published var fixInProgress: UUID?
    @Published var generatedPublicKey: String?
    @Published var pendingHostKeyFingerprint: String?
    @Published var pendingHostKeyProfile: SSHConnectionProfile?

    var makeConnection: @MainActor (SSHConnectionProfile) -> any SSHProfileTestingConnection = {
        SSHProfileTestingConnectionAdapter(profile: $0)
    }
    var fetchFingerprint: @Sendable (String, UInt16) async -> String? = { host, port in
        await KnownHostsValidator.fetchFingerprint(host: host, port: port)
    }

    private var pendingConnections: [UUID: any SSHProfileTestingConnection] = [:]

    func validateKey(for profile: SSHConnectionProfile) {
        keyStatuses[profile.id] = .checking
        let path = resolveKeyPath(for: profile)
        guard let path else { keyStatuses[profile.id] = .valid("SSH Agent"); return }

        Task.detached(priority: .userInitiated) {
            let result = SSHKeyLoader.validate(path: path)
            await MainActor.run {
                if result.isValid { self.keyStatuses[profile.id] = .valid(result.message) }
                else if result.message.contains("RSA") { self.keyStatuses[profile.id] = .rsaIncompatible }
                else if result.message.contains("passphrase") { self.keyStatuses[profile.id] = .passphrase }
                else { self.keyStatuses[profile.id] = .invalid(result.message) }
            }
        }
    }

    func validateAll(_ profiles: [SSHConnectionProfile]) {
        for profile in profiles { validateKey(for: profile) }
    }

    func testConnection(for profile: SSHConnectionProfile) {
        testStatuses[profile.id] = .testing("Connecting…")
        pendingHostKeyFingerprint = nil
        pendingHostKeyProfile = nil
        pendingConnections.removeValue(forKey: profile.id)
        Task {
            let connection = makeConnection(profile)
            do {
                try await connection.connect()
                testStatuses[profile.id] = .success
                await connection.disconnect()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if testStatuses[profile.id] == .success { testStatuses[profile.id] = .idle }
            } catch is HostKeyUnknownError {
                pendingConnections[profile.id] = connection
                pendingHostKeyProfile = profile
                testStatuses[profile.id] = .testing("Fetching host key…")
                let fp = await fetchFingerprint(profile.host, profile.port)
                pendingHostKeyFingerprint = fp ?? "Unable to fetch fingerprint"
                testStatuses[profile.id] = .idle
            } catch {
                await connection.disconnect()
                testStatuses[profile.id] = .failed(error.localizedDescription)
            }
        }
    }

    func acceptHostKeyAndContinue() {
        guard let profile = pendingHostKeyProfile else { return }
        let connection = pendingConnections[profile.id] ?? makeConnection(profile)
        pendingHostKeyProfile = nil
        pendingHostKeyFingerprint = nil
        pendingConnections.removeValue(forKey: profile.id)
        testStatuses[profile.id] = .testing("Saving host key and connecting…")

        Task {
            do {
                try await connection.acceptAndConnect()
                testStatuses[profile.id] = .success
                await connection.disconnect()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if testStatuses[profile.id] == .success { testStatuses[profile.id] = .idle }
            } catch {
                await connection.disconnect()
                testStatuses[profile.id] = .failed(error.localizedDescription)
            }
        }
    }

    func rejectHostKey() {
        guard let profile = pendingHostKeyProfile else { return }
        pendingConnections.removeValue(forKey: profile.id)
        pendingHostKeyProfile = nil
        pendingHostKeyFingerprint = nil
        if case .testing = testStatuses[profile.id] {
            testStatuses[profile.id] = .idle
        }
    }

    func generateReplacementKey(for profile: SSHConnectionProfile, profileStore: SSHProfileStore) {
        fixInProgress = profile.id
        Task.detached(priority: .userInitiated) {
            let name = profile.displayName.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            let keyPath = NSString(string: "~/.ssh/\(name)_ed25519").expandingTildeInPath
            guard !FileManager.default.fileExists(atPath: keyPath) else {
                await MainActor.run { self.fixInProgress = nil; self.keyStatuses[profile.id] = .invalid("Key already exists") }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-t", "ed25519", "-f", keyPath, "-N", "", "-C", "crispyvibes-\(name)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                await MainActor.run { self.fixInProgress = nil; self.keyStatuses[profile.id] = .invalid("Failed to generate key") }
                return
            }
            let pubKey = (try? String(contentsOfFile: keyPath + ".pub", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run {
                var updated = profile; updated.authMethod = .keyFile(keyPath)
                profileStore.update(updated)
                self.generatedPublicKey = pubKey; self.fixInProgress = nil
                self.keyStatuses[profile.id] = .valid("ED25519 256-bit key (new)")
            }
        }
    }

    func dismissPublicKey() { generatedPublicKey = nil }

    private func resolveKeyPath(for profile: SSHConnectionProfile) -> String? {
        switch profile.authMethod {
        case .keyFile(let path): return NSString(string: path).expandingTildeInPath
        case .agent: return SSHKeyLoader.findDefaultKeyPath()
        }
    }
}
