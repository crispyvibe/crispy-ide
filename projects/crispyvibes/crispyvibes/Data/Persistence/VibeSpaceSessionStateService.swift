import CryptoKit
import Foundation

/// Centralized service for capturing and restoring vibespace session state.
/// Separate from vibespace settings and preset configuration.
/// Single responsibility: serialize runtime state on close, deserialize on open.
final class VibeSpaceSessionStateService {
    static let shared = VibeSpaceSessionStateService()

    private let persistenceStore: AppPersistenceDataStore
    private let directoryURL: URL
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.persistenceStore = AppPersistenceDataStore(fileManager: fileManager)
        self.directoryURL = directoryURL ?? persistenceStore.appFileURL(
            relativePath: "vibespace-session-state",
            isDirectory: true
        )
    }

    func save(_ state: VibeSpaceSessionState, for vibespaceID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let fileURL = stateFileURL(for: vibespaceID)
        persistenceStore.save(state, to: fileURL)
    }

    func load(for vibespaceID: UUID) -> VibeSpaceSessionState? {
        lock.lock()
        defer { lock.unlock() }
        let fileURL = stateFileURL(for: vibespaceID)
        return persistenceStore.load(VibeSpaceSessionState.self, from: fileURL)
    }

    func remove(for vibespaceID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        persistenceStore.removeFile(at: stateFileURL(for: vibespaceID))
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        persistenceStore.removeFile(at: directoryURL)
    }

    private func stateFileURL(for vibespaceID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(vibespaceID.uuidString)
            .appendingPathExtension("json")
    }
}
