import Foundation
import WebKit
import AppKit
import PDFKit

// MARK: - Navigation Commands

extension BrowserAgentAPI {
    func navigate(_ params: [String: Any]) -> Result {
        guard let url = (params["url"] as? String).flatMap(URL.init(string:)) else {
            return .err(code: "invalid_params", message: "Missing url")
        }
        viewModel?.navigate(to: url)
        return .ok(["url": url.absoluteString])
    }

    func urlGet() -> Result {
        .ok(["url": viewModel?.currentURL?.absoluteString ?? ""])
    }

    func getTitle() -> Result {
        .ok(["title": viewModel?.displayTitle ?? ""])
    }

    func simpleAction(_ action: (BrowserPanelViewModel) -> Void) -> Result {
        guard let vm = viewModel else { return .err(code: "unavailable", message: "No browser") }
        action(vm)
        return .ok([:])
    }
}

// MARK: - Selector Action JS Templates

extension BrowserAgentAPI {
    static let clickJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    el.scrollIntoView({ block: 'nearest' });
    el.click();
    return { ok: true };
    """

    static let dblclickJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    el.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, detail: 2 }));
    return { ok: true };
    """

    static let hoverJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
    el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: false }));
    return { ok: true };
    """

    static let focusJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    el.focus();
    return { ok: true };
    """

    static let checkJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    if (!el.checked) { el.click(); }
    return { ok: true };
    """

    static let uncheckJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    if (el.checked) { el.click(); }
    return { ok: true };
    """

    static let scrollIntoViewJS = """
    const el = document.querySelector(__SEL__);
    if (!el) return { ok: false, error: 'not_found' };
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    return { ok: true };
    """

    func selectorAction(_ params: [String: Any], js: String) async -> Result {
        let result = await runSelectorJS(params, js: js)
        switch result {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            if let dict = val as? [String: Any], dict["ok"] as? Bool == false {
                return .err(code: dict["error"] as? String ?? "not_found", message: "Element not found")
            }
            return .ok([:])
        }
    }
}

// MARK: - Fill, Type, Press, Select, Scroll

extension BrowserAgentAPI {
    func fill(_ params: [String: Any]) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        guard let text = params["text"] as? String ?? params["value"] as? String else { return .err(code: "invalid_params", message: "Missing text") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el) return { ok: false, error: 'not_found' };
        el.focus();
        const v = String(\(jsonLiteral(text)));
        let ns = null;
        for (let p = Object.getPrototypeOf(el); p; p = Object.getPrototypeOf(p)) {
            const d = Object.getOwnPropertyDescriptor(p, 'value');
            if (d && d.set) { ns = d.set; break; }
        }
        if (ns) { ns.call(el, v); } else { el.value = v; }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return { ok: true };
        """
        let result = await runJS(js)
        switch result {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            if let dict = val as? [String: Any], dict["ok"] as? Bool == false {
                return .err(code: "not_found", message: "Element not found")
            }
            return .ok([:])
        }
    }

    func typeText(_ params: [String: Any]) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        guard let text = params["text"] as? String else { return .err(code: "invalid_params", message: "Missing text") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el) return { ok: false, error: 'not_found' };
        el.focus();
        for (const ch of \(jsonLiteral(text))) {
            el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
            el.dispatchEvent(new KeyboardEvent('keypress', { key: ch, bubbles: true }));
            document.execCommand('insertText', false, ch);
            el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
        }
        return { ok: true };
        """
        return await evalAndCheck(js)
    }

    func press(_ params: [String: Any]) async -> Result {
        guard let key = params["key"] as? String else { return .err(code: "invalid_params", message: "Missing key") }
        let js = """
        const t = document.activeElement || document.body;
        const k = \(jsonLiteral(key));
        t.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
        t.dispatchEvent(new KeyboardEvent('keypress', { key: k, bubbles: true, cancelable: true }));
        t.dispatchEvent(new KeyboardEvent('keyup', { key: k, bubbles: true, cancelable: true }));
        return { ok: true };
        """
        return await evalAndCheck(js)
    }

    func selectOption(_ params: [String: Any]) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        guard let value = params["value"] as? String else { return .err(code: "invalid_params", message: "Missing value") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el || el.tagName !== 'SELECT') return { ok: false, error: 'not_found' };
        el.value = \(jsonLiteral(value));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return { ok: true };
        """
        return await evalAndCheck(js)
    }

    func scroll(_ params: [String: Any]) async -> Result {
        let x = params["x"] as? Int ?? 0
        let y = params["y"] as? Int ?? 0
        let js = "window.scrollBy(\(x), \(y)); return { ok: true };"
        return await evalAndCheck(js)
    }

    private func evalAndCheck(_ js: String) async -> Result {
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            if let dict = val as? [String: Any], dict["ok"] as? Bool == false {
                return .err(code: dict["error"] as? String ?? "error", message: "Action failed")
            }
            return .ok([:])
        }
    }
}

// MARK: - DOM Queries

extension BrowserAgentAPI {
    func getText(_ params: [String: Any]) async -> Result { await queryElement(params, prop: "el.innerText || el.textContent || ''") }
    func getHTML(_ params: [String: Any]) async -> Result { await queryElement(params, prop: "el.outerHTML") }
    func getValue(_ params: [String: Any]) async -> Result { await queryElement(params, prop: "el.value !== undefined ? el.value : el.textContent || ''") }

    func getAttr(_ params: [String: Any]) async -> Result {
        guard let name = params["name"] as? String ?? params["attr"] as? String else { return .err(code: "invalid_params", message: "Missing attr name") }
        return await queryElement(params, prop: "el.getAttribute(\(jsonLiteral(name)))")
    }

    func getCount(_ params: [String: Any]) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        let js = "return document.querySelectorAll(\(jsonLiteral(selector))).length;"
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val): return .ok(["count": val])
        }
    }

    func getBox(_ params: [String: Any]) async -> Result {
        return await queryElement(params, prop: "(() => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; })()")
    }

    func getStyles(_ params: [String: Any]) async -> Result {
        let props = params["properties"] as? [String] ?? []
        let propsJS = jsonLiteral(props.joined(separator: ","))
        return await queryElement(params, prop: "(() => { const s = getComputedStyle(el); const ps = \(propsJS).split(','); const r = {}; ps.forEach(p => { if(p) r[p.trim()] = s.getPropertyValue(p.trim()); }); return r; })()")
    }

    private func queryElement(_ params: [String: Any], prop: String) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el) return { ok: false, error: 'not_found' };
        return { ok: true, value: \(prop) };
        """
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            guard let dict = val as? [String: Any] else { return .ok(["value": val]) }
            if dict["ok"] as? Bool == false { return .err(code: "not_found", message: "Element not found") }
            return .ok(["value": dict["value"] ?? NSNull()])
        }
    }
}

