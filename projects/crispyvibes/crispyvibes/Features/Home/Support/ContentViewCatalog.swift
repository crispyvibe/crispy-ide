import SwiftUI

extension ContentView {
    private var shouldRestoreVibeSpaceCatalogOnLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CRISPYVIBES_UI_TEST_MODE"] == "1" else {
            return false
        }
        return environment["CRISPYVIBES_UI_TEST_START_IN_VIBESPACE"] == "1"
    }

    func loadVibeSpaceCatalogIfNeeded() {
        homeCatalogCoordinator.loadVibeSpaceCatalogIfNeeded(
            shouldRestoreVibeSpaceCatalogOnLaunch: shouldRestoreVibeSpaceCatalogOnLaunch
        ) { vibespaceName in
            untrustedVibeSpaceName = vibespaceName
        }
    }

    func applyUITestOverridesIfNeeded() {
        guard !didApplyUITestOverrides else { return }
        didApplyUITestOverrides = true

        let environment = ProcessInfo.processInfo.environment
        guard environment["CRISPYVIBES_UI_TEST_MODE"] == "1" else { return }

        if environment["CRISPYVIBES_UI_TEST_RESET_STATE"] == "1" {
            appContainer.appPersistenceStore.resetAppStorage()
            UserDefaults.standard.removeObject(forKey: AppPreferences.onboardingDisclaimerAcceptedKey)
            homeCatalogCoordinator.cancelCatalogLoading()
            homeCatalogCoordinator.clearDisplayedVibeSpaces()
            homeCatalogCoordinator.markCatalogNeedsReload()
        }

        let shouldAutoAcceptDisclaimer = environment["CRISPYVIBES_UI_TEST_SHOW_ONBOARDING"] != "1"
        if shouldAutoAcceptDisclaimer {
            vibespaceManagement.setAcceptedDisclaimer(true)
        }

        if let catalog = environment["CRISPYVIBES_UI_TEST_VIBESPACE_CATALOG"],
           !catalog.isEmpty {
            if let data = catalog.data(using: .utf8),
               let entries = try? JSONDecoder().decode([UITestVibeSpaceEntry].self, from: data) {
                for entry in entries {
                    vibespaceManagement.saveVibeSpaceConfig(entry.config)
                    for path in entry.config.projectPaths {
                        var projectConfig = ProjectConfigFile.empty(projectPath: path)
                        projectConfig.colorTag = entry.projectColorTags?[path]
                        projectConfig.shortcutIndex = entry.projectShortcuts?[path]
                        projectConfig.startupOverride = entry.projectStartupOverrides?[path]
                        projectConfig.terminalShellOverride = entry.projectTerminalShellOverrides?[path]
                        vibespaceManagement.saveProjectConfig(projectConfig, in: entry.config.id)
                    }
                    vibespaceManagement.touchRecent(entry.config.id)
                }
            }
            homeCatalogCoordinator.markCatalogNeedsReload()
        }

        if let appearance = environment["CRISPYVIBES_UI_TEST_APPEARANCE"],
           AppearancePreference(rawValue: appearance) != nil {
            appearancePreference = appearance
        }
    }

    /// Fills missing auth configuration from the app bundle (Info.plist) so end users
    /// don't need to manually enter Cognito settings.
    func ensureAuthDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let desiredDomain = AppPreferences.defaultAuthCognitoDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentDomain = (defaults.string(forKey: AppPreferences.authCognitoDomainKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDomain.isEmpty,
           !desiredDomain.isEmpty {
            defaults.set(desiredDomain, forKey: AppPreferences.authCognitoDomainKey)
        }

        let desiredClientId = AppPreferences.defaultAuthCognitoMacClientId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentClientID = (defaults.string(forKey: AppPreferences.authCognitoMacClientIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if currentClientID.isEmpty,
           !desiredClientId.isEmpty {
            defaults.set(desiredClientId, forKey: AppPreferences.authCognitoMacClientIdKey)
        }
    }

    func persistVibeSpaceCatalog() {
        homeCatalogCoordinator.persistVibeSpaceCatalog()
    }

}

/// Lightweight struct for UI test catalog injection via environment variable.
struct UITestVibeSpaceEntry: Codable {
    var config: VibeSpaceConfigFile
    var projectColorTags: [String: String]?
    var projectShortcuts: [String: Int]?
    var projectStartupOverrides: [String: VibeSpaceProjectStartupOverride]?
    var projectTerminalShellOverrides: [String: TerminalShellPreference]?
}
