import SwiftUI

extension AppSettingsSheetView {
    var servicesCategoryContent: some View {
        Group {
            SettingsCard(
                title: "CLI Defaults",
                description: "Profiles populate command and argument defaults for common CLIs."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(title: "CLI profile", detail: nil) {
                        Picker("CLI profile", selection: serviceProfileBinding) {
                            ForEach(CLIToolCatalog.textServiceDisplayProfiles) { profile in
                                Text(profile.title).tag(profile)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.services.cli-profile")
                    }

                    if serviceProfileBinding.wrappedValue != .custom {
                        SettingsFieldRow(title: "Trust mode", detail: "Controls preset defaults only") {
                            Picker("Trust mode", selection: serviceTrustModeBinding) {
                                ForEach(CLIToolCatalog.supportedTrustModes(for: serviceProfileBinding.wrappedValue)) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("app.settings.services.cli-trust-mode")
                        }
                    }

                    SettingsFieldRow(title: "CLI command", detail: nil) {
                        TextField("CLI command", text: $serviceCLICommand)
                            .textFieldStyle(SquareBorderTextFieldStyle())
                            .accessibilityIdentifier("app.settings.services.cli-command")
                    }

                    SettingsFieldRow(title: "CLI arguments", detail: "Passed before prompt text") {
                        TextField("CLI arguments (before prompt)", text: $serviceCLIArguments)
                            .textFieldStyle(SquareBorderTextFieldStyle())
                            .accessibilityIdentifier("app.settings.services.cli-arguments")
                    }

                    SettingsFieldRow(title: "Default agent", detail: nil) {
                        TextField("Default agent", text: $serviceDefaultAgent)
                            .textFieldStyle(SquareBorderTextFieldStyle())
                            .accessibilityIdentifier("app.settings.services.default-agent")
                    }

                    Toggle("Pass `--agent` argument when available", isOn: $servicePassAgentFlag)
                        .accessibilityIdentifier("app.settings.services.pass-agent-flag")
                }
            }

            SettingsCard(
                title: "Prompt Templates",
                description: "Prompts support an optional `{{text}}` placeholder."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Settings.Services.rephrasePrompt)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                        TextEditor(text: $serviceRephrasePrompt)
                            .font(AppTypographyTokens.bodyMonospaced)
                            .frame(minHeight: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                                    .stroke(appThemePalette.borderColorValue.opacity(0.8), lineWidth: 1)
                            )
                            .accessibilityIdentifier("app.settings.services.rephrase-prompt")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Settings.Services.researchPrompt)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                        TextEditor(text: $serviceResearchPrompt)
                            .font(AppTypographyTokens.bodyMonospaced)
                            .frame(minHeight: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                                    .stroke(appThemePalette.borderColorValue.opacity(0.8), lineWidth: 1)
                            )
                            .accessibilityIdentifier("app.settings.services.research-prompt")
                    }

                    Button(AppStrings.Settings.Services.resetDefaults) {
                        serviceCLIProfile = AppPreferences.defaultTextServiceCLIProfile
                        serviceCLITrustMode = AppPreferences.defaultTextServiceCLITrustMode
                        serviceCLICommand = AppPreferences.defaultTextServiceCLICommand
                        serviceCLIArguments = AppPreferences.defaultTextServiceCLIArguments
                        servicePassAgentFlag = AppPreferences.defaultTextServicePassAgentFlag
                        serviceDefaultAgent = AppPreferences.defaultTextServiceDefaultAgent
                        serviceRephrasePrompt = AppPreferences.defaultTextServiceRephrasePrompt
                        serviceResearchPrompt = AppPreferences.defaultTextServiceResearchPrompt
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityIdentifier("app.settings.services.reset")
                }
            }
        }
    }
}