// MARK: - State Checks

extension BrowserAgentAPI {
    func isVisible(_ params: [String: Any]) async -> Result { await checkElement(params, check: "el.offsetWidth > 0 && el.offsetHeight > 0 && getComputedStyle(el).visibility !== 'hidden'") }
    func isEnabled(_ params: [String: Any]) async -> Result { await checkElement(params, check: "!el.disabled") }
    func isChecked(_ params: [String: Any]) async -> Result { await checkElement(params, check: "!!el.checked") }

    private func checkElement(_ params: [String: Any], check: String) async -> Result {
        guard let selector = resolveSelector(params) else { return .err(code: "invalid_params", message: "Missing selector") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el) return { ok: false, error: 'not_found' };
        return { ok: true, value: \(check) };
        """
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            guard let dict = val as? [String: Any] else { return .ok(["value": false]) }
            if dict["ok"] as? Bool == false { return .err(code: "not_found", message: "Element not found") }
            return .ok(["value": dict["value"] ?? false])
        }
    }
}

// MARK: - Find Commands

extension BrowserAgentAPI {
    func findByText(_ params: [String: Any]) async -> Result {
        guard let text = params["text"] as? String ?? params["value"] as? String else { return .err(code: "invalid_params", message: "Missing text") }
        let js = """
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node; const t = \(jsonLiteral(text)).toLowerCase();
        while (node = walker.nextNode()) {
            if (node.textContent.toLowerCase().includes(t)) {
                const el = node.parentElement;
                return { ok: true, tag: el.tagName, text: el.innerText?.slice(0,120), selector: __cssPath(el) };
            }
        }
        return { ok: false, error: 'not_found' };
        """
        return await findWithCSSPath(js)
    }

    func findByAttr(_ params: [String: Any], attr: String) async -> Result {
        guard let value = params["value"] as? String ?? params["text"] as? String else { return .err(code: "invalid_params", message: "Missing value") }
        let js = """
        const els = document.querySelectorAll('[\(attr)]');
        const v = \(jsonLiteral(value)).toLowerCase();
        for (const el of els) {
            if (el.getAttribute('\(attr)').toLowerCase().includes(v)) {
                return { ok: true, tag: el.tagName, text: el.innerText?.slice(0,120), selector: __cssPath(el) };
            }
        }
        return { ok: false, error: 'not_found' };
        """
        return await findWithCSSPath(js)
    }

    func findFirst(_ params: [String: Any]) async -> Result {
        guard let selector = params["selector"] as? String ?? params["sel"] as? String else { return .err(code: "invalid_params", message: "Missing selector") }
        let js = """
        const el = document.querySelector(\(jsonLiteral(selector)));
        if (!el) return { ok: false, error: 'not_found' };
        return { ok: true, tag: el.tagName, text: el.innerText?.slice(0,120), selector: __cssPath(el) };
        """
        return await findWithCSSPath(js)
    }

    func findLast(_ params: [String: Any]) async -> Result {
        guard let selector = params["selector"] as? String ?? params["sel"] as? String else { return .err(code: "invalid_params", message: "Missing selector") }
        let js = """
        const els = document.querySelectorAll(\(jsonLiteral(selector)));
        if (!els.length) return { ok: false, error: 'not_found' };
        const el = els[els.length - 1];
        return { ok: true, tag: el.tagName, text: el.innerText?.slice(0,120), selector: __cssPath(el) };
        """
        return await findWithCSSPath(js)
    }

    func findNth(_ params: [String: Any]) async -> Result {
        guard let selector = params["selector"] as? String ?? params["sel"] as? String else { return .err(code: "invalid_params", message: "Missing selector") }
        let index = params["index"] as? Int ?? 0
        let js = """
        const els = document.querySelectorAll(\(jsonLiteral(selector)));
        if (\(index) >= els.length) return { ok: false, error: 'not_found' };
        const el = els[\(index)];
        return { ok: true, tag: el.tagName, text: el.innerText?.slice(0,120), selector: __cssPath(el) };
        """
        return await findWithCSSPath(js)
    }

    private static let cssPathHelper = """
    function __cssPath(el) {
        const parts = [];
        while (el && el !== document.body && parts.length < 6) {
            let sel = el.tagName.toLowerCase();
            if (el.id) { parts.unshift('#' + el.id); break; }
            const parent = el.parentElement;
            if (parent) {
                const siblings = Array.from(parent.children).filter(c => c.tagName === el.tagName);
                if (siblings.length > 1) sel += ':nth-of-type(' + (siblings.indexOf(el) + 1) + ')';
            }
            parts.unshift(sel);
            el = parent;
        }
        return parts.join(' > ') || 'body';
    }
    """

    private func findWithCSSPath(_ finderJS: String) async -> Result {
        let js = Self.cssPathHelper + "\n" + finderJS
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            guard let dict = val as? [String: Any] else { return .err(code: "js_error", message: "Unexpected result") }
            if dict["ok"] as? Bool == false { return .err(code: "not_found", message: "Element not found") }
            let selector = dict["selector"] as? String ?? ""
            let ref = allocateRef(selector: selector)
            return .ok(["ref": ref, "selector": selector, "tag": dict["tag"] ?? "", "text": dict["text"] ?? ""])
        }
    }
}

// MARK: - Snapshot, Eval, Wait, Screenshot, Cookies

extension BrowserAgentAPI {
    func snapshot(_ params: [String: Any]) async -> Result {
        let maxDepth = params["max_depth"] as? Int ?? 12
        let js = """
        \(Self.cssPathHelper)
        const entries = [];
        function walk(node, depth) {
            if (depth > \(maxDepth) || !node) return;
            if (node.nodeType !== 1) return;
            const el = node;
            const style = getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden') return;
            const rect = el.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) return;
            let role = el.getAttribute('role') || '';
            if (!role) {
                const tag = el.tagName.toLowerCase();
                const roleMap = {button:'button',a:'link',input:'textbox',textarea:'textbox',select:'combobox',img:'img',h1:'heading',h2:'heading',h3:'heading',h4:'heading',h5:'heading',h6:'heading',li:'listitem',nav:'navigation',main:'main',header:'banner',footer:'contentinfo',form:'form',table:'table',summary:'button'};
                role = roleMap[tag] || '';
                if (tag === 'input') {
                    const t = el.type?.toLowerCase();
                    if (t === 'checkbox') role = 'checkbox';
                    else if (t === 'radio') role = 'radio';
                    else if (t === 'submit' || t === 'button') role = 'button';
                }
                if (tag === 'a' && el.href) role = 'link';
            }
            const name = el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('title') || (el.innerText || '').slice(0, 120).trim();
            if (role || name) {
                entries.push({ selector: __cssPath(el), role, name, depth });
            }
            for (const child of el.children) walk(child, depth + 1);
        }
        walk(document.body, 0);
        return { title: document.title, url: location.href, entries };
        """
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val):
            guard let dict = val as? [String: Any],
                  let entries = dict["entries"] as? [[String: Any]] else { return .ok(["snapshot": ""]) }
            var lines: [String] = []
            var refs: [String: [String: String]] = [:]
            for entry in entries {
                let selector = entry["selector"] as? String ?? ""
                let role = entry["role"] as? String ?? ""
                let name = entry["name"] as? String ?? ""
                let depth = entry["depth"] as? Int ?? 0
                let ref = allocateRef(selector: selector)
                let indent = String(repeating: "  ", count: depth)
                let label = name.isEmpty ? role : "\(role) \"\(name)\""
                lines.append("\(indent)- \(label) [ref=\(ref)]")
                refs[ref] = ["role": role, "name": name]
            }
            return .ok([
                "snapshot": lines.joined(separator: "\n"),
                "refs": refs,
                "title": dict["title"] ?? "",
                "url": dict["url"] ?? ""
            ])
        }
    }

    func eval(_ params: [String: Any]) async -> Result {
        guard let script = params["script"] as? String else { return .err(code: "invalid_params", message: "Missing script") }
        switch await runJS("return \(script)") {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val): return .ok(["value": val])
        }
    }

    func wait(_ params: [String: Any]) async -> Result {
        let timeout = params["timeout"] as? Int ?? 5000
        let condition: String
        if let sel = params["selector"] as? String {
            condition = "document.querySelector(\(jsonLiteral(sel))) !== null"
        } else if let text = params["text_contains"] as? String {
            condition = "document.body.innerText.includes(\(jsonLiteral(text)))"
        } else if let url = params["url_contains"] as? String {
            condition = "location.href.includes(\(jsonLiteral(url)))"
        } else {
            condition = "document.readyState === 'complete'"
        }
        let js = """
        return await new Promise((resolve) => {
            if (\(condition)) { resolve({ ok: true }); return; }
            const obs = new MutationObserver(() => { if (\(condition)) { obs.disconnect(); resolve({ ok: true }); } });
            obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true, characterData: true });
            setTimeout(() => { obs.disconnect(); resolve(\(condition) ? { ok: true } : { ok: false, error: 'timeout' }); }, \(timeout));
        });
        """
        switch await runJS(js, timeout: Double(timeout) / 1000.0 + 2.0) {
        case .failure(let err): return .err(code: "timeout", message: err.message)
        case .success(let val):
            if let dict = val as? [String: Any], dict["ok"] as? Bool == false {
                return .err(code: "timeout", message: "Wait timed out")
            }
            return .ok([:])
        }
    }

    func screenshot(_ params: [String: Any] = [:]) async -> Result {
        guard let vm = viewModel else { return .err(code: "unavailable", message: "No browser") }
        let fullPage = (params["full_page"] as? Bool) ?? (params["fullPage"] as? Bool) ?? false

        if fullPage {
            // Use `createPDF` rather than `takeSnapshot` for full-page capture.
            // `WKSnapshotConfiguration.rect` is in the **view's** coordinate space, so
            // setting it larger than the visible bounds doesn't capture content below
            // the fold — WebKit only rasterizes what's in the view's frame buffer. The
            // PDF API instead routes through WebKit's render-to-arbitrary-surface path
            // (the same path used for print preview and Safari Web Inspector's
            // full-page screenshot), so the entire scrollable document is rendered
            // without resizing the visible WKWebView. We then rasterize the PDF page
            // to PNG. This is the WKWebView equivalent of Chrome's internal
            // `Page.captureScreenshot { captureBeyondViewport: true }` path — same
            // trick, different intermediate format because Apple only exposes the
            // render path via `createPDF`.
            //
            // The Objective-C `createPDFWithConfiguration:completionHandler:` is
            // marked `NS_REFINED_FOR_SWIFT`, so Swift's automatic async bridging is
            // suppressed and the symbol isn't visible under the obvious `createPDF`
            // name. Bridge the completion-handler form via a continuation.
            do {
                let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
                    vm.webView.createPDF(configuration: WKPDFConfiguration()) { result in
                        switch result {
                        case .success(let data):
                            continuation.resume(returning: data)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
                guard let pdfDocument = PDFDocument(data: pdfData), pdfDocument.pageCount > 0 else {
                    return .err(code: "internal_error", message: "Failed to load PDF for screenshot")
                }
                guard let png = rasterizePDF(pdfDocument) else {
                    return .err(code: "internal_error", message: "Failed to rasterize PDF to PNG")
                }
                return .ok([
                    "base64": png.base64EncodedString(),
                    "size": png.count,
                    "format": "png",
                    "full_page": true,
                ])
            } catch {
                return .err(code: "internal_error", message: error.localizedDescription)
            }
        }

        // Viewport-only screenshot (default). Captures whatever is currently visible.
        let config = WKSnapshotConfiguration()
        do {
            let image = try await vm.webView.takeSnapshot(configuration: config)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                return .err(code: "internal_error", message: "Failed to encode screenshot")
            }
            return .ok([
                "base64": png.base64EncodedString(),
                "size": png.count,
                "format": "png",
                "full_page": false,
            ])
        } catch {
            return .err(code: "internal_error", message: error.localizedDescription)
        }
    }

    /// Renders all pages of a `PDFDocument` into a single PNG, stacking them
    /// vertically. In practice `WKWebView.createPDF` with no rect produces a single
    /// page that spans the entire scrollable document, but we handle the multi-page
    /// case defensively for paginated documents (e.g., printed CSS with `page-break`).
    private func rasterizePDF(_ document: PDFDocument) -> Data? {
        var pageImages: [(image: NSImage, size: CGSize)] = []
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = NSImage(size: bounds.size)
            image.lockFocusFlipped(false)
            if let context = NSGraphicsContext.current?.cgContext {
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: bounds.size))
                page.draw(with: .mediaBox, to: context)
            }
            image.unlockFocus()
            pageImages.append((image, bounds.size))
            totalHeight += bounds.size.height
            maxWidth = max(maxWidth, bounds.size.width)
        }

        guard totalHeight > 0, maxWidth > 0 else { return nil }

        // If only one page, encode it directly to avoid an unnecessary composite.
        if pageImages.count == 1 {
            let only = pageImages[0].image
            return pngData(from: only)
        }

        // Multi-page: composite vertically.
        let composite = NSImage(size: CGSize(width: maxWidth, height: totalHeight))
        composite.lockFocusFlipped(false)
        var y = totalHeight
        for entry in pageImages {
            y -= entry.size.height
            entry.image.draw(in: CGRect(x: 0, y: y, width: entry.size.width, height: entry.size.height))
        }
        composite.unlockFocus()
        return pngData(from: composite)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func cookiesGet(_ params: [String: Any]) async -> Result {
        guard let store = viewModel?.webView.configuration.websiteDataStore.httpCookieStore else {
            return .err(code: "unavailable", message: "No cookie store")
        }
        let cookies = await store.allCookies()
        let nameFilter = params["name"] as? String
        let filtered = cookies.filter { nameFilter == nil || $0.name == nameFilter }
        let result = filtered.map { ["name": $0.name, "value": $0.value, "domain": $0.domain, "path": $0.path] }
        return .ok(["cookies": result])
    }

    func cookiesSet(_ params: [String: Any]) async -> Result {
        guard let store = viewModel?.webView.configuration.websiteDataStore.httpCookieStore,
              let name = params["name"] as? String,
              let value = params["value"] as? String,
              let domain = params["domain"] as? String else {
            return .err(code: "invalid_params", message: "Missing name, value, or domain")
        }
        let props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: params["path"] as? String ?? "/"]
        guard let cookie = HTTPCookie(properties: props) else { return .err(code: "invalid_params", message: "Invalid cookie") }
        await store.setCookie(cookie)
        return .ok([:])
    }

    func cookiesClear() async -> Result {
        guard let store = viewModel?.webView.configuration.websiteDataStore.httpCookieStore else {
            return .err(code: "unavailable", message: "No cookie store")
        }
        for cookie in await store.allCookies() { await store.deleteCookie(cookie) }
        return .ok([:])
    }

    func storageGet(_ params: [String: Any]) async -> Result {
        let key = params["key"] as? String
        let storage = params["storage"] as? String ?? "local"
        let js: String
        if let key {
            js = "return \(storage)Storage.getItem(\(jsonLiteral(key)));"
        } else {
            js = """
            const r = {}; for (let i = 0; i < \(storage)Storage.length; i++) {
                const k = \(storage)Storage.key(i); r[k] = \(storage)Storage.getItem(k);
            } return r;
            """
        }
        switch await runJS(js) {
        case .failure(let err): return .err(code: "js_error", message: err.message)
        case .success(let val): return .ok(["value": val])
        }
    }
}
