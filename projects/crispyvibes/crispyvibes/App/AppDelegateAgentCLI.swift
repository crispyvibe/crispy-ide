import AppKit
import Foundation

extension AppDelegate {
    static let infoPlistEnableAgentCLIKey = "CrispyVibesEnableAgentCLI"

    static var isAgentCLIEnabled: Bool {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: infoPlistEnableAgentCLIKey) else {
            return true
        }
        if let enabled = rawValue as? Bool {
            return enabled
        }
        if let stringValue = rawValue as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "0", "false", "no": return false
            case "1", "true", "yes": return true
            default: return true
            }
        }
        return true
    }

    @MainActor
    func startAgentCLISocketServerIfEnabled() {
        guard Self.isAgentCLIEnabled else {
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .info,
                event: "agent_cli_disabled"
            )
            return
        }
        guard let server = appContainer?.cliSocketServer else { return }
        do {
            try server.start()
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .info,
                event: "agent_cli_started",
                metadata: [
                    "socket_path": server.resolvedSocketPath.path
                ]
            )
        } catch CLISocketServerError.alreadyServing {
            // A healthy listener already owns the socket (e.g. another live
            // instance, or this server is already running). Not an error.
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .info,
                event: "agent_cli_already_serving"
            )
        } catch {
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .error,
                event: "agent_cli_start_failed",
                metadata: [
                    "error": "\(error)"
                ]
            )
        }
        startAgentCLIExecRelayIfEnabled()
    }

    /// F051: starts the remote-CLI exec relay (idempotent; self-heals on
    /// reactivation like the command socket).
    @MainActor
    func startAgentCLIExecRelayIfEnabled() {
        guard Self.isAgentCLIEnabled else { return }
        if cliExecRelayServer == nil { cliExecRelayServer = CLIExecRelayServer() }
        do {
            try cliExecRelayServer?.start()
        } catch CLISocketServerError.alreadyServing {
            // Already serving — fine.
        } catch {
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .error,
                event: "agent_cli_relay_start_failed",
                metadata: ["error": "\(error)"]
            )
        }
    }
}
