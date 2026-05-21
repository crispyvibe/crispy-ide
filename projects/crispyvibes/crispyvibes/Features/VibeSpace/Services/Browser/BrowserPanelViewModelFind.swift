import Foundation
import WebKit

// MARK: - Find in Page

extension BrowserPanelViewModel {
    static let findInPageJS: String = """
    (() => {
      let highlights = [];
      let currentIdx = -1;
      const HIGHLIGHT_CLASS = '__crispyvibes-find-highlight';
      const CURRENT_CLASS = '__crispyvibes-find-current';
      const style = document.createElement('style');
      style.textContent = `.${HIGHLIGHT_CLASS}{background:#ffff00;color:#000}.${CURRENT_CLASS}{background:#ff9632;color:#000}`;
      document.head.appendChild(style);
      function clearHighlights() {
        highlights.forEach(el => { const parent = el.parentNode; parent.replaceChild(document.createTextNode(el.textContent), el); parent.normalize(); });
        highlights = []; currentIdx = -1;
      }
      window.__crispyvibesFindSearch = (query) => {
        clearHighlights();
        if (!query) return JSON.stringify({total:0,current:0});
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        const nodes = []; let node;
        while (node = walker.nextNode()) nodes.push(node);
        const lowerQuery = query.toLowerCase();
        nodes.forEach(textNode => {
          const text = textNode.textContent;
          const lower = text.toLowerCase();
          let idx = lower.indexOf(lowerQuery);
          if (idx === -1) return;
          const frag = document.createDocumentFragment();
          let lastIdx = 0;
          while (idx !== -1) {
            frag.appendChild(document.createTextNode(text.slice(lastIdx, idx)));
            const mark = document.createElement('mark');
            mark.className = HIGHLIGHT_CLASS;
            mark.textContent = text.slice(idx, idx + query.length);
            frag.appendChild(mark);
            highlights.push(mark);
            lastIdx = idx + query.length;
            idx = lower.indexOf(lowerQuery, lastIdx);
          }
          frag.appendChild(document.createTextNode(text.slice(lastIdx)));
          textNode.parentNode.replaceChild(frag, textNode);
        });
        if (highlights.length > 0) { currentIdx = 0; highlights[0].classList.add(CURRENT_CLASS); highlights[0].scrollIntoView({block:'center'}); }
        return JSON.stringify({total:highlights.length, current: currentIdx+1});
      };
      window.__crispyvibesFindNext = () => {
        if (!highlights.length) return JSON.stringify({total:0,current:0});
        highlights[currentIdx]?.classList.remove(CURRENT_CLASS);
        currentIdx = (currentIdx + 1) % highlights.length;
        highlights[currentIdx].classList.add(CURRENT_CLASS);
        highlights[currentIdx].scrollIntoView({block:'center'});
        return JSON.stringify({total:highlights.length, current:currentIdx+1});
      };
      window.__crispyvibesFindPrev = () => {
        if (!highlights.length) return JSON.stringify({total:0,current:0});
        highlights[currentIdx]?.classList.remove(CURRENT_CLASS);
        currentIdx = (currentIdx - 1 + highlights.length) % highlights.length;
        highlights[currentIdx].classList.add(CURRENT_CLASS);
        highlights[currentIdx].scrollIntoView({block:'center'});
        return JSON.stringify({total:highlights.length, current:currentIdx+1});
      };
      window.__crispyvibesFindClear = () => { clearHighlights(); return JSON.stringify({total:0,current:0}); };
    })();
    """

    func startFind() { isFindVisible = true }

    func dismissFind() {
        isFindVisible = false
        findQuery = ""
        findMatchCount = 0
        findCurrentMatch = 0
        webView.evaluateJavaScript("window.__crispyvibesFindClear && window.__crispyvibesFindClear()")
    }

    func findNext() { evaluateFindJS("window.__crispyvibesFindNext && window.__crispyvibesFindNext()") }
    func findPrevious() { evaluateFindJS("window.__crispyvibesFindPrev && window.__crispyvibesFindPrev()") }

    func updateFindQuery(_ query: String) {
        findQuery = query
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        evaluateFindJS("window.__crispyvibesFindSearch && window.__crispyvibesFindSearch('\(escaped)')")
    }

    func evaluateFindJS(_ js: String) {
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self?.findMatchCount = parsed["total"] as? Int ?? 0
            self?.findCurrentMatch = parsed["current"] as? Int ?? 0
        }
    }
}
