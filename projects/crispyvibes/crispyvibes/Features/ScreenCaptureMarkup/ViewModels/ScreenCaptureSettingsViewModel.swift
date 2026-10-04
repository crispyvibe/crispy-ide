import Combine
import Foundation

/// Settings state for F062 with injected preference, authorization, shortcut, and history stores.
@MainActor
final class ScreenCaptureSettingsViewModel: ObservableObject {
    @Published private(set) var preferences: ScreenCapturePreferences
    @Published private(set) var authorizationState: ScreenCaptureAuthorizationState
    @Published private(set) var registration: GlobalCaptureShortcutRegistration = .disabled
    @Published private(set) var historyCount = 0
    @Published private(set) var historyFailure: ScreenCaptureHistoryStoreFailure?
    @Published private(set) var isHistoryWorking = false

    private let preferenceStore: any ScreenCapturePreferencesManaging
    private let authorizer: any ScreenCaptureAuthorizing
    private let registrationProvider: () -> GlobalCaptureShortcutRegistration
    private let historyStore: ScreenCaptureHistoryStore
    private let clearHistoryHandler: () -> Void
    private let relaunchApplication: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferenceStore: any ScreenCapturePreferencesManaging,
        authorizer: any ScreenCaptureAuthorizing,
        registrationProvider: @escaping () -> GlobalCaptureShortcutRegistration,
        historyStore: ScreenCaptureHistoryStore,
        clearHistory: @escaping () -> Void,
        relaunchApplication: @escaping () -> Void = {}
    ) {
        self.preferenceStore = preferenceStore
        self.authorizer = authorizer
        self.registrationProvider = registrationProvider
        self.historyStore = historyStore
        clearHistoryHandler = clearHistory
        self.relaunchApplication = relaunchApplication
        preferences = preferenceStore.screenCapturePreferences
        authorizationState = authorizer.cachedAuthorizationState
        preferenceStore.screenCapturePreferencesPublisher
            .sink { [weak self] preferences in self?.preferences = preferences }
            .store(in: &cancellables)
        historyStore.$entries
            .sink { [weak self] entries in self?.historyCount = entries.count }
            .store(in: &cancellables)
        historyStore.$failure
            .sink { [weak self] failure in self?.historyFailure = failure }
            .store(in: &cancellables)
        historyStore.$isWorking
            .sink { [weak self] working in self?.isHistoryWorking = working }
            .store(in: &cancellables)
        refreshRegistrationStatus()
    }

    func recheckPermission() { authorizationState = authorizer.authorizationStatus() }
    func setMode(_ mode: CaptureMode) { preferenceStore.updateRememberedMode(mode) }
    func setDelay(_ delay: CaptureDelay) { preferenceStore.updateDelay(delay) }
    func setIncludesPointer(_ includesPointer: Bool) {
        preferenceStore.updateIncludesPointer(includesPointer)
    }
    func openSystemSettings() { authorizer.openScreenRecordingSettings() }
    func relaunch() { relaunchApplication() }
    func clearHistory() { clearHistoryHandler() }
    func refreshRegistrationStatus() { registration = registrationProvider() }

    var registrationStatus: String {
        switch registration {
        case .registered: return AppStrings.ScreenCapture.shortcutRegistered
        case .disabled: return AppStrings.ScreenCapture.shortcutDisabled
        case .conflict: return AppStrings.ScreenCapture.shortcutConflict
        case .failed: return AppStrings.ScreenCapture.shortcutFailed
        }
    }
}
