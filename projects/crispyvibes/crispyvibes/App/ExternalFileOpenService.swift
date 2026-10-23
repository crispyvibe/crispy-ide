import Foundation

@MainActor
final class ExternalFileOpenService: ExternalFileOpening {
    private let openURL: @MainActor (URL) -> Bool
    private let fileManager: FileManager

    convenience init(
        interaction: VibeSpaceInteractionService,
        fileManager: FileManager = .default
    ) {
        self.init(fileManager: fileManager, openURL: { interaction.open($0) })
    }

    init(
        fileManager: FileManager = .default,
        openURL: @escaping @MainActor (URL) -> Bool
    ) {
        self.openURL = openURL
        self.fileManager = fileManager
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("crispyvibes-remote-open", isDirectory: true)
        if (try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)) != nil {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            cleanupStaleContainers(in: root)
        }
    }

    func open(
        fileURL: URL,
        fileContentProvider: (any FileContentProviding)?
    ) async throws -> URL {
        guard let fileContentProvider,
              fileContentProvider.requiresMaterializedLocalPreview else {
            guard openURL(fileURL) else { throw ExternalFileOpenError.launchFailed }
            return fileURL
        }

        let data = try await fileContentProvider.readFile(at: fileURL.path)
        try Task.checkCancellation()
        let localURL = try stage(data: data, sourceURL: fileURL)
        guard openURL(localURL) else {
            try? fileManager.removeItem(at: localURL.deletingLastPathComponent())
            throw ExternalFileOpenError.launchFailed
        }
        return localURL
    }

    private func stage(data: Data, sourceURL: URL) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("crispyvibes-remote-open", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        cleanupStaleContainers(in: root)

        let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: false)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path)
            let name = Self.safeName(sourceURL.lastPathComponent)
            let destination = container.appendingPathComponent(name)
            try data.write(to: destination, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? fileManager.removeItem(at: container)
            throw error
        }
    }

    private func cleanupStaleContainers(in root: URL) {
        let expiration = Date().addingTimeInterval(-24 * 60 * 60)
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for child in children {
            let modified = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < expiration }) == true {
                try? fileManager.removeItem(at: child)
            }
        }
    }

    private static func safeName(_ value: String) -> String {
        let name = (value as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return "remote-file"
        }
        return name
    }
}

enum ExternalFileOpenError: LocalizedError, Equatable {
    case launchFailed

    var errorDescription: String? {
        AppStrings.Editor.systemApplicationLaunchFailed
    }
}
