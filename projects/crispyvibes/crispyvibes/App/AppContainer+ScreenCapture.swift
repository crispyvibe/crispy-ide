import AppKit
import CoreGraphics
import OSLog

@MainActor
private final class ScreenCaptureCoordinatorRelay {
    weak var coordinator: ScreenCaptureCoordinator?

    func handle(_ command: GlobalCaptureShortcutCommand) {
        switch command {
        case .captureScreen:
            coordinator?.beginCapture()
        }
    }
}

extension AppContainer {
    /// Assembles the complete F062 graph. This is the sole concrete composition site.
    @MainActor
    static func makeScreenCaptureServices(
        rasterServices: RasterImageEditorServices,
        appPersistenceStore: AppPersistenceDataStore
    ) -> ScreenCaptureServices {
        let userDefaults = UserDefaults.standard
        AppPreferences.migrateUserDefaultsIfNeeded(userDefaults: userDefaults)
        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: userDefaults)

        let workspace = NSWorkspace.shared
        let currentApplication = NSRunningApplication.current
        let geometry = ScreenCaptureGeometry()
        let resourcePolicy = ScreenCaptureResourcePolicy()
        let preferences = ScreenCapturePreferencesStore(userDefaults: userDefaults)
        let authorizationHistory = UserDefaultsScreenCaptureAuthorizationHistoryStore(
            defaults: userDefaults,
            key: AppPreferences.screenCaptureAuthorizationHistoryKey
        )
        let authorizer = ScreenCaptureTCCAuthorizer(
            historyStore: authorizationHistory,
            preflightAccess: { CGPreflightScreenCaptureAccess() },
            requestAccess: { CGRequestScreenCaptureAccess() },
            openSettings: { workspace.open($0) }
        )
        let registry = ScreenCaptureSurfaceRegistry()
        let announcer = rasterServices.announcer
        let scheduler = ContinuousScreenCaptureScheduler()
        let magnifierSampler = ScreenCaptureKitMagnifierSampler()
        let overlay = ScreenCaptureOverlayController(
            surfaceRegistry: registry,
            selectionViewModelFactory: { catalog, initialMode, options in
                CaptureSelectionViewModel(
                    catalog: catalog,
                    initialMode: initialMode,
                    options: options,
                    geometry: geometry,
                    magnifierSampler: magnifierSampler,
                    excludedWindowIDs: {
                        registry.excludedCaptureWindowIDs
                    },
                    scheduler: scheduler,
                    announce: { message in announcer.announce(message) }
                )
            }
        )
        let historyRoot = appPersistenceStore.appFileURL(
            relativePath: "ScreenCapture/History",
            isDirectory: true
        )
        let historyLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
            category: "screenCapture.history"
        )
        let historyRepository = LocalScreenCaptureHistoryRepository(
            rootURL: historyRoot,
            clock: SystemScreenCaptureHistoryClock(),
            imageProcessor: ScreenCaptureThumbnailService(),
            maintenanceWarningHandler: { warning in
                switch warning {
                case .quarantineFailed:
                    historyLogger.warning("A corrupt screenshot history item could not be quarantined.")
                case .quarantineCleanupFailed:
                    historyLogger.warning("Quarantined screenshot history trash could not be removed.")
                }
            }
        )
        let historyStore = ScreenCaptureHistoryStore(repository: historyRepository)
        let output = ScreenCaptureOutputService(
            encoder: RasterImageEncoder(),
            resourcePolicy: resourcePolicy
        )
        let clipboard = AppKitScreenCaptureClipboard(pasteboard: NSPasteboard.general)
        let studioWindowController = ScreenshotStudioWindowController(
            registry: registry,
            announcer: announcer,
            applicationActivator: AppKitScreenCaptureApplicationActivator(
                application: currentApplication
            ),
            windowFocuser: AppKitScreenCaptureWindowFocuser()
        )
        let studioCoordinator = ScreenshotStudioCoordinator(
            windowController: studioWindowController,
            historyStore: historyStore,
            viewModelFactory: { placement in
                let delivery = ScreenCaptureDeliveryCoordinator(
                    exporter: rasterServices.exporter,
                    encoder: output,
                    clipboard: clipboard,
                    repository: historyRepository,
                    historyStore: historyStore,
                    scheduler: scheduler
                )
                return ScreenshotStudioViewModel(
                    rasterViewModel: RasterImageEditorViewModel(services: rasterServices),
                    repository: historyRepository,
                    delivery: delivery,
                    placement: placement
                )
            }
        )
        let recoveryController = ScreenCaptureRecoveryPanelController(
            registry: registry,
            authorizer: authorizer,
            viewModelFactory: { title, message, commands in
                ScreenCaptureRecoveryViewModel(
                    title: title,
                    message: message,
                    commands: commands
                )
            }
        )
        let originTracker = ScreenCaptureOriginAppAdapter(
            workspace: workspace,
            currentApplication: currentApplication,
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            keyWindowProvider: { NSApp.keyWindow }
        )
        let coordinator = ScreenCaptureCoordinator(
            authorizer: authorizer,
            provider: ScreenCaptureKitStillProvider(
                geometry: geometry,
                resourcePolicy: resourcePolicy
            ),
            preferences: preferences,
            selectionController: overlay,
            exclusionProvider: registry,
            studioRouter: studioCoordinator,
            originTracker: originTracker
        )
        let relay = ScreenCaptureCoordinatorRelay()
        relay.coordinator = coordinator
        let shortcutManager = CarbonGlobalCaptureShortcutManager { [weak relay] command in
            relay?.handle(command)
        }
        let relaunchApplication = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            workspace.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { _, _ in NSApp.terminate(nil) }
        }
        let settingsViewModel = ScreenCaptureSettingsViewModel(
            preferenceStore: preferences,
            authorizer: authorizer,
            registrationProvider: { [weak shortcutManager] in
                shortcutManager?.registration(for: .captureScreen) ?? .disabled
            },
            historyStore: historyStore,
            clearHistory: { studioCoordinator.clearHistory() },
            relaunchApplication: relaunchApplication
        )
        let shortcutSettingsStore = AppShortcutSettingsStore(
            userDefaults: userDefaults,
            globalRegistrationProvider: { [weak shortcutManager] action in
                guard action == .captureScreen else { return nil }
                return shortcutManager?.registration(for: .captureScreen)
            }
        )
        return ScreenCaptureServices(
            coordinator: coordinator,
            preferences: preferences,
            shortcutManager: shortcutManager,
            settingsViewModel: settingsViewModel,
            shortcutSettingsStore: shortcutSettingsStore,
            historyStore: historyStore,
            recoveryController: recoveryController,
            authorizer: authorizer,
            shortcutResolver: CarbonGlobalCaptureShortcutManager.shortcut(from:),
            relaunchApplication: relaunchApplication,
            userDefaults: userDefaults
        )
    }
}
