// SSHPortForwardService.swift — SSH Remote Development
// Port forwarding via ssh -O forward/cancel on the ControlMaster socket.

import Foundation

@MainActor
final class SSHPortForwardService: ObservableObject {
    @Published private(set) var activeForwards: [PortForwardRule] = []

    func addForward(_ rule: PortForwardRule, controlPath: String, profile: SSHConnectionProfile) async throws {
        if activeForwards.contains(where: { $0.localPort == rule.localPort }) {
            throw SSHRemoteError.portForwardAlreadyExists(rule.localPort)
        }

        let fwdSpec = "\(rule.localPort):\(rule.remoteHost):\(rule.remotePort)"
        let result = try await SSHConnection.runSSH(args: [
            "-o", "ControlPath=\(controlPath)",
            "-O", "forward", "-L", fwdSpec,
            "\(profile.user)@\(profile.host)"
        ], timeout: 5)

        guard result.status == 0 else {
            let msg = (String(data: result.stderr, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.lowercased().contains("address already in use") {
                throw SSHRemoteError.portForwardLocalPortInUse(rule.localPort)
            }
            throw SSHRemoteError.portForwardSetupFailed(msg.isEmpty ? "ssh -O forward failed" : msg)
        }
        activeForwards.append(rule)
    }

    func removeForward(_ rule: PortForwardRule, controlPath: String, profile: SSHConnectionProfile) async {
        let fwdSpec = "\(rule.localPort):\(rule.remoteHost):\(rule.remotePort)"
        let _ = try? await SSHConnection.runSSH(args: [
            "-o", "ControlPath=\(controlPath)",
            "-O", "cancel", "-L", fwdSpec,
            "\(profile.user)@\(profile.host)"
        ], timeout: 3)
        activeForwards.removeAll { $0.id == rule.id }
    }

    func removeAll(controlPath: String, profile: SSHConnectionProfile) async {
        for rule in activeForwards {
            await removeForward(rule, controlPath: controlPath, profile: profile)
        }
    }

    /// Safety net — ControlMaster exit handles actual forward cleanup.
    deinit {}
}
