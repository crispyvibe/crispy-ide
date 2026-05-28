import Combine
import Foundation
import os
import WebKit

/// F049-v2: comment-surface bridge for browser-window WKWebViews.
///
/// Owns the JavaScript bundle that lives in the page (selection capture,
/// decorations, gutter buttons, scroll-to-anchor) and the script-message
/// plumbing that routes events back to native. Shares the CSS-selector
/// anchoring approach used by HTML preview iframes.
@MainActor
final class BrowserSurfaceBridge: NSObject, ObservableObject, CommentSurfaceBridge, WKScriptMessageHandler {

    /// Bumps when the page navigates / reloads so observers (the panel) can
    /// refresh the active thread list.
    @Published private(set) var geometryTick: Int = 0

    /// Canonical URL of the currently-loaded page (the comment-anchor key).
    /// Updated by `pageDidLoad(url:)` after the navigation delegate observes
    /// a finished load.
    @Published private(set) var canonicalURL: String?

    /// Pending continuation for the next `commentsRichSelectionCaptured`
    /// message. Set by `captureSelectionAnchor`, fulfilled by
    /// `userContentController(_:didReceive:)`.
    private var pendingSelectionContinuation: CheckedContinuation<CommentAnchor?, Never>?
    private var pendingSelectionTask: Task<Void, Never>?

    private weak var webView: WKWebView?

    /// Forwarded by `BrowserPanelViewModel` whenever the user (or JS in the
    /// page) clicks a gutter button, so the panel can open and select.
    var onGutterClick: ((String) -> Void)?
    /// Forwarded by `BrowserPanelViewModel` when the user clicks the
    /// floating "Add Comment" button on a selection.
    var onRequestAdd: ((CommentAnchor) -> Void)?
    /// Posted when the page's `pushState` / `popstate` reports a route
    /// change so the panel can re-query for the new canonical URL.
    var onURLChanged: ((String) -> Void)?

    // MARK: - Setup

    /// Attach the bridge to a WKWebView. Idempotent — re-attaching to the
    /// same webView is a no-op; switching webviews tears the prior link
    /// down first.
    func attach(webView: WKWebView) {
        guard self.webView !== webView else { return }
        detach()
        self.webView = webView
        let controller = webView.configuration.userContentController
        controller.add(self, name: "commentsRichDebug")
        controller.add(self, name: "commentsRichSelectionCaptured")
        controller.add(self, name: "commentsRichRequestAdd")
        controller.add(self, name: "commentsRichGutterClick")
        controller.add(self, name: "commentsRichURLChanged")
    }

