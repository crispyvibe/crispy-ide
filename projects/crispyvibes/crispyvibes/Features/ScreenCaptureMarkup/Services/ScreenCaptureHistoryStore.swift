import Combine
import Foundation

/// Main-actor presentation state for bounded screenshot history.
@MainActor
final class ScreenCaptureHistoryStore: ObservableObject {
    @Published private(set) var entries: [ScreenCaptureHistoryEntry] = []
    @Published private(set) var failure: ScreenCaptureHistoryStoreFailure?
    @Published private(set) var isWorking = false

    private let repository: any ScreenCaptureHistoryRepository
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    init(repository: any ScreenCaptureHistoryRepository) {
        self.repository = repository
    }

    /// Loads newest-first summaries and applies repository cleanup and retention.
    func load() {
        let repository = repository
        start(.load) { try await repository.loadEntries() }
    }

    /// Persists one flattened capture, then refreshes bounded summaries.
    func add(id: UUID = UUID(), content: ScreenCaptureHistoryContent) {
        let repository = repository
        start(.add) {
            _ = try await repository.add(id: id, content: content)
            return try await repository.loadEntries()
        }
    }

    /// Commits an immutable replacement version, then refreshes summaries.
    func update(id: UUID, content: ScreenCaptureHistoryContent) {
        let repository = repository
        start(.update) {
            _ = try await repository.update(id: id, content: content)
            return try await repository.loadEntries()
        }
    }

    /// Deletes by private atomic rename before removing the summary.
    func delete(id: UUID) {
        let repository = repository
        start(.delete) {
            try await repository.delete(id: id)
            return try await repository.loadEntries()
        }
    }

    /// Atomically retires all visible items and publishes an empty history.
    func clear() {
        let repository = repository
        start(.clear) {
            try await repository.clear()
            return []
        }
    }

    /// Waits for the currently tracked operation; primarily useful to lifecycle owners and tests.
    func waitForPendingOperation() async {
        let task = operationTask
        await task?.value
    }

    /// Applies a repository-confirmed snapshot from another injected F062 owner.
    func synchronize(entries: [ScreenCaptureHistoryEntry]) {
        self.entries = entries
        failure = nil
    }

    /// Cancels pending presentation work and releases all published metadata.
    func shutdown() {
        operationID = nil
        operationTask?.cancel()
        operationTask = nil
        entries = []
        failure = nil
        isWorking = false
    }

    private func start(
        _ operation: ScreenCaptureHistoryStoreOperation,
        work: @escaping @Sendable () async throws -> [ScreenCaptureHistoryEntry]
    ) {
        operationTask?.cancel()
        let id = UUID()
        operationID = id
        failure = nil
        isWorking = true
        operationTask = Task { [weak self] in
            do {
                let loaded = try await work()
                guard !Task.isCancelled else { return }
                self?.finish(id: id, entries: loaded)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(id: id, operation: operation, error: error)
            }
        }
    }

    private func finish(id: UUID, entries: [ScreenCaptureHistoryEntry]) {
        guard operationID == id else { return }
        self.entries = entries
        failure = nil
        isWorking = false
        operationTask = nil
        operationID = nil
    }

    private func finish(id: UUID, operation: ScreenCaptureHistoryStoreOperation, error: Error) {
        guard operationID == id else { return }
        let historyError = error as? ScreenCaptureHistoryError ?? .fileOperationFailed
        failure = ScreenCaptureHistoryStoreFailure(operation: operation, error: historyError)
        isWorking = false
        operationTask = nil
        operationID = nil
    }
}
