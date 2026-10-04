import Combine
import Foundation

/// UserDefaults-backed non-content preferences for F062.
@MainActor
final class ScreenCapturePreferencesStore: ObservableObject, ScreenCapturePreferencesManaging {
    @Published private(set) var screenCapturePreferences: ScreenCapturePreferences

    var screenCapturePreferencesPublisher: AnyPublisher<ScreenCapturePreferences, Never> {
        $screenCapturePreferences.eraseToAnyPublisher()
    }

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults,
        key: String = AppPreferences.screenCapturePreferencesKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ScreenCapturePreferences.self, from: data) {
            screenCapturePreferences = decoded
            persist(decoded)
        } else {
            screenCapturePreferences = .default
        }
    }

    func updateRememberedMode(_ mode: CaptureMode) {
        update { $0.mode = mode }
    }

    func updateDelay(_ delay: CaptureDelay) {
        update { $0.options.delay = delay }
    }

    func updateIncludesPointer(_ includesPointer: Bool) {
        update { $0.options.includesPointer = includesPointer }
    }

    func reset() {
        screenCapturePreferences = .default
        userDefaults.removeObject(forKey: key)
    }

    private func update(_ mutation: (inout ScreenCapturePreferences) -> Void) {
        var preferences = screenCapturePreferences
        mutation(&preferences)
        guard preferences != screenCapturePreferences else { return }
        screenCapturePreferences = preferences
        persist(preferences)
    }

    private func persist(_ preferences: ScreenCapturePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        userDefaults.set(data, forKey: key)
    }
}
