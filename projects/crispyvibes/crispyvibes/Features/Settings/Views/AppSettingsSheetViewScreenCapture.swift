import SwiftUI

extension AppSettingsSheetView {
    var screenCaptureCategoryContent: some View {
        Group {
            SettingsCard(
                title: AppStrings.ScreenCapture.settingsCaptureTitle,
                description: AppStrings.ScreenCapture.settingsCaptureDescription
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(title: AppStrings.ScreenCapture.rememberedMode, detail: nil) {
                        Picker(
                            AppStrings.ScreenCapture.rememberedMode,
                            selection: Binding(
                                get: { screenCaptureSettingsViewModel.preferences.mode },
                                set: { screenCaptureSettingsViewModel.setMode($0) }
                            )
                        ) {
                            Text(AppStrings.ScreenCapture.region).tag(CaptureMode.region)
                            Text(AppStrings.ScreenCapture.window).tag(CaptureMode.window)
                            Text(AppStrings.ScreenCapture.display).tag(CaptureMode.display)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("screenCapture.settings.mode")
                    }

                    SettingsFieldRow(title: AppStrings.ScreenCapture.delay, detail: nil) {
                        Picker(
                            AppStrings.ScreenCapture.delay,
                            selection: Binding(
                                get: { screenCaptureSettingsViewModel.preferences.options.delay },
                                set: { screenCaptureSettingsViewModel.setDelay($0) }
                            )
                        ) {
                            Text(AppStrings.ScreenCapture.delayNone).tag(CaptureDelay.none)
                            Text(AppStrings.ScreenCapture.delaySeconds(3)).tag(CaptureDelay.threeSeconds)
                            Text(AppStrings.ScreenCapture.delaySeconds(5)).tag(CaptureDelay.fiveSeconds)
                            Text(AppStrings.ScreenCapture.delaySeconds(10)).tag(CaptureDelay.tenSeconds)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("screenCapture.settings.delay")
                    }

                    Toggle(
                        AppStrings.ScreenCapture.includePointer,
                        isOn: Binding(
                            get: { screenCaptureSettingsViewModel.preferences.options.includesPointer },
                            set: { screenCaptureSettingsViewModel.setIncludesPointer($0) }
                        )
                    )
                    .accessibilityIdentifier("screenCapture.settings.includePointer")
                }
            }

            SettingsCard(
                title: AppStrings.ScreenCapture.globalShortcut,
                description: AppStrings.ScreenCapture.globalShortcutsDescription
            ) {
                HStack {
                    Text(AppStrings.ScreenCapture.captureScreenshot)
                        .font(AppTypographyTokens.settingsFieldTitle)
                    Spacer()
                    Text(screenCaptureSettingsViewModel.registrationStatus)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                    Button(AppStrings.ScreenCapture.editShortcuts) {
                        selectedCategory = .shortcuts
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityIdentifier("screenCapture.settings.editShortcuts")
                }
            }

            SettingsCard(
                title: AppStrings.ScreenCapture.permissionTitle,
                description: AppStrings.ScreenCapture.permissionMessage(
                    screenCaptureSettingsViewModel.authorizationState
                )
            ) {
                HStack(spacing: 10) {
                    Text(AppStrings.ScreenCapture.authorizationStatus(
                        screenCaptureSettingsViewModel.authorizationState
                    ))
                    .font(AppTypographyTokens.settingsFieldTitle)
                    Spacer()
                    if screenCaptureSettingsViewModel.authorizationState == .deniedOrRestricted
                        || screenCaptureSettingsViewModel.authorizationState == .revoked {
                        Button(AppStrings.ScreenCapture.openSystemSettings) {
                            screenCaptureSettingsViewModel.openSystemSettings()
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("screenCapture.settings.openSystemSettings")
                    }
                    if screenCaptureSettingsViewModel.authorizationState == .grantedRelaunchRequired {
                        Button(AppStrings.ScreenCapture.relaunchCrispy) {
                            screenCaptureSettingsViewModel.relaunch()
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("screenCapture.settings.relaunch")
                    }
                    Button(AppStrings.ScreenCapture.recheck) {
                        screenCaptureSettingsViewModel.recheckPermission()
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityIdentifier("screenCapture.settings.recheck")
                }
            }

            SettingsCard(
                title: AppStrings.ScreenCapture.historySettingsTitle,
                description: AppStrings.ScreenCapture.historySettingsDescription
            ) {
                HStack(spacing: 10) {
                    Text(AppStrings.ScreenCapture.historyItemCount(
                        screenCaptureSettingsViewModel.historyCount
                    ))
                    .font(AppTypographyTokens.settingsFieldTitle)
                    if screenCaptureSettingsViewModel.isHistoryWorking {
                        ProgressView().controlSize(.small)
                    }
                    if screenCaptureSettingsViewModel.historyFailure != nil {
                        Text(AppStrings.ScreenCapture.historyClearFailed)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.warningColor)
                    }
                    Spacer()
                    Button(AppStrings.ScreenCapture.clearScreenshotHistory, role: .destructive) {
                        screenCaptureSettingsViewModel.clearHistory()
                    }
                    .buttonStyle(.crispyvibesText)
                    .disabled(
                        screenCaptureSettingsViewModel.isHistoryWorking
                            || screenCaptureSettingsViewModel.historyCount == 0
                    )
                    .accessibilityIdentifier("screenCapture.settings.clearHistory")
                }
            }
        }
    }
}
