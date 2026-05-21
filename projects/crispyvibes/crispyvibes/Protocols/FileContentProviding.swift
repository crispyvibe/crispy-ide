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

    /// Indicates whether previews need a staged local file URL instead of the source path.
    /// Remote SSH-backed providers return `true`; local providers can render directly.
    var requiresMaterializedLocalPreview: Bool { get }
}

extension FileContentProviding {
    func fileSize(at path: String) async throws -> UInt64? { nil }
    var requiresMaterializedLocalPreview: Bool { false }
}
