import Foundation

enum MarkdownImageCandidateScanner {
    private static let allowedImageExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif",
        "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"
    ]

    static func scan(baseDirectoryURL: URL?) -> [MarkdownImageCandidate] {
        guard let baseDirectoryURL else { return [] }
        let baseDirectory = baseDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .nameKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [MarkdownImageCandidate] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard allowedImageExtensions.contains(ext) else {
                continue
            }

            let filename = values.name ?? fileURL.lastPathComponent
            let relativePath = relativePathForFile(fileURL, baseDirectory: baseDirectory)
            guard !relativePath.isEmpty else {
                continue
            }
            candidates.append(
                MarkdownImageCandidate(
                    filename: filename,
                    relativePath: relativePath,
                    insertPath: relativePath,
                    previewURL: fileURL.absoluteString
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            let filenameOrder = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
            if filenameOrder == .orderedSame {
                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            return filenameOrder == .orderedAscending
        }
    }

    private static func relativePathForFile(_ fileURL: URL, baseDirectory: URL) -> String {
        let standardizedBasePath = baseDirectory.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filePath = fileURL.standardizedFileURL.path
        guard !standardizedBasePath.isEmpty else {
            return fileURL.lastPathComponent
        }

        let basePrefix = "/\(standardizedBasePath)/"
        guard filePath.hasPrefix(basePrefix) else {
            return fileURL.lastPathComponent
        }

        let relativePath = String(filePath.dropFirst(basePrefix.count))
        return relativePath.replacingOccurrences(of: "\\", with: "/")
    }
}
