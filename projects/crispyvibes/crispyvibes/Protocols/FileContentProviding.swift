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

    /// F050: a host capable of running a Jupyter server on the machine that owns
    /// the file. Remote (SSH) providers vend their connection so notebooks launch
    /// and execute on the remote host; local providers return `nil` (the server
    /// runs locally).
    var remoteNotebookHost: RemoteNotebookHosting? { get }
}

extension FileContentProviding {
    func fileSize(at path: String) async throws -> UInt64? { nil }
    func modificationToken(at path: String) async throws -> String? { nil }
    var requiresMaterializedLocalPreview: Bool { false }
    var remoteNotebookHost: RemoteNotebookHosting? { nil }
}

/// F050: the minimal remote capability the notebook server lifecycle needs —
/// run a login-shell script on the host and forward a loopback port to it over
/// the existing SSH ControlMaster. `SSHConnection` is the production conformer.
@MainActor
protocol RemoteNotebookHosting: AnyObject, Sendable {
    /// Stable per-host identifier used to key one server per host + root.
    var notebookHostKey: String { get }
    /// Runs `script` in a remote login shell (fed via stdin), returning stdout.
    func runLoginScript(_ script: String, timeout: TimeInterval) async throws -> String
    /// Forwards `localPort` on the loopback to `127.0.0.1:remotePort` on the host.
    func forwardPort(localPort: UInt16, remotePort: UInt16) async throws
    /// Cancels a forward previously created by `forwardPort`.
    func cancelForward(localPort: UInt16, remotePort: UInt16) async
}
