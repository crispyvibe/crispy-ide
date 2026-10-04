import Foundation

extension LocalScreenCaptureHistoryRepository {
    func createItemDirectories(at item: URL) throws {
        try createDirectory(item)
        try createDirectory(item.appendingPathComponent("versions", isDirectory: true))
        try createDirectory(item.appendingPathComponent("thumbnails", isDirectory: true))
    }

    func createDirectory(_ url: URL) throws {
        try fileOperation {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func excludeRootFromBackup() throws {
        do {
            let values = try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey, .volumeIsLocalKey])
            guard values.isSymbolicLink != true,
                  values.volumeIsLocal != false,
                  !fileManager.isUbiquitousItem(at: rootURL) else {
                throw ScreenCaptureHistoryError.invalidRoot
            }
            var mutableRoot = rootURL
            var backupValues = URLResourceValues()
            backupValues.isExcludedFromBackup = true
            try mutableRoot.setResourceValues(backupValues)
        } catch let error as ScreenCaptureHistoryError {
            throw error
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func directoryContents(_ url: URL) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func removeContents(of directory: URL) throws {
        for url in try directoryContentsIncludingHidden(directory) {
            try Task.checkCancellation()
            try fileOperation { try fileManager.removeItem(at: url) }
        }
    }

    func directoryContentsIncludingHidden(_ url: URL) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func isRegularNonSymbolicFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    func fileOperation(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch let error as ScreenCaptureHistoryError {
            throw error
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func mapped(_ error: Error) -> ScreenCaptureHistoryError {
        if let error = error as? ScreenCaptureHistoryError { return error }
        if error is CancellationError { return .cancelled }
        return .fileOperationFailed
    }
}
