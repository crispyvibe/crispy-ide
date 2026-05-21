import Foundation

/// View model for the terminal scroll-assist control pad (F046).
///
/// Owns:
/// - Search visibility, query, and result list.
/// - History cursor for up/down navigation through `ComposeHistoryStore` entries.
/// - Logic for resetting the cursor when new entries are recorded (i.e., user typed).
@MainActor
final class TerminalScrollAssistViewModel: ObservableObject {
    @Published var isSearchVisible = false
    @Published var searchQuery = ""
    @Published var matches: [TerminalScrollbackReader.Match] = []
    @Published private(set) var historyCursor: Int?

    private let session: TerminalSession
    private let composeHistoryStore: ComposeHistoryStore?
    private var searchTask: Task<Void, Never>?
    private var lastSeenHistoryCount = 0

    init(session: TerminalSession) {
        self.session = session
        self.composeHistoryStore = session.composeHistoryStore
        self.lastSeenHistoryCount = composeHistoryStore?.entries(for: session.id).count ?? 0
    }

    // MARK: - History

    private var historyEntries: [String] {
        composeHistoryStore?.entries(for: session.id) ?? []
    }

    var canNavigatePrevious: Bool {
        let entries = historyEntries
        guard !entries.isEmpty else { return false }
        // Reset detection: if entries grew, we'll start from newest.
        if entries.count != lastSeenHistoryCount { return true }
        guard let cursor = historyCursor else { return true }
        return cursor > 0
    }

    var canNavigateNext: Bool {
        historyCursor != nil
    }

    func navigatePrevious() {
        let entries = historyEntries
        guard !entries.isEmpty else { return }

        // If user typed since last navigation, reset cursor.
        if entries.count != lastSeenHistoryCount {
            historyCursor = nil
            lastSeenHistoryCount = entries.count
        }

        let target: Int
        if let cursor = historyCursor {
            target = max(cursor - 1, 0)
        } else {
            target = entries.count - 1
        }
        historyCursor = target

        let text = entries[target]
        Task { [session] in
            await TerminalScrollbackReader.scrollToText(in: session, text: text)
        }
    }

    func navigateNext() {
        let entries = historyEntries
        guard let cursor = historyCursor, !entries.isEmpty else { return }

        if cursor + 1 >= entries.count {
            historyCursor = nil
            Task { [session] in
                await TerminalScrollbackReader.scrollToBottom(in: session)
            }
            return
        }

        let target = cursor + 1
        historyCursor = target
        let text = entries[target]
        Task { [session] in
            await TerminalScrollbackReader.scrollToText(in: session, text: text)
        }
    }

    // MARK: - Search

    func toggleSearch() {
        if isSearchVisible {
            closeSearch()
        } else {
            isSearchVisible = true
        }
    }

    func closeSearch() {
        searchTask?.cancel()
        isSearchVisible = false
        searchQuery = ""
        matches = []
    }

    func runSearch() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matches = []
            return
        }
        searchTask = Task { [session] in
            let results = await TerminalScrollbackReader.search(in: session, query: trimmed, limit: 200)
            guard !Task.isCancelled else { return }
            self.matches = results
        }
    }

    func scrollToMatch(_ match: TerminalScrollbackReader.Match) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [session, matches] in
            await TerminalScrollbackReader.scrollToMatch(
                in: session,
                match: match,
                allMatches: matches,
                query: query
            )
        }
    }
}
