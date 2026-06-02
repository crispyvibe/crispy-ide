import Foundation

@MainActor
enum VibeSpaceTerminalBoardTerminalScope: Hashable {
    case project(String)
    case standalone
}

@MainActor
struct VibeSpaceTerminalBoardTerminalIdentity: Hashable {
    let scope: VibeSpaceTerminalBoardTerminalScope
    let tabID: UUID
}

@MainActor
struct VibeSpaceTerminalBoardDesiredTabState {
    let desiredByIdentity: [VibeSpaceTerminalBoardTerminalIdentity: TerminalTab]
    let orderedIdentities: [VibeSpaceTerminalBoardTerminalIdentity]
    let activeProjectPaths: Set<String>

    init(
        orderedProjectPaths: [String],
        projectsByPath: [String: AnyProjectSession],
        hiddenTerminalIDsByProjectPath: [String: Set<UUID>],
        standaloneTabs: [TerminalTab],
        excludedTerminalIdentities: Set<VibeSpaceTerminalBoardTerminalIdentity> = []
    ) {
        var desiredByIdentity: [VibeSpaceTerminalBoardTerminalIdentity: TerminalTab] = [:]
        var orderedIdentities: [VibeSpaceTerminalBoardTerminalIdentity] = []
        orderedIdentities.reserveCapacity(VibeSpaceTerminalBoardLayout.maximumTileCount)

        for projectPath in orderedProjectPaths {
            guard let project = projectsByPath[projectPath] else { continue }
            for tab in project.terminal.tabs {
                guard !(hiddenTerminalIDsByProjectPath[projectPath]?.contains(tab.id) ?? false) else { continue }
                let identity = VibeSpaceTerminalBoardTerminalIdentity(
                    scope: .project(projectPath),
                    tabID: tab.id
                )
                guard !excludedTerminalIdentities.contains(identity) else { continue }
                desiredByIdentity[identity] = tab
                orderedIdentities.append(identity)
            }
        }

        for tab in standaloneTabs {
            let identity = VibeSpaceTerminalBoardTerminalIdentity(
                scope: .standalone,
                tabID: tab.id
            )
            guard !excludedTerminalIdentities.contains(identity) else { continue }
            desiredByIdentity[identity] = tab
            orderedIdentities.append(identity)
        }

        self.desiredByIdentity = desiredByIdentity
        self.orderedIdentities = orderedIdentities
        self.activeProjectPaths = Set(orderedProjectPaths)
    }
}

