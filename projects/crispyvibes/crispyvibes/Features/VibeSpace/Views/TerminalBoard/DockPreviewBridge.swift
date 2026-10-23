import Foundation

@MainActor
final class DockPreviewBridge: ObservableObject {
    @Published private(set) var pendingTarget: TerminalFileSystemTarget?

    func requestPreview(for fileURL: URL, projectIdentifier: String? = nil) {
        pendingTarget = TerminalFileSystemTarget(
            url: fileURL.standardizedFileURL,
            line: nil,
            column: nil,
            projectIdentifier: projectIdentifier
        )
    }

    func consumePending() -> TerminalFileSystemTarget? {
        guard let target = pendingTarget else { return nil }
        pendingTarget = nil
        return target
    }
}
