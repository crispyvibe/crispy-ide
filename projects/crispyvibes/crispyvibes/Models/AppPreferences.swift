import AppKit
import SwiftUI

enum TerminalShellPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case zsh
    case bash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zsh:
            return "zsh"
        case .bash:
            return "bash"
        }
    }

    var executablePath: String {
        switch self {
        case .zsh:
            return "/bin/zsh"
        case .bash:
            return "/bin/bash"
        }
    }
}

enum AppPreferences {

    // MARK: - Key Convention: crispyvibes.{domain}.{setting}

    // MARK: Appearance
    static let appearancePreferenceKey = "crispyvibes.appearance.mode"
    static let appThemePresetKey = "crispyvibes.appearance.themePreset"
    static let appCustomThemePaletteJSONKey = "crispyvibes.appearance.customThemePaletteJSON"
    static let codeFontFamilyKey = "crispyvibes.appearance.fontFamily"
    static let codeFontSizeKey = "crispyvibes.appearance.fontSize"
    static let railTerminalFontScaleKey = "crispyvibes.appearance.railFontScale"
    static let railTerminalCompactFontSizeKey = "crispyvibes.appearance.railCompactFontSize"

    // MARK: Terminal
    static let terminalShellPreferenceKey = "crispyvibes.terminal.shell"
    static let terminalShellPreferenceExplicitSelectionKey = "crispyvibes.terminal.shellExplicitSelection"
    static let terminalPresetLaunchModeKey = "crispyvibes.terminal.presetLaunchMode"
    static let terminalComposeInlineTriggerKey = "crispyvibes.terminal.inlineTrigger"
    static let nerdTerminalEngineKey = "crispyvibes.terminal.engine"
    static let terminalShortcutDefinitionsKey = "crispyvibes.terminal.shortcutDefinitions"
    static let terminalToolDiagnosticsVersionKey = "crispyvibes.terminal.diagnosticsVersion"
    static let terminalToolDiagnosticsInstalledToolsKey = "crispyvibes.terminal.diagnosticsInstalledTools"

    // MARK: Shortcuts
    static let appShortcutOverridesKey = "crispyvibes.shortcuts.overrides"

    // MARK: Agent
    static let acpDefaultAgentIDKey = "crispyvibes.agent.defaultID"
    static let acpDefaultTrustModeKey = "crispyvibes.agent.defaultTrustMode"
    static let acpDefaultModelKey = "crispyvibes.agent.defaultModel"
    static let acpDefaultReasoningLevelKey = "crispyvibes.agent.defaultReasoningLevel"
    static let acpCustomAgentsKey = "crispyvibes.agent.customAgents"

    // MARK: Todo Lane Pipeline (F060)
    /// Auto-triage mode for todos (off | projectTodosOnly | allTodos).
    static let todoTriageModeKey = "crispyvibes.todos.triageMode"
    /// On lane task done — true auto-completes the todo, false offers one-tap.
    static let todoAutoCompleteOnDoneKey = "crispyvibes.todos.autoCompleteOnDone"

    // MARK: Services
    static let textServiceCLIProfileKey = "crispyvibes.services.cliProfile"
    static let textServiceCLITrustModeKey = "crispyvibes.services.cliTrustMode"
    static let textServiceCLICommandKey = "crispyvibes.services.cliCommand"
    static let textServiceCLIArgumentsKey = "crispyvibes.services.cliArguments"
    static let textServicePassAgentFlagKey = "crispyvibes.services.passAgentFlag"
    static let textServiceDefaultAgentKey = "crispyvibes.services.defaultAgent"
    static let textServiceRephrasePromptKey = "crispyvibes.services.rephrasePrompt"
    static let textServiceResearchPromptKey = "crispyvibes.services.researchPrompt"

    // MARK: Layout
    static let defaultRailPositionKey = "defaultRailPosition"
    static let appSideMenuDockPositionKey = "crispyvibes.layout.sideMenuDock"

    // MARK: Updates
    static let autoUpdateChecksEnabledKey = "crispyvibes.updates.autoCheck"
    static let appUpdateFeedURLKey = "crispyvibes.updates.feedURL"
    static let appUpdateChannelKey = "crispyvibes.updates.channel"