    /// Detach observers; called on bridge teardown or webview swap.
    func detach() {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "commentsRichDebug")
        controller.removeScriptMessageHandler(forName: "commentsRichSelectionCaptured")
        controller.removeScriptMessageHandler(forName: "commentsRichRequestAdd")
        controller.removeScriptMessageHandler(forName: "commentsRichGutterClick")
        controller.removeScriptMessageHandler(forName: "commentsRichURLChanged")
        self.webView = nil
    }

    deinit {
        // Native objects guarantee removal on dealloc, but be explicit.
        pendingSelectionTask?.cancel()
    }

    // MARK: - Page lifecycle

    /// Inform the bridge that a navigation has finished. Triggers JS bundle
    /// injection (idempotent inside the page) and stores the canonical URL.
    func pageDidLoad(url: URL?) {
        let canonical = url.map { BrowserCommentURLNormalizer.canonicalize($0) }
        canonicalURL = canonical
        geometryTick &+= 1
        injectBundleIfNeeded()
    }

    private func injectBundleIfNeeded() {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.bundleSource) { _, error in
            if let error {
                os_log(.error, "F049: comments bundle injection failed: %{public}@", (error as NSError).localizedDescription)
            }
        }
    }

    // MARK: - CommentSurfaceBridge

    func captureSelectionAnchor() async -> CommentAnchor? {
        guard let webView else { return nil }
        // Cancel any prior pending capture.
        pendingSelectionContinuation?.resume(returning: nil)
        pendingSelectionContinuation = nil
        pendingSelectionTask?.cancel()

        return await withCheckedContinuation { (continuation: CheckedContinuation<CommentAnchor?, Never>) in
            self.pendingSelectionContinuation = continuation
            // 2-second timeout — if the page can't respond, return nil rather
            // than block the panel forever.
            self.pendingSelectionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                if let pending = self.pendingSelectionContinuation {
                    self.pendingSelectionContinuation = nil
                    pending.resume(returning: nil)
                }
            }
            webView.evaluateJavaScript(
                "if(window.crispyvibesComments){window.crispyvibesComments.captureSelection();}",
                completionHandler: nil
            )
        }
    }

    func scrollAndSelect(anchor: CommentAnchor) async {
        guard let webView else { return }
        let selectorJSON: String
        if let selector = anchor.domSelector,
           let data = try? JSONEncoder().encode(selector),
           let str = String(data: data, encoding: .utf8) {
            selectorJSON = str
        } else {
            selectorJSON = "null"
        }
        let js = "if(window.crispyvibesComments){window.crispyvibesComments.scrollToAnchor(\(selectorJSON));}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func syncDecorations(threads: [CommentThread], selectedThreadID: String?) {
        guard let webView else { return }
        let payload = threads.compactMap { thread -> [String: Any]? in
            guard let selector = thread.root.anchor.domSelector else { return nil }
            return [
                "id": thread.id,
                "selector": selector,
                "status": thread.status.rawValue,
            ]
        }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let selected = selectedThreadID.map { "\"\($0)\"" } ?? "null"
        let js = "if(window.crispyvibesComments){window.crispyvibesComments.setComments(\(json), \(selected));}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let name = message.name
        let body = message.body
        Task { @MainActor [weak self] in
            self?.handleScriptMessage(name: name, body: body)
        }
    }

    private func handleScriptMessage(name: String, body: Any) {
        switch name {
        case "commentsRichDebug":
            guard let info = body as? [String: Any],
                  let event = info["event"] as? String else { return }
            os_log(.debug, "F049: browser comments JS %{public}@ %{public}@", event, String(describing: info))

        case "commentsRichSelectionCaptured":
            let anchor = (body as? [String: Any]).map { CommentAnchor.fromNotificationPayload($0) }
            pendingSelectionTask?.cancel()
            pendingSelectionTask = nil
            if let pending = pendingSelectionContinuation {
                pendingSelectionContinuation = nil
                pending.resume(returning: anchor)
            }

        case "commentsRichRequestAdd":
            guard let info = body as? [String: Any] else { return }
            let anchor = CommentAnchor.fromNotificationPayload(info)
            onRequestAdd?(anchor)

        case "commentsRichGutterClick":
            guard let info = body as? [String: Any], let id = info["threadID"] as? String else { return }
            onGutterClick?(id)

        case "commentsRichURLChanged":
            guard let info = body as? [String: Any], let raw = info["url"] as? String else { return }
            let canonical = BrowserCommentURLNormalizer.canonicalize(string: raw)
            canonicalURL = canonical
            geometryTick &+= 1
            onURLChanged?(canonical)

        default:
            break
        }
    }

    // MARK: - JS bundle

    /// Idempotent JS bundle injected after every navigation. Provides:
    /// - `window.crispyvibesComments.setComments(threads, selectedID)`
    /// - `window.crispyvibesComments.scrollToAnchor(selector)`
    /// - `window.crispyvibesComments.captureSelection()` (one-shot, replies
    ///    via `commentsRichSelectionCaptured`)
    /// - selection-aware floating "Add Comment" button
    /// - SPA route-change observer (pushState/replaceState/popstate)
    static let bundleSource: String = {
        // Marker check + cssPath helper + selection capture + decoration apply.
        return #"""
        (function() {
          if (window.__crispyvibesCommentsBundleInstalled && window.crispyvibesComments) return;

          var STYLES = "[data-crispyvibes-comment]{outline:1px solid rgba(42,144,255,0.55);outline-offset:2px;background:rgba(42,144,255,0.08);transition:background .2s;}"
            + "[data-crispyvibes-comment-status='resolved']{outline-color:rgba(150,150,150,0.5);background:rgba(150,150,150,0.04);}"
            + "[data-crispyvibes-comment-status='stale']{outline:1.5px dashed rgba(255,165,0,0.7);background:transparent;}"
            + ".crispyvibes-comment-selected{background:rgba(42,144,255,0.2)!important;outline-width:2px!important;}"
            + ".crispyvibes-gutter-btn{position:absolute;left:-22px;top:0;width:18px;height:18px;padding:0;margin:0;border:none;background:transparent;cursor:pointer;opacity:0.85;}"
            + ".crispyvibes-gutter-btn::before{content:'';display:block;width:16px;height:16px;background:url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path fill='%232a90ff' d='M3 2h10a2 2 0 012 2v6a2 2 0 01-2 2H8l-3 3v-3H3a2 2 0 01-2-2V4a2 2 0 012-2z'/></svg>\") no-repeat center / contain;}"
            + "#crispyvibes-comment-add-button{position:fixed;z-index:2147483647;display:none;padding:4px 9px;font:12px system-ui,sans-serif;background:rgba(40,40,40,0.92);color:white;border:0.5px solid rgba(255,255,255,0.18);border-radius:6px;box-shadow:0 2px 8px rgba(0,0,0,0.4);cursor:pointer;user-select:none;}";

          function ensureStyles() {
            if (document.getElementById("crispyvibes-comment-styles")) return;
            var host = document.head || document.documentElement;
            if (!host) return;
            var styleEl = document.createElement("style");
            styleEl.id = "crispyvibes-comment-styles";
            styleEl.textContent = STYLES;
            host.appendChild(styleEl);
          }
          ensureStyles();

          function postDebug(event, payload) {
            if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentsRichDebug)) return;
            var info = payload || {};
            info.event = event;
            try { window.webkit.messageHandlers.commentsRichDebug.postMessage(info); } catch (_) {}
          }

          function forceStyle(el, styles) {
            for (var key in styles) {
              if (Object.prototype.hasOwnProperty.call(styles, key)) {
                el.style.setProperty(key, styles[key], "important");
              }
            }
          }

          function styleGutterButton(btn) {
            forceStyle(btn, {
              "all": "initial",
              "position": "absolute",
              "left": "-22px",
              "top": "0",
              "width": "18px",
              "height": "18px",
              "min-width": "18px",
              "min-height": "18px",
              "max-width": "18px",
              "max-height": "18px",
              "padding": "0",
              "margin": "0",
              "border": "0",
              "border-radius": "0",
              "box-shadow": "none",
              "background-color": "transparent",
              "background-image": "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path fill='%232a90ff' d='M3 2h10a2 2 0 012 2v6a2 2 0 01-2 2H8l-3 3v-3H3a2 2 0 01-2-2V4a2 2 0 012-2z'/></svg>\")",
              "background-repeat": "no-repeat",
              "background-position": "center",
              "background-size": "16px 16px",
              "cursor": "pointer",
              "opacity": "0.9",
              "z-index": "2147483647",
              "appearance": "none",
              "-webkit-appearance": "none",
              "font": "12px system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
              "line-height": "18px",
              "color": "transparent",
              "overflow": "hidden",
              "box-sizing": "border-box"
            });
          }

          // cssPath: bounded-depth selector path (≤6), prefer #id, fall back to nth-of-type.
          function cssPath(el) {
            var parts = [];
            while (el && el !== document.body && el.nodeType === 1 && parts.length < 6) {
              var s = el.tagName.toLowerCase();
              if (el.id) { parts.unshift("#" + cssEscape(el.id)); break; }
              var p = el.parentElement;
              if (p) {
                var sibs = Array.prototype.filter.call(p.children, function(c) { return c.tagName === el.tagName; });
                if (sibs.length > 1) s += ":nth-of-type(" + (sibs.indexOf(el) + 1) + ")";
              }
              parts.unshift(s);
              el = p;
            }
            return parts.join(" > ") || "body";
          }

          // Minimal CSS.escape for ids that contain dots/colons.
          function cssEscape(s) { return (window.CSS && window.CSS.escape) ? window.CSS.escape(s) : String(s).replace(/[^a-zA-Z0-9_-]/g, "\\$&"); }

          // Walk up from a text node to its containing block-ish element.
          function blockAncestor(node) {
            var el = node && node.nodeType === 1 ? node : (node && node.parentElement);
            while (el && el !== document.body) {
              var d = window.getComputedStyle(el).display;
              if (d === "block" || d === "list-item" || d === "table" || d === "table-cell" || d === "flex" || d === "grid") return el;
              el = el.parentElement;
            }
            return el || document.body;
          }

          function sha256Hex(str) {
            // Lightweight: just take a stable djb2 hash hex-encoded — full SHA
            // would require subtleCrypto async. The Swift side recomputes
            // SHA-256 from the original anchorText for exact verification;
            // this fingerprint is just a tie-break heuristic for the JS side.
            var h = 5381;
            for (var i = 0; i < str.length; i++) h = ((h << 5) + h) + str.charCodeAt(i);
            return (h >>> 0).toString(16);
          }

          function captureSelectionAnchor() {
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
            var range = sel.getRangeAt(0);
            var block = blockAncestor(range.commonAncestorContainer);
            if (!block) return null;
            var selector = cssPath(block);
            var blockRange = document.createRange();
            blockRange.selectNodeContents(block);
            try { blockRange.setEnd(range.startContainer, range.startOffset); } catch (_) { return null; }
            var offset = blockRange.toString().length;
            var anchorText = sel.toString().slice(0, 4096);
            var length = anchorText.length;
            var fingerprint = sha256Hex((block.textContent || "").slice(0, 4096));
            return {
              startLine: 1, startColumn: 1, endLine: 1, endColumn: 1,
              anchorText: anchorText, leadingContext: "", trailingContext: "",
              domSelector: selector, domTextOffset: offset, domTextLength: length,
              domFingerprint: fingerprint,
            };
          }

          function locateAnchorElement(selector) {
            if (!selector) return null;
            try { return document.querySelector(selector); }
            catch (_) { return null; }
          }

          window.crispyvibesComments = {
            setComments: function(threads, selectedID) {
              ensureStyles();
              // Clear previous decorations + gutter buttons.
              var prev = document.querySelectorAll("[data-crispyvibes-comment]");
              for (var i = 0; i < prev.length; i++) {
                prev[i].removeAttribute("data-crispyvibes-comment");
                prev[i].removeAttribute("data-crispyvibes-comment-status");
                prev[i].classList.remove("crispyvibes-comment-selected");
              }
              var oldBtns = document.querySelectorAll(".crispyvibes-gutter-btn");
              for (var b = 0; b < oldBtns.length; b++) oldBtns[b].remove();

              if (!Array.isArray(threads)) return;
              for (var t = 0; t < threads.length; t++) {
                var th = threads[t];
                var el = locateAnchorElement(th.selector);
                if (!el) continue;
                el.setAttribute("data-crispyvibes-comment", th.id || "");
                el.setAttribute("data-crispyvibes-comment-status", th.status || "active");
                if (selectedID && th.id === selectedID) el.classList.add("crispyvibes-comment-selected");

                // Make the host position-relative so the absolutely-positioned
                // gutter button sits next to it.
                if (window.getComputedStyle(el).position === "static") el.style.position = "relative";

                var btn = document.createElement("button");
                btn.type = "button";
                btn.className = "crispyvibes-gutter-btn";
                btn.setAttribute("data-thread-id", th.id || "");
                btn.title = "Comment thread";
                btn.setAttribute("aria-label", "Comment thread");
                styleGutterButton(btn);
                btn.addEventListener("mousedown", function(e) { e.preventDefault(); e.stopPropagation(); });
                btn.addEventListener("click", function(e) {
                  e.preventDefault(); e.stopPropagation();
                  var threadID = this.getAttribute("data-thread-id");
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentsRichGutterClick) {
                    window.webkit.messageHandlers.commentsRichGutterClick.postMessage({ threadID: threadID });
                  }
                });
                el.appendChild(btn);
              }
            },
            scrollToAnchor: function(selector) {
              var el = locateAnchorElement(selector);
              if (!el) return;
              el.scrollIntoView({ behavior: "smooth", block: "center" });
              el.classList.add("crispyvibes-comment-selected");
              setTimeout(function() { el.classList.remove("crispyvibes-comment-selected"); }, 1200);
            },
            captureSelection: function() {
              var anchor = captureSelectionAnchor();
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentsRichSelectionCaptured) {
                window.webkit.messageHandlers.commentsRichSelectionCaptured.postMessage(anchor || {});
              }
            },
          };

          // Floating "Add Comment" button on selection.
          var addBtn = null;
          var lastAnchor = null;
          function ensureAddButton() {
            if (addBtn && document.body && addBtn.parentNode !== document.body) {
              document.body.appendChild(addBtn);
              return addBtn;
            }
            if (addBtn) return addBtn;
            if (!document.body) return null;
            addBtn = document.createElement("button");
            addBtn.id = "crispyvibes-comment-add-button";
            addBtn.type = "button";
            addBtn.textContent = "💬 Add Comment";
            forceStyle(addBtn, {
              "all": "initial",
              "position": "fixed",
              "z-index": "2147483647",
              "display": "none",
              "padding": "4px 9px",
              "font": "12px system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
              "line-height": "16px",
              "background": "rgba(40,40,40,0.92)",
              "color": "white",
              "border": "0.5px solid rgba(255,255,255,0.18)",
              "border-radius": "6px",
              "box-shadow": "0 2px 8px rgba(0,0,0,0.4)",
              "cursor": "pointer",
              "user-select": "none",
              "-webkit-user-select": "none",
              "white-space": "nowrap"
            });
            addBtn.addEventListener("mousedown", function(e) { e.preventDefault(); });
            addBtn.addEventListener("click", function() {
              if (!lastAnchor) return;
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentsRichRequestAdd) {
                window.webkit.messageHandlers.commentsRichRequestAdd.postMessage(lastAnchor);
              }
              addBtn.style.display = "none";
            });
            document.body.appendChild(addBtn);
            return addBtn;
          }
          ensureAddButton();
          function repositionAddButton() {
            var button = ensureAddButton();
            if (!button) return;
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
              button.style.display = "none";
              lastAnchor = null;
              return;
            }
            var anchor = captureSelectionAnchor();
            if (!anchor) {
              button.style.display = "none";
              lastAnchor = null;
              return;
            }
            lastAnchor = anchor;
            var rect = sel.getRangeAt(0).getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) { button.style.display = "none"; return; }
            var top = Math.max(8, rect.top - 30);
            var left = Math.min(window.innerWidth - 130, Math.max(8, rect.left));
            button.style.setProperty("top", top + "px", "important");
            button.style.setProperty("left", left + "px", "important");
            button.style.setProperty("display", "block", "important");
            postDebug("selection-ready", {
              selector: anchor.domSelector || "",
              textLength: anchor.anchorText ? anchor.anchorText.length : 0,
              top: top,
              left: left
            });
          }
          function scheduleRepositionAddButton() {
            setTimeout(repositionAddButton, 0);
          }
          document.addEventListener("selectionchange", scheduleRepositionAddButton);
          document.addEventListener("mouseup", scheduleRepositionAddButton, true);
          document.addEventListener("keyup", scheduleRepositionAddButton, true);
          document.addEventListener("pointerup", scheduleRepositionAddButton, true);
          document.addEventListener("scroll", function() {
            if (addBtn && addBtn.style.display === "block") repositionAddButton();
          }, true);

          // SPA route observer.
          function postURLChange() {
            // Re-append the floating button if the SPA replaced document.body
            // (React, Vue full-page transitions, etc.). Without this, the
            // button disappears after route changes on SPAs.
            ensureStyles();
            ensureAddButton();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentsRichURLChanged) {
              window.webkit.messageHandlers.commentsRichURLChanged.postMessage({ url: window.location.href });
            }
          }
          var origPushState = history.pushState;
          var origReplaceState = history.replaceState;
          history.pushState = function() { var r = origPushState.apply(this, arguments); postURLChange(); return r; };
          history.replaceState = function() { var r = origReplaceState.apply(this, arguments); postURLChange(); return r; };
          window.addEventListener("popstate", postURLChange);
          window.__crispyvibesCommentsBundleInstalled = true;
          postDebug("installed", { url: window.location.href });
        })();
        """#
    }()
}
