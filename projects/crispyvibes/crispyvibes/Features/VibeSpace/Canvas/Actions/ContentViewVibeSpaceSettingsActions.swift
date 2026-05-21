import AppKit
import SwiftUI

extension ContentView {
    func promptRenameVibeSpace(_ vibespaceID: UUID) {
        guard let currentName = vibespaceValue(for: vibespaceID, { $0.name }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename VibeSpace"
        alert.informativeText = "Choose a name for this vibespace."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(string: currentName)
        inputField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        inputField.placeholderString = "VibeSpace"
        alert.accessoryView = inputField
        inputField.selectText(nil)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        homeCatalogCoordinator.renameVibeSpace(
            vibespaceID,
            to: inputField.stringValue,
            onActiveVibeSpaceRenamed: syncWindowTitleWithVibeSpace
        )
    }

    @ViewBuilder
    func vibespaceSettingsSheet(for vibespaceID: UUID) -> some View {
        if let context = vibespaceSettingsContext(for: vibespaceID) {
            VibeSpaceSettingsSheetView(
                vibespaceName: context.vibespaceName,
                selectedCategory: context.selectedCategory,
                projects: context.projects,
                availableTerminalPresets: context.availableTerminalPresets,
                availableACPAgents: context.availableACPAgents,
                startupSettings: context.startupSettings,
                vibespaceDefaultTerminalShell: context.vibespaceDefaultTerminalShell,
                sourceControlSettings: context.sourceControlSettings,
                startupOverrideForPath: context.startupOverrideForPath,
                setStartupOverride: context.setStartupOverride,
                projectACPAgentOverrideIDForPath: context.projectACPAgentOverrideIDForPath,
                setProjectACPAgentOverrideID: context.setProjectACPAgentOverrideID,
                setProjectShortcut: context.setProjectShortcut,
                projectColorTagForPath: context.projectColorTagForPath,
                setProjectColorTag: context.setProjectColorTag,
                projectTerminalShellOverrideForPath: context.projectTerminalShellOverrideForPath,
                setProjectTerminalShellOverride: context.setProjectTerminalShellOverride,
                onAddProjects: context.onAddProjects,
                onAddRemoteProject: context.onAddRemoteProject,
                onRemoveProject: context.onRemoveProject,
                onMoveProjects: context.onMoveProjects,
                onRenameVibeSpace: context.onRenameVibeSpace,
                onReindexProjects: context.onReindexProjects,
                onClose: context.onClose,
                vibespaceShortcuts: context.vibespaceShortcuts,
                setVibeSpaceShortcuts: context.setVibeSpaceShortcuts,
                projectShortcutsForPath: context.projectShortcutsForPath,
                setProjectShortcutsForPath: context.setProjectShortcutsForPath
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .applyingAppThemePalette(activeThemePalette)
            .applyingAppAccentTheme(activeThemePalette.accentColor)
        } else {
            VStack(spacing: 12) {
                Text(AppStrings.VibeSpaceSettings.settingsUnavailable)
                    .font(AppTypographyTokens.headline)
                Button(AppStrings.Common.close) {
                    vibespaceShell.dismissSurface()
                }
                .buttonStyle(.crispyvibesPrimary)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    func appSettingsSheet() -> some View {
        let activeVibeSpaceShortcutContext: AppShortcutVibeSpaceContext? = activeVibeSpaceID.flatMap { vibespaceID in
            guard let context = vibespaceSettingsContext(for: vibespaceID) else { return nil }
            return AppShortcutVibeSpaceContext(
                vibespaceName: context.vibespaceName,
                projects: context.projects,
                vibespaceShortcuts: context.vibespaceShortcuts,
                setVibeSpaceShortcuts: context.setVibeSpaceShortcuts,
                projectShortcutsForPath: context.projectShortcutsForPath,
                setProjectShortcutsForPath: context.setProjectShortcutsForPath
            )
        }

        AppSettingsSheetView(
            appearancePreference: $appearancePreference,
            defaultTerminalShellRaw: $terminalShellPreference,
            defaultRailPosition: Binding(
                get: {
                    ProjectRailPosition(rawValue: defaultRailPositionRaw)
                        ?? AppFirstRunExperience.Layout.defaultRailPosition
                },
                set: { defaultRailPositionRaw = $0.rawValue }
            ),
            sideMenuDockPositionRaw: $appSideMenuDockPositionRaw,
            themePreset: $appThemePreset,
            customThemePaletteJSON: $appCustomThemePaletteJSON,
            selectedCategory: vibespaceShell.appSettingsCategoryBinding,
            vibespaceShortcutContext: activeVibeSpaceShortcutContext,
            onResetLocalState: {
                homeCatalogCoordinator.resetLocalAppState(
                    clearExpandedVibeSpaceSidebarProjectPaths: {
                        expandedVibeSpaceSidebarProjectPaths = []
                    },
                    applyDefaultPreferences: {
                        appearancePreference = AppPreferences.defaultAppearancePreference
                        terminalShellPreference = AppPreferences.defaultTerminalShellPreference
                        appThemePreset = AppPreferences.defaultAppThemePreset
                        appCustomThemePaletteJSON = AppPreferences.defaultAppCustomThemePaletteJSON
                        appSideMenuDockPositionRaw = AppPreferences.defaultAppSideMenuDockPosition
                    },
                    ensureAuthDefaultsIfNeeded: {
                        ensureAuthDefaultsIfNeeded()
                    }
                )
            },
            onClose: {
                if vibespaceShell.isAppSettingsPresented {
                    vibespaceShell.dismissSurface()
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyingAppThemePalette(activeThemePalette)
        .applyingAppAccentTheme(activeThemePalette.accentColor)
    }

    @ViewBuilder
    func developerToolsSheet() -> some View {
        DeveloperToolsView(
            metricsStore: appContainer.operationMetricsStore,
            diagnosticsSnapshot: appContainer.terminalServices.diagnosticsSnapshot,
            acpObservabilityStore: appContainer.acpObservabilityStore,
            experimentalFeatures: appContainer.experimentalFeatures,
            acpVibeSpaceContextStore: appContainer.acpVibeSpaceContextStore,
            acpDeveloperToolsService: appContainer.acpDeveloperToolsService
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyingAppThemePalette(activeThemePalette)
        .applyingAppAccentTheme(activeThemePalette.accentColor)
    }
}
