import Foundation

@MainActor
extension SpotlightItem {
    var persistentID: SpotlightPersistentItemID {
        switch self {
        case let .terminal(project, tab):
            return .terminal(projectPath: project.rootURL.standardizedFileURL.path, tabID: tab.id)
        case let .standaloneTerminal(surfaceID, tileID, _, tab):
            return .standaloneTerminal(surfaceID: surfaceID, tileID: tileID, tabID: tab.id)
        case .vibeCast: return .vibeCast
        case .vibeLanes: return .vibeLanes
        case let .acp(tileID, storeID, _, _): return .acp(tileID: tileID, storeID: storeID)
        case let .file(tileID, _): return .file(tileID: tileID)
        case let .browser(tileID, _): return .browser(tileID: tileID)
        }
    }
}

extension SpotlightPersistentItemID {
    @MainActor
    var navigationIdentity: SpotlightNavigationIdentity {
        switch self {
        case let .terminal(projectPath, tabID):
            return .terminal(projectScope: .projectPath(URL(fileURLWithPath: projectPath).standardizedFileURL.path), tabID: tabID)
        case let .standaloneTerminal(_, tileID, tabID):
            return .terminal(projectScope: .unscoped(tileID), tabID: tabID)
        case .vibeCast: return .vibeCast
        case .vibeLanes: return .vibeLanes
        case let .acp(tileID, storeID): return .acp(tileID: tileID, storeID: storeID)
        case let .file(tileID): return .file(tileID: tileID)
        case let .browser(tileID): return .browser(tileID: tileID)
        }
    }
}

@MainActor
enum SpotlightPositionNavigationResolver {
    static func relativeSelection(
        offset: Int,
        currentIdentity: SpotlightNavigationIdentity,
        snapshot: SpotlightLayoutSnapshot,
        items: [SpotlightItem]
    ) -> SpotlightNavigationSelection? {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.persistentID, $0) })
        guard let currentID = items.first(where: { $0.navigationIdentity == currentIdentity })?.persistentID,
              let currentIndex = snapshot.positions.firstIndex(where: { $0.members.contains(currentID) }),
              snapshot.positions.count > 1 else { return nil }
        let targetIndex = (currentIndex + offset + snapshot.positions.count) % snapshot.positions.count
        guard let targetID = snapshot.positions[targetIndex].members.first,
              let targetItem = byID[targetID] else { return nil }
        return SpotlightNavigationSelection(
            item: targetItem,
            sourceIdentity: currentIdentity,
            targetIdentity: targetItem.navigationIdentity,
            direction: offset > 0 ? 1 : -1
        )
    }

    static func selection(
        targetIdentity: SpotlightNavigationIdentity,
        currentIdentity: SpotlightNavigationIdentity,
        snapshot: SpotlightLayoutSnapshot,
        items: [SpotlightItem]
    ) -> SpotlightNavigationSelection? {
        guard targetIdentity != currentIdentity,
              let currentItem = items.first(where: { $0.navigationIdentity == currentIdentity }),
              let targetItem = items.first(where: { $0.navigationIdentity == targetIdentity }),
              let currentIndex = snapshot.positions.firstIndex(where: { $0.members.contains(currentItem.persistentID) }),
              let targetIndex = snapshot.positions.firstIndex(where: { $0.members.contains(targetItem.persistentID) }) else {
            return nil
        }
        return SpotlightNavigationSelection(
            item: targetItem,
            sourceIdentity: currentIdentity,
            targetIdentity: targetIdentity,
            direction: targetIndex == currentIndex ? 0 : (targetIndex > currentIndex ? 1 : -1)
        )
    }
}

extension TerminalSpotlightState {
    var persistentItemID: SpotlightPersistentItemID? {
        switch source {
        case let .persistent(_, tabID):
            if case let .terminal(.unscoped(tileID), _) = navigationIdentity,
               let surfaceID {
                return .standaloneTerminal(surfaceID: surfaceID, tileID: tileID, tabID: tabID)
            }
            guard let path = owningProjectRootURL?.standardizedFileURL.path else { return nil }
            return .terminal(projectPath: path, tabID: tabID)
        case .vibeCast: return .vibeCast
        case .vibeLanes: return .vibeLanes
        case let .acp(tileID, storeID): return .acp(tileID: tileID, storeID: storeID)
        case let .file(tileID, _, _): return .file(tileID: tileID)
        case let .browser(tileID, _): return .browser(tileID: tileID)
        case .transient, .todos, .filePreview, .browserPreview: return nil
        }
    }
}


