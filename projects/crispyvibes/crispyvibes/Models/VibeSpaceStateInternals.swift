import Foundation

@MainActor
extension VibeSpaceState {
    mutating func pruneColorTags() {
        let validPaths = Set(projects.map { $0.projectIdentifier } + unresolvedProjectPaths)
        projectColorTagsByPath = projectColorTagsByPath.filter { validPaths.contains($0.key) }
        projectStartupOverridesByPath = projectStartupOverridesByPath.filter { validPaths.contains($0.key) }
        projectACPAgentOverrideIDsByPath = projectACPAgentOverrideIDsByPath.filter { validPaths.contains($0.key) }
        projectTerminalShellOverridesByPath = projectTerminalShellOverridesByPath.filter { validPaths.contains($0.key) }
        let validProjectPaths = Set(projects.map { $0.projectIdentifier })
        projectShortcutByPath = projectShortcutByPath.filter { validProjectPaths.contains($0.key) }
        normalizeProjectShortcuts()
    }

    mutating func moveProjectAssociatedState(
        from sourcePath: String,
        to destinationPath: String,
        onlyIfDestinationMissing: Bool,
        includeShortcut: Bool = true
    ) {
        if let movingTag = projectColorTagsByPath[sourcePath],
           !onlyIfDestinationMissing || projectColorTagsByPath[destinationPath] == nil {
            projectColorTagsByPath[destinationPath] = movingTag
        }

        if let movingStartupOverride = projectStartupOverridesByPath[sourcePath],
           !onlyIfDestinationMissing || projectStartupOverridesByPath[destinationPath] == nil {
            projectStartupOverridesByPath[destinationPath] = movingStartupOverride
        }

        if let movingACPAgentOverrideID = projectACPAgentOverrideIDsByPath[sourcePath],
           !onlyIfDestinationMissing || projectACPAgentOverrideIDsByPath[destinationPath] == nil {
            projectACPAgentOverrideIDsByPath[destinationPath] = movingACPAgentOverrideID
        }

        if let movingShellOverride = projectTerminalShellOverridesByPath[sourcePath],
           !onlyIfDestinationMissing || projectTerminalShellOverridesByPath[destinationPath] == nil {
            projectTerminalShellOverridesByPath[destinationPath] = movingShellOverride
        }

        if includeShortcut,
           let movingShortcut = projectShortcutByPath[sourcePath],
           !onlyIfDestinationMissing || projectShortcutByPath[destinationPath] == nil {
            projectShortcutByPath[destinationPath] = movingShortcut
        }
    }

    mutating func removeProjectAssociatedState(
        for path: String,
        includeShortcut: Bool = true
    ) {
        projectColorTagsByPath.removeValue(forKey: path)
        projectStartupOverridesByPath.removeValue(forKey: path)
        projectACPAgentOverrideIDsByPath.removeValue(forKey: path)
        projectTerminalShellOverridesByPath.removeValue(forKey: path)
        if includeShortcut {
            projectShortcutByPath.removeValue(forKey: path)
        }
    }

    mutating func normalizeProjectShortcuts() {
        let validProjectPaths = Set(projects.map { $0.projectIdentifier })

        var normalizedShortcuts: [String: Int] = [:]
        var usedShortcuts = Set<Int>()
        for (path, shortcut) in projectShortcutByPath.sorted(by: { $0.key < $1.key }) {
            guard validProjectPaths.contains(path) else { continue }
            guard (1...9).contains(shortcut) else { continue }
            guard !usedShortcuts.contains(shortcut) else { continue }
            normalizedShortcuts[path] = shortcut
            usedShortcuts.insert(shortcut)
        }

        var nextShortcut = 1
        for path in projects.map(\.projectIdentifier) {
            guard normalizedShortcuts[path] == nil else { continue }
            while usedShortcuts.contains(nextShortcut), nextShortcut <= 9 {
                nextShortcut += 1
            }
            guard nextShortcut <= 9 else { break }
            normalizedShortcuts[path] = nextShortcut
            usedShortcuts.insert(nextShortcut)
            nextShortcut += 1
        }

        projectShortcutByPath = normalizedShortcuts
    }

