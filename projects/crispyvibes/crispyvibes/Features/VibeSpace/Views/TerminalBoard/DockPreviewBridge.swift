import Foundation

@MainActor
final class DockPreviewBridge: ObservableObject {
    @Published var pendingFileURL: URL?

    func requestPreview(for fileURL: URL) {
        pendingFileURL = fileURL.standardizedFileURL
    }

    func consumePending() -> URL? {
        guard let url = pendingFileURL else { return nil }
        pendingFileURL = nil
        return url
    }
}
