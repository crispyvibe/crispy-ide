// SFTPFileSystemProvider.swift — SSH Remote Development
// File system operations on a remote host via persistent SFTP subprocess.

import Foundation

struct SFTPFileSystemProvider: FileSystemProviding {
    let connection: SSHConnection

    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        let sftp = try connection.availableSFTP()
        AppDiagnostics.record(category: .remote, level: .info, event: "sftp_list_start", metadata: ["path": path])
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let entries = try sftp.listDirectory(path)
                    AppDiagnostics.record(category: .remote, level: .info, event: "sftp_list_ok", metadata: ["path": path, "count": String(entries.count)])
                    continuation.resume(returning: entries.map { entry in
                        FileItemDescriptor(
                            name: entry.name,
                            path: entry.path,
                            isDirectory: entry.isDirectory,
                            isHidden: entry.name.hasPrefix("."),
                            size: entry.size,
                            modificationDate: entry.modificationDate
                        )
                    })
                } catch {
                    AppDiagnostics.record(category: .remote, level: .error, event: "sftp_list_failed", metadata: ["path": path, "error": String(error.localizedDescription.prefix(300))])
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func createDirectory(at path: String) async throws {
        let sftp = try connection.availableSFTP()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try sftp.mkdir(path)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func createFile(at path: String, contents: Data?) async throws {
        if let contents {
            let sftp = try connection.availableSFTP()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try sftp.writeFile(path, contents: contents)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } else {
            let esc = path.replacingOccurrences(of: "'", with: "'\\''")
            _ = try await connection.executeCommand("touch '\(esc)'")
        }
    }

    func removeItem(at path: String) async throws {
        let esc = path.replacingOccurrences(of: "'", with: "'\\''")
        _ = try await connection.executeCommand("rm -rf '\(esc)'")
    }

    func moveItem(from source: String, to destination: String) async throws {
        let sftp = try connection.availableSFTP()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try sftp.rename(from: source, to: destination)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