    // MARK: Experimental
    static let experimentalTmuxIntegrationKey = "crispyvibes.experimental.tmuxIntegration"
    static let experimentalTmuxSessionBehaviorKey = "crispyvibes.experimental.tmuxSessionBehavior"
    static let experimentalTmuxSessionBehaviorDefault = TmuxSessionBehavior.detach.rawValue
    static let experimentalTmuxTabCloseBehaviorKey = "crispyvibes.experimental.tmuxTabCloseBehavior"
    static let experimentalTmuxTabCloseBehaviorDefault = TmuxSessionBehavior.terminate.rawValue
    static let experimentalACPObservabilityKey = "crispyvibes.experimental.acpObservability"
    static let experimentalACPObservabilityVerboseKey = "crispyvibes.experimental.acpObservabilityVerbose"
    static let experimentalTerminalInsightKey = "crispyvibes.experimental.terminalInsight"

    // MARK: Remote
    static let enhancedRemoteExplorerKey = "crispyvibes.remote.enhancedExplorer"

    // MARK: Auth
    static let authCognitoDomainKey = "crispyvibes.auth.cognitoDomain"
    static let authCognitoMacClientIdKey = "crispyvibes.auth.cognitoClientId"

    // MARK: Onboarding
    static let onboardingDisclaimerAcceptedKey = "crispyvibes.onboarding.disclaimerAccepted"
    static let featureWalkthroughCompletedKey = "crispyvibes.onboarding.walkthroughCompleted"

    // MARK: VibeSpace (hardcoded in views — constants for migration only)
    static let vibespaceShelfExpandedKey = "crispyvibes.vibespace.shelf.expanded"
    static let vibespaceSourceControlLayoutKey = "crispyvibes.vibespace.sourceControl.layoutMode"

    // MARK: Info.plist (not UserDefaults — no migration)
    static let infoPlistAuthCognitoDomainKey = "CrispyVibesCognitoDomain"
    static let infoPlistAuthCognitoMacClientIdKey = "CrispyVibesCognitoMacClientId"
    static let infoPlistAppUpdateFeedURLKey = "CrispyVibesAppUpdateFeedURL"
    static let nerdTerminalEngineDefault = "ghostty"

    // MARK: - Legacy Key Migration

    /// Maps old UserDefaults keys to their new crispyvibes.{domain}.{setting} equivalents.
    /// Run once at app launch via `migrateUserDefaultsIfNeeded()`.
    private static let legacyKeyMigrations: [(old: String, new: String)] = [
        // Appearance
        ("appearancePreference", appearancePreferenceKey),
        ("appThemePreset", appThemePresetKey),
        ("appCustomThemePaletteJSON", appCustomThemePaletteJSONKey),
        ("codeFontFamily", codeFontFamilyKey),
        ("codeFontSize", codeFontSizeKey),
        ("railTerminalFontScale", railTerminalFontScaleKey),
        ("railTerminalCompactFontSize", railTerminalCompactFontSizeKey),
        // Terminal
        ("terminalShellPreference", terminalShellPreferenceKey),
        ("terminalShellPreferenceExplicitSelection", terminalShellPreferenceExplicitSelectionKey),
        ("terminalPresetLaunchMode", terminalPresetLaunchModeKey),
        ("terminalComposeInlineTrigger", terminalComposeInlineTriggerKey),
        ("nerd.terminalEngine", nerdTerminalEngineKey),
        ("terminalShortcutDefinitions", terminalShortcutDefinitionsKey),
        ("terminalToolDiagnostics.version", terminalToolDiagnosticsVersionKey),
        ("terminalToolDiagnostics.installedTools", terminalToolDiagnosticsInstalledToolsKey),
        // Shortcuts
        ("appShortcutOverrides", appShortcutOverridesKey),
        // Agent
        ("acpDefaultAgentID", acpDefaultAgentIDKey),
        ("acpDefaultTrustMode", acpDefaultTrustModeKey),
        ("acpDefaultModel", acpDefaultModelKey),
        ("acpDefaultReasoningLevel", acpDefaultReasoningLevelKey),
        ("acpCustomAgents", acpCustomAgentsKey),
        // Services
        ("textServiceCLIProfile", textServiceCLIProfileKey),
        ("textServiceCLITrustMode", textServiceCLITrustModeKey),
        ("textServiceCLICommand", textServiceCLICommandKey),
        ("textServiceCLIArguments", textServiceCLIArgumentsKey),
        ("textServicePassAgentFlag", textServicePassAgentFlagKey),
        ("textServiceDefaultAgent", textServiceDefaultAgentKey),
        ("textServiceRephrasePrompt", textServiceRephrasePromptKey),
        ("textServiceResearchPrompt", textServiceResearchPromptKey),
        // Layout
        ("defaultRailPosition", defaultRailPositionKey),
        ("appSideMenuDockPosition", appSideMenuDockPositionKey),
        // Updates
        ("autoUpdateChecksEnabled", autoUpdateChecksEnabledKey),
        ("appUpdateFeedURL", appUpdateFeedURLKey),
        // Experimental
        ("experimental.tmuxIntegration", experimentalTmuxIntegrationKey),
        ("experimental.tmuxSessionBehavior", experimentalTmuxSessionBehaviorKey),
        ("experimental.tmuxTabCloseBehavior", experimentalTmuxTabCloseBehaviorKey),
        ("experimental.acpObservability", experimentalACPObservabilityKey),
        ("experimental.acpObservabilityVerbose", experimentalACPObservabilityVerboseKey),
        ("experimental.terminalInsight", experimentalTerminalInsightKey),
        // Auth
        ("authCognitoDomain", authCognitoDomainKey),
        ("authCognitoMacClientId", authCognitoMacClientIdKey),
        // Onboarding
        ("onboardingDisclaimerAccepted", onboardingDisclaimerAcceptedKey),
        ("featureWalkthroughCompleted", featureWalkthroughCompletedKey),
        // VibeSpace
        ("vibespace.sidebar.shelf.expanded", vibespaceShelfExpandedKey),
        ("vibespace.source-control.layout-mode", vibespaceSourceControlLayoutKey),
    ]

