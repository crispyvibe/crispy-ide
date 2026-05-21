import AppKit
import Foundation

extension AppDelegate {
    func configureWindowChromeObservers() {
        let center = NotificationCenter.default
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.applyWindowChrome(to: window)
            }
        )
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.applyWindowChrome(to: window)
            }
        )
        windowObservers.append(
            center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                self?.handleUserDefaultsDidChange()
            }
        )
        windowObservers.append(
            center.addObserver(
                forName: .checkForAppUpdates,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.performSparkleManualUpdateCheck()
                }
            }
        )

        distributedThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleApplyWindowChromeToAllWindows()
        }
    }

    func scheduleApplyWindowChromeToAllWindows() {
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowChromeToAllWindows()
        }
    }

    func handleUserDefaultsDidChange() {
        let defaults = UserDefaults.standard
        let currentPreference = defaults.string(forKey: AppPreferences.appearancePreferenceKey)
            ?? AppPreferences.defaultAppearancePreference
        let currentThemePreset = defaults.string(forKey: AppPreferences.appThemePresetKey)
            ?? AppPreferences.defaultAppThemePreset
        let currentCustomThemeJSON = defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
            ?? ""
        let currentAutoUpdateChecksEnabled = AppPreferences.autoUpdateChecksEnabled(
            userDefaults: defaults
        )
        let currentAppUpdateFeedURL = Self.normalizedAppUpdateFeedURL(userDefaults: defaults)
        let currentCodeFontSize = Double(AppPreferences.codeFontSize(userDefaults: defaults))
        let customThemeActive = currentThemePreset == AppThemePreset.custom.rawValue

        let didAppearanceChange = currentPreference != lastObservedAppearancePreference
        let didPresetChange = currentThemePreset != lastObservedThemePreset
        let didCustomThemeChange = customThemeActive
            && currentCustomThemeJSON != lastObservedCustomThemeJSON
        let didCodeFontSizeChange = currentCodeFontSize != lastObservedCodeFontSize
        let didAutoUpdateChecksChange = currentAutoUpdateChecksEnabled
            != lastObservedAutoUpdateChecksEnabled
        let didAppUpdateFeedURLChange = currentAppUpdateFeedURL != lastObservedAppUpdateFeedURL

        if didAutoUpdateChecksChange || didAppUpdateFeedURLChange {
            lastObservedAutoUpdateChecksEnabled = currentAutoUpdateChecksEnabled
            lastObservedAppUpdateFeedURL = currentAppUpdateFeedURL
            configureSparkleUpdater(
                autoChecksEnabled: currentAutoUpdateChecksEnabled,
                feedURLString: currentAppUpdateFeedURL,
                shouldResetCycle: true
            )
        }

        guard didAppearanceChange || didPresetChange || didCustomThemeChange || didCodeFontSizeChange else { return }

        lastObservedAppearancePreference = currentPreference
        lastObservedThemePreset = currentThemePreset
        lastObservedCustomThemeJSON = currentCustomThemeJSON
        lastObservedCodeFontSize = currentCodeFontSize
        scheduleApplyWindowChromeToAllWindows()
    }

    static func normalizedAppUpdateFeedURL(userDefaults: UserDefaults) -> String {
        AppPreferences.effectiveAppUpdateFeedURL(userDefaults: userDefaults)
    }
}
