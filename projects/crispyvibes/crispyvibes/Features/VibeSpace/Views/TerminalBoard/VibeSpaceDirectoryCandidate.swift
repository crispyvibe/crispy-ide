import Foundation

struct VibeSpaceDirectoryCandidate: Identifiable, Equatable {
    let path: String
    let displayPath: String
    let depth: Int

    var id: String { path }

    static func collect(
        from roots: [URL]
    ) -> [VibeSpaceDirectoryCandidate] {
        let fileManager = FileManager.default
        var candidates: [VibeSpaceDirectoryCandidate] = []
        var seenPaths = Set<String>()
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path

        for rootURL in roots {
            let normalizedRoot = rootURL.standardizedFileURL
            let rootPath = normalizedRoot.path
            if seenPaths.insert(rootPath).inserted {
                candidates.append(
                    VibeSpaceDirectoryCandidate(
                        path: rootPath,
                        displayPath: formatDisplayPath(for: rootPath),
                        depth: 0
                    )
                )
            }

            // Avoid broad home-directory crawling to prevent privacy prompts and UI stalls.
            guard rootPath != homePath else { continue }

            guard let children = try? fileManager.contentsOfDirectory(
                at: normalizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            var depth1Count = 0
            for childURL in children {
                guard depth1Count < 60 else { break }
                guard let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else {
                    continue
                }

                let standardizedChild = childURL.standardizedFileURL
                let childPath = standardizedChild.path
                guard !skippedDirectoryNames.contains(standardizedChild.lastPathComponent) else {
                    continue
                }
                guard seenPaths.insert(childPath).inserted else { continue }
                candidates.append(
                    VibeSpaceDirectoryCandidate(
                        path: childPath,
                        displayPath: formatDisplayPath(for: childPath),
                        depth: 1
                    )
                )
                depth1Count += 1

                // Depth 2: scan grandchildren
                guard let grandchildren = try? fileManager.contentsOfDirectory(
                    at: standardizedChild,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }

                var depth2Count = 0
                for grandchildURL in grandchildren {
                    guard depth2Count < 20 else { break }
                    guard let gcValues = try? grandchildURL.resourceValues(forKeys: [.isDirectoryKey]),
                          gcValues.isDirectory == true else {
                        continue
                    }

                    let standardizedGrandchild = grandchildURL.standardizedFileURL
                    let gcPath = standardizedGrandchild.path
                    guard !skippedDirectoryNames.contains(standardizedGrandchild.lastPathComponent) else {
                        continue
                    }
                    guard seenPaths.insert(gcPath).inserted else { continue }
                    candidates.append(
                        VibeSpaceDirectoryCandidate(
                            path: gcPath,
                            displayPath: formatDisplayPath(for: gcPath),
                            depth: 2
                        )
                    )
                    depth2Count += 1
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            return lhs.displayPath.localizedCaseInsensitiveCompare(rhs.displayPath) == .orderedAscending
        }
    }

    static func formatDisplayPath(for path: String) -> String {
        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private static let skippedDirectoryNames: Set<String> = [
        "node_modules", ".build", "DerivedData", ".git", ".svn", ".hg",
        "Pods", "Carthage", ".swiftpm", "__pycache__", ".tox", ".venv",
        "dist", "build", ".next", ".nuxt"
    ]
}
