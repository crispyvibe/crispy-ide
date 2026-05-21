// SFTPFileContentProvider.swift — SSH Remote Development
// Reads and writes file content on a remote host via persistent SFTP subprocess.

import Foundation

struct SFTPFileContentProvider: FileContentProviding {
    let connection: SSHConnection

    var requiresMaterializedLocalPreview: Bool { true }

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
}
