import SwiftUI

extension AppSettingsSheetView {
    var layoutCategoryContent: some View {
        SettingsCard(
            title: "App Chrome",
            description: "Controls default rail placement and the app side menu dock."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(title: "Rail position", detail: nil) {
                    Picker("Rail position", selection: $defaultRailPosition) {
                        ForEach(ProjectRailPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("app.settings.default-rail-position")
                }

                SettingsFieldRow(
                    title: "App side menu dock",
                    detail: "Automatically moves left when the vibespace rail is docked on the right."
                ) {
                    Picker("App side menu dock", selection: sideMenuDockPositionBinding) {
                        ForEach(AppSideMenuDockPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("app.settings.app-side-menu-dock")
                }
            }
        }
    }

    var terminalCategoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "Terminal Defaults",
                description: "Controls shell selection and terminal link behavior."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(
                        title: "Default terminal shell",
                        detail: "Used when a project does not define vibespace or folder shell overrides."
                    ) {
                        Picker("Default terminal shell", selection: defaultTerminalShellBinding) {
                            ForEach(TerminalShellPreference.allCases) { shellPreference in
                                Text(shellPreference.title).tag(shellPreference)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.terminal.default-shell")
                    }
                }
            }

            terminalEngineCard

            SettingsCard(
                title: AppStrings.Settings.Experimental.tmuxIntegrationTitle,
                description: AppStrings.Settings.Experimental.tmuxIntegrationDescription
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $experimentalTmuxIntegration) {
                        Text(AppStrings.Settings.Experimental.tmuxIntegrationTitle)
                            .font(AppTypographyTokens.settingsFieldTitle)
                    }
                    .accessibilityIdentifier("app.settings.terminal.tmux-integration")
                    .toggleStyle(.switch)

                    if experimentalTmuxIntegration {
                        Divider()

                        Picker(AppStrings.Settings.Experimental.tmuxSessionBehaviorTitle, selection: tmuxSessionBehaviorBinding) {
                            ForEach(TmuxSessionBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.terminal.tmux-session-behavior")

                        Picker(AppStrings.Settings.Experimental.tmuxTabCloseBehaviorTitle, selection: tmuxTabCloseBehaviorBinding) {
                            ForEach(TmuxSessionBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.terminal.tmux-tab-close-behavior")

                        Button(AppStrings.Settings.Experimental.tmuxManagerTitle) {
                            showTmuxSessionManager = true
                        }
                        .accessibilityIdentifier("app.settings.terminal.tmux-manager")
                        .sheet(isPresented: $showTmuxSessionManager) {
                            TmuxSessionManagerView()
                        }
                    }
                }
            }
        }
    }

    var updatesCategoryContent: some View {
        SettingsCard(
            title: "Update Delivery",
            description: "Configure Sparkle automatic checks and the update channel used by Crispy."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Automatically check for updates",
                    isOn: $autoUpdateChecksEnabled
                )
                .accessibilityIdentifier("app.settings.updates.auto-check")

                SettingsFieldRow(
                    title: "Update channel",
                    detail: appUpdateChannel.summary
                ) {
                    Picker("Update channel", selection: appUpdateChannelBinding) {
                        ForEach(AppUpdateChannel.allCases) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("app.settings.updates.channel")
                }

                if appUpdateChannel == .custom {
                    SettingsFieldRow(
                        title: "Custom feed URL",
                        detail: "Sparkle appcast endpoint to use instead of a built-in channel."
                    ) {
                        TextField(
                            "https://crispyvibe.com/updates/macos/appcast.xml",
                            text: $appUpdateFeedURL
                        )
                        .textFieldStyle(SquareBorderTextFieldStyle())
                        .accessibilityIdentifier("app.settings.updates.feed-url")
                    }
                } else if let channelURL = appUpdateChannel.feedURL {
                    Text(channelURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("app.settings.updates.channel-url")
                }

                HStack(spacing: 8) {
                    Button(AppStrings.Settings.Updates.checkNow) {
                        NotificationCenter.default.post(
                            name: .checkForAppUpdates,
                            object: nil,
                            userInfo: [AppCommandUserInfoKey.source: AppCommandSource.settings]
                        )
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityIdentifier("app.settings.updates.check-now")

                    if appUpdateChannel == .custom {
                        Button(AppStrings.Settings.Updates.resetFeedURL) {
                            appUpdateFeedURL = AppPreferences.defaultAppUpdateFeedURL
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("app.settings.updates.reset-feed")
                    }
                }
            }
        }
    }

    private var appUpdateChannel: AppUpdateChannel {
        AppUpdateChannel(rawValue: appUpdateChannelRaw) ?? AppPreferences.defaultAppUpdateChannel
    }

    private var appUpdateChannelBinding: Binding<AppUpdateChannel> {
        Binding(
            get: { appUpdateChannel },
            set: { newValue in
                appUpdateChannelRaw = newValue.rawValue
                if let channelURL = newValue.feedURL {
                    // Mirror the channel's URL into the stored feed URL so any
                    // legacy reader (or accessibility tooling) sees the active
                    // endpoint without having to know about channels.
                    appUpdateFeedURL = channelURL
                }
            }
        )
    }

    var resetCategoryContent: some View {
        SettingsCard(
            title: "Start Fresh",
            description: "Delete local vibespaces, recents, shelf state, walkthrough progress, layout state, and all saved app overrides on this Mac."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.Settings.cannotBeUndone)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)

                Button(AppStrings.Settings.Reset.localState) {
                    isShowingResetConfirmation = true
                }
                .buttonStyle(.crispyvibesPrimary)
                .tint(themePreviewPalette.errorColor)
                .accessibilityIdentifier("app.settings.reset.local-state")
            }
        }
    }
}
