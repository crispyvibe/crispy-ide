import CryptoKit
import Foundation
import Security

protocol SigningKeychainStoring {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
}

extension KeychainStore: SigningKeychainStoring {}

struct SigningKeychainVariant: Hashable {
    let service: String
}

/// File I/O layer for per-vibespace directory structure.
/// Knows paths. Delegates actual read/write to AppPersistenceDataStore.
final class VibeSpacePersistenceStore {
    private let store: AppPersistenceDataStore
    private let vibespacesDirectoryURL: URL
    private let appStateFileURL: URL
    private let signingKeychainService: String
    private let legacySigningKeychainServices: [String]
    private let keychainStoreFactory: (SigningKeychainVariant) -> any SigningKeychainStoring
    private var _signingKey: SymmetricKey?

    init(
        store: AppPersistenceDataStore,
        signingKeychainService: String? = nil,
        legacySigningKeychainServices: [String]? = nil,
        keychainStoreFactory: @escaping (SigningKeychainVariant) -> any SigningKeychainStoring = { variant in
            KeychainStore(service: variant.service)
        }
    ) {
        self.store = store
        self.vibespacesDirectoryURL = store.appFileURL(relativePath: "vibespaces", isDirectory: true)
        self.appStateFileURL = store.appFileURL(relativePath: "app-state.json")
        let resolvedService = signingKeychainService ?? Self.resolveSigningKeychainService()
        self.signingKeychainService = resolvedService
        self.legacySigningKeychainServices = legacySigningKeychainServices
            ?? Self.legacySigningKeychainServices(currentService: resolvedService)
        self.keychainStoreFactory = keychainStoreFactory
    }

    func invalidateSigningKeyCache() {
        _signingKey = nil
    }

    // MARK: - Signing Key

    private var signingKey: SymmetricKey {
        if let key = _signingKey { return key }
        let key = loadOrCreateSigningKey()
        _signingKey = key
        return key
    }

    private static let signingKeychainServiceInfoKey = "CrispyVibesConfigSigningKeychainService"
    private static let defaultKeychainService = "com.crispyvibe.app.config-signing"
    private static let keychainAccount = "vibespace-hmac-key"

