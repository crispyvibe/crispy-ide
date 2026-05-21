// SSHKeyLoader.swift — SSH Remote Development
// Validates SSH keys via ssh-keygen. System ssh handles all key formats natively.

import Foundation

enum SSHKeyLoader {

    /// Validates a key file using ssh-keygen. Returns (isValid, description or error).
    static func validate(path: String) -> (isValid: Bool, message: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            return (false, "File not found")
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-l", "-f", expanded]
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { return (false, "Cannot read key file") }
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            let keyType = output.components(separatedBy: "(").last?.replacingOccurrences(of: ")", with: "") ?? "Unknown"
            let bits = output.components(separatedBy: " ").first ?? ""
            // Check for companion certificate
            let certPath = expanded + "-cert.pub"
            let hasCert = FileManager.default.fileExists(atPath: certPath)
            let certSuffix = hasCert ? " + certificate" : ""
            return (true, "\(keyType) \(bits)-bit key\(certSuffix)")
        }

        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if err.contains("passphrase") || err.contains("incorrect") {
            return (false, "Key is encrypted with a passphrase — not yet supported.")
        }
        return (false, "Cannot read key — check file permissions and format.")
    }

    /// Returns the path of the first usable private key in ~/.ssh.
    static func findDefaultKeyPath() -> String? {
        let sshDir = NSString(string: "~/.ssh").expandingTildeInPath
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sshDir) else { return nil }

        return files
            .filter { !$0.hasSuffix(".pub") && !$0.hasPrefix("known_hosts") && !$0.hasPrefix("config") && !$0.hasPrefix("authorized") }
            .map { (sshDir as NSString).appendingPathComponent($0) }
            .filter { FileManager.default.isReadableFile(atPath: $0) }
            .sorted { a, b in
                if a.contains("ed25519") { return true }
                if b.contains("ed25519") { return false }
                return a.contains("ecdsa") && !b.contains("ecdsa")
            }
            .first { validate(path: $0).isValid }
    }
}
