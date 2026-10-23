import Foundation

/// Streams files and directory trees from one active SSH project to local storage.
actor RemoteItemTransferService: RemoteItemTransferring {
    private struct ManifestEntry: Sendable {
        let remotePath: String
        let relativePath: String
        let isDirectory: Bool
        let size: UInt64
        let modificationTime: UInt32?
    }

    private struct Manifest: Sendable {
        let canonicalRoot: String
        let entries: [ManifestEntry]
        let totalBytes: UInt64
        let totalFiles: Int
    }

    private let connection: SSHConnection
    private let remoteRoot: String
    private let fileManager: FileManager
    private let maximumItemCount = 250_000
    private let maximumDepth = 256

    init(
        connection: SSHConnection,
        remoteRoot: String,
        fileManager: FileManager = .default
    ) {
        self.connection = connection
        self.remoteRoot = remoteRoot
        self.fileManager = fileManager
    }

    func download(
        _ item: RemoteTransferItem,
        to destinationURL: URL,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) async throws -> RemoteTransferReceipt {
        try await transfer(item, to: destinationURL, isTemporary: false, progress: progress)
    }

    func materializeForExternalOpen(
        _ item: RemoteTransferItem,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) async throws -> RemoteTransferReceipt {
        let container = try makeTemporaryContainer()
        let destination = container.appendingPathComponent(
            Self.safeDisplayName(item.displayName),
            isDirectory: item.isDirectory
        )
        do {
            return try await transfer(item, to: destination, isTemporary: true, progress: progress)
        } catch {
            try? fileManager.removeItem(at: container)
            throw error
        }
    }

    private func transfer(
        _ item: RemoteTransferItem,
        to destinationURL: URL,
        isTemporary: Bool,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) async throws -> RemoteTransferReceipt {
        progress(RemoteTransferProgress(
            phase: .preparing,
            completedBytes: 0,
            totalBytes: 0,
            completedFiles: 0,
            totalFiles: 0,
            currentItem: item.displayName
        ))

        try await connection.ensureFileServicesConnected()
        let sftp = try connection.makeDedicatedSFTP()

        return try await withTaskCancellationHandler {
            defer { sftp.terminate() }
            let manifest = try Self.buildManifest(
                item: item,
                remoteRoot: remoteRoot,
                sftp: sftp,
                maximumItemCount: maximumItemCount,
                maximumDepth: maximumDepth
            )
            try Task.checkCancellation()
            progress(RemoteTransferProgress(
                phase: .transferring,
                completedBytes: 0,
                totalBytes: manifest.totalBytes,
                completedFiles: 0,
                totalFiles: manifest.totalFiles,
                currentItem: item.displayName
            ))
            try Self.publish(
                manifest: manifest,
                destinationURL: destinationURL,
                sftp: sftp,
                fileManager: fileManager,
                progress: progress
            )
            return RemoteTransferReceipt(localURL: destinationURL, isTemporary: isTemporary)
        } onCancel: {
            sftp.terminate()
        }
    }

    private func makeTemporaryContainer() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("crispyvibes-remote-open", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        cleanupStaleTemporaryContainers(in: root)

        let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: container, withIntermediateDirectories: false)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path)
        return container
    }

    private func cleanupStaleTemporaryContainers(in root: URL) {
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

    private static func buildManifest(
        item: RemoteTransferItem,
        remoteRoot: String,
        sftp: SFTPSubprocess,
        maximumItemCount: Int,
        maximumDepth: Int
    ) throws -> Manifest {
        let canonicalRoot = try sftp.realpath(remoteRoot)
        let sourcePath = item.path == remoteRoot ? canonicalRoot : item.path
        let sourceAttributes = try sftp.lstat(sourcePath)
        let sourceKind = sourceAttributes.fileKind
        if sourceKind == .symbolicLink {
            throw RemoteTransferError.symbolicLinkUnsupported(item.displayName)
        }
        guard (item.isDirectory && sourceKind == .directory)
                || (!item.isDirectory && sourceKind == .regular) else {
            throw RemoteTransferError.unsupportedItem(item.displayName)
        }
        let canonicalSource = try sftp.realpath(sourcePath)
        guard isPath(canonicalSource, within: canonicalRoot) else {
            throw RemoteTransferError.outsideProjectRoot
        }

        if !item.isDirectory {
            guard let size = sourceAttributes.size,
                  let modificationTime = sourceAttributes.mtime else {
                throw RemoteTransferError.missingMetadata(item.displayName)
            }
            let entry = ManifestEntry(
                remotePath: canonicalSource,
                relativePath: "",
                isDirectory: false,
                size: size,
                modificationTime: modificationTime
            )
            return Manifest(
                canonicalRoot: canonicalRoot,
                entries: [entry],
                totalBytes: entry.size,
                totalFiles: 1
            )
        }

        var entries = [ManifestEntry(
            remotePath: canonicalSource,
            relativePath: "",
            isDirectory: true,
            size: 0,
            modificationTime: sourceAttributes.mtime
        )]
        var pending: [(remotePath: String, relativePath: String, depth: Int)] = [
            (canonicalSource, "", 0)
        ]
        var totalBytes: UInt64 = 0
        var totalFiles = 0

        while let directory = pending.popLast() {
            try Task.checkCancellation()
            guard directory.depth <= maximumDepth else {
                throw RemoteTransferError.limitExceeded
            }
            let directoryAttributes = try sftp.lstat(directory.remotePath)
            guard directoryAttributes.fileKind == .directory else {
                throw RemoteTransferError.sourceChanged(directory.relativePath)
            }
            let canonicalDirectory = try sftp.realpath(directory.remotePath)
            guard isPath(canonicalDirectory, within: canonicalRoot) else {
                throw RemoteTransferError.outsideProjectRoot
            }

            let remainingEntryBudget = maximumItemCount - entries.count
            guard remainingEntryBudget > 0 else { throw RemoteTransferError.limitExceeded }
            let children: [SFTPEntry]
            do {
                children = try sftp.listDirectory(
                    canonicalDirectory,
                    maximumEntries: remainingEntryBudget
                )
            } catch let error as SFTPError {
                if case .entryLimitExceeded = error {
                    throw RemoteTransferError.limitExceeded
                }
                throw error
            }
            for child in children {
                try Task.checkCancellation()
                guard isSafeName(child.name) else {
                    throw RemoteTransferError.invalidName(child.name)
                }
                guard entries.count < maximumItemCount else {
                    throw RemoteTransferError.limitExceeded
                }
                let relativePath = directory.relativePath.isEmpty
                    ? child.name
                    : (directory.relativePath as NSString).appendingPathComponent(child.name)
                let attributes = try sftp.lstat(child.path)
                switch attributes.fileKind {
                case .symbolicLink:
                    throw RemoteTransferError.symbolicLinkUnsupported(relativePath)
                case .other:
                    throw RemoteTransferError.unsupportedItem(relativePath)
                case .directory, .regular:
                    break
                }
                let canonicalChild = try sftp.realpath(child.path)
                guard isPath(canonicalChild, within: canonicalRoot) else {
                    throw RemoteTransferError.outsideProjectRoot
                }

                switch attributes.fileKind {
                case .directory:
                    entries.append(ManifestEntry(
                        remotePath: canonicalChild,
                        relativePath: relativePath,
                        isDirectory: true,
                        size: 0,
                        modificationTime: attributes.mtime
                    ))
                    pending.append((canonicalChild, relativePath, directory.depth + 1))
                case .regular:
                    guard let size = attributes.size,
                          let modificationTime = attributes.mtime else {
                        throw RemoteTransferError.missingMetadata(relativePath)
                    }
                    totalBytes = try adding(totalBytes, size)
                    totalFiles += 1
                    entries.append(ManifestEntry(
                        remotePath: canonicalChild,
                        relativePath: relativePath,
                        isDirectory: false,
                        size: size,
                        modificationTime: modificationTime
                    ))
                case .symbolicLink, .other:
                    break
                }
            }
        }

        entries.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return Manifest(
            canonicalRoot: canonicalRoot,
            entries: entries,
            totalBytes: totalBytes,
            totalFiles: totalFiles
        )
    }

    private static func publish(
        manifest: Manifest,
        destinationURL: URL,
        sftp: SFTPSubprocess,
        fileManager: FileManager,
        progress: @escaping @Sendable (RemoteTransferProgress) -> Void
    ) throws {
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stagingURL = parent.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).crispy-partial-\(UUID().uuidString)",
            isDirectory: manifest.entries.first?.isDirectory == true
        )
        try? fileManager.removeItem(at: stagingURL)

        do {
            let rootIsDirectory = manifest.entries.first?.isDirectory == true
            if rootIsDirectory {
                try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagingURL.path)
            }

            var completedBytes: UInt64 = 0
            var completedFiles = 0
            for entry in manifest.entries {
                try Task.checkCancellation()
                let localURL = entry.relativePath.isEmpty
                    ? stagingURL
                    : stagingURL.appendingPathComponent(entry.relativePath, isDirectory: entry.isDirectory)
                if entry.isDirectory {
                    if entry.relativePath.isEmpty { continue }
                    try fileManager.createDirectory(at: localURL, withIntermediateDirectories: false)
                    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: localURL.path)
                    continue
                }

                let initialAttributes = try sftp.lstat(entry.remotePath)
                let canonicalPath = try sftp.realpath(entry.remotePath)
                guard initialAttributes.fileKind == .regular,
                      canonicalPath == entry.remotePath,
                      isPath(canonicalPath, within: manifest.canonicalRoot),
                      initialAttributes.size == entry.size,
                      initialAttributes.mtime == entry.modificationTime else {
                    throw RemoteTransferError.sourceChanged(entry.relativePath)
                }

                try fileManager.createDirectory(
                    at: localURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var lastReportedBytes = completedBytes
                let writtenBytes = try sftp.downloadFile(entry.remotePath, to: localURL) { fileBytes in
                    let aggregate = completedBytes + fileBytes
                    if aggregate >= lastReportedBytes + 256 * 1024 || aggregate == manifest.totalBytes {
                        lastReportedBytes = aggregate
                        progress(RemoteTransferProgress(
                            phase: .transferring,
                            completedBytes: aggregate,
                            totalBytes: manifest.totalBytes,
                            completedFiles: completedFiles,
                            totalFiles: manifest.totalFiles,
                            currentItem: entry.relativePath.isEmpty
                                ? destinationURL.lastPathComponent
                                : entry.relativePath
                        ))
                    }
                }
                guard writtenBytes == entry.size else {
                    throw RemoteTransferError.incompleteTransfer(entry.relativePath)
                }
                let finalAttributes = try sftp.lstat(entry.remotePath)
                let finalCanonicalPath = try sftp.realpath(entry.remotePath)
                guard finalAttributes.fileKind == .regular,
                      finalCanonicalPath == entry.remotePath,
                      isPath(finalCanonicalPath, within: manifest.canonicalRoot),
                      finalAttributes.size == entry.size,
                      finalAttributes.mtime == entry.modificationTime else {
                    throw RemoteTransferError.sourceChanged(entry.relativePath)
                }
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localURL.path)
                completedBytes = try adding(completedBytes, entry.size)
                completedFiles += 1
                progress(RemoteTransferProgress(
                    phase: .transferring,
                    completedBytes: completedBytes,
                    totalBytes: manifest.totalBytes,
                    completedFiles: completedFiles,
                    totalFiles: manifest.totalFiles,
                    currentItem: entry.relativePath.isEmpty
                        ? destinationURL.lastPathComponent
                        : entry.relativePath
                ))
            }

            try Task.checkCancellation()
            progress(RemoteTransferProgress(
                phase: .publishing,
                completedBytes: completedBytes,
                totalBytes: manifest.totalBytes,
                completedFiles: completedFiles,
                totalFiles: manifest.totalFiles,
                currentItem: destinationURL.lastPathComponent
            ))
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func safeDisplayName(_ value: String) -> String {
        let candidate = (value as NSString).lastPathComponent
        return isSafeName(candidate) ? candidate : "remote-item"
    }

    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    static func isPath(_ candidate: String, within root: String) -> Bool {
        let root = URL(fileURLWithPath: root).standardizedFileURL.path
        let candidate = URL(fileURLWithPath: candidate).standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func adding(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw RemoteTransferError.limitExceeded }
        return sum
    }
}

enum RemoteTransferError: LocalizedError {
    case outsideProjectRoot
    case symbolicLinkUnsupported(String)
    case unsupportedItem(String)
    case invalidName(String)
    case missingMetadata(String)
    case incompleteTransfer(String)
    case sourceChanged(String)
    case limitExceeded

    var errorDescription: String? {
        switch self {
        case .outsideProjectRoot:
            return AppStrings.RemoteTransfer.outsideProjectRoot
        case .symbolicLinkUnsupported(let path):
            return AppStrings.RemoteTransfer.symbolicLinkUnsupported(path)
        case .unsupportedItem(let path):
            return AppStrings.RemoteTransfer.unsupportedItem(path)
        case .invalidName(let name):
            return AppStrings.RemoteTransfer.invalidName(name)
        case .missingMetadata(let path):
            return AppStrings.RemoteTransfer.missingMetadata(path)
        case .incompleteTransfer(let path):
            return AppStrings.RemoteTransfer.incompleteTransfer(path)
        case .sourceChanged(let path):
            return AppStrings.RemoteTransfer.sourceChanged(path)
        case .limitExceeded:
            return AppStrings.RemoteTransfer.limitExceeded
        }
    }
}
