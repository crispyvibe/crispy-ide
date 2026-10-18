import AppKit
import SwiftUI

extension ContentView {
    @ViewBuilder
    func terminalSpotlightCard(for presentation: SpotlightCardPresentation) -> some View {
        let spotlight = presentation.focused
        let pinMetadata = spotlightPinMetadata(for: spotlight)
        TerminalSpotlightCardView(
            spotlight: spotlight,
            onDismiss: closeTerminalSpotlight,
            onPin: pinMetadata?.action,
            pinAccessibilityLabel: pinMetadata?.label,
            shortcutDefinitions: spotlight.shortcutDefinitions,
            onShortcutSelected: spotlight.onShortcutSelected,
            onManageShortcutsRequested: spotlight.onManageShortcutsRequested,
            onSendSignal: spotlightSendSignalHandler(for: spotlight),
            onRenamePersistentTab: { terminalViewModel, tabID, title in
                terminalViewModel.renameTab(tabID, to: title)
            },
            comboMembers: presentation.members,
            comboOrientation: presentation.orientation,
            onFocusMember: selectSpotlightItem(_:),
            onToggleComboOrientation: {
                guard let positionID = presentation.positionID else { return }
                let items = flatSpotlightItems
                let liveIDs = items.map(\.persistentID)
                let snapshot = layoutPersistence.spotlightLayout(liveIDs: liveIDs, for: activeVibeSpaceID)
                guard let updated = SpotlightLayoutReducer.togglingOrientation(
                    positionID: positionID,
                    snapshot: snapshot
                ) else { return }
                if commitMainSpotlightLayout(updated, liveIDs: liveIDs) {
                    terminalSpotlightCoordinator.noteLayoutCommitted()
                }
            },
            spotlightContent: { member, interaction in
                terminalSpotlightContent(for: member, interaction: interaction)
            },
            inputBarContent: { member, requestsInitialFocus, onActivate in
                SpotlightTerminalInputBar(
                    spotlight: member,
                    vibespaceProjects: vibespaceView.activeVibeSpaceProjects,
                    requestsInitialFocus: requestsInitialFocus,
                    onActivate: onActivate
                )
            }
        )
    }