    /// Migrates legacy UserDefaults keys to the new `crispyvibes.{domain}.{setting}` convention.
    /// Copies old values to new keys (if new key is absent), then removes old keys.
    /// Safe to call multiple times — idempotent.
    static func migrateUserDefaultsIfNeeded(userDefaults: UserDefaults = .standard) {
        for (oldKey, newKey) in legacyKeyMigrations {
            guard oldKey != newKey else { continue }
            guard let oldValue = userDefaults.object(forKey: oldKey) else { continue }
            if userDefaults.object(forKey: newKey) == nil {
                userDefaults.set(oldValue, forKey: newKey)
            }
            userDefaults.removeObject(forKey: oldKey)
        }
    }

    static let minimumRailTerminalCompactFontSize: Double = 1.0
    static let maximumRailTerminalCompactFontSize: Double = 100.0
    static let defaultRailTerminalCompactFontSize = AppFirstRunExperience.AppSettings.railTerminalCompactFontSize
    static let minimumCodeFontSize: Double = 1.0
    static let maximumCodeFontSize: Double = 100.0
    static let defaultCodeFontSize = AppFirstRunExperience.AppSettings.codeFontSize
    static let minimumChromeScale: CGFloat = 0.9
    static let maximumChromeScale: CGFloat = 1.3

    static let defaultAppearancePreference = AppFirstRunExperience.AppSettings.appearancePreference.rawValue
    static let defaultTextServiceCLIProfile = AppFirstRunExperience.AppSettings.textServiceCLIProfile.rawValue
    static let defaultTextServiceCLITrustMode = AppFirstRunExperience.AppSettings.textServiceCLITrustMode.rawValue
    static let defaultTextServiceCLICommand = AppFirstRunExperience.AppSettings.textServiceCLICommand
    static let defaultTextServiceCLIArguments = AppFirstRunExperience.AppSettings.textServiceCLIArguments
    static let defaultTextServicePassAgentFlag = AppFirstRunExperience.AppSettings.textServicePassAgentFlag
    static let defaultTextServiceDefaultAgent = AppFirstRunExperience.AppSettings.textServiceDefaultAgent
    static let defaultCodeFontFamily = AppFirstRunExperience.AppSettings.codeFontFamily.rawValue
    static let defaultTerminalShellPreference = AppFirstRunExperience.AppSettings.terminalShellPreference.rawValue
    static let defaultAppThemePreset = AppFirstRunExperience.AppSettings.themePreset.rawValue
    static let defaultAppCustomThemePaletteJSON = AppFirstRunExperience.AppSettings.customThemePaletteJSON
    static let defaultAppSideMenuDockPosition =
        AppFirstRunExperience.AppSettings.sideMenuDockPosition.rawValue
    static let defaultRailPositionRawValue =
        AppFirstRunExperience.Layout.defaultRailPosition.rawValue
    static let defaultAutoUpdateChecksEnabled = AppFirstRunExperience.AppSettings.autoUpdateChecksEnabled
    static let appUpdateAutoCheckInterval: TimeInterval = 12 * 60 * 60
    static var defaultAuthCognitoDomain: String {
        AppFirstRunExperience.AppSettings.authCognitoDomain
    }

