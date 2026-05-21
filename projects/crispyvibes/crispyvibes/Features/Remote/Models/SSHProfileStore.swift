// SSHProfileStore.swift — SSH Remote Development

import Foundation

/// Persists SSH connection profiles to JSON in Application Support/CrispyVibes.
/// No secrets stored — only host, port, user, key path.
@MainActor
final class SSHProfileStore: ObservableObject {
    @Published private(set) var profiles: [SSHConnectionProfile] = []

    private static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CrispyVibes")
            .appendingPathComponent("ssh-profiles.json")
    }

    init() { load() }

    func add(_ profile: SSHConnectionProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: SSHConnectionProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else { return }
        profiles = (try? JSONDecoder().decode([SSHConnectionProfile].self, from: data)) ?? []
    }

    private func save() {
        let url = Self.storageURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(profiles).write(to: url)
    }
}
