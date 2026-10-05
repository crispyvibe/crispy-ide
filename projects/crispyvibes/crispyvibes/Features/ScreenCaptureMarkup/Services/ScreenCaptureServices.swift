import Combine
import Foundation

/// Long-lived F062 dependency aggregate owned and assembled by `AppContainer`.
@MainActor
final class ScreenCaptureServices {
    enum LifecycleState: Equatable {
        case idle
        case running
        case shutDown
    }

    let coordinator: ScreenCaptureCoordinator
    let preferences: any ScreenCapturePreferencesManaging
    let shortcutManager: any GlobalCaptureShortcutManaging
    let settingsViewModel: ScreenCaptureSettingsViewModel
    let shortcutSettingsStore: AppShortcutSettingsStore
    let historyStore: ScreenCaptureHistoryStore

    private let recoveryController: any ScreenCaptureRecoveryPresenting
    private let authorizer: any ScreenCaptureAuthorizing
    private let relaunchHandler: () -> Void
    private let shortcutResolver: (AppShortcutBinding?) -> GlobalCaptureShortcut?
    private let userDefaults: UserDefaults
    private var coordinatorCancellable: AnyCancellable?
    private var bindingObserver: NSObjectProtocol?
    private(set) var lifecycleState: LifecycleState = .idle
    private var isRecoveryPresented = false

    init(
        coordinator: ScreenCaptureCoordinator,
        preferences: any ScreenCapturePreferencesManaging,
        shortcutManager: any GlobalCaptureShortcutManaging,
        settingsViewModel: ScreenCaptureSettingsViewModel,
        shortcutSettingsStore: AppShortcutSettingsStore,
        historyStore: ScreenCaptureHistoryStore,
        recoveryController: any ScreenCaptureRecoveryPresenting,
        authorizer: any ScreenCaptureAuthorizing,
        shortcutResolver: @escaping (AppShortcutBinding?) -> GlobalCaptureShortcut?,
        relaunchApplication: @escaping () -> Void,
        userDefaults: UserDefaults
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.shortcutManager = shortcutManager
        self.settingsViewModel = settingsViewModel
        self.shortcutSettingsStore = shortcutSettingsStore
        self.historyStore = historyStore
        self.recoveryController = recoveryController
        self.authorizer = authorizer
        self.shortcutResolver = shortcutResolver
        relaunchHandler = relaunchApplication
        self.userDefaults = userDefaults
    }

    /// Starts bounded-history loading and observers once, then reconciles global registration on every call.
    func start() {
        guard lifecycleState != .shutDown else { return }
        if lifecycleState == .idle {
            lifecycleState = .running
            historyStore.load()
            shortcutManager.onRegistrationChanged = { [weak self] in
                self?.publishRegistrationState()
            }
            bindingObserver = NotificationCenter.default.addObserver(
                forName: .appShortcutBindingsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebindGlobalShortcut() }
            }
            coordinatorCancellable = coordinator.$state.sink { [weak self] state in
                self?.handleCoordinatorState(state)
            }
        }
        reconcileGlobalShortcut()
    }

    /// Reconciles the configured binding with current manager state without churning an exact registration.
    func reconcileGlobalShortcut() {
        guard lifecycleState != .shutDown else { return }
        let expectedShortcut = configuredGlobalShortcut()
        let registration = shortcutManager.registration(for: .captureScreen)
        switch (expectedShortcut, registration) {
        case (nil, .disabled):
            publishRegistrationState()
        case (let expected?, .registered(let registered)) where registered == expected:
            publishRegistrationState()
        default:
            _ = shortcutManager.rebind(.captureScreen, to: expectedShortcut)
            publishRegistrationState()
        }
    }

    func rebindGlobalShortcut() {
        guard lifecycleState != .shutDown else { return }
        _ = shortcutManager.rebind(
            .captureScreen,
            to: configuredGlobalShortcut()
        )
        publishRegistrationState()
    }

    func shutdown() {
        guard lifecycleState != .shutDown else { return }
        lifecycleState = .shutDown
        if let bindingObserver {
            NotificationCenter.default.removeObserver(bindingObserver)
            self.bindingObserver = nil
        }
        coordinatorCancellable?.cancel()
        coordinatorCancellable = nil
        dismissRecoveryIfPresented()
        shortcutManager.shutdown()
        publishRegistrationState()
        coordinator.shutdown()
        historyStore.shutdown()
    }

    private func configuredGlobalShortcut() -> GlobalCaptureShortcut? {
        let binding = AppShortcutRegistry.binding(for: .captureScreen, userDefaults: userDefaults)
        return shortcutResolver(binding)
    }

    private func publishRegistrationState() {
        settingsViewModel.refreshRegistrationStatus()
        shortcutSettingsStore.reload()
    }

    private func handleCoordinatorState(_ state: ScreenCaptureCoordinatorState) {
        switch state {
        case .permissionRequired(_, let authorization):
            isRecoveryPresented = true
            recoveryController.presentPermission(
                authorization,
                recheck: { [weak self] in self?.performRecovery(.recheckPermission) },
                relaunch: { [weak self] in self?.relaunchHandler() },
                cancel: { [weak self] in self?.performRecovery(.cancel) }
            )
        case .failed(_, let error):
            isRecoveryPresented = true
            recoveryController.presentError(error) { [weak self] action in
                self?.performRecovery(action)
            }
        default:
            dismissRecoveryIfPresented()
        }
    }

    private func performRecovery(_ action: ScreenCaptureRecoveryAction) {
        dismissRecoveryIfPresented()
        switch action {
        case .retry, .beginNewCapture, .recheckPermission:
            coordinator.beginCapture()
        case .openSystemSettings:
            authorizer.openScreenRecordingSettings()
        case .relaunchApplication:
            relaunchHandler()
        case .cancel:
            coordinator.cancelCapture()
        }
    }

    private func dismissRecoveryIfPresented() {
        guard isRecoveryPresented else { return }
        isRecoveryPresented = false
        recoveryController.dismiss()
    }
}