    static var defaultAuthCognitoMacClientId: String {
        AppFirstRunExperience.AppSettings.authCognitoMacClientId
    }

    static var defaultAppUpdateFeedURL: String {
        AppFirstRunExperience.AppSettings.appUpdateFeedURL
    }

    static let defaultTextServiceRephrasePrompt = AppFirstRunExperience.AppSettings.textServiceRephrasePrompt
    static let defaultTextServiceResearchPrompt = AppFirstRunExperience.AppSettings.textServiceResearchPrompt
    static let defaultTerminalComposeInlineTrigger = "`"

    static let defaultRailTerminalFontScale = AppFirstRunExperience.AppSettings.railTerminalFontScale.rawValue

    static func clampedRailTerminalCompactFontSize(_ value: Double) -> Double {
        Swift.max(minimumRailTerminalCompactFontSize, Swift.min(value, maximumRailTerminalCompactFontSize))
    }

    static func clampedCodeFontSize(_ value: Double) -> Double {
        Swift.max(minimumCodeFontSize, Swift.min(value, maximumCodeFontSize))
    }

    static func railTerminalFontScale(userDefaults: UserDefaults = .standard) -> TerminalRailFontScale {
        let raw = userDefaults.string(forKey: railTerminalFontScaleKey) ?? defaultRailTerminalFontScale
        return TerminalRailFontScale(rawValue: raw) ?? AppFirstRunExperience.AppSettings.railTerminalFontScale
    }

    static func railTerminalCompactFontSize(userDefaults: UserDefaults = .standard) -> CGFloat {
        let scale = railTerminalFontScale(userDefaults: userDefaults)
        let baseSize = codeFontSize(userDefaults: userDefaults)
        return CGFloat(Swift.max(1, (baseSize * scale.multiplier).rounded()))
    }

    static func codeFontSize(userDefaults: UserDefaults = .standard) -> CGFloat {
        let stored = userDefaults.object(forKey: codeFontSizeKey) as? Double
        let resolved = clampedCodeFontSize(stored ?? defaultCodeFontSize)
        return CGFloat(resolved)
    }

    static func chromeScale(userDefaults: UserDefaults = .standard) -> CGFloat {
        chromeScale(forCodeFontSize: Double(codeFontSize(userDefaults: userDefaults)))
    }

    static func chromeScale(forCodeFontSize codeFontSize: Double) -> CGFloat {
        let clampedCodeSize = clampedCodeFontSize(codeFontSize)
        let defaultSize = max(defaultCodeFontSize, 1)
        let scaled = pow(clampedCodeSize / defaultSize, 0.30)
        return Swift.max(minimumChromeScale, CGFloat(scaled))
    }

    static func resolvedCodeFontFamily(rawValue: String?) -> AppCodeFontFamily {
        AppCodeFontFamily(rawValue: rawValue ?? "") ?? .systemMonospaced
    }

    static func codeFont(size: CGFloat, userDefaults: UserDefaults = .standard) -> NSFont {
        let rawValue = userDefaults.string(forKey: codeFontFamilyKey) ?? defaultCodeFontFamily
        return codeFont(familyRawValue: rawValue, size: size)
    }

    static func codeFont(familyRawValue: String, size: CGFloat) -> NSFont {
        let clampedSize = CGFloat(clampedCodeFontSize(Double(size)))
        let family = resolvedCodeFontFamily(rawValue: familyRawValue)
        return family.font(size: clampedSize)
    }

    static func normalizedSetting(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : fallback
    }

    static func normalizedTerminalComposeInlineTrigger(_ value: String?) -> String {
        let candidate = normalizedSetting(value, fallback: defaultTerminalComposeInlineTrigger)
        guard !candidate.contains(where: \.isWhitespace) else {
            return defaultTerminalComposeInlineTrigger
        }
        return String(candidate.prefix(8))
    }

