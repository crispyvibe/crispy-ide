import Foundation

struct HomeVibeSpaceImportTargets {
    let directories: [URL]
    let files: [URL]
}

struct HomeVibeSpaceImportUseCase {
    func initialVibeSpaceName(
        for projectURLs: [URL],
        defaultName: String,
        existingNamesLowercased: Set<String>
    ) -> String {
        guard projectURLs.count > 1 else {
            return projectURLs.first?.lastPathComponent ?? defaultName
        }
        return nextTemporaryVibeSpaceName(
            defaultName: defaultName,
            existingNamesLowercased: existingNamesLowercased
        )
    }

    func nextTemporaryVibeSpaceName(
        defaultName: String,
        existingNamesLowercased: Set<String>
    ) -> String {
        if !existingNamesLowercased.contains(defaultName.lowercased()) {
            return defaultName
        }

        var suffix = 2
        while existingNamesLowercased.contains("\(defaultName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(defaultName) \(suffix)"
    }

    func resolvedVibeSpaceName(
        proposedName: String,
        projectURLs: [URL],
        defaultName: String,
        existingNamesLowercased: Set<String>
    ) -> String {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else { return trimmedName }
        return initialVibeSpaceName(
            for: projectURLs,
            defaultName: defaultName,
            existingNamesLowercased: existingNamesLowercased
        )
    }

    func normalizedUniqueDirectoryURLs(from urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []
        uniqueURLs.reserveCapacity(urls.count)

        for url in urls {
            let normalized = url.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { continue }
            uniqueURLs.append(normalized)
        }
        return uniqueURLs
    }

    func normalizedExistingExternalTargets(from urls: [URL]) -> HomeVibeSpaceImportTargets {
        var seenPaths = Set<String>()
        var directories: [URL] = []
        var files: [URL] = []
        let fileManager = FileManager.default

        for rawURL in urls {
            let normalizedURL = rawURL.standardizedFileURL
            guard seenPaths.insert(normalizedURL.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                directories.append(normalizedURL)
            } else {
                files.append(normalizedURL)
            }
        }

        return HomeVibeSpaceImportTargets(directories: directories, files: files)
    }
}
