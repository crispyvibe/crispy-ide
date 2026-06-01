// SSHConnectionSheetViewModel.swift — SSH Remote Development

import Foundation

/// Drives the SSH connection sheet — validates key files, manages form state.
@MainActor
final class SSHConnectionSheetViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var host = ""
    @Published var port = "22"
    @Published var user = NSUserName()
    @Published var useKeyFile = false
    @Published var keyFilePath = ""
    @Published var agentCLIEnabled = true
    @Published var keyValidationStatus: KeyValidationStatus = .none

    enum KeyValidationStatus: Equatable {
        case none, checking
        case valid(String)
        case invalid(String)

        var isUsable: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !user.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!useKeyFile || keyValidationStatus.isUsable)
    }

    func load(from profile: SSHConnectionProfile?) {
        displayName = profile?.displayName ?? ""
        host = profile?.host ?? ""
        port = String(profile?.port ?? 22)
        user = profile?.user ?? NSUserName()
        if case .keyFile(let path) = profile?.authMethod {
            useKeyFile = true; keyFilePath = path
        }
        agentCLIEnabled = profile?.isAgentCLIEnabled ?? true
    }

    func validateKey() {
        let path = keyFilePath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { keyValidationStatus = .none; return }
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            keyValidationStatus = .invalid("File not found"); return
        }
        keyValidationStatus = .checking
        Task.detached(priority: .userInitiated) {
            let result = SSHKeyLoader.validate(path: expanded)
            let status: KeyValidationStatus = result.isValid ? .valid(result.message) : .invalid(result.message)
            await MainActor.run { self.keyValidationStatus = status }
        }
    }

    func buildProfile(existingID: UUID?, importedFromConfig: Bool) -> SSHConnectionProfile {
        SSHConnectionProfile(
            id: existingID ?? UUID(),
            displayName: displayName.isEmpty ? host : displayName,
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(port) ?? 22,
            user: user.trimmingCharacters(in: .whitespaces),
            authMethod: useKeyFile ? .keyFile(keyFilePath.trimmingCharacters(in: .whitespaces)) : .agent,
            importedFromConfig: importedFromConfig,
            agentCLIEnabled: agentCLIEnabled
        )
    }
}