    private func spotlightSendSignalHandler(for spotlight: TerminalSpotlightState) -> ((String) -> Void)? {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            return { signal in
                terminalViewModel.session(for: tabID)?.sendRawText(signal)
            }
        case let .transient(session):
            return { signal in
                session.sendRawText(signal)
            }
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    @ViewBuilder
    private func terminalSpotlightContent(
        for spotlight: TerminalSpotlightState,
        interaction: SpotlightMemberInteractionContext
    ) -> some View {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            if let resolvedTab = terminalViewModel.tabs.first(where: { $0.id == tabID }) {
                TerminalSessionView(
                    tab: resolvedTab,
                    viewModel: terminalViewModel,
                    isActive: true,
                    sessionAccessibilityIdentifier: "terminal.spotlight.session",
                    sessionHostAccessibilityIdentifier: "terminal.spotlight.host",
                    inlineTriggerTerminalTitle: resolvedTab.title.isEmpty ? spotlight.title : resolvedTab.title,
                    inlineTriggerSearchRoots: spotlightInlineTriggerSearchRoots(for: spotlight, fallbackDirectory: resolvedTab.workingDirectory),
                    inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                    onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                    onSessionSelected: { _ in
                        interaction.handleTerminalSelection {
                            terminalViewModel.selectTab(resolvedTab)
                            terminalViewModel.focusActiveTerminal()
                        }
                    },
                    onSessionDoubleClicked: handleTerminalSpotlightSessionDoubleClick,
                    onSplitTerminalRequested: { tab in
                        createSplitTerminal(
                            in: terminalViewModel,
                            directoryURL: tab.workingDirectory,
                            surfaceID: spotlight.surfaceID,
                            owningProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onTemporaryTerminalRequested: { tab in
                        presentTemporaryTerminalSpotlight(
                            title: spotlight.title,
                            accentColor: spotlight.accentColor,
                            directoryURL: tab.workingDirectory,
                            shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                            onSplitTerminalRequested: {
                                createSplitTerminal(
                                    in: terminalViewModel,
                                    directoryURL: tab.workingDirectory,
                                    surfaceID: spotlight.surfaceID,
                                    owningProjectRootURL: spotlight.owningProjectRootURL
                                )
                            },
                            owningProjectRootURL: spotlight.owningProjectRootURL,
                            surfaceID: spotlight.surfaceID
                        )
                    },
                    onOpenInEditorPaneRequested: { tab in
                        openTerminalInEditorPane(tabID: tab.id, projectRootURL: spotlight.owningProjectRootURL)
                    },
                    onLinkTargetActivated: { url in
                        openTerminalLinkTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onFileSystemTargetActivated: { url in
                        openTerminalFileSystemTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    }
                )
            } else {
                ContentUnavailableView(
                    AppStrings.Spotlight.terminalUnavailable,
                    systemImage: "terminal",
                    description: Text(AppStrings.Terminal.selectedUnavailable)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .transient(session):
            TerminalSessionHostView(
                session: session,
                displayDensity: .regular,
                isActive: true,
                accessibilityIdentifier: "terminal.spotlight.host",
                inlineTriggerTerminalTitle: spotlight.title,
                inlineTriggerSearchRoots: spotlightInlineTriggerSearchRoots(
                    for: spotlight,
                    fallbackDirectory: session.currentWorkingDirectory
                ),
                inlineTriggerShortcuts: spotlight.shortcutDefinitions,
                onManageInlineTriggerShortcutsRequested: spotlight.onManageShortcutsRequested,
                onSplitTerminalRequested: spotlight.onSplitTerminalRequested,
                onTemporaryTerminalRequested: spotlight.onTemporaryTerminalRequested,
                onLinkTargetActivated: { url in
                    openTerminalLinkTarget(
                        url,
                        preferredProjectRootURL: spotlight.owningProjectRootURL
                    )
                },
                onFileSystemTargetActivated: { url in
                    openTerminalFileSystemTarget(
                        url,
                        preferredProjectRootURL: spotlight.owningProjectRootURL
                    )
                }
            )
            .id(session.viewIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .vibeCast:
            VibeCastView(
                store: contentViewerStore.vibeCastStore,
                terminalSources: vibespaceView.activeVibeSpaceProjects.map { project in
                    .init(
                        id: project.id.uuidString,
                        projectTitle: project.title,
                        projectRootURL: project.rootURL,
                        accentColor: vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color ?? activeThemePalette.accentColor,
                        viewModel: project.terminalViewModel
                    )
                },
                isActive: true,
                onManageShortcutsRequested: spotlight.onManageShortcutsRequested
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .vibeLanes:
            VibeLaneSurfaceView(
                focusedProjectPath: vibespaceView.focusedProject?.rootURL.standardizedFileURL.path,
                onOpenACPSession: {
                    contentViewerStore.openVibeLaneACPPane(
                        target: $0,
                        projects: vibespaceView.activeVibeSpaceProjects,
                        vibespaceID: activeVibeSpaceID
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .todos:
            TodosSurfaceView(
                store: appContainer.vibespaceTodoStore,
                focusedProjectPath: vibespaceView.focusedProject?.rootURL.standardizedFileURL.path
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .acp(_, storeID):
            if let store = contentViewerStore.acpStore(for: storeID) {
                ACPStandalonePaneContentView(
                    store: store,
                    projects: vibespaceView.activeVibeSpaceProjects,
                    displayMode: .spotlight,
                    onLinkTargetActivated: { url in
                        openTerminalLinkTarget(
                            url,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    },
                    onFileSystemTargetActivated: { target in
                        openTerminalFileSystemTarget(
                            target,
                            preferredProjectRootURL: spotlight.owningProjectRootURL
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    AppStrings.ACP.unavailableTitle,
                    systemImage: "sparkles",
                    description: Text(AppStrings.ACP.unavailableDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .filePreview(_, group):
            EditorGroupFileSurface(group: group, onInteraction: interaction.requestFocus)
                .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .file(_, _, group):
            EditorGroupFileSurface(group: group, onInteraction: interaction.requestFocus)
                .environment(\.vibespaceCommentStoreEnvironment, appContainer.vibespaceCommentStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browserPreview(snapshot):
            let vm = spotlightBrowserPreviewViewModel(
                snapshot: snapshot,
                projectPath: spotlight.owningProjectRootURL?.path
            )
            BrowserContentView(viewModel: vm, presentation: .spotlight, onInteraction: interaction.requestFocus)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browser(tileID, url):
            let vm = dockedBrowserCoordinator.viewModel(for: tileID, url: url)
            BrowserContentView(viewModel: vm, presentation: .spotlight, onInteraction: interaction.requestFocus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func spotlightInlineTriggerSearchRoots(
        for spotlight: TerminalSpotlightState,
        fallbackDirectory: URL
    ) -> [URL] {
        var roots: [URL] = [fallbackDirectory]
        if let owningProjectRootURL = spotlight.owningProjectRootURL {
            roots.append(owningProjectRootURL)
        }
        roots.append(contentsOf: vibespaceView.activeVibeSpaceProjects.map(\.rootURL))
        roots.append(spotlight.workingDirectoryURL)

        var seen = Set<String>()
        return roots.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private struct SpotlightPinMetadata {
        let label: String
        let action: () -> Void
    }

    private func spotlightPinMetadata(for spotlight: TerminalSpotlightState) -> SpotlightPinMetadata? {
        switch ContentSurfacePolicy.surface(for: .spotlightPin, mode: vibespaceView.selectedCanvasMode) {
        case .detailTab:
            guard spotlightSupportsDetailedPin(spotlight) else { return nil }
            return SpotlightPinMetadata(label: AppStrings.Spotlight.openInViewer, action: {
                pinSpotlightToDetailedViewer(spotlight)
            })
        case .boardTile:
            guard spotlightSupportsBoardPin(spotlight) else { return nil }
            return SpotlightPinMetadata(label: AppStrings.Spotlight.pinToDock, action: {
                pinSpotlightToTerminalBoard(spotlight)
            })
        case .dockedPreview, .spotlight:
            assertionFailure("spotlightPin must resolve to .detailTab or .boardTile")
            return nil
        }
    }

    private func spotlightSupportsDetailedPin(_ spotlight: TerminalSpotlightState) -> Bool {
        switch spotlight.source {
        case .filePreview, .file, .browserPreview, .browser:
            return true
        case .persistent, .transient, .vibeCast, .vibeLanes, .todos, .acp:
            return false
        }
    }

    private func spotlightSupportsBoardPin(_ spotlight: TerminalSpotlightState) -> Bool {
        spotlight.source.supportsBoardPin
    }

    private func pinSpotlightToDetailedViewer(_ spotlight: TerminalSpotlightState) {
        switch spotlight.source {
        case let .filePreview(_, group), let .file(_, _, group):
            guard let reference = group.activeFileDocumentReference else { return }
            contentViewerStore.activeGroup.openFileInTab(
                at: reference.url,
                documentReference: reference,
                fileContentProvider: group.activeFileContentProvider
            )
        case let .browserPreview(snapshot):
            let fallbackURL = snapshot.urlString.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!
            let effectiveSnapshot = dockedBrowserCoordinator.previewSnapshot(fallbackURL: fallbackURL) ?? snapshot
            let reference = BrowserTabReference(
                url: effectiveSnapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL,
                projectPath: spotlight.owningProjectRootURL?.path
            )
            dockedBrowserCoordinator.restoreDetailedBrowser(reference: reference, snapshot: effectiveSnapshot)
            contentViewerStore.activeGroup.openTab(.webPage(reference: reference))
        case let .browser(tileID, url):
            let viewModel = dockedBrowserCoordinator.viewModel(for: tileID, url: url)
            let currentURL = viewModel.currentURL ?? url
            let reference = BrowserTabReference(
                url: currentURL,
                projectPath: spotlight.owningProjectRootURL?.path,
                linkedTileID: tileID
            )
            dockedBrowserCoordinator.restoreDetailedBrowser(
                reference: reference,
                snapshot: viewModel.sessionSnapshot()
            )
            contentViewerStore.activeGroup.openTab(.webPage(reference: reference))
        case .persistent, .transient, .vibeCast, .vibeLanes, .todos, .acp:
            return
        }
        dismissTerminalSpotlight()
    }

    private func pinSpotlightToTerminalBoard(_ spotlight: TerminalSpotlightState) {
        guard let boardStore = vibespaceHydrationCoordinator.boardStore else { return }

        switch spotlight.source {
        case let .filePreview(target, group):
            guard let tileID = boardStore.pinPreviewToDock(fileURL: target.url) else { return }
            dockedFileViewerCoordinator.assignEditorGroup(
                group,
                for: tileID,
                fileURL: target.url
            )
        case let .browserPreview(snapshot):
            let fallbackURL = snapshot.urlString.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!
            let effectiveSnapshot = dockedBrowserCoordinator.previewSnapshot(fallbackURL: fallbackURL) ?? snapshot
            let resolvedURL = effectiveSnapshot.urlString.flatMap(URL.init(string:)) ?? fallbackURL
            let tileID = UUID()
            guard boardStore.pinBrowserToDock(
                id: tileID,
                url: resolvedURL,
                projectPath: spotlight.owningProjectRootURL?.path,
                surfaceID: spotlight.surfaceID ?? boardStore.primarySurfaceID,
                browserSession: effectiveSnapshot
            ) != nil else { return }
            dockedBrowserCoordinator.promotePreview(to: tileID, snapshot: effectiveSnapshot)
            boardStore.commit()
        case .vibeLanes:
            guard boardStore.addVibeLanesTile(
                surfaceID: spotlight.surfaceID ?? boardStore.primarySurfaceID
            ) else { return }
        case .persistent, .transient, .vibeCast, .todos, .acp, .file, .browser:
            return
        }
        dismissTerminalSpotlight()
    }
}
