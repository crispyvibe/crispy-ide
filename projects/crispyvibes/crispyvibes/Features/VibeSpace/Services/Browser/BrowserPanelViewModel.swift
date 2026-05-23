import Foundation
import Combine
import WebKit
import AppKit

@MainActor
final class BrowserPanelViewModel: ObservableObject {
    private enum Constants {
        static let minimumZoomScale = 0.25
        static let maximumZoomScale = 5.0
    }

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"

    enum SearchEngine: String, CaseIterable, Codable {
        case google, duckDuckGo, bing

        var searchURLTemplate: String {
            switch self {
            case .google: return "https://www.google.com/search?q=%s"
            case .duckDuckGo: return "https://duckduckgo.com/?q=%s"
            case .bing: return "https://www.bing.com/search?q=%s"
            }
        }

        func searchURL(for query: String) -> URL? {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return URL(string: searchURLTemplate.replacingOccurrences(of: "%s", with: encoded))
        }
    }

    let id: UUID
    /// F012-R17: project ownership.
    /// Each browser instance is owned by exactly one project, identified by
    /// normalized root path. Set at creation time; never reassigned during a
    /// browser's lifetime. Browsers without an owner (preview-only / pre-restore
    /// state) carry `nil`. `DockedBrowserCoordinator.closeBrowsers(forProjectPath:)`
    /// uses this field to enumerate and tear down all browsers belonging to a
    /// project being removed or parked (F012-R18).
    let projectPath: String?
    private(set) var usesEphemeralDataStore: Bool
    private(set) var webView: CrispyVibesBrowserWebView

    @Published var currentURL: URL?
    @Published private(set) var pageTitle: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published private(set) var estimatedProgress: Double = 0.0
    @Published var addressBarText: String = ""
    @Published var faviconData: Data?
    @Published var zoomScale: Double = 1.0
    @Published var searchEngine: SearchEngine = .google
    @Published private(set) var hasOnlySecureContent: Bool = false
    @Published private(set) var navigationError: NSError?

    // Find in Page (accessed from BrowserPanelViewModelFind)
    @Published var isFindVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var findMatchCount: Int = 0
    @Published var findCurrentMatch: Int = 0

    // Theme Mode (accessed from BrowserPanelViewModelTheme)
    enum BrowserThemeMode: String, CaseIterable { case system, light, dark }
    @Published var themeMode: BrowserThemeMode = .system

    // Insecure HTTP
    private static let defaultInsecureHTTPAllowlist: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
    @Published var customInsecureHTTPAllowlist: Set<String> = []
    @Published var searchSuggestionsEnabled: Bool = true
    @Published var isDownloading: Bool = false
    @Published var consoleMessages: [(level: String, text: String)] = []
    @Published var externalOpenPatterns: [String] = []

    private var webViewObservers: [NSKeyValueObservation] = []
    private var navigationDelegate: BrowserNavigationDelegate?
    private var uiDelegate: BrowserUIDelegate?
    let hostOwnershipCoordinator = BrowserHostOwnershipCoordinator()

    // Session history (accessed from BrowserPanelViewModelSession)
    var usesRestoredSessionHistory = false
    var restoredBackStack: [URL] = []
    var restoredForwardStack: [URL] = []

    var onOpenNewBrowser: ((URL) -> Void)?
    var onSessionStateChanged: (() -> Void)?
    var historyStore: BrowserHistoryStore?

