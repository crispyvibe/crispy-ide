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

    /// F052: create an empty `.excalidraw` whiteboard in the app-global shelf
    /// staging directory, add it to the Shelf, and open it. The user can later
    /// drag the shelf row into a project to move the file there.
    func createNewWhiteboardInShelf() {
        let stagingDirectory = appContainer.appPersistenceStore
            .appFileURL(relativePath: "Whiteboards", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        } catch {
            ShelfItemDrag.logger.error("whiteboard staging dir create failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let url = WhiteboardDocument.createUntitled(in: stagingDirectory) else { return }
        openFilesInShelf([url])
    }

    /// F052: move a Shelf item into a project directory (drag Shelf row → file
    /// tree). Moves the file, then retargets any open editor tab and removes the
    /// item from the Shelf (it now lives in the project).
    func moveShelfItemToProject(sourcePath: String, targetDirectory: URL) {
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let targetDir = targetDirectory.standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        // M4: only allow dropping into a directory inside an open project.
        let projectRoots = activeVibeSpaceSession.projects.map { $0.rootURL.standardizedFileURL.path }
        let targetPath = targetDir.path
        guard projectRoots.contains(where: { targetPath == $0 || targetPath.hasPrefix($0 + "/") }) else {
            ShelfItemDrag.logger.error("shelf move rejected: target outside open projects: \(targetPath, privacy: .public)")
            return
        }

        var destinationURL = targetDir.appendingPathComponent(sourceURL.lastPathComponent).standardizedFileURL
        guard destinationURL.path != sourceURL.path else { return }

        // Avoid clobbering an existing file in the target directory.
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let ext = sourceURL.pathExtension
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            var suffix = 2
            repeat {
                let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
                destinationURL = targetDir.appendingPathComponent(name).standardizedFileURL
                suffix += 1
            } while FileManager.default.fileExists(atPath: destinationURL.path)
        }

        // B1: flush any unsaved buffered edits to the source file first, so the
        // move carries the latest content instead of a stale autosave snapshot.
        contentViewerStore.flushUnsavedEdits(forFileURL: sourceURL)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            // The open editor tab follows the file to its new project location...
            contentViewerStore.retargetFileSystemLocation(from: sourceURL, to: destinationURL)
            // ...and the item leaves the Shelf — it now lives in the project.
            shelfStore.removeFile(at: sourceURL.path)
            ShelfItemDrag.logger.info("shelf move OK: \(sourceURL.path, privacy: .public) -> \(destinationURL.path, privacy: .public)")
        } catch {
            ShelfItemDrag.logger.error("shelf move FAILED: \(error.localizedDescription, privacy: .public)")
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
