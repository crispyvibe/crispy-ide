import AppKit
import SwiftUI

struct AppSettingsSheetView: View {
    @Environment(\.colorScheme) var systemColorScheme
    @Environment(\.appThemePalette) var appThemePalette
    @Environment(\.crispyvibesTheme) var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) var uiScale
    @EnvironmentObject var themeManager: CrispyVibesThemeManager
    @Binding var appearancePreference: String
    @Binding var defaultTerminalShellRaw: String
    @Binding var defaultRailPosition: ProjectRailPosition
    @Binding var sideMenuDockPositionRaw: String
    @Binding var themePreset: String
    @Binding var customThemePaletteJSON: String
    @Binding var selectedCategory: AppSettingsCategory
    @AppStorage(AppPreferences.railTerminalFontScaleKey)
    var railFontScale = AppPreferences.defaultRailTerminalFontScale
    @AppStorage(AppPreferences.codeFontFamilyKey)
    var codeFontFamilyRaw = AppPreferences.defaultCodeFontFamily
    @AppStorage(AppPreferences.codeFontSizeKey)
    var codeFontSize = AppPreferences.defaultCodeFontSize
    @AppStorage(AppPreferences.textServiceCLIProfileKey)
    var serviceCLIProfile = AppPreferences.defaultTextServiceCLIProfile
    @AppStorage(AppPreferences.textServiceCLITrustModeKey)
    var serviceCLITrustMode = AppPreferences.defaultTextServiceCLITrustMode
    @AppStorage(AppPreferences.textServiceCLICommandKey)
    var serviceCLICommand = AppPreferences.defaultTextServiceCLICommand
    @AppStorage(AppPreferences.textServiceCLIArgumentsKey)
    var serviceCLIArguments = AppPreferences.defaultTextServiceCLIArguments
    @AppStorage(AppPreferences.textServicePassAgentFlagKey)
    var servicePassAgentFlag = AppPreferences.defaultTextServicePassAgentFlag
    @AppStorage(AppPreferences.textServiceDefaultAgentKey)
    var serviceDefaultAgent = AppPreferences.defaultTextServiceDefaultAgent
    @AppStorage(AppPreferences.textServiceRephrasePromptKey)
    var serviceRephrasePrompt = AppPreferences.defaultTextServiceRephrasePrompt
    @AppStorage(AppPreferences.textServiceResearchPromptKey)
    var serviceResearchPrompt = AppPreferences.defaultTextServiceResearchPrompt
    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    var terminalComposeInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @AppStorage(AppPreferences.authCognitoDomainKey)
    var authCognitoDomain = AppPreferences.defaultAuthCognitoDomain
    @AppStorage(AppPreferences.authCognitoMacClientIdKey)
    var authCognitoMacClientId = AppPreferences.defaultAuthCognitoMacClientId
    @AppStorage(AppPreferences.autoUpdateChecksEnabledKey)
    var autoUpdateChecksEnabled = AppPreferences.defaultAutoUpdateChecksEnabled
    @AppStorage(AppPreferences.appUpdateFeedURLKey)
    var appUpdateFeedURL = AppPreferences.defaultAppUpdateFeedURL
    @AppStorage(AppPreferences.appUpdateChannelKey)
    var appUpdateChannelRaw = AppPreferences.defaultAppUpdateChannel.rawValue
    @AppStorage(AppPreferences.experimentalTmuxIntegrationKey)
    var experimentalTmuxIntegration = false
    @AppStorage(AppPreferences.experimentalTmuxSessionBehaviorKey)
    var experimentalTmuxSessionBehavior = AppPreferences.experimentalTmuxSessionBehaviorDefault
    @AppStorage(AppPreferences.experimentalTmuxTabCloseBehaviorKey)
    var experimentalTmuxTabCloseBehavior = AppPreferences.experimentalTmuxTabCloseBehaviorDefault
    @AppStorage(AppPreferences.experimentalACPObservabilityKey)
    var experimentalACPObservability = false
    @AppStorage(AppPreferences.experimentalACPObservabilityVerboseKey)
    var experimentalACPObservabilityVerbose = false
    @AppStorage(AppPreferences.experimentalTerminalInsightKey)
    var experimentalTerminalInsight = false
    @AppStorage(AppPreferences.nerdTerminalEngineKey)
    var nerdTerminalEngine = AppPreferences.nerdTerminalEngineDefault
    let vibespaceShortcutContext: AppShortcutVibeSpaceContext?
    let vibespacesContext: AppSettingsVibeSpacesContext?
    let onClose: () -> Void
    let onResetLocalState: () -> Void

    @State var customThemeDraft = AppThemePalette.midnightMono
    @State var themeTokenErrors: [AppThemeColorRole: String] = [:]
    @State var isShowingResetConfirmation = false
    @State var showTmuxSessionManager = false
    @StateObject var authService = CognitoAuthService()
    @StateObject var appShortcutSettingsStore = AppShortcutSettingsStore()

    init(
        appearancePreference: Binding<String>,
        railFontScale: Binding<String>? = nil,
        codeFontFamilyRaw: Binding<String>? = nil,
        codeFontSize: Binding<Double>? = nil,
        defaultTerminalShellRaw: Binding<String>,
        defaultRailPosition: Binding<ProjectRailPosition>,
        sideMenuDockPositionRaw: Binding<String>,
        serviceCLIProfile: Binding<String>? = nil,
        serviceCLITrustMode: Binding<String>? = nil,
        serviceCLICommand: Binding<String>? = nil,
        serviceCLIArguments: Binding<String>? = nil,
        servicePassAgentFlag: Binding<Bool>? = nil,
        serviceDefaultAgent: Binding<String>? = nil,
        serviceRephrasePrompt: Binding<String>? = nil,
        serviceResearchPrompt: Binding<String>? = nil,
        themePreset: Binding<String>,
        customThemePaletteJSON: Binding<String>,
        selectedCategory: Binding<AppSettingsCategory>,
        vibespaceShortcutContext: AppShortcutVibeSpaceContext? = nil,
        vibespacesContext: AppSettingsVibeSpacesContext? = nil,
        authCognitoDomain: Binding<String>? = nil,
        authCognitoMacClientId: Binding<String>? = nil,
        autoUpdateChecksEnabled: Binding<Bool>? = nil,
        appUpdateFeedURL: Binding<String>? = nil,
        onResetLocalState: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        _appearancePreference = appearancePreference
        _defaultTerminalShellRaw = defaultTerminalShellRaw
        _defaultRailPosition = defaultRailPosition
        _sideMenuDockPositionRaw = sideMenuDockPositionRaw
        _themePreset = themePreset
        _customThemePaletteJSON = customThemePaletteJSON
        _selectedCategory = selectedCategory
        self.vibespaceShortcutContext = vibespaceShortcutContext
        self.vibespacesContext = vibespacesContext
        self.onResetLocalState = onResetLocalState
        self.onClose = onClose

        if let railFontScale {
            self.railFontScale = railFontScale.wrappedValue
        }
        if let codeFontFamilyRaw {
            self.codeFontFamilyRaw = codeFontFamilyRaw.wrappedValue
        }
        if let codeFontSize {
            self.codeFontSize = codeFontSize.wrappedValue
        }
        if let serviceCLIProfile {
            self.serviceCLIProfile = serviceCLIProfile.wrappedValue
        }
        if let serviceCLITrustMode {
            self.serviceCLITrustMode = serviceCLITrustMode.wrappedValue
        }
        if let serviceCLICommand {
            self.serviceCLICommand = serviceCLICommand.wrappedValue
        }
        if let serviceCLIArguments {
            self.serviceCLIArguments = serviceCLIArguments.wrappedValue
        }
        if let servicePassAgentFlag {
            self.servicePassAgentFlag = servicePassAgentFlag.wrappedValue
        }
        if let serviceDefaultAgent {
            self.serviceDefaultAgent = serviceDefaultAgent.wrappedValue
        }
        if let serviceRephrasePrompt {
            self.serviceRephrasePrompt = serviceRephrasePrompt.wrappedValue
        }
        if let serviceResearchPrompt {
            self.serviceResearchPrompt = serviceResearchPrompt.wrappedValue
        }
        if let authCognitoDomain {
            self.authCognitoDomain = authCognitoDomain.wrappedValue
        }
        if let authCognitoMacClientId {
            self.authCognitoMacClientId = authCognitoMacClientId.wrappedValue
        }
        if let autoUpdateChecksEnabled {
            self.autoUpdateChecksEnabled = autoUpdateChecksEnabled.wrappedValue
        }
        if let appUpdateFeedURL {
            self.appUpdateFeedURL = appUpdateFeedURL.wrappedValue
        }
    }

    var categoryItems: [SettingsCategoryItem] {
        AppSettingsCategory.sidebarCases
            .map(\.categoryItem)
    }

    var selectedCategoryIDBinding: Binding<String> {
        Binding(
            get: { activeCategory.rawValue },
            set: { rawValue in
                selectedCategory = AppSettingsCategory(rawValue: rawValue) ?? .general
            }
        )
    }

    var activeCategory: AppSettingsCategory {
        selectedCategory.sidebarReplacement
    }

    var codeFontSizeBinding: Binding<Double> {
        Binding(
            get: { AppPreferences.clampedCodeFontSize(codeFontSize) },
            set: { codeFontSize = AppPreferences.clampedCodeFontSize($0) }
        )
    }

    var codeFontFamilyBinding: Binding<AppCodeFontFamily> {
        Binding(
            get: { AppPreferences.resolvedCodeFontFamily(rawValue: codeFontFamilyRaw) },
            set: { codeFontFamilyRaw = $0.rawValue }
        )
    }

    var tmuxSessionBehaviorBinding: Binding<TmuxSessionBehavior> {
        Binding(
            get: { TmuxSessionBehavior(rawValue: experimentalTmuxSessionBehavior) ?? .detach },
            set: { experimentalTmuxSessionBehavior = $0.rawValue }
        )
    }

    var tmuxTabCloseBehaviorBinding: Binding<TmuxSessionBehavior> {
        Binding(
            get: { TmuxSessionBehavior(rawValue: experimentalTmuxTabCloseBehavior) ?? .terminate },
            set: { experimentalTmuxTabCloseBehavior = $0.rawValue }
        )
    }

    var sideMenuDockPositionBinding: Binding<AppSideMenuDockPosition> {
        Binding(
            get: {
                AppSideMenuDockPosition(rawValue: sideMenuDockPositionRaw)
                    ?? AppFirstRunExperience.AppSettings.sideMenuDockPosition
            },
            set: { sideMenuDockPositionRaw = $0.rawValue }
        )
    }

    var defaultTerminalShellBinding: Binding<TerminalShellPreference> {
        Binding(
            get: { AppPreferences.resolvedTerminalShellPreference(rawValue: defaultTerminalShellRaw) },
            set: { defaultTerminalShellRaw = $0.rawValue }
        )
    }

    var terminalEngineBinding: Binding<String> {
        Binding(
            get: { nerdTerminalEngine == "swiftterm" ? "swiftterm" : "ghostty" },
            set: { nerdTerminalEngine = $0 == "swiftterm" ? "swiftterm" : "ghostty" }
        )
    }

    var serviceProfileBinding: Binding<TextServiceCLIProfile> {
        Binding(
            get: { AppPreferences.resolvedTextServiceCLIProfile(rawValue: serviceCLIProfile) },
            set: { newProfile in
                serviceCLIProfile = newProfile.rawValue
                if newProfile == .custom {
                    serviceCLITrustMode = CLITrustMode.standard.rawValue
                    return
                }
                let resolvedTrustMode = AppPreferences.resolvedTextServiceCLITrustMode(
                    rawValue: serviceCLITrustMode,
                    profile: newProfile
                )
                serviceCLITrustMode = resolvedTrustMode.rawValue
                applyTextServiceDefaults(profile: newProfile, trustMode: resolvedTrustMode)
            }
        )
    }

    var selectedServiceTrustMode: CLITrustMode {
        let profile = AppPreferences.resolvedTextServiceCLIProfile(rawValue: serviceCLIProfile)
        return AppPreferences.resolvedTextServiceCLITrustMode(
            rawValue: serviceCLITrustMode,
            profile: profile
        )
    }

    var serviceTrustModeBinding: Binding<CLITrustMode> {
        Binding(
            get: { selectedServiceTrustMode },
            set: { newTrustMode in
                let profile = AppPreferences.resolvedTextServiceCLIProfile(rawValue: serviceCLIProfile)
                let resolvedTrustMode = AppPreferences.resolvedTextServiceCLITrustMode(
                    rawValue: newTrustMode.rawValue,
                    profile: profile
                )
                serviceCLITrustMode = resolvedTrustMode.rawValue
                guard profile != .custom else { return }
                applyTextServiceDefaults(profile: profile, trustMode: resolvedTrustMode)
            }
        )
    }

    private func applyTextServiceDefaults(profile: TextServiceCLIProfile, trustMode: CLITrustMode) {
        guard let defaults = CLIToolCatalog.textServiceDefaults(for: profile, trustMode: trustMode) else {
            return
        }
        serviceCLICommand = defaults.command
        serviceCLIArguments = defaults.arguments
        servicePassAgentFlag = defaults.passAgentFlag
    }

    var resolvedAuthDomain: String {
        AppPreferences.normalizedSetting(
            authCognitoDomain,
            fallback: AppPreferences.defaultAuthCognitoDomain
        )
    }

    var resolvedAuthClientID: String {
        AppPreferences.normalizedSetting(
            authCognitoMacClientId,
            fallback: AppPreferences.defaultAuthCognitoMacClientId
        )
    }

    var selectedThemePresetBinding: Binding<AppThemePreset> {
        Binding(
            get: { AppThemePreset(rawValue: themePreset) ?? .system },
            set: { newPreset in
                let previousPreset = AppThemePreset(rawValue: themePreset) ?? .system
                themePreset = newPreset.rawValue
                themeTokenErrors.removeAll()

                guard newPreset == .custom else { return }

                if let decoded = AppThemePalette.decodeFromJSON(customThemePaletteJSON) {
                    customThemeDraft = decoded
                } else {
                    let sourcePreset = previousPreset == .custom ? .system : previousPreset
                    let base = previewPalette(for: sourcePreset)
                    customThemeDraft = base
                    customThemePaletteJSON = AppThemePalette.encodeToJSON(base)
                }
            }
        )
    }

    var themePreviewPalette: AppThemePalette {
        previewPalette(for: selectedThemePresetBinding.wrappedValue)
    }

    var nonCustomThemePresets: [AppThemePreset] {
        AppThemePreset.allCases
            .filter { $0 != .custom }
            .sorted { $0.title < $1.title }
    }

    var globalTextColorBinding: Binding<Color> {
        Binding(
            get: { themePreviewPalette.terminalForegroundColor },
            set: { newColor in
                ensureCustomThemeDraftForEditing()
                customThemeDraft.terminalForeground = ProjectColorTag(color: newColor)
                customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                themeTokenErrors.removeValue(forKey: .terminalForeground)
            }
        )
    }

    var globalTextColorTokenBinding: Binding<String> {
        Binding(
            get: { themePreviewPalette.terminalForeground.storageToken },
            set: { newToken in
                let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    themeTokenErrors[.terminalForeground] = "Token cannot be empty."
                    return
                }
                guard let parsed = ProjectColorTag(storageToken: trimmed) else {
                    themeTokenErrors[.terminalForeground] = "Use hex color like #RRGGBB or #RRGGBBAA."
                    return
                }

                ensureCustomThemeDraftForEditing()
                customThemeDraft.terminalForeground = parsed
                customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                themeTokenErrors.removeValue(forKey: .terminalForeground)
            }
        )
    }

    var body: some View {
        SettingsSplitView(
            title: AppStrings.Settings.appTitle,
            subtitle: AppStrings.Settings.appSubtitle,
            doneAccessibilityIdentifier: "app.settings.done",
            categories: categoryItems,
            selectedCategoryID: selectedCategoryIDBinding,
            onClose: onClose
        ) {
            SettingsDetailPanel {
                SettingsCategoryHeader(
                    title: activeCategory.title,
                    description: activeCategory.subtitle
                )

                selectedCategoryContent
            }
        }
        .buttonBorderShape(crispyvibesTheme.borderShape.buttonBorderShape)
        .onAppear {
            loadCustomThemeDraft()
        }
        .alert(AppStrings.Settings.Reset.title, isPresented: $isShowingResetConfirmation) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.Common.reset, role: .destructive) {
                onResetLocalState()
            }
        } message: {
            Text(AppStrings.Settings.Reset.message)
        }
    }

    @ViewBuilder
    var selectedCategoryContent: some View {
        switch activeCategory {
        case .account:
            accountCategoryContent
        case .general:
            generalCategoryContent
        case .vibespaces:
            vibespacesCategoryContent
        case .shortcuts:
            shortcutsCategoryContent
        case .terminal:
            terminalCategoryContent
        case .updates:
            updatesCategoryContent
        case .services:
            servicesCategoryContent
        case .acp:
            acpAgentCategoryContent
        case .experimental:
            experimentalCategoryContent
        case .remoteSSH:
            remoteSSHCategoryContent
        case .reset:
            resetCategoryContent
        case .layout, .nerd:
            EmptyView()
        }
    }

    func previewPalette(for preset: AppThemePreset) -> AppThemePalette {
        if preset == .custom {
            return customThemeDraft
        }

        let resolvedColorScheme = AppThemeResolver.resolvedColorScheme(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: systemColorScheme
        )
        return AppThemeResolver.palette(
            appearancePreferenceRaw: appearancePreference,
            fallbackSystemColorScheme: resolvedColorScheme,
            themePresetRaw: preset.rawValue,
            customThemeJSON: customThemePaletteJSON
        )
    }

    func applyThemePreset(_ preset: AppThemePreset) {
        selectedThemePresetBinding.wrappedValue = preset
    }

    func ensureCustomThemeDraftForEditing() {
        let currentPreset = selectedThemePresetBinding.wrappedValue
        guard currentPreset != .custom else { return }
        let base = previewPalette(for: currentPreset)
        customThemeDraft = base
        customThemePaletteJSON = AppThemePalette.encodeToJSON(base)
        themePreset = AppThemePreset.custom.rawValue
        themeTokenErrors.removeAll()
    }

    func loadCustomThemeDraft() {
        if let decoded = AppThemePalette.decodeFromJSON(customThemePaletteJSON) {
            customThemeDraft = decoded
            return
        }

        let preset = AppThemePreset(rawValue: themePreset) ?? .system
        let sourcePreset = preset == .custom ? .system : preset
        let base = previewPalette(for: sourcePreset)
        customThemeDraft = base
        if preset == .custom {
            customThemePaletteJSON = AppThemePalette.encodeToJSON(base)
        }
    }

    func themeTokenBinding(for role: AppThemeColorRole) -> Binding<String> {
        Binding(
            get: { customThemeDraft.token(for: role) },
            set: { newToken in
                let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    themeTokenErrors[role] = "Token cannot be empty."
                    return
                }

                if customThemeDraft.setToken(trimmed, for: role) {
                    themeTokenErrors.removeValue(forKey: role)
                    customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                } else {
                    themeTokenErrors[role] = "Use hex color like #RRGGBB or #RRGGBBAA."
                }
            }
        )
    }

    func themeColorBinding(for role: AppThemeColorRole) -> Binding<Color> {
        Binding(
            get: { customThemeDraft.color(for: role) },
            set: { newColor in
                customThemeDraft[keyPath: role.keyPath] = ProjectColorTag(color: newColor)
                customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                themeTokenErrors.removeValue(forKey: role)
            }
        )
    }
}
