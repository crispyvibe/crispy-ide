import Foundation

/// Debounces dirty-buffer saves with a configurable delay.
///
/// Each buffer gets at most one pending work item. Scheduling again
/// for the same buffer cancels the previous timer and restarts.
@MainActor
final class AutosaveScheduler {

    private var pendingWork: [String: DispatchWorkItem] = [:]
    private let delay: TimeInterval
    private let writer: (URL, SaveToken) async throws -> Void

    /// Creates a scheduler with the given debounce delay and write closure.
    init(delay: TimeInterval = 0.45, writer: @escaping (URL, SaveToken) async throws -> Void) {
        self.delay = delay
        self.writer = writer
    }

    /// Schedules a debounced save for the given buffer. No-op if the buffer is not dirty.
    func scheduleSave(for buffer: DocumentBuffer) {
        guard buffer.isDirty else { return }
        cancel(for: buffer.id)

        let item = DispatchWorkItem { [weak self, weak buffer] in
            Task { @MainActor [weak self, weak buffer] in
                guard let self, let buffer else { return }
                guard let token = buffer.beginSave() else { return }

                // F039-R04: reject empty content when baseline is non-empty
                if token.content.isEmpty, let baseline = buffer.baseline, !baseline.isEmpty {
                    buffer.didFailSave(token: token)
                    return
                }

                do {
                    try await self.writer(buffer.fileURL, token)
                    buffer.didSave(token: token)
                } catch {
                    buffer.didFailSave(token: token)
                }
            }
        }

        pendingWork[buffer.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Cancels any pending save for the given buffer ID.
    func cancel(for bufferID: String) {
        pendingWork.removeValue(forKey: bufferID)?.cancel()
    }

    /// Cancels all pending saves.
    func cancelAll() {
        pendingWork.values.forEach { $0.cancel() }
        pendingWork.removeAll()
    }
}