    init(id: UUID = UUID(), initialURL: URL? = nil, usesEphemeralDataStore: Bool = false, projectPath: String? = nil) {
        self.id = id
        self.projectPath = projectPath
        self.usesEphemeralDataStore = usesEphemeralDataStore
        let webView = Self.makeWebView(usesEphemeralDataStore: usesEphemeralDataStore)
        self.webView = webView

        let navDelegate = BrowserNavigationDelegate()
        navDelegate.onDidFinish = { [weak self] url, title in
            guard url?.absoluteString != "about:blank" else { return }
            self?.currentURL = url
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self?.pageTitle = title
            }
            (self?.historyStore)?.recordVisit(url: url, title: title)
            self?.refreshFavicon()
            self?.onSessionStateChanged?()
        }
        navDelegate.onWebContentProcessTerminated = { [weak self] terminatedWebView in
            self?.replaceWebViewAfterTermination(terminatedWebView)
        }
        navDelegate.onOpenInNewTab = { [weak self] url in
            self?.onOpenNewBrowser?(url)
        }
        navDelegate.shouldBlockInsecureHTTP = { [weak self] url in
            self?.shouldBlockInsecureHTTP(url) ?? false
        }
        navDelegate.onInsecureHTTPBlocked = { [weak self] url in
            self?.presentInsecureHTTPAlert(for: url)
        }
        navDelegate.onNavigationFailed = { [weak self] url, error in
            self?.handleNavigationFailure(url: url, error: error)
        }
        navDelegate.onExternalScheme = { url in
            NSWorkspace.shared.open(url)
        }
        navDelegate.onExternalPattern = { [weak self] url in
            guard let self, self.shouldOpenExternally(url) else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
        navDelegate.downloadDelegate = BrowserDownloadDelegate()
        navDelegate.downloadDelegate?.onDownloadStarted = { [weak self] in self?.setDownloading(true) }
        navDelegate.downloadDelegate?.onDownloadEnded = { [weak self] in self?.setDownloading(false) }
        self.navigationDelegate = navDelegate
        webView.navigationDelegate = navDelegate

        let browserUIDelegate = BrowserUIDelegate()
        browserUIDelegate.onOpenInNewTab = { [weak self] url in
            self?.onOpenNewBrowser?(url)
        }
        self.uiDelegate = browserUIDelegate
        webView.uiDelegate = browserUIDelegate

        webView.onOpenInNewTab = { [weak self] url in
            self?.onOpenNewBrowser?(url)
        }

        setupObservers()

        if let url = initialURL {
            navigate(to: url)
        }
    }

