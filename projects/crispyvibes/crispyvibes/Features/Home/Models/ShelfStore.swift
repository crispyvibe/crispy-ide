import Foundation
import SwiftUI

struct ShelfSnapshot: Codable, Equatable {
    var filePaths: [String]
    var selectedFilePath: String?
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var filePaths: [String] = []
    @Published private(set) var selectedFilePath: String?

    private let persistenceStore: AppPersistenceDataStore
    private let shelfFileURL: URL
    private var didLoad = false

    init(
        persistenceStore: AppPersistenceDataStore
    ) {
        self.persistenceStore = persistenceStore
        self.shelfFileURL = persistenceStore.appFileURL(relativePath: "shelf-state.json")
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let shelf = persistenceStore.load(ShelfSnapshot.self, from: shelfFileURL) else {
            filePaths = []
            selectedFilePath = nil
            return
        }

        filePaths = normalizedUniquePaths(shelf.filePaths)
        if let selectedFilePath = shelf.selectedFilePath {
            let normalized = URL(fileURLWithPath: selectedFilePath).standardizedFileURL.path
            self.selectedFilePath = filePaths.contains(normalized) ? normalized : filePaths.first
        } else {
            selectedFilePath = filePaths.first
        }
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> URL? {
        let normalized = urls.map { $0.standardizedFileURL }
        guard !normalized.isEmpty else { return nil }

        var mergedPaths = filePaths
        for url in normalized.reversed() {
            let path = url.path
            mergedPaths.removeAll(where: { $0 == path })
            mergedPaths.insert(path, at: 0)
        }
        filePaths = normalizedUniquePaths(mergedPaths)

        if let selected = normalized.first {
            selectedFilePath = selected.path
            persist()
            return selected
        }

        persist()
        return nil
    }

    @discardableResult
    func selectFile(at path: String) -> URL? {
        let normalizedURL = URL(fileURLWithPath: path).standardizedFileURL
        guard filePaths.contains(normalizedURL.path) else { return nil }
        selectedFilePath = normalizedURL.path
        persist()
        return normalizedURL
    }

    /// Adds `url` to the shelf only if it is not already present, preserving
    /// existing ordering for already-shelved entries (unlike `addFiles` which
    /// always moves items to the front and changes selection).
    ///
    /// - Parameters:
    ///   - url: File or directory to add.
    ///   - select: When true, the entry becomes the selected shelf item even
    ///     if it was already present.
    /// - Returns: `true` if a new entry was added, `false` if the item was
    ///   already in the shelf.
    @discardableResult
    func addFileIfAbsent(_ url: URL, select: Bool) -> Bool {
        let normalized = url.standardizedFileURL
        let path = normalized.path
        let alreadyPresent = filePaths.contains(path)
        if !alreadyPresent {
            filePaths.insert(path, at: 0)
            filePaths = normalizedUniquePaths(filePaths)
        }
        if select {
            selectedFilePath = path
        } else if !alreadyPresent && selectedFilePath == nil {
            selectedFilePath = path
        }
        persist()
        return !alreadyPresent
    }

    @discardableResult
    func removeFile(at path: String) -> String? {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        filePaths.removeAll(where: { $0 == normalizedPath })

        if selectedFilePath == normalizedPath {
            selectedFilePath = filePaths.first
        }

        persist()
        return selectedFilePath
    }

    func clear() {
        filePaths = []
        selectedFilePath = nil
        persist()
    }

    func resetForFreshStart() {
        filePaths = []
        selectedFilePath = nil
        didLoad = false
    }

    @discardableResult
    func ensureSelectionIfNeeded() -> String? {
        guard !filePaths.isEmpty else { return nil }
        let resolvedPath = selectedFilePath.flatMap { selectedPath in
            filePaths.contains(selectedPath) ? selectedPath : nil
        } ?? filePaths.first
        guard let resolvedPath else { return nil }
        if selectedFilePath != resolvedPath {
            selectedFilePath = resolvedPath
            persist()
        }
        return resolvedPath
    }

    func syncSelection(from activeFileURL: URL?) {
        guard let activeFileURL else { return }
        let normalizedPath = activeFileURL.standardizedFileURL.path
        guard filePaths.contains(normalizedPath) else { return }
        selectedFilePath = normalizedPath
        persist()
    }

    func retargetFile(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        guard oldPath != newPath else { return }

        var didChange = false
        let updatedPaths = filePaths.map { path -> String in
            guard path == oldPath else { return path }
            didChange = true
            return newPath
        }

        guard didChange else { return }

        filePaths = normalizedUniquePaths(updatedPaths)
        if selectedFilePath == oldPath {
            selectedFilePath = newPath
        }
        persist()
    }

    private func persist() {
        let normalizedPaths = normalizedUniquePaths(filePaths)
        filePaths = normalizedPaths
        let selectedPath = selectedFilePath.flatMap { selectedPath in
            normalizedPaths.contains(selectedPath) ? selectedPath : normalizedPaths.first
        }
        selectedFilePath = selectedPath

        guard !normalizedPaths.isEmpty else {
            persistenceStore.removeFile(at: shelfFileURL)
            return
        }

        persistenceStore.save(
            ShelfSnapshot(
                filePaths: normalizedPaths,
                selectedFilePath: selectedPath
            ),
            to: shelfFileURL
        )
    }

    private func normalizedUniquePaths(_ rawPaths: [String]) -> [String] {
        rawPaths.reduce(into: (ordered: [String](), seen: Set<String>())) { state, rawPath in
            let normalized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            guard state.seen.insert(normalized).inserted else { return }
            state.ordered.append(normalized)
        }.ordered
    }
}
