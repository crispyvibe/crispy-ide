import Foundation
import WebKit
import Network

/// Routes browser requests through an SSH remote vibespace proxy.
/// Uses SSH port forwarding to tunnel HTTP traffic to the remote host.
@MainActor
final class BrowserProxyCoordinator {
    private var activeTunnels: [String: Process] = [:]

    struct ProxyEndpoint {
        let localPort: UInt16
        let remoteHost: String
        let remotePort: UInt16
    }

    /// Creates a SOCKS proxy tunnel through an SSH connection.
    func createTunnel(sshProfile: SSHConnectionProfile, localPort: UInt16 = 0) async throws -> ProxyEndpoint {
        let port = localPort == 0 ? UInt16.random(in: 49152...65535) : localPort
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N", "-D", "\(port)",
            "-o", "ControlMaster=no",
            "-o", "ExitOnForwardFailure=yes",
            "-p", "\(sshProfile.port)",
            "\(sshProfile.user)@\(sshProfile.host)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let key = sshProfile.connectionString
        activeTunnels[key]?.terminate()
        activeTunnels[key] = process

        return ProxyEndpoint(localPort: port, remoteHost: sshProfile.host, remotePort: sshProfile.port)
    }

    /// Configures a WKWebView to route through the proxy.
    func configureWebView(_ webView: WKWebView, endpoint: ProxyEndpoint) {
        let proxyConfig = ProxyConfiguration(socksv5Proxy: .hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: endpoint.localPort)
        ))
        webView.configuration.websiteDataStore.proxyConfigurations = [proxyConfig]
    }

    func teardownTunnel(for connectionString: String) {
        activeTunnels[connectionString]?.terminate()
        activeTunnels.removeValue(forKey: connectionString)
    }

    func teardownAll() {
        activeTunnels.values.forEach { $0.terminate() }
        activeTunnels.removeAll()
    }

    deinit {
        activeTunnels.values.forEach { $0.terminate() }
    }
}
