import Foundation

// MARK: - Session Persistence

extension BrowserPanelViewModel {
    func sessionSnapshot() -> BrowserSessionSnapshot {
        let back: [String]
        let forward: [String]
        if usesRestoredSessionHistory {
            back = restoredBackStack.map(\.absoluteString)
            forward = restoredForwardStack.reversed().map(\.absoluteString)
        } else {
            back = webView.backForwardList.backList.compactMap { $0.url.absoluteString }
            forward = webView.backForwardList.forwardList.compactMap { $0.url.absoluteString }
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
        usesRestoredSessionHistory = false
        restoredBackStack.removeAll()
        restoredForwardStack.removeAll()

        let back = snapshot.backHistoryURLStrings.compactMap { URL(string: $0) }
        let forward = snapshot.forwardHistoryURLStrings.compactMap { URL(string: $0) }
        if !back.isEmpty || !forward.isEmpty {
            usesRestoredSessionHistory = true
            restoredBackStack = back
            restoredForwardStack = Array(forward.reversed())
        }
        if snapshot.pageZoom.isFinite {
            restoreZoom(snapshot.pageZoom)
        }
        if let modeRaw = snapshot.themeMode, let mode = BrowserThemeMode(rawValue: modeRaw) {
            setThemeMode(mode)
        }
        if let urlString = snapshot.urlString, urlString != "about:blank", let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
            addressBarText = urlString
            currentURL = url
        }
        if currentURL == nil {
            restoreZoom(Double(webView.pageZoom))
        }
        refreshNavigationState()
    }
}
