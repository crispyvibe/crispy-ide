import Foundation

/// Opens a local file directly or materializes a remote file before using its system handler.
@MainActor
protocol ExternalFileOpening: AnyObject {
    func open(
        fileURL: URL,
        fileContentProvider: (any FileContentProviding)?
    ) async throws -> URL
}
