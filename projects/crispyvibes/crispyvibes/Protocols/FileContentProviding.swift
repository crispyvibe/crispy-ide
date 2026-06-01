// FileContentProviding.swift — SSH Remote Development

import Foundation

/// Abstraction over reading and writing file contents.
/// Local: wraps Data(contentsOf:)/data.write(to:). Remote: wraps SFTP read/write.
/// All methods are async and run off the main actor.
protocol FileContentProviding: Sendable {
    func readFile(at path: String) async throws -> Data
    func writeFile(at path: String, contents: Data) async throws

    /// Returns file size in bytes, or nil if unknown.
    /// Used for large-file prompts on remote files.
    func fileSize(at path: String) async throws -> UInt64?

    /// An opaque change token (e.g. "size mtime") for the file, or nil if the
    /// provider can't cheaply determine one. Used to detect external content
    /// changes by polling. Local providers return nil (they use FSEvents).
    func modificationToken(at path: String) async throws -> String?

    /// Indicates whether previews need a staged local file URL instead of the source path.
    /// Remote SSH-backed providers return `true`; local providers can render directly.
    var requiresMaterializedLocalPreview: Bool { get }
}

extension FileContentProviding {
    func fileSize(at path: String) async throws -> UInt64? { nil }
    func modificationToken(at path: String) async throws -> String? { nil }
    var requiresMaterializedLocalPreview: Bool { false }
}