    static func makeWebView(usesEphemeralDataStore: Bool = false) -> CrispyVibesBrowserWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = usesEphemeralDataStore ? .nonPersistent() : .default()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let findScript = WKUserScript(source: findInPageJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(findScript)

        let consoleScript = WKUserScript(source: consoleCapureJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(consoleScript)

        let webView = CrispyVibesBrowserWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.customUserAgent = safariUserAgent
        return webView
    }

    private func setupObservers() {
        webViewObservers.append(webView.observe(\.url) { [weak self] wv, _ in
            Task { @MainActor in
                guard wv.url?.absoluteString != "about:blank" else { return }
                self?.currentURL = wv.url
            }
        })
        webViewObservers.append(webView.observe(\.title) { [weak self] wv, _ in
            Task { @MainActor in
                let t = (wv.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { self?.pageTitle = t }
            }
        })
        webViewObservers.append(webView.observe(\.isLoading) { [weak self] wv, _ in
            Task { @MainActor in self?.isLoading = wv.isLoading }
        })
        webViewObservers.append(webView.observe(\.canGoBack) { [weak self] _, _ in
            Task { @MainActor in self?.refreshNavigationState() }
        })
        webViewObservers.append(webView.observe(\.canGoForward) { [weak self] _, _ in
            Task { @MainActor in self?.refreshNavigationState() }
        })
        webViewObservers.append(webView.observe(\.estimatedProgress) { [weak self] wv, _ in
            Task { @MainActor in self?.estimatedProgress = wv.estimatedProgress }
        })
        webViewObservers.append(webView.observe(\.hasOnlySecureContent) { [weak self] wv, _ in
            Task { @MainActor in self?.hasOnlySecureContent = wv.hasOnlySecureContent }
        })
    }

    func refreshNavigationState() {
        if usesRestoredSessionHistory {
            canGoBack = !restoredBackStack.isEmpty
            canGoForward = !restoredForwardStack.isEmpty
        } else {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        }
    }

    // MARK: - Navigation

    func navigate(to url: URL) {
        if shouldBlockInsecureHTTP(url) {
            presentInsecureHTTPAlert(for: url)
            return
        }
        load(url, abandoningRestoredHistory: true)
    }

    func navigateSmart(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = resolveNavigableURL(trimmed) {
            (historyStore)?.recordTypedNavigation(url: url)
            navigate(to: url)
        } else {
            if let searchURL = searchEngine.searchURL(for: trimmed) {
                navigate(to: searchURL)
            }
        }
    }

    private func resolveNavigableURL(_ input: String) -> URL? {
        let lower = input.lowercased()

        // Explicit schemes
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url
        }

        // Localhost variants → http
        if lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") ||
           lower.hasPrefix("[::1]") || lower.hasPrefix("0.0.0.0") {
            return URL(string: "http://\(input)")
        }

        // Contains dot with no spaces → likely a URL
        if input.contains(".") && !input.contains(" ") {
            return URL(string: "https://\(input)")
        }

        // Contains colon (port) or slash (path) with no spaces → likely a URL
        if (input.contains(":") || input.contains("/")) && !input.contains(" ") {
            return URL(string: "https://\(input)")
        }

        return nil
    }

    func goBack() {
        guard canGoBack else { return }
        if usesRestoredSessionHistory, let target = restoredBackStack.popLast() {
            if let current = currentURL { restoredForwardStack.append(current) }
            refreshNavigationState()
            loadWithoutAbandoningHistory(target)
            return
        }
        webView.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        if usesRestoredSessionHistory, let target = restoredForwardStack.popLast() {
            if let current = currentURL { restoredBackStack.append(current) }
            refreshNavigationState()
            loadWithoutAbandoningHistory(target)
            return
        }
        webView.goForward()
    }

    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func zoomOut() {
        setZoom(zoomScale - 0.1)
    }

    func zoomIn() {
        setZoom(zoomScale + 0.1)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    var zoomPercentageLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private func setZoom(_ zoom: Double) {
        let clampedZoom = clampedZoomScale(from: zoom)
        webView.pageZoom = CGFloat(clampedZoom)
        zoomScale = clampedZoom
        onSessionStateChanged?()
    }

    func restoreZoom(_ zoom: Double) {
        let clampedZoom = clampedZoomScale(from: zoom)
        webView.pageZoom = CGFloat(clampedZoom)
        zoomScale = clampedZoom
    }

    private func loadWithoutAbandoningHistory(_ url: URL) {
        load(url, abandoningRestoredHistory: false)
    }

    // MARK: - Insecure HTTP

    private func shouldBlockInsecureHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        guard let host = url.host?.lowercased() else { return true }
        return !Self.defaultInsecureHTTPAllowlist.contains(host) && !customInsecureHTTPAllowlist.contains(where: { pattern in
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1))
                return host.hasSuffix(suffix) || host == String(pattern.dropFirst(2))
            }
            return host == pattern
        })
    }

    private func presentInsecureHTTPAlert(for url: URL) {
        let host = url.host ?? url.absoluteString
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppStrings.Browser.insecureConnectionTitle
        alert.informativeText = "\(host) uses plain HTTP. Open in default browser, proceed in Crispy, or cancel."
        alert.addButton(withTitle: AppStrings.Browser.openInDefaultBrowser)
        alert.addButton(withTitle: AppStrings.Browser.proceed)
        alert.addButton(withTitle: AppStrings.Common.cancel)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            load(url, abandoningRestoredHistory: true)
        default:
            break
        }
    }

    private func load(_ url: URL, abandoningRestoredHistory: Bool) {
        if abandoningRestoredHistory {
            abandonRestoredHistory()
        }
        navigationError = nil
        webView.customUserAgent = Self.safariUserAgent
        webView.load(URLRequest(url: url))
        addressBarText = url.absoluteString
    }

    private func clampedZoomScale(from zoom: Double) -> Double {
        max(Constants.minimumZoomScale, min(Constants.maximumZoomScale, zoom))
    }

    func abandonRestoredHistory() {
        guard usesRestoredSessionHistory else { return }
        usesRestoredSessionHistory = false
        restoredBackStack.removeAll()
        restoredForwardStack.removeAll()
    }

    // MARK: - Display

    var displayTitle: String {
        if !pageTitle.isEmpty { return pageTitle }
        if let url = currentURL { return ContentViewerTab.browserTitle(for: url) }
        return AppStrings.Browser.newTab
    }

    // MARK: - Navigation Failure

    private func handleNavigationFailure(url: URL?, error: NSError) {
        isLoading = false
        navigationError = error
        pageTitle = AppStrings.Browser.failedToLoad
    }

    // MARK: - Element Picker

    @Published var isElementPickerActive: Bool = false

    func toggleElementPicker() {
        if isElementPickerActive {
            deactivateElementPicker()
        } else {
            activateElementPicker()
        }
    }

    private func activateElementPicker() {
        isElementPickerActive = true
        webView.evaluateJavaScript(Self.elementPickerJS) { [weak self] _, _ in
            // JS calls cleanup() on click or escape — poll for deactivation
            self?.pollPickerDeactivation()
        }
    }

    func deactivateElementPicker() {
        isElementPickerActive = false
        webView.evaluateJavaScript("window.__crispyvibesPickerDeactivate && window.__crispyvibesPickerDeactivate();")
    }

    private func pollPickerDeactivation() {
        Task { @MainActor [weak self] in
            while self?.isElementPickerActive == true {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                let result = try? await self.webView.evaluateJavaScript("window.__crispyvibesPickerActive === true")
                if result as? Bool != true {
                    self.isElementPickerActive = false
                }
            }
        }
    }

    private static let elementPickerJS = """
    (() => {
      if (window.__crispyvibesPickerActive) return;
      window.__crispyvibesPickerActive = true;
      const ov = document.createElement('div');
      Object.assign(ov.style, {
        position:'fixed', pointerEvents:'none', zIndex:'2147483647',
        border:'2px solid #0A84FF', background:'rgba(10,132,255,0.08)',
        borderRadius:'3px', transition:'all 0.05s ease', display:'none'
      });
      const label = document.createElement('div');
      Object.assign(label.style, {
        position:'fixed', zIndex:'2147483647', pointerEvents:'none',
        background:'#1a1a1a', color:'#fff', fontSize:'11px', fontFamily:'SF Mono,monospace',
        padding:'2px 6px', borderRadius:'3px', maxWidth:'400px', overflow:'hidden',
        whiteSpace:'nowrap', textOverflow:'ellipsis', display:'none'
      });
      document.body.appendChild(ov);
      document.body.appendChild(label);
      let lastEl = null;

      function cssPath(el) {
        const parts = [];
        while (el && el !== document.body && parts.length < 6) {
          let s = el.tagName.toLowerCase();
          if (el.id) { parts.unshift('#' + el.id); break; }
          const p = el.parentElement;
          if (p) {
            const sibs = Array.from(p.children).filter(c => c.tagName === el.tagName);
            if (sibs.length > 1) s += ':nth-of-type(' + (sibs.indexOf(el) + 1) + ')';
          }
          parts.unshift(s);
          el = p;
        }
        return parts.join(' > ') || 'body';
      }

      function reactInfo(el) {
        for (const key of Object.keys(el)) {
          if (key.startsWith('__reactFiber$') || key.startsWith('__reactInternalInstance$')) {
            let fiber = el[key];
            while (fiber) {
              if (fiber.type && typeof fiber.type === 'function') {
                const name = fiber.type.displayName || fiber.type.name || '';
                if (name) {
                  let file = '';
                  try { file = fiber._debugSource?.fileName || ''; } catch(_) {}
                  return { component: name, file };
                }
              }
              fiber = fiber.return;
            }
          }
        }
        return null;
      }

      function onMove(e) {
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (!el || el === ov || el === label || el === lastEl) return;
        lastEl = el;
        const r = el.getBoundingClientRect();
        Object.assign(ov.style, {
          display:'block', top:r.top+'px', left:r.left+'px',
          width:r.width+'px', height:r.height+'px'
        });
        const tag = el.tagName.toLowerCase();
        const id = el.id ? '#'+el.id : '';
        const cls = el.className && typeof el.className === 'string' ? '.'+el.className.trim().split(/\\s+/).join('.') : '';
        label.textContent = tag + id + cls;
        label.style.display = 'block';
        label.style.top = Math.max(0, r.top - 24) + 'px';
        label.style.left = r.left + 'px';
      }

      function onClick(e) {
        e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (el && el !== ov && el !== label) {
          const sel = cssPath(el);
          const tag = el.tagName.toLowerCase();
          const id = el.id ? '#'+el.id : '';
          const cls = el.className && typeof el.className === 'string' ? '.'+el.className.trim().split(/\\s+/).join('.') : '';
          const text = (el.innerText || '').slice(0, 200).trim();
          const html = el.outerHTML.slice(0, 500);
          let ctx = 'Selector: ' + sel + '\\n';
          ctx += 'Tag: ' + tag + id + cls + '\\n';
          if (text) ctx += 'Text: ' + text + '\\n';
          const ri = reactInfo(el);
          if (ri) {
            ctx += 'Component: ' + ri.component + '\\n';
            if (ri.file) ctx += 'File: ' + ri.file + '\\n';
          }
          ctx += 'HTML: ' + html;
          navigator.clipboard.writeText(ctx).catch(() => {});
        }
        cleanup();
        return false;
      }

      function onKey(e) { if (e.key === 'Escape') { cleanup(); } }

      function cleanup() {
        window.__crispyvibesPickerActive = false;
        document.removeEventListener('mousemove', onMove, true);
        document.removeEventListener('click', onClick, true);
        document.removeEventListener('keydown', onKey, true);
        ov.remove(); label.remove();
      }
      window.__crispyvibesPickerDeactivate = cleanup;

      document.addEventListener('mousemove', onMove, true);
      document.addEventListener('click', onClick, true);
      document.addEventListener('keydown', onKey, true);
    })();
    """

    // MARK: - Focus

    func openInSystemBrowser() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.open(url)
    }

    func clearBrowsingData() {
        historyStore?.clearAll()
        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }

    func takeScreenshot() {
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, _ in
            guard let image else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "screenshot.png"
            panel.begin { result in
                guard result == .OK, let url = panel.url,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: url)
            }
        }
    }

    func focus() {
        guard let window = webView.window, !webView.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(webView)
    }

    func unfocus() {
        guard let window = webView.window else { return }
        if window.firstResponder === webView || isInResponderChain(window.firstResponder) {
            window.makeFirstResponder(nil)
        }
    }

    private func isInResponderChain(_ start: NSResponder?) -> Bool {
        var r = start
        var hops = 0
        while let cur = r, hops < 64 {
            if cur === webView { return true }
            r = cur.nextResponder
            hops += 1
        }
        return false
    }

    // MARK: - Process Recovery

    private func replaceWebViewAfterTermination(_ terminatedWebView: WKWebView) {
        guard terminatedWebView === webView else { return }
        let snapshot = sessionSnapshot()
        webViewObservers.removeAll()
        terminatedWebView.stopLoading()
        terminatedWebView.navigationDelegate = nil
        terminatedWebView.uiDelegate = nil
        let replacement = Self.makeWebView(usesEphemeralDataStore: usesEphemeralDataStore)
        webView = replacement
        replacement.navigationDelegate = navigationDelegate
        replacement.uiDelegate = uiDelegate
        replacement.onOpenInNewTab = { [weak self] url in
            self?.onOpenNewBrowser?(url)
        }
        setupObservers()
        restoreSession(snapshot)
    }

    // MARK: - Favicon

    func refreshFavicon() {
        let js = """
        (() => {
            const links = document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"]');
            if (links.length > 0) return links[links.length - 1].href;
            return '';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let href = result as? String, !href.isEmpty,
                  let url = URL(string: href) else {
                guard let pageURL = self?.currentURL,
                      let faviconURL = URL(string: "/favicon.ico", relativeTo: pageURL) else { return }
                self?.fetchFaviconData(from: faviconURL)
                return
            }
            self?.fetchFaviconData(from: url)
        }
    }

    private func fetchFaviconData(from url: URL) {
        Task { @MainActor [weak self] in
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.0
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  NSImage(data: data) != nil else {
                self?.faviconData = nil
                return
            }
            self?.faviconData = data
        }
    }

    deinit {
        MainActor.assumeIsolated {
            webViewObservers.removeAll()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
    }
}
