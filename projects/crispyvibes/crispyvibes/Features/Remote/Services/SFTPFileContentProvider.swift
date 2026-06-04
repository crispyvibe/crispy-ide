// SFTPFileContentProvider.swift — SSH Remote Development
// Reads and writes file content on a remote host via persistent SFTP subprocess.

import Foundation

struct SFTPFileContentProvider: FileContentProviding {
    let connection: SSHConnection

    var requiresMaterializedLocalPreview: Bool { true }

    /// F050: notebooks for remote files launch and execute on the remote host.
    var remoteNotebookHost: RemoteNotebookHosting? { connection }

    func readFile(at path: String) async throws -> Data {
        let sftp = try connection.availableSFTP()
        let path = path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let data = try sftp.readFile(path)
                    continuation.resume(returning: data)
                } catch {
                    AppDiagnostics.record(category: .remote, level: .error, event: "read_file_failed", metadata: ["path": path, "error": String(error.localizedDescription.prefix(200))])
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func writeFile(at path: String, contents: Data) async throws {
        let sftp = try connection.availableSFTP()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try sftp.writeFile(path, contents: contents)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fileSize(at path: String) async throws -> UInt64? {
        let sftp = try connection.availableSFTP()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let size = try sftp.fileSize(path)
                    continuation.resume(returning: size)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// "size mtime" via remote `stat` (GNU, then BSD fallback). Used to detect
    /// external content edits to an open remote file by polling.
    func modificationToken(at path: String) async throws -> String? {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let command =
            "stat -c '%s %Y' '\(escaped)' 2>/dev/null || stat -f '%z %m' '\(escaped)' 2>/dev/null"
        let output = try await connection.executeCommand(command, timeout: 10)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