@MainActor
enum VibeSpaceTerminalBoardLayoutSync {
    static func syncTiles(
        layout: inout VibeSpaceTerminalBoardLayout,
        desiredTabState: VibeSpaceTerminalBoardDesiredTabState,
        allKnownTabIDs: Set<UUID> = [],
        addMissingTabs: Bool = true
    ) -> Bool {
        var didChange = false
        var seenIdentities = Set<VibeSpaceTerminalBoardTerminalIdentity>()
        var pendingTileCountByProject: [String: Int] = [:]

        layout.minimizedTiles.removeAll { tile in
            guard tile.isTerminal else { return false }
            guard let identity = terminalIdentity(for: tile),
                  desiredTabState.desiredByIdentity[identity] != nil else {
                // Tab exists but is hidden/filtered → remove. Tab doesn't exist yet → keep (hydration pending).
                let tabExists = tile.terminalTabID.map { allKnownTabIDs.contains($0) } ?? false
                if !tabExists, let pp = tile.projectPath {
                    pendingTileCountByProject[pp, default: 0] += 1
                    return false
                }
                didChange = true
                return true
            }
            seenIdentities.insert(identity)
            return false
        }

        for existingTile in layout.tiles {
            guard existingTile.isTerminal else { continue }
            guard let identity = terminalIdentity(for: existingTile),
                  let desiredTab = desiredTabState.desiredByIdentity[identity],
                  !seenIdentities.contains(identity) else {
                let tabExists = existingTile.terminalTabID.map { allKnownTabIDs.contains($0) } ?? false
                if !tabExists, let pp = existingTile.projectPath {
                    pendingTileCountByProject[pp, default: 0] += 1
                } else {
                    _ = layout.removeTile(withID: existingTile.id)
                    didChange = true
                }
                continue
            }

            let normalizedWorkingDirectoryPath = desiredTab.workingDirectory.standardizedFileURL.path
            if existingTile.workingDirectoryPath != normalizedWorkingDirectoryPath {
                layout.updateTile(existingTile.id) { updated in
                    updated.workingDirectoryPath = normalizedWorkingDirectoryPath
                }
                didChange = true
            }
            seenIdentities.insert(identity)
        }

        guard addMissingTabs else {
            let normalizedLayout = layout.normalized()
            if normalizedLayout != layout {
                layout = normalizedLayout
                didChange = true
            }
            return didChange
        }

        let terminalHintTileID = layout.tiles.last(where: { $0.isTerminal })?.id ?? layout.activeTileID

        for identity in desiredTabState.orderedIdentities where !seenIdentities.contains(identity) {
            guard layout.tileCount < VibeSpaceTerminalBoardLayout.maximumTileCount else { break }
            guard let desiredTab = desiredTabState.desiredByIdentity[identity] else { continue }

            let tileProjectPath: String?
            switch identity.scope {
            case let .project(projectPath):
                // Skip if we're holding pending tiles for this project (awaiting hydration rebind)
                if let pending = pendingTileCountByProject[projectPath], pending > 0 {
                    pendingTileCountByProject[projectPath] = pending - 1
                    continue
                }
                tileProjectPath = projectPath
            case .standalone:
                tileProjectPath = nil
            }

            let tile = VibeSpaceTerminalBoardTile(
                heightWeight: 1,
                projectPath: tileProjectPath,
                terminalTabID: identity.tabID,
                workingDirectoryPath: desiredTab.workingDirectory.standardizedFileURL.path
            )

            if layout.insertNewTile(tile, activeHintTileID: terminalHintTileID, activateInsertedTile: false) {
                seenIdentities.insert(identity)
                didChange = true
            }
        }

        let normalizedLayout = layout.normalized()
        if normalizedLayout != layout {
            layout = normalizedLayout
            didChange = true
        }

        return didChange
    }

    static func resolveProjectPath(
        preferredProjectPath: String?,
        workingDirectoryPath: String?,
        orderedProjectPaths: [String],
        projectsByPath: [String: AnyProjectSession],
        activeProjectPath: String?
    ) -> String? {
        if let preferredProjectPath {
            let normalizedPath = preferredProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if projectsByPath[normalizedPath] != nil {
                return normalizedPath
            }
        }

        if let workingDirectoryPath {
            let trimmedPath = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                let normalizedWorkingDirectoryPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
                let matchedProjectPath = orderedProjectPaths
                    .filter { projectPath in
                        normalizedWorkingDirectoryPath == projectPath
                            || normalizedWorkingDirectoryPath.hasPrefix(projectPath + "/")
                    }
                    .max(by: { lhs, rhs in lhs.count < rhs.count })
                if let matchedProjectPath {
                    return matchedProjectPath
                }
            }
        }

        if let activeProjectPath,
           projectsByPath[activeProjectPath] != nil {
            return activeProjectPath
        }

        return orderedProjectPaths.first
    }

    static func terminalIdentity(for tile: VibeSpaceTerminalBoardTile) -> VibeSpaceTerminalBoardTerminalIdentity? {
        guard let terminalTabID = tile.terminalTabID else {
            return nil
        }

        if let projectPath = tile.projectPath {
            return VibeSpaceTerminalBoardTerminalIdentity(scope: .project(projectPath), tabID: terminalTabID)
        }

        return VibeSpaceTerminalBoardTerminalIdentity(scope: .standalone, tabID: terminalTabID)
    }
}
