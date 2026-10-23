import Foundation

/// A file-system item on an active remote project that can be exported locally.
struct RemoteTransferItem: Equatable, Sendable {
    let path: String
    let displayName: String
    let isDirectory: Bool

    init(path: String, displayName: String, isDirectory: Bool) {
        self.path = path
        self.displayName = displayName
        self.isDirectory = isDirectory
    }
}

/// Monotonic progress emitted while preparing or downloading a remote item.
struct RemoteTransferProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case transferring
        case publishing
    }

    let phase: Phase
    let completedBytes: UInt64
    let totalBytes: UInt64
    let completedFiles: Int
    let totalFiles: Int
    let currentItem: String?
}

/// The completed local snapshot produced by a remote transfer.
struct RemoteTransferReceipt: Equatable, Sendable {
    let localURL: URL
    let isTemporary: Bool
}

/// Project-scoped boundary for exporting remote files and folders.
protocol RemoteItemTransferring: Sendable {
    func download(
        _ item: RemoteTransferItem,
        to destinationURL: URL,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) async throws -> RemoteTransferReceipt

    func materializeForExternalOpen(
        _ item: RemoteTransferItem,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) async throws -> RemoteTransferReceipt
}
