import Foundation
import SwiftUI

/// In-memory history store for compose inputs across the app.
///
/// Each bucket is keyed by a stable resource UUID (terminal session id, ACP
/// store id, VibeCast session id). Entries are the trimmed text of each
/// successful send. Consecutive duplicates are suppressed. Each bucket is
/// capped at `maxEntriesPerBucket` (oldest dropped on overflow).
///
/// Owned as a singleton by `AppContainer`. Not persisted across app restarts.
@MainActor
final class ComposeHistoryStore {
    private var buckets: [UUID: [String]] = [:]
    let maxEntriesPerBucket: Int

    init(maxEntriesPerBucket: Int = 500) {
        self.maxEntriesPerBucket = maxEntriesPerBucket
    }

    func entries(for key: UUID) -> [String] {
        buckets[key] ?? []
    }

    func append(_ text: String, for key: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var bucket = buckets[key] ?? []
        // Deduplicate consecutive
        if bucket.last == trimmed { return }
        bucket.append(trimmed)
        // Enforce cap
        if bucket.count > maxEntriesPerBucket {
            bucket.removeFirst(bucket.count - maxEntriesPerBucket)
        }
        buckets[key] = bucket
    }

    func clear(for key: UUID) {
        buckets.removeValue(forKey: key)
    }
}

// MARK: - Environment Key

private struct ComposeHistoryStoreKey: EnvironmentKey {
    static let defaultValue: ComposeHistoryStore? = nil
}

extension EnvironmentValues {
    var composeHistoryStore: ComposeHistoryStore? {
        get { self[ComposeHistoryStoreKey.self] }
        set { self[ComposeHistoryStoreKey.self] = newValue }
    }
}