    static func autoUpdateChecksEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: autoUpdateChecksEnabledKey) != nil else {
            return defaultAutoUpdateChecksEnabled
        }
        return userDefaults.bool(forKey: autoUpdateChecksEnabledKey)
    }

    static func normalizedAppUpdateFeedURL(_ value: String?, fallback: String? = nil) -> String {
        normalizedSetting(value, fallback: fallback ?? defaultAppUpdateFeedURL)
    }

    static func resolvedAppUpdateFeedURL(_ value: String?, fallback: String? = nil) -> URL? {
        let normalized = normalizedAppUpdateFeedURL(value, fallback: fallback)
        guard let url = URL(string: normalized), url.scheme != nil else {
            return nil
        }
        return url
    }

    /// The default channel for fresh installs, inferred from the build's
    /// configured Info.plist feed URL. Production `Release` builds default to
    /// `.stable`; everything else (Debug, DebugLocal, ReleaseLocal, etc.)
    /// defaults to `.dev`.
    static var defaultAppUpdateChannel: AppUpdateChannel {
        AppUpdateChannel.inferred(fromFeedURL: defaultAppUpdateFeedURL)
    }

    /// Reads the user-selected update channel from defaults, migrating from
    /// the legacy "edit feed URL directly" preference if no channel is stored.
    static func appUpdateChannel(userDefaults: UserDefaults = .standard) -> AppUpdateChannel {
        if let raw = userDefaults.string(forKey: appUpdateChannelKey),
           let stored = AppUpdateChannel(rawValue: raw) {
            return stored
        }
        // Migration: infer channel from any previously-stored custom feed URL.
        let storedURL = userDefaults.string(forKey: appUpdateFeedURLKey)
        if let storedURL,
           !storedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppUpdateChannel.inferred(fromFeedURL: storedURL)
        }
        return defaultAppUpdateChannel
    }

    /// Resolves the effective Sparkle feed URL based on the user's channel
    /// selection. For `.stable` and `.dev` channels, returns the channel's
    /// canonical feed URL; for `.custom`, returns the user-supplied feed URL
    /// (falling back to the build default if empty/invalid).
    static func effectiveAppUpdateFeedURL(userDefaults: UserDefaults = .standard) -> String {
        let channel = appUpdateChannel(userDefaults: userDefaults)
        if let channelURL = channel.feedURL {
            return channelURL
        }
        return normalizedAppUpdateFeedURL(
            userDefaults.string(forKey: appUpdateFeedURLKey),
            fallback: defaultAppUpdateFeedURL
        )
    }

    static func resetAllUserOverrides(
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        let trimmedIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let domainName = (trimmedIdentifier?.isEmpty == false)
            ? trimmedIdentifier!
            : "com.crispyvibe.app"
        userDefaults.removePersistentDomain(forName: domainName)
    }

    static func resolvedTerminalShellPreference(rawValue: String?) -> TerminalShellPreference {
        TerminalShellPreference(rawValue: rawValue ?? "") ?? .zsh
    }

    static func resolvedTextServiceCLIProfile(rawValue: String?) -> TextServiceCLIProfile {
        TextServiceCLIProfile(rawValue: rawValue ?? "") ?? AppFirstRunExperience.AppSettings.textServiceCLIProfile
    }

    static func resolvedTextServiceCLITrustMode(
        rawValue: String?,
        profile: TextServiceCLIProfile? = nil
    ) -> CLITrustMode {
        let resolvedProfile = profile ?? AppFirstRunExperience.AppSettings.textServiceCLIProfile
        let requestedMode = CLITrustMode(rawValue: rawValue ?? "")
            ?? AppFirstRunExperience.AppSettings.textServiceCLITrustMode
        if CLIToolCatalog.supportedTrustModes(for: resolvedProfile).contains(requestedMode) {
            return requestedMode
        }
        return .standard
    }

    static func defaultTextServiceCLIConfiguration(
        profile: TextServiceCLIProfile = AppFirstRunExperience.AppSettings.textServiceCLIProfile,
        trustMode: CLITrustMode = AppFirstRunExperience.AppSettings.textServiceCLITrustMode
    ) -> TextServiceCLIConfiguration {
        CLIToolCatalog.textServiceDefaults(for: profile, trustMode: trustMode)
            ?? TextServiceCLIConfiguration(
                profile: profile,
                trustMode: .standard,
                command: "",
                arguments: "",
                passAgentFlag: false
            )
    }

    static func resolvedTextServiceCLIConfiguration(
        userDefaults: UserDefaults = .standard
    ) -> TextServiceCLIConfiguration {
        let profile = resolvedTextServiceCLIProfile(
            rawValue: userDefaults.string(forKey: textServiceCLIProfileKey)
        )
        let trustMode = resolvedTextServiceCLITrustMode(
            rawValue: userDefaults.string(forKey: textServiceCLITrustModeKey),
            profile: profile
        )
        let defaults = defaultTextServiceCLIConfiguration(profile: profile, trustMode: trustMode)

        let resolvedCommand: String
        if profile == .custom {
            resolvedCommand = normalizedSetting(
                userDefaults.string(forKey: textServiceCLICommandKey),
                fallback: ""
            )
        } else {
            resolvedCommand = normalizedSetting(
                userDefaults.string(forKey: textServiceCLICommandKey),
                fallback: defaults.command
            )
        }

        let resolvedArguments = userDefaults.string(forKey: textServiceCLIArgumentsKey)
            ?? defaults.arguments
        let resolvedPassAgentFlag: Bool
        if userDefaults.object(forKey: textServicePassAgentFlagKey) != nil {
            resolvedPassAgentFlag = userDefaults.bool(forKey: textServicePassAgentFlagKey)
        } else {
            resolvedPassAgentFlag = defaults.passAgentFlag
        }

        return TextServiceCLIConfiguration(
            profile: profile,
            trustMode: trustMode,
            command: resolvedCommand,
            arguments: resolvedArguments,
            passAgentFlag: resolvedPassAgentFlag
        )
    }

    static func resolvedTextServiceAgentName(
        primaryEnvironmentKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> String? {
        let configuredCandidate = (
            environment[primaryEnvironmentKey]
            ?? environment["CRISPYVIBES_KIRO_AGENT"]
            ?? userDefaults.string(forKey: textServiceDefaultAgentKey)
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredCandidate, !configuredCandidate.isEmpty {
            return configuredCandidate
        }

        let fallbackAgent = defaultTextServiceDefaultAgent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackAgent.isEmpty ? nil : fallbackAgent
    }

    static func storedTerminalShellPreference(
        userDefaults: UserDefaults = .standard
    ) -> TerminalShellPreference? {
        let storedValue: String?
        if userDefaults === UserDefaults.standard {
            let domainName = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
            let persistedDomain = userDefaults.persistentDomain(forName: domainName)
            storedValue = persistedDomain?[terminalShellPreferenceKey] as? String
        } else {
            storedValue = userDefaults.object(forKey: terminalShellPreferenceKey) as? String
        }

        guard let rawValue = storedValue else {
            return nil
        }
        let hasExplicitSelection = userDefaults.bool(forKey: terminalShellPreferenceExplicitSelectionKey)
        if !hasExplicitSelection, rawValue == TerminalShellPreference.zsh.rawValue {
            return nil
        }
        return TerminalShellPreference(rawValue: rawValue)
    }

    // MARK: - ACP Agent Settings

    static func acpDefaultAgentID(userDefaults: UserDefaults = .standard) -> String? {
        let trimmed = userDefaults.string(forKey: acpDefaultAgentIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func setACPDefaultAgentID(_ agentID: String?, userDefaults: UserDefaults = .standard) {
        let trimmed = agentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            userDefaults.set(trimmed, forKey: acpDefaultAgentIDKey)
        } else {
            userDefaults.removeObject(forKey: acpDefaultAgentIDKey)
        }
    }

    static func acpDefaultModelID(userDefaults: UserDefaults = .standard) -> String? {
        let trimmed = userDefaults.string(forKey: acpDefaultModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func acpDefaultTrustMode(userDefaults: UserDefaults = .standard) -> CLITrustMode {
        guard let rawValue = userDefaults.string(forKey: acpDefaultTrustModeKey),
              let mode = CLITrustMode(rawValue: rawValue) else {
            return .standard
        }
        return mode
    }

    static func acpDefaultReasoningLevel(userDefaults: UserDefaults = .standard) -> AgentReasoningLevel {
        guard let rawValue = userDefaults.string(forKey: acpDefaultReasoningLevelKey),
              let level = AgentReasoningLevel(rawValue: rawValue) else {
            return .medium
        }
        return level
    }

    // MARK: - Todo Lane Pipeline (F060)

    static func todoTriageMode(userDefaults: UserDefaults = .standard) -> TodoTriageMode {
        guard let raw = userDefaults.string(forKey: todoTriageModeKey),
              let mode = TodoTriageMode(rawValue: raw) else {
            return .projectTodosOnly
        }
        return mode
    }

    static func setTodoTriageMode(_ mode: TodoTriageMode, userDefaults: UserDefaults = .standard) {
        userDefaults.set(mode.rawValue, forKey: todoTriageModeKey)
    }

    static func todoAutoCompleteOnDone(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: todoAutoCompleteOnDoneKey)   // default false = one-tap
    }

    static func setTodoAutoCompleteOnDone(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: todoAutoCompleteOnDoneKey)
    }

    static func resolvedACPDefaultAgent(
        userDefaults: UserDefaults = .standard,
        resolveExecutable: (String) -> String? = ACPAgentRegistry.resolveExecutable
    ) -> ACPAgentDefinition? {
        guard let agentID = acpDefaultAgentID(userDefaults: userDefaults) else { return nil }
        return ACPAgentRegistry.agentDefinition(
            id: agentID,
            userDefaults: userDefaults,
            resolveExecutable: resolveExecutable
        )
    }

    static func customACPAgents(userDefaults: UserDefaults = .standard) -> [CustomACPAgent] {
        guard let data = userDefaults.data(forKey: acpCustomAgentsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomACPAgent].self, from: data)) ?? []
    }

    static func setCustomACPAgents(
        _ agents: [CustomACPAgent],
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(try? JSONEncoder().encode(agents), forKey: acpCustomAgentsKey)
    }
}

