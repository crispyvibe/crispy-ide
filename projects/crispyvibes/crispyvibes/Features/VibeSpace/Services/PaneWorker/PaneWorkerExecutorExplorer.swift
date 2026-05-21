import Foundation

extension PaneWorkerExecutor {
    static let maxImmediateChildrenForGitIgnoreProbe = 400

    static func loadImmediateChildren(of directory: URL) throws -> [WorkerFileNode] {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(directoryKeys),
            options: [.skipsPackageDescendants]
        )
        let ignoredPaths: Set<String>
        if childURLs.count <= maxImmediateChildrenForGitIgnoreProbe {
            ignoredPaths = gitIgnoredAbsolutePaths(for: directory, candidateURLs: childURLs)
        } else {
            ignoredPaths = []
        }

        let nodes = try childURLs.compactMap { childURL -> WorkerFileNode? in
            let values = try childURL.resourceValues(forKeys: directoryKeys)
            let isDirectory = values.isDirectory ?? false
            let normalizedPath = childURL.standardizedFileURL.path
            return WorkerFileNode(
                path: normalizedPath,
                isDirectory: isDirectory,
                isHidden: values.isHidden ?? false,
                isGitIgnored: ignoredPaths.contains(normalizedPath),
                children: nil
            )
        }

        return nodes.sorted(by: sortNodes)
    }

    static func sortNodes(_ lhs: WorkerFileNode, _ rhs: WorkerFileNode) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }

        let lhsName = URL(fileURLWithPath: lhs.path).lastPathComponent
        let rhsName = URL(fileURLWithPath: rhs.path).lastPathComponent
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
    }

    static func createItem(in directoryURL: URL, name: String, isDirectory: Bool) throws -> URL {
        let createdURL = uniqueURL(in: directoryURL, proposedName: name)
        if isDirectory {
            try fileManager.createDirectory(at: createdURL, withIntermediateDirectories: false)
        } else {
            guard fileManager.createFile(atPath: createdURL.path, contents: Data(), attributes: nil) else {
                throw PaneWorkerError.workerFailure("Unable to create file at \(createdURL.path).")
            }
        }
        return createdURL
    }

    static func renameItem(at oldURL: URL, toName newName: String) throws -> URL {
        let trimmedName = sanitizedPathComponent(newName)
        guard !trimmedName.isEmpty else {
            throw PaneWorkerError.workerFailure("Item name cannot be empty.")
        }

        let destinationURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmedName)
        guard destinationURL.path != oldURL.path else {
            return oldURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw PaneWorkerError.workerFailure("A file or folder named \(trimmedName) already exists.")
        }

        try fileManager.moveItem(at: oldURL, to: destinationURL)
        return destinationURL
    }

    static func moveItem(at sourceURL: URL, toDirectory destinationDirectoryURL: URL) throws -> URL {
        try transferItem(at: sourceURL, toDirectory: destinationDirectoryURL, operation: .move)
    }

    static func copyItem(at sourceURL: URL, toDirectory destinationDirectoryURL: URL) throws -> URL {
        try transferItem(at: sourceURL, toDirectory: destinationDirectoryURL, operation: .copy)
    }

    private enum FileTransferOperation {
        case move
        case copy
    }

    private static func transferItem(
        at sourceURL: URL,
        toDirectory destinationDirectoryURL: URL,
        operation: FileTransferOperation
    ) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let destinationDirectory = destinationDirectoryURL.standardizedFileURL

        var destinationDirectoryIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &destinationDirectoryIsDirectory),
              destinationDirectoryIsDirectory.boolValue else {
            throw PaneWorkerError.workerFailure("Destination folder does not exist.")
        }

        guard fileManager.fileExists(atPath: source.path) else {
            throw PaneWorkerError.workerFailure("Source file or folder does not exist.")
        }

        if source.deletingLastPathComponent() == destinationDirectory {
            if operation == .move {
                return source
            }
            throw PaneWorkerError.workerFailure("Source and destination folders are the same.")
        }

        if isDescendant(destinationDirectory, of: source) {
            let action = operation == .move ? "move" : "copy"
            throw PaneWorkerError.workerFailure("Cannot \(action) a folder into itself.")
        }

        let targetURL = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw PaneWorkerError.workerFailure("Destination already contains an item named \(source.lastPathComponent).")
        }

        switch operation {
        case .move:
            try fileManager.moveItem(at: source, to: targetURL)
        case .copy:
            try fileManager.copyItem(at: source, to: targetURL)
        }
        return targetURL
    }

    static func uniqueURL(in directory: URL, proposedName: String) -> URL {
        let baseName = (proposedName as NSString).deletingPathExtension
        let pathExtension = (proposedName as NSString).pathExtension

        var candidate = directory.appendingPathComponent(proposedName)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let indexedName: String
            if pathExtension.isEmpty {
                indexedName = "\(baseName) \(counter)"
            } else {
                indexedName = "\(baseName) \(counter).\(pathExtension)"
            }
            candidate = directory.appendingPathComponent(indexedName)
            counter += 1
        }
        return candidate
    }

    static func sanitizedPathComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !trimmed.contains("/") && !trimmed.contains("\\") && trimmed != "." && trimmed != ".." else {
            return ""
        }
        return trimmed
    }

    static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if candidatePath == ancestorPath {
            return true
        }
        let prefix = ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
        return candidatePath.hasPrefix(prefix)
    }
}
