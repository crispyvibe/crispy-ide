import Foundation
import WebKit

/// Browser automation API callable from terminal/agent commands.
/// Implements Playwright-style browser control: navigate, click, fill, snapshot, find, wait, etc.
@MainActor
final class BrowserAgentAPI {

    private(set) weak var viewModel: BrowserPanelViewModel?
    private(set) var nextElementOrdinal: Int = 1
    private(set) var elementRefs: [String: ElementRef] = [:]

    struct ElementRef {
        let selector: String
    }

    struct AgentError: Error {
        let message: String
    }

    enum Result {
        case ok([String: Any])
        case err(code: String, message: String)
    }

    init(viewModel: BrowserPanelViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Dispatch

    func dispatch(method: String, params: [String: Any]) async -> Result {
        switch method {
        // Navigation
        case "browser.navigate": return navigate(params)
        case "browser.back": return simpleAction { $0.goBack() }
        case "browser.forward": return simpleAction { $0.goForward() }
        case "browser.reload": return simpleAction { $0.reload() }
        case "browser.url.get": return urlGet()
        case "browser.get.title": return getTitle()

        // DOM interaction
        case "browser.click": return await selectorAction(params, js: Self.clickJS)
        case "browser.dblclick": return await selectorAction(params, js: Self.dblclickJS)
        case "browser.hover": return await selectorAction(params, js: Self.hoverJS)
        case "browser.focus": return await selectorAction(params, js: Self.focusJS)
        case "browser.fill": return await fill(params)
        case "browser.type": return await typeText(params)
        case "browser.press": return await press(params)
        case "browser.check": return await selectorAction(params, js: Self.checkJS)
        case "browser.uncheck": return await selectorAction(params, js: Self.uncheckJS)
        case "browser.select": return await selectOption(params)
        case "browser.scroll": return await scroll(params)
        case "browser.scroll_into_view": return await selectorAction(params, js: Self.scrollIntoViewJS)

        // DOM queries
        case "browser.get.text": return await getText(params)
        case "browser.get.html": return await getHTML(params)
        case "browser.get.value": return await getValue(params)
        case "browser.get.attr": return await getAttr(params)
        case "browser.get.count": return await getCount(params)
        case "browser.get.box": return await getBox(params)
        case "browser.get.styles": return await getStyles(params)

        // State checks
        case "browser.is.visible": return await isVisible(params)
        case "browser.is.enabled": return await isEnabled(params)
        case "browser.is.checked": return await isChecked(params)

        // Element finding
        case "browser.find.role": return await findByAttr(params, attr: "role")
        case "browser.find.text": return await findByText(params)
        case "browser.find.label": return await findByAttr(params, attr: "aria-label")
        case "browser.find.placeholder": return await findByAttr(params, attr: "placeholder")
        case "browser.find.alt": return await findByAttr(params, attr: "alt")
        case "browser.find.title": return await findByAttr(params, attr: "title")
        case "browser.find.testid": return await findByAttr(params, attr: "data-testid")
        case "browser.find.first": return await findFirst(params)
        case "browser.find.last": return await findLast(params)
        case "browser.find.nth": return await findNth(params)

        // Advanced
        case "browser.snapshot": return await snapshot(params)
        case "browser.eval": return await eval(params)
        case "browser.wait": return await wait(params)
        case "browser.screenshot": return await screenshot(params)

        // Dialogs
        case "browser.dialog.accept": return .ok(["accepted": true])
        case "browser.dialog.dismiss": return .ok(["dismissed": true])

        // Cookies
        case "browser.cookies.get": return await cookiesGet(params)
        case "browser.cookies.set": return await cookiesSet(params)
        case "browser.cookies.clear": return await cookiesClear()
        case "browser.storage.get": return await storageGet(params)

        default:
            return .err(code: "not_supported", message: "Unknown method: \(method)")
        }
    }

    // MARK: - Element Refs

    func allocateRef(selector: String) -> String {
        let ref = "@e\(nextElementOrdinal)"
        nextElementOrdinal += 1
        elementRefs[ref] = ElementRef(selector: selector)
        return ref
    }

    func resolveSelector(_ params: [String: Any]) -> String? {
        let raw = (params["selector"] as? String) ?? (params["sel"] as? String)
            ?? (params["element_ref"] as? String) ?? (params["ref"] as? String)
        guard let raw else { return nil }
        let key = raw.hasPrefix("@") ? raw : "@\(raw)"
        if let entry = elementRefs[key] { return entry.selector }
        return raw.hasPrefix("@e") ? nil : raw
    }

    // MARK: - JS Execution

    func runJS(_ script: String, timeout: TimeInterval = 5.0) async -> Swift.Result<Any, AgentError> {
        guard let webView = viewModel?.webView else { return .failure(AgentError(message: "No WebView")) }
        // Use `callAsyncJavaScript` rather than `evaluateJavaScript`. The previous
        // implementation wrapped the script in an async IIFE, which made the result
        // a `Promise`. `evaluateJavaScript` does not await promises and reported
        // them as `WKErrorJavaScriptResultTypeIsUnsupported` ("JavaScript execution
        // returned a result of an unsupported type"). `callAsyncJavaScript` treats
        // the input as a function body (so `return` works at the top level) and
        // awaits any returned promise, returning the resolved value.
        do {
            let result = try await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return .success(result ?? NSNull())
        } catch {
            return .failure(AgentError(message: error.localizedDescription))
        }
    }

    func runSelectorJS(_ params: [String: Any], js: String) async -> Swift.Result<Any, AgentError> {
        guard let selector = resolveSelector(params) else { return .failure(AgentError(message: "Missing selector")) }
        let escaped = jsonLiteral(selector)
        let script = js.replacingOccurrences(of: "__SEL__", with: escaped)
        return await runJS(script)
    }

    /// JSON-encodes a string for safe inline injection into JavaScript source. The
    /// previous implementation called `JSONSerialization.data(withJSONObject:)` with
    /// a raw `String`, which `NSJSONSerialization` rejects with an
    /// `NSInvalidArgumentException` ("Invalid top-level type in JSON write") because
    /// it requires the top level to be a dictionary or array. The Objective-C
    /// exception is not caught by `try?` and crashes the process. `.fragmentsAllowed`
    /// (macOS 10.15+) permits a top-level scalar and returns the correctly escaped
    /// JSON string literal, e.g. `"foo \"bar\"\n"`.
    func jsonLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        // Defensive fallback: hand-escape characters that would break a JS string
        // literal. Reached only if the serializer fails for some unexpected reason.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