    mutating func reindexProjectShortcutsByProjectOrder() {
        var reindexedShortcuts: [String: Int] = [:]
        for (offset, path) in projects.map(\.projectIdentifier).enumerated() where offset < 9 {
            reindexedShortcuts[path] = offset + 1
        }
        projectShortcutByPath = reindexedShortcuts
    }

    mutating func assignAutoColorTagIfNeeded(forPath path: String) {
        let normalizedPath = Self.normalizedPath(from: path)
        guard projectColorTagsByPath[normalizedPath] == nil else { return }
        projectColorTagsByPath[normalizedPath] = Self.autoAssignedColorTag(forPath: normalizedPath)
    }

    static func autoAssignedColorTag(forPath path: String) -> ProjectColorTag {
        let hash = stablePathHash(path)
        let hue = Double(hash % 360) / 360.0
        let saturationSeed = Double((hash >> 9) & 0xFF) / 255.0
        let brightnessSeed = Double((hash >> 17) & 0xFF) / 255.0
        let saturation = 0.58 + (0.24 * saturationSeed)
        let brightness = 0.72 + (0.20 * brightnessSeed)
        let rgb = rgbFromHSV(
            h: hue,
            s: saturation,
            v: brightness
        )
        return ProjectColorTag(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func stablePathHash(_ path: String) -> UInt64 {
        let normalized = normalizedPath(from: path)
        var hash: UInt64 = 1469598103934665603
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    static func rgbFromHSV(h: Double, s: Double, v: Double) -> (red: Double, green: Double, blue: Double) {
        let hue = h.truncatingRemainder(dividingBy: 1.0)
        let saturation = max(0.0, min(1.0, s))
        let value = max(0.0, min(1.0, v))

        if saturation == 0 {
            return (value, value, value)
        }

        let sector = hue * 6.0
        let index = Int(floor(sector))
        let fraction = sector - Double(index)
        let p = value * (1.0 - saturation)
        let q = value * (1.0 - saturation * fraction)
        let t = value * (1.0 - saturation * (1.0 - fraction))

        switch index % 6 {
        case 0:
            return (value, t, p)
        case 1:
            return (q, value, p)
        case 2:
            return (p, value, t)
        case 3:
            return (p, q, value)
        case 4:
            return (t, p, value)
        default:
            return (value, p, q)
        }
    }

    nonisolated static func existingDirectoryPaths(for paths: [String]) async -> Set<String> {
        let normalizedPaths = paths
            .map(Self.normalizedPath(from:))
            .reduce(into: (ordered: [String](), seen: Set<String>())) { state, path in
                guard state.seen.insert(path).inserted else { return }
                state.ordered.append(path)
            }
            .ordered

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            var existingPaths = Set<String>()
            existingPaths.reserveCapacity(normalizedPaths.count)
            for path in normalizedPaths where Self.isExistingDirectory(path: path, fileManager: fileManager) {
                existingPaths.insert(path)
            }
            return existingPaths
        }.value
    }

    nonisolated static func isExistingDirectory(path: String) -> Bool {
        if path.hasPrefix("ssh://") { return true } // Remote projects are always "existing" (connection is async)
        return isExistingDirectory(path: path, fileManager: FileManager.default)
    }

    nonisolated static func isExistingDirectory(path: String, fileManager: FileManager) -> Bool {
        if path.hasPrefix("ssh://") { return true }
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    nonisolated static func normalizedPath(from rawPath: String) -> String {
        // SSH URIs must not be treated as local filesystem paths
        if rawPath.hasPrefix("ssh://") { return rawPath }
        let cleanedRawPath = rawPath.replacingOccurrences(of: "\\/", with: "/")
        return URL(fileURLWithPath: cleanedRawPath).standardizedFileURL.path
    }
}
