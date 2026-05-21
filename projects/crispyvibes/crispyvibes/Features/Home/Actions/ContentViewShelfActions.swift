import SwiftUI

extension ContentView {
    func openFilesInShelf(_ urls: [URL], makeVisible: Bool = true) {
        let selectedURL = shelfStore.addFiles(urls)
        guard makeVisible else { return }
        guard revealShelfInFilesSidebar() else { return }
        if let selectedURL {
            openShelfFile(at: selectedURL.path, makeVisible: false)
        }
    }

    func openShelfFile(at path: String, makeVisible: Bool = true) {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        _ = shelfStore.selectFile(at: path)
        if makeVisible {
            guard revealShelfInFilesSidebar() else { return }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        guard !isDir.boolValue else { return }

        let target = TerminalFileSystemTarget(url: fileURL, line: nil, column: nil)
        openTerminalFileSystemTarget(target)
    }

    func removeShelfFile(at path: String) {
        let removedSelectedPath = shelfStore.selectedFilePath == URL(fileURLWithPath: path).standardizedFileURL.path
        let nextSelectedPath = shelfStore.removeFile(at: path)
        if removedSelectedPath, let nextSelectedPath {
            openShelfFile(at: nextSelectedPath, makeVisible: false)
        }
    }

    func clearShelf() {
        shelfStore.clear()
    }

    func openShelfFileInFinder(at path: String) {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            appContainer.vibespaceInteraction.revealInFinder(fileURL)
        } else {
            appContainer.vibespaceInteraction.open(fileURL.deletingLastPathComponent())
        }
    }

    func openShelfDirectoryInTerminal(at path: String) {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let directoryURL = fileURL.deletingLastPathComponent()
        guard let project = activeVibeSpaceSession.focusedProject ?? activeVibeSpaceSession.projects.first else { return }
        project.terminal.openOrSelectTab(for: directoryURL)
    }

    func renameShelfFile(at path: String, to newName: String) throws {
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        let trimmedName = sanitizedShelfFileName(newName)
        guard !trimmedName.isEmpty else {
            throw ShelfActionError("Item name cannot be empty.")
        }

        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(trimmedName).standardizedFileURL
        guard destinationURL.path != sourceURL.path else { return }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw ShelfActionError("A file or folder named \(trimmedName) already exists.")
        }

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        shelfStore.retargetFile(from: sourceURL, to: destinationURL)
        contentViewerStore.retargetFileSystemLocation(from: sourceURL, to: destinationURL)
    }

    func deleteShelfFile(at path: String) throws {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        try FileManager.default.removeItem(at: fileURL)
        contentViewerStore.closeFileTabs(at: fileURL)
        removeShelfFile(at: fileURL.path)
    }

    func ensureShelfSelectionIfNeeded() {
        shelfStore.ensureSelectionIfNeeded()
    }

    @discardableResult
    private func revealShelfInFilesSidebar() -> Bool {
        if activeVibeSpaceID == nil,
           let fallbackVibeSpaceID = vibespaceCatalogStore.vibespaces.first?.id {
            homeShell.showVibeSpace(fallbackVibeSpaceID)
        }

        guard activeVibeSpaceID != nil else {
            homeShell.showHome()
            return false
        }

        homeShell.dismissSurface()
        homeShell.dismissHome()
        homeShell.showVibeSpaceSidebar(.files)
        synchronizeVibeSpaceSidebarExpansion()
        return true
    }

    private func sanitizedShelfFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !trimmed.contains("/") && !trimmed.contains("\\") && trimmed != "." && trimmed != ".." else {
            return ""
        }
        return trimmed
    }
}

private struct ShelfActionError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