enum TerminalRailFontScale: String, CaseIterable, Identifiable {
    case quarter = "1/4"
    case half = "1/2"
    case full = "1:1"

    var id: String { rawValue }

    var title: String { rawValue }

    var multiplier: CGFloat {
        switch self {
        case .quarter: return 0.25
        case .half: return 0.5
        case .full: return 1.0
        }
    }
}

enum AppCodeFontFamily: String, CaseIterable, Identifiable {
    case systemMonospaced
    case sfMono
    case menlo
    case monaco
    case courier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemMonospaced:
            return "System Monospace"
        case .sfMono:
            return "SF Mono"
        case .menlo:
            return "Menlo"
        case .monaco:
            return "Monaco"
        case .courier:
            return "Courier"
        }
    }

    fileprivate func font(size: CGFloat) -> NSFont {
        if self == .systemMonospaced {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        for candidate in fontCandidates {
            if let font = NSFont(name: candidate, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private var fontCandidates: [String] {
        switch self {
        case .systemMonospaced:
            return []
        case .sfMono:
            return ["SFMono-Regular", "SF Mono Regular", "SFMono-Medium"]
        case .menlo:
            return ["Menlo-Regular", "Menlo"]
        case .monaco:
            return ["Monaco", "Monaco-Regular"]
        case .courier:
            return ["Courier", "CourierNewPSMT"]
        }
    }
}

enum TextServiceCLIProfile: String, CaseIterable, Identifiable {
    case kiro
    case claudeCode
    case codex
    case gemini
    case opencode
    case custom

    var id: String { rawValue }

    var title: String {
        CLIToolCatalog.textServiceDefinition(for: self).title
    }

    var defaultCommand: String {
        AppPreferences.defaultTextServiceCLIConfiguration(profile: self).command
    }

    var defaultArguments: String {
        AppPreferences.defaultTextServiceCLIConfiguration(profile: self).arguments
    }

    var defaultPassAgentFlag: Bool {
        AppPreferences.defaultTextServiceCLIConfiguration(profile: self).passAgentFlag
    }

    var supportsFullTrust: Bool {
        CLIToolCatalog.supportsFullTrust(profile: self)
    }

    var isInstalled: Bool {
        guard self != .custom else { return true }
        guard let definition = CLIToolCatalog.textServiceDefaults(for: self, trustMode: .standard) else {
            return false
        }
        let command = definition.command
        guard !command.isEmpty else { return false }
        let searchPaths = CommandPathResolver.searchPaths()
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return true }
        }
        return false
    }

    var iconName: String? {
        CLIToolCatalog.textServiceDefinition(for: self).terminalPresentation?.symbolName
    }

    var isCustomIcon: Bool {
        CLIToolCatalog.textServiceDefinition(for: self).terminalPresentation?.isCustomIcon ?? false
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
