import AppKit
import Foundation
import Sparkle

extension AppDelegate {
    func configureSparkleUpdater(
        autoChecksEnabled: Bool,
        feedURLString: String,
        shouldResetCycle: Bool
    ) {
        guard let updater = sparkleUpdaterController?.updater else {
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .info,
                event: "sparkle_updater_disabled"
            )
            return
        }

        if updater.automaticallyChecksForUpdates != autoChecksEnabled {
            updater.automaticallyChecksForUpdates = autoChecksEnabled
        }
        if updater.updateCheckInterval != AppPreferences.appUpdateAutoCheckInterval {
            updater.updateCheckInterval = AppPreferences.appUpdateAutoCheckInterval
        }

        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: .info,
            event: "sparkle_updater_configured",
            metadata: [
                "auto_checks": autoChecksEnabled ? "true" : "false",
                "feed": feedURLString
            ]
        )

        if shouldResetCycle {
            updater.resetUpdateCycleAfterShortDelay()
        }
    }

    @MainActor
    func performSparkleManualUpdateCheck() {
        sparkleUpdaterController?.checkForUpdates(nil)
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.normalizedAppUpdateFeedURL(userDefaults: .standard)
    }
}