@MainActor
enum SpotlightTerminalPresentationWiring {
    static func identityAfterSelectingTab(
        _ selectedTabID: UUID,
        from spotlight: TerminalSpotlightState
    ) -> SpotlightNavigationIdentity? {
        guard spotlight.owningProjectRootURL == nil,
              spotlight.surfaceID != nil,
              case let .terminal(projectScope: .unscoped(tileID), tabID: _) = spotlight.navigationIdentity else {
            return nil
        }
        return .terminal(projectScope: .unscoped(tileID), tabID: selectedTabID)
    }

    static func standaloneIdentity(
        terminalViewModel: TerminalViewModel,
        tabID: UUID,
        surfaceID: UUID,
        boardStore: VibeSpaceTerminalBoardStore
    ) -> SpotlightNavigationIdentity? {
        let layout = boardStore.layout(for: surfaceID)
        guard let tile = (layout.tiles + layout.minimizedTiles).first(where: { tile in
            guard let context = boardStore.tileContext(for: tile) else { return false }
            return context.terminalViewModel === terminalViewModel && context.terminalTab.id == tabID
        }) else { return nil }
        return .terminal(projectScope: .unscoped(tile.id), tabID: tabID)
    }
}

@MainActor
enum DetachedSpotlightStateFactory {
    static func attach(
        _ spotlight: TerminalSpotlightState,
        to surfaceID: UUID
    ) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: spotlight.id,
            source: spotlight.source,
            title: spotlight.title,
            accentColor: spotlight.accentColor,
            workingDirectoryURL: spotlight.workingDirectoryURL,
            onSplitTerminalRequested: spotlight.onSplitTerminalRequested,
            onTemporaryTerminalRequested: spotlight.onTemporaryTerminalRequested,
            shortcutDefinitions: spotlight.shortcutDefinitions,
            onShortcutSelected: spotlight.onShortcutSelected,
            onManageShortcutsRequested: spotlight.onManageShortcutsRequested,
            agentPresets: spotlight.agentPresets,
            onAgentPresetSelected: spotlight.onAgentPresetSelected,
            isTemporary: spotlight.isTemporary,
            owningProjectRootURL: spotlight.owningProjectRootURL,
            surfaceID: surfaceID,
            navigationIdentityOverride: spotlight.navigationIdentityOverride
        )
    }
}

enum SpotlightTransientShortcutRouter {
    static func route(
        _ shortcut: TerminalShortcutDefinition,
        current: () -> Void,
        temporary: () -> Void,
        permanent: () -> Void
    ) {
        switch shortcut.launchBehavior {
        case .currentTerminal:
            current()
        case .newTemporaryTerminal:
            temporary()
        case .newPermanentTerminal:
            permanent()
        }
    }
}


@MainActor
enum DetachedPermanentShortcutTileLauncher {
    @discardableResult
    static func launch(
        _ shortcut: TerminalShortcutDefinition,
        directoryURL: URL,
        owningProjectRootURL: URL?,
        surfaceID: UUID,
        boardStore: VibeSpaceTerminalBoardStore
    ) -> Bool {
        let layout = boardStore.layout(for: surfaceID)
        let existingTileIDs = Set((layout.tiles + layout.minimizedTiles).map(\.id))
        let projectPath = owningProjectRootURL?.standardizedFileURL.path
        guard boardStore.addTile(
            projectPath: projectPath,
            directoryURL: directoryURL.standardizedFileURL,
            preferStandalone: projectPath == nil,
            surfaceID: surfaceID
        ) else { return false }
        let updatedLayout = boardStore.layout(for: surfaceID)
        guard let createdTile = (updatedLayout.tiles + updatedLayout.minimizedTiles).first(where: {
            !existingTileIDs.contains($0.id)
        }),
        let context = boardStore.tileContext(for: createdTile),
        let session = context.terminalViewModel.session(for: context.terminalTab.id) else { return false }
        session.sendStartupCommand(shortcut.command.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }
}

/// Stable identity for pane-local Spotlight compose drafts and history.
enum SpotlightComposeIdentity: Hashable {
    case persistent(SpotlightPersistentItemID)
    case transient(UUID)

    var historyKey: String {
        switch self {
        case let .persistent(id): return "spotlight:\(id.safeToken)"
        case let .transient(id): return "spotlight:transient:\(id.uuidString)"
        }
    }
}

extension TerminalSpotlightState {
    var composeIdentity: SpotlightComposeIdentity? {
        if case let .transient(session) = source { return .transient(session.id) }
        guard let persistentItemID else { return nil }
        switch persistentItemID {
        case .terminal, .standaloneTerminal:
            return .persistent(persistentItemID)
        case .vibeCast, .vibeLanes, .acp, .file, .browser:
            return nil
        }
    }
}