    private func loadOrCreateSigningKey() -> SymmetricKey {
        if let existingKeyData = loadKeychainItem(service: signingKeychainService) {
            return SymmetricKey(data: existingKeyData)
        }
        for legacyService in legacySigningKeychainServices {
            guard let legacyKeyData = loadKeychainItem(service: legacyService) else { continue }
            persistKeychainItem(legacyKeyData, service: signingKeychainService)
            return SymmetricKey(data: legacyKeyData)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        persistKeychainItem(keyData, service: signingKeychainService)
        return newKey
    }

    private func loadKeychainItem(service: String) -> Data? {
        for variant in Self.keychainReadVariants(for: service) {
            if let data = try? keychainStoreFactory(variant).read(account: Self.keychainAccount) {
                return data
            }
        }
        return nil
    }

    private func persistKeychainItem(_ data: Data, service: String) {
        for variant in Self.keychainWriteVariants(for: service) {
            if (try? keychainStoreFactory(variant).write(data, account: Self.keychainAccount)) != nil {
                return
            }
        }
    }

    private static func resolveSigningKeychainService(bundle: Bundle = .main) -> String {
        if let service = (bundle.object(forInfoDictionaryKey: signingKeychainServiceInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !service.isEmpty {
            return service
        }
        return defaultKeychainService
    }

    private static func legacySigningKeychainServices(
        currentService: String,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> [String] {
        []
    }

    static func _test_resolveSigningKeychainService(bundle: Bundle = .main) -> String {
        resolveSigningKeychainService(bundle: bundle)
    }

    static func _test_legacySigningKeychainServices(
        currentService: String,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> [String] {
        legacySigningKeychainServices(currentService: currentService, bundleIdentifier: bundleIdentifier)
    }

    private static func keychainReadVariants(for service: String) -> [SigningKeychainVariant] {
        [
            SigningKeychainVariant(service: service),
        ]
    }

    private static func keychainWriteVariants(for service: String) -> [SigningKeychainVariant] {
        [
            SigningKeychainVariant(service: service),
        ]
    }

    // MARK: - App State

    func loadAppState() -> AppStateFile {
        store.load(AppStateFile.self, from: appStateFileURL) ?? .empty
    }

    func saveAppState(_ state: AppStateFile) {
        store.save(state, to: appStateFileURL)
    }

    // MARK: - VibeSpace Directory

    func vibespaceDirectoryURL(for id: UUID) -> URL {
        vibespacesDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func vibespaceConfigURL(for id: UUID) -> URL {
        vibespaceDirectoryURL(for: id).appendingPathComponent("vibespace.json")
    }

    func vibespaceLayoutURL(for id: UUID) -> URL {
        vibespaceDirectoryURL(for: id).appendingPathComponent("layout.json")
    }

    func vibespaceSessionURL(for id: UUID) -> URL {
        vibespaceDirectoryURL(for: id).appendingPathComponent("session.json")
    }

    func projectsDirectoryURL(for vibespaceID: UUID) -> URL {
        vibespaceDirectoryURL(for: vibespaceID).appendingPathComponent("projects", isDirectory: true)
    }

    func projectConfigURL(for projectPath: String, in vibespaceID: UUID) -> URL {
        let hash = SHA256.hash(data: Data(projectPath.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return projectsDirectoryURL(for: vibespaceID)
            .appendingPathComponent(hash)
            .appendingPathExtension("json")
    }

    // MARK: - VibeSpace CRUD

    func saveVibeSpaceConfig(_ config: VibeSpaceConfigFile) {
        store.createDirectory(at: vibespaceDirectoryURL(for: config.id))
        store.saveWithIntegrity(config, to: vibespaceConfigURL(for: config.id), using: signingKey)
    }

    func loadVibeSpaceConfig(for id: UUID) -> AppPersistenceDataStore.SignedLoadResult<VibeSpaceConfigFile>? {
        store.loadWithIntegrity(VibeSpaceConfigFile.self, from: vibespaceConfigURL(for: id), using: signingKey)
    }

    func deleteVibeSpace(_ id: UUID) {
        store.removeDirectory(at: vibespaceDirectoryURL(for: id))
    }

    func existingVibeSpaceIDs() -> [UUID] {
        store.contentsOfDirectory(at: vibespacesDirectoryURL).compactMap { url in
            UUID(uuidString: url.lastPathComponent)
        }
    }

    // MARK: - Project Config CRUD

    func saveProjectConfig(_ config: ProjectConfigFile, in vibespaceID: UUID) {
        store.createDirectory(at: projectsDirectoryURL(for: vibespaceID))
        store.saveWithIntegrity(config, to: projectConfigURL(for: config.projectPath, in: vibespaceID), using: signingKey)
    }

    func loadProjectConfig(for projectPath: String, in vibespaceID: UUID) -> AppPersistenceDataStore.SignedLoadResult<ProjectConfigFile>? {
        store.loadWithIntegrity(ProjectConfigFile.self, from: projectConfigURL(for: projectPath, in: vibespaceID), using: signingKey)
    }

    func deleteProjectConfig(for projectPath: String, in vibespaceID: UUID) {
        store.removeFile(at: projectConfigURL(for: projectPath, in: vibespaceID))
    }

    // MARK: - Pruning

    func pruneInvalidVibeSpaceDirectories() {
        for url in store.contentsOfDirectory(at: vibespacesDirectoryURL) {
            guard UUID(uuidString: url.lastPathComponent) != nil else {
                store.removeDirectory(at: url)
                continue
            }
            let configURL = url.appendingPathComponent("vibespace.json")
            if !FileManager.default.fileExists(atPath: configURL.path) {
                store.removeDirectory(at: url)
            }
        }
    }
}
