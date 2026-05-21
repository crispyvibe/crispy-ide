// FileSystemProviding.swift — SSH Remote Development

import Foundation

/// Abstraction over directory listing and file CRUD operations.
/// Local: wraps FileManager. Remote: wraps SFTP.
/// All methods are async and run off the main actor.
protocol FileSystemProviding: Sendable {
    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor]
    func createDirectory(at path: String) async throws
    func createFile(at path: String, contents: Data?) async throws
    func removeItem(at path: String) async throws
    func moveItem(from source: String, to destination: String) async throws
}
