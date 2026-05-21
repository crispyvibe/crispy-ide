import AppKit
import Foundation

@MainActor
final class VibeSpaceInteractionService {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealInFinder(_ url: URL) {
        revealInFinder([url])
    }

    func selectFile(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
