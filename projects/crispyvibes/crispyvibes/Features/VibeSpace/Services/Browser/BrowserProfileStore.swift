import Foundation
import WebKit

/// Manages named browser profiles with isolated data stores.
@MainActor
final class BrowserProfileStore: ObservableObject {
    struct Profile: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var isDefault: Bool

        init(id: UUID = UUID(), name: String, isDefault: Bool = false) {
            self.id = id; self.name = name; self.isDefault = isDefault
        }
    }

    @Published private(set) var profiles: [Profile] = []
    private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        loadProfiles()
        if profiles.isEmpty {
            profiles.append(Profile(name: "Default", isDefault: true))
            save()
        }
    }

    var defaultProfile: Profile? { profiles.first(where: \.isDefault) ?? profiles.first }

    func dataStore(for profileID: UUID) -> WKWebsiteDataStore {
        if let existing = dataStores[profileID] { return existing }
        if profiles.first(where: { $0.id == profileID })?.isDefault == true {
            let store = WKWebsiteDataStore.default()
            dataStores[profileID] = store
            return store
        }
        let store = WKWebsiteDataStore.nonPersistent()
        dataStores[profileID] = store
        return store
    }

    func createProfile(name: String) -> Profile {
        let profile = Profile(name: name)
        profiles.append(profile)
        save()
        return profile
    }

    func deleteProfile(id: UUID) {
        guard profiles.first(where: { $0.id == id })?.isDefault != true else { return }
        profiles.removeAll { $0.id == id }
        dataStores.removeValue(forKey: id)
        save()
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else { return }
        profiles = decoded
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(profiles) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private nonisolated static func defaultFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let bundleId = Bundle.main.bundleIdentifier ?? "crispyvibes"
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("browser_profiles.json")
    }
}
