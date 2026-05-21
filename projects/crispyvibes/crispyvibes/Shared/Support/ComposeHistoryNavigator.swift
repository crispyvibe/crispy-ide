import Foundation

/// Per-compose-view navigator that manages cursor state for history recall.
///
/// Each compose surface (terminal spotlight, ACP chat, VibeCast) owns one
/// navigator instance. The navigator references the shared
/// `ComposeHistoryStore` and tracks which bucket it's bound to, the current
/// cursor position within that bucket, and the pending draft that was saved
/// when the user first entered history navigation.
@MainActor
final class ComposeHistoryNavigator: ObservableObject {
    enum Nav: Equatable {
        case noChange
        case replace(text: String)
    }

    private let store: ComposeHistoryStore
    private var key: UUID?
    private var cursor: Int?
    private var pendingDraft: String?

    /// True while the navigator is applying a history replacement to the text
    /// view. Text-change observers should check this flag and skip calling
    /// `resetOnUnrelatedEdit()` when it is true. Callers must set this to true
    /// before replacing text and false after the change propagates.
    var isApplyingNavigation = false

    init(store: ComposeHistoryStore) {
        self.store = store
    }

    /// Bind the navigator to a bucket. Resets cursor and draft. Call on view
    /// appearance and whenever the underlying identity changes (tab switch,
    /// thread switch, etc.).
    func attach(to key: UUID?) {
        guard self.key != key else { return }
        self.key = key
        cursor = nil
        pendingDraft = nil
    }

    /// Record a successful send. Appends to the store, clears cursor and
    /// pending draft so the old draft is never resurfaced.
    func append(_ text: String) {
        guard let key else { return }
        store.append(text, for: key)
        cursor = nil
        pendingDraft = nil
    }

    /// Called when Up is pressed on the first visual line.
    func navigateBack(currentText: String) -> Nav {
        guard let key else { return .noChange }
        let entries = store.entries(for: key)
        guard !entries.isEmpty else { return .noChange }

        if cursor == nil {
            // Enter history from idle
            pendingDraft = currentText
            cursor = entries.count - 1
        } else if let c = cursor, c > 0 {
            cursor = c - 1
        } else {
            // Already at oldest
            return .noChange
        }

        return .replace(text: entries[cursor!])
    }

    /// Called when Down is pressed on the last visual line.
    func navigateForward(currentText: String) -> Nav {
        guard let key else { return .noChange }
        guard let c = cursor else { return .noChange }

        let entries = store.entries(for: key)

        if c < entries.count - 1 {
            cursor = c + 1
            return .replace(text: entries[cursor!])
        }

        // Exit history — restore pending draft
        let draft = pendingDraft ?? ""
        cursor = nil
        pendingDraft = nil
        return .replace(text: draft)
    }

    /// Call whenever the text changes from a source other than history
    /// navigation (user typing, paste, etc.). Exits history mode and discards
    /// the pending draft.
    func resetOnUnrelatedEdit() {
        guard cursor != nil else { return }
        cursor = nil
        pendingDraft = nil
    }
}
