import Foundation
import WebKit

// MARK: - Console Capture (S46)

extension BrowserPanelViewModel {
    static let consoleCapureJS: String = """
    (() => {
      window.__crispyvibesConsoleLog = [];
      ['log','warn','error','info','debug'].forEach(level => {
        const orig = console[level];
        console[level] = function() {
          const text = Array.from(arguments).map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ');
          if (window.__crispyvibesConsoleLog.length < 512) {
            window.__crispyvibesConsoleLog.push({level, text, ts: Date.now()});
          }
          orig.apply(console, arguments);
        };
      });
    })();
    """

    func flushConsoleMessages() {
        webView.evaluateJavaScript("""
        (() => {
            const msgs = window.__crispyvibesConsoleLog || [];
            window.__crispyvibesConsoleLog = [];
            return JSON.stringify(msgs);
        })();
        """) { [weak self] result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let newMessages = entries.compactMap { entry -> (level: String, text: String)? in
                guard let level = entry["level"] as? String,
                      let text = entry["text"] as? String else { return nil }
                return (level: level, text: text)
            }
            self?.consoleMessages.append(contentsOf: newMessages)
        }
    }
}

// MARK: - Download Progress (S45)

extension BrowserPanelViewModel {
    func setDownloading(_ value: Bool) {
        isDownloading = value
    }
}

// MARK: - Host Allowlist / External Patterns (S54)

extension BrowserPanelViewModel {
    func shouldOpenExternally(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let urlString = url.absoluteString
        return externalOpenPatterns.contains { pattern in
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                return regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil
            }
            return host.contains(pattern.lowercased())
        }
    }
}
