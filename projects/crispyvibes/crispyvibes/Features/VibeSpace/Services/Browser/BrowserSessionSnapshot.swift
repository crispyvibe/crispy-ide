import Foundation

struct BrowserSessionSnapshot: Codable, Sendable, Equatable {
    var urlString: String?
    var backHistoryURLStrings: [String]
    var forwardHistoryURLStrings: [String]
    var pageZoom: Double
    var themeMode: String?

    init(
        urlString: String? = nil,
        backHistoryURLStrings: [String] = [],
        forwardHistoryURLStrings: [String] = [],
        pageZoom: Double = 1.0,
        themeMode: String? = nil
    ) {
        self.urlString = urlString
        self.backHistoryURLStrings = backHistoryURLStrings
        self.forwardHistoryURLStrings = forwardHistoryURLStrings
        self.pageZoom = pageZoom
        self.themeMode = themeMode
    }
}
