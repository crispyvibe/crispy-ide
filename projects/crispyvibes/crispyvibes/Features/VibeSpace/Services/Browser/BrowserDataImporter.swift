import Foundation
import SQLite3

/// Imports browser history from Chrome and Safari into BrowserHistoryStore.
@MainActor
struct BrowserDataImporter {

    enum Source: String, CaseIterable {
        case chrome, safari

        var displayName: String {
            switch self {
            case .chrome: return "Google Chrome"
            case .safari: return "Safari"
            }
        }
    }

    struct ImportedEntry {
        let url: String
        let title: String?
        let lastVisited: Date
        let visitCount: Int
    }

    // MARK: - Chrome

    static func importChrome() -> [ImportedEntry] {
        let path = NSString(string: "~/Library/Application Support/Google/Chrome/Default/History").expandingTildeInPath
        return readSQLiteHistory(path: path, query: """
            SELECT u.url, u.title, u.visit_count, u.last_visit_time
            FROM urls u ORDER BY u.last_visit_time DESC LIMIT 5000
        """, timeConverter: chromeTimeToDate)
    }

    // MARK: - Safari

    static func importSafari() -> [ImportedEntry] {
        let path = NSString(string: "~/Library/Safari/History.db").expandingTildeInPath
        return readSQLiteHistory(path: path, query: """
            SELECT hi.url, hv.title, COUNT(hv.id) as visit_count, MAX(hv.visit_time) as last_visit
            FROM history_items hi
            LEFT JOIN history_visits hv ON hi.id = hv.history_item
            GROUP BY hi.url ORDER BY last_visit DESC LIMIT 5000
        """, timeConverter: safariTimeToDate)
    }

    // MARK: - Import into Store

    static func importInto(store: BrowserHistoryStore, from source: Source) -> Int {
        let entries: [ImportedEntry]
        switch source {
        case .chrome: entries = importChrome()
        case .safari: entries = importSafari()
        }
        var imported = 0
        for entry in entries {
            guard let url = URL(string: entry.url) else { continue }
            let existing = store.entries.contains { $0.url == entry.url }
            if !existing {
                store.recordVisit(url: url, title: entry.title)
                imported += 1
            }
        }
        return imported
    }

    // MARK: - SQLite Reader

    private static func readSQLiteHistory(
        path: String,
        query: String,
        timeConverter: (Int64) -> Date
    ) -> [ImportedEntry] {
        // Copy to temp to avoid locking the live database
        let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".db"
        guard (try? FileManager.default.copyItem(atPath: path, toPath: tempPath)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [ImportedEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlCStr = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlCStr)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let visitCount = Int(sqlite3_column_int(stmt, 2))
            let timeValue = sqlite3_column_int64(stmt, 3)
            results.append(ImportedEntry(url: url, title: title, lastVisited: timeConverter(timeValue), visitCount: max(1, visitCount)))
        }
        return results
    }

    // Chrome timestamps: microseconds since 1601-01-01
    private static func chromeTimeToDate(_ value: Int64) -> Date {
        let secondsSince1601 = Double(value) / 1_000_000.0
        let secondsBetween1601And1970: Double = 11_644_473_600
        return Date(timeIntervalSince1970: secondsSince1601 - secondsBetween1601And1970)
    }

    // Safari timestamps: seconds since 2001-01-01 (Core Data epoch)
    private static func safariTimeToDate(_ value: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(value))
    }
}
