import Foundation

/// Ensures async operations execute in FIFO order. Each enqueued operation
/// waits for the previous one to complete before starting.
@MainActor
final class SerialTaskQueue {
    private var pending: Task<Void, Never>?

    func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
            // Clear reference if this is still the latest task
            if self?.pending?.isCancelled == false {
                // no-op: next enqueue will chain
            }
        }
    }

    func cancelAll() {
        pending?.cancel()
        pending = nil
    }
}
