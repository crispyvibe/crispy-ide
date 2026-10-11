import Foundation

// MARK: - Session Persistence

extension BrowserPanelViewModel {
    func sessionSnapshot() -> BrowserSessionSnapshot {
        let back: [String]
        let forward: [String]
        if usesRestoredSessionHistory {
            back = restoredBackStack.suffix(Self.logicalHistoryLimit).map(\.absoluteString)
            forward = restoredForwardStack.reversed().prefix(Self.logicalHistoryLimit).map(\.absoluteString)
        } else {
            back = webView.backForwardList.backList
                .suffix(Self.logicalHistoryLimit)
                .map { $0.url.absoluteString }
            forward = webView.backForwardList.forwardList
                .prefix(Self.logicalHistoryLimit)
                .map { $0.url.absoluteString }
        }
        return BrowserSessionSnapshot(
            urlString: currentURL?.absoluteString,
            backHistoryURLStrings: back,
            forwardHistoryURLStrings: forward,
            pageZoom: Double(webView.pageZoom),
            themeMode: themeMode.rawValue
        )
    }

    func restoreSession(_ snapshot: BrowserSessionSnapshot) {
        resetLogicalHistoryTracking()
        usesRestoredSessionHistory = false
        restoredBackStack.removeAll()
        restoredForwardStack.removeAll()

        let back = snapshot.backHistoryURLStrings.compactMap { URL(string: $0) }
        let forward = snapshot.forwardHistoryURLStrings.compactMap { URL(string: $0) }
        if !back.isEmpty || !forward.isEmpty {
            usesRestoredSessionHistory = true
            restoredBackStack = Array(back.suffix(Self.logicalHistoryLimit))
            restoredForwardStack = Array(forward.prefix(Self.logicalHistoryLimit).reversed())
        }
        if snapshot.pageZoom.isFinite {
            restoreZoom(snapshot.pageZoom)
        }
        if let modeRaw = snapshot.themeMode, let mode = BrowserThemeMode(rawValue: modeRaw) {
            setThemeMode(mode)
        }
        if let urlString = snapshot.urlString, urlString != "about:blank", let url = URL(string: urlString) {
            restoreCurrentPage(url)
        }
        if currentURL == nil {
            restoreZoom(Double(webView.pageZoom))
        }
        refreshNavigationState()
    }
}
