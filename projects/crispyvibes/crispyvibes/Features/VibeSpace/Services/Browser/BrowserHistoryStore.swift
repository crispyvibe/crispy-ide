import Foundation

@MainActor
final class BrowserHistoryStore: ObservableObject {

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        var url: String
        var title: String?
        var lastVisited: Date
        var visitCount: Int
        var typedCount: Int
        var lastTypedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case id, url, title, lastVisited, visitCount, typedCount, lastTypedAt
        }

        init(id: UUID, url: String, title: String?, lastVisited: Date, visitCount: Int, typedCount: Int = 0, lastTypedAt: Date? = nil) {
            self.id = id; self.url = url; self.title = title; self.lastVisited = lastVisited
            self.visitCount = visitCount; self.typedCount = typedCount; self.lastTypedAt = lastTypedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            url = try c.decode(String.self, forKey: .url)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            lastVisited = try c.decode(Date.self, forKey: .lastVisited)
            visitCount = try c.decode(Int.self, forKey: .visitCount)
            typedCount = try c.decodeIfPresent(Int.self, forKey: .typedCount) ?? 0
            lastTypedAt = try c.decodeIfPresent(Date.self, forKey: .lastTypedAt)
        }
    }

    @Published private(set) var entries: [Entry] = []
    private let fileURL: URL?
    private var didLoad = false
    private let maxEntries = 5000

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let fileURL else { return }
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
            let loaded = decoded.sorted { $0.lastVisited > $1.lastVisited }
            await MainActor.run { [weak self] in
                guard let self else { return }
                var merged = Dictionary(uniqueKeysWithValues: loaded.map { ($0.url, $0) })
                for entry in self.entries { merged[entry.url] = entry }
                var sorted = merged.values.sorted { $0.lastVisited > $1.lastVisited }
                if sorted.count > self.maxEntries { sorted.removeLast(sorted.count - self.maxEntries) }
                self.entries = sorted
                if !self.entries.isEmpty { self.scheduleSave() }
            }
        }
    }

    func recordVisit(url: URL?, title: String?) {
        loadIfNeeded()
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        let urlString = url.absoluteString
        if let idx = entries.firstIndex(where: { $0.url == urlString }) {
            entries[idx].lastVisited = Date()
            entries[idx].visitCount += 1
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entries[idx].title = title
            }
        } else {
            entries.insert(Entry(id: UUID(), url: urlString, title: title, lastVisited: Date(), visitCount: 1), at: 0)
        }
        entries.sort { $0.lastVisited > $1.lastVisited }
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        scheduleSave()
    }

    func recordTypedNavigation(url: URL?) {
        loadIfNeeded()
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        let urlString = url.absoluteString
        let now = Date()
        if let idx = entries.firstIndex(where: { $0.url == urlString }) {
            entries[idx].typedCount += 1
            entries[idx].lastTypedAt = now
            entries[idx].lastVisited = now
        } else {
            entries.insert(Entry(id: UUID(), url: urlString, title: nil, lastVisited: now, visitCount: 1, typedCount: 1, lastTypedAt: now), at: 0)
        }
        entries.sort { $0.lastVisited > $1.lastVisited }
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        scheduleSave()
    }

    func suggestions(for query: String, limit: Int = 8) -> [Entry] {
        loadIfNeeded()
        let q = query.lowercased()
        guard !q.isEmpty else { return Array(entries.prefix(limit)) }
        let now = Date()
        return entries.compactMap { entry -> (Entry, Double)? in
            let urlLower = entry.url.lowercased()
            let titleLower = (entry.title ?? "").lowercased()
            let hostLower = URLComponents(string: entry.url)?.host?.lowercased() ?? ""
            guard urlLower.contains(q) || titleLower.contains(q) else { return nil }

            var score = 0.0
            // URL match scoring
            if urlLower == q { score += 1200 }
            else if hostLower.hasPrefix(q) { score += 680 }
            else if urlLower.contains(q) { score += 210 }
            // Title match scoring
            if titleLower.contains(q) { score += 210 }

            let ageHours = max(0, now.timeIntervalSince(entry.lastVisited) / 3600)
            score += max(0, 110 - (ageHours / 3))
            score += min(120, log1p(Double(entry.visitCount)) * 38)
            score += min(190, log1p(Double(entry.typedCount)) * 80)
            return (entry, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    private var saveTask: Task<Void, Never>?
    private func scheduleSave() {
        guard let fileURL else { return }
        saveTask?.cancel()
        let snapshot = entries
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            let dir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Clear Data (S39)

    func clearAll() {
        entries.removeAll()
        scheduleSave()
    }

    private nonisolated static func defaultFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let bundleId = Bundle.main.bundleIdentifier ?? "crispyvibes"
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("browser_history.json")
    }
}
