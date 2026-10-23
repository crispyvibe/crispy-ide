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
    let projectRootPathsByIdentifier: [String: String]

    init(
        projects: [AnyProjectSession],
        hiddenTerminalIDsByProjectPath: [String: Set<UUID>],
        standaloneTabs: [TerminalTab],
        excludedTerminalIdentities: Set<VibeSpaceTerminalBoardTerminalIdentity> = []
    ) {
        var desiredByIdentity: [VibeSpaceTerminalBoardTerminalIdentity: TerminalTab] = [:]
        var orderedIdentities: [VibeSpaceTerminalBoardTerminalIdentity] = []
        orderedIdentities.reserveCapacity(VibeSpaceTerminalBoardLayout.maximumTileCount)

        for project in projects {
            let projectIdentifier = project.projectIdentifier
            let projectRootPath = project.rootURL.standardizedFileURL.path
            let hiddenIDs = hiddenTerminalIDsByProjectPath[projectIdentifier]
                ?? hiddenTerminalIDsByProjectPath[projectRootPath]
                ?? []
            for tab in project.terminal.tabs {
                guard !hiddenIDs.contains(tab.id) else { continue }
                let identity = VibeSpaceTerminalBoardTerminalIdentity(
                    scope: .project(projectIdentifier),
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
        self.activeProjectPaths = Set(projects.map(\.projectIdentifier))
        self.projectRootPathsByIdentifier = Dictionary(
            uniqueKeysWithValues: projects.map {
                ($0.projectIdentifier, $0.rootURL.standardizedFileURL.path)
            }
        )
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
                if !tabExists, let owner = tile.projectIdentifier ?? tile.projectPath {
                    pendingTileCountByProject[owner, default: 0] += 1
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
                if !tabExists, let owner = existingTile.projectIdentifier ?? existingTile.projectPath {
                    pendingTileCountByProject[owner, default: 0] += 1
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
            let tileProjectIdentifier: String?
            switch identity.scope {
            case let .project(projectIdentifier):
                // Skip if we're holding pending tiles for this project (awaiting hydration rebind)
                if let pending = pendingTileCountByProject[projectIdentifier], pending > 0 {
                    pendingTileCountByProject[projectIdentifier] = pending - 1
                    continue
                }
                tileProjectIdentifier = projectIdentifier
                tileProjectPath = desiredTabState.projectRootPathsByIdentifier[projectIdentifier]
            case .standalone:
                tileProjectPath = nil
                tileProjectIdentifier = nil
            }

            let tile = VibeSpaceTerminalBoardTile(
                heightWeight: 1,
                projectPath: tileProjectPath,
                projectIdentifier: tileProjectIdentifier,
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
            let preferred = preferredProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if projectsByPath[preferred] != nil { return preferred }
            let normalizedPreferred = URL(fileURLWithPath: preferred).standardizedFileURL.path
            let matchingIdentifiers = orderedProjectPaths.filter { identifier in
                projectsByPath[identifier]?.rootURL.standardizedFileURL.path == normalizedPreferred
            }
            if let activeProjectPath, matchingIdentifiers.contains(activeProjectPath) {
                return activeProjectPath
            }
            if matchingIdentifiers.count == 1 { return matchingIdentifiers[0] }
        }

        if let workingDirectoryPath {
            let trimmedPath = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                let normalizedWorkingDirectoryPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
                let matchingIdentifiers = orderedProjectPaths.filter { identifier in
                    guard let root = projectsByPath[identifier]?.rootURL.standardizedFileURL.path else {
                        return false
                    }
                    return normalizedWorkingDirectoryPath == root
                        || normalizedWorkingDirectoryPath.hasPrefix(root.hasSuffix("/") ? root : root + "/")
                }
                if let activeProjectPath, matchingIdentifiers.contains(activeProjectPath) {
                    return activeProjectPath
                }
                if let deepest = matchingIdentifiers.max(by: { lhs, rhs in
                    let lhsCount = projectsByPath[lhs]?.rootURL.standardizedFileURL.path.count ?? 0
                    let rhsCount = projectsByPath[rhs]?.rootURL.standardizedFileURL.path.count ?? 0
                    return lhsCount < rhsCount
                }) {
                    return deepest
                }
            }
        }

        if let activeProjectPath, projectsByPath[activeProjectPath] != nil {
            return activeProjectPath
        }
        return orderedProjectPaths.first
    }

    static func terminalIdentity(for tile: VibeSpaceTerminalBoardTile) -> VibeSpaceTerminalBoardTerminalIdentity? {
        guard let terminalTabID = tile.terminalTabID else {
            return nil
        }

        if let projectIdentity = tile.projectIdentifier ?? tile.projectPath {
            return VibeSpaceTerminalBoardTerminalIdentity(scope: .project(projectIdentity), tabID: terminalTabID)
        }

        return VibeSpaceTerminalBoardTerminalIdentity(scope: .standalone, tabID: terminalTabID)
    }
}
