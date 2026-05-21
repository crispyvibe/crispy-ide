import Foundation
import WebKit
import AppKit

final class BrowserUIDelegate: NSObject, WKUIDelegate {
    var onOpenInNewTab: ((URL) -> Void)?

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            // If window features suggest a popup (has size), create a popup window
            if windowFeatures.width != nil || windowFeatures.height != nil {
                let popupWebView = WKWebView(frame: .zero, configuration: configuration)
                let w = CGFloat(truncating: windowFeatures.width ?? 800)
                let h = CGFloat(truncating: windowFeatures.height ?? 600)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                                      styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                      backing: .buffered, defer: false)
                window.contentView = popupWebView
                window.title = url.host ?? url.absoluteString
                window.center()
                window.makeKeyAndOrderFront(nil)
                popupWebView.load(URLRequest(url: url))
                return popupWebView
            }
            if let onOpenInNewTab {
                onOpenInNewTab(url)
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }

    // MARK: - File Upload (S75)

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: - Media Capture (S76)

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? AppStrings.Browser.dialogFallbackTitle
        alert.informativeText = message
        alert.addButton(withTitle: AppStrings.Common.ok)
        if let window = webView.window {
            alert.beginSheetModal(for: window) { _ in completionHandler() }
        } else {
            alert.runModal()
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? AppStrings.Browser.dialogFallbackTitle
        alert.informativeText = message
        alert.addButton(withTitle: AppStrings.Common.ok)
        alert.addButton(withTitle: AppStrings.Common.cancel)
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? AppStrings.Browser.dialogFallbackTitle
        alert.informativeText = prompt
        alert.addButton(withTitle: AppStrings.Common.ok)
        alert.addButton(withTitle: AppStrings.Common.cancel)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if let window = webView.window {
            alert.beginSheetModal(for: window) { response in
                completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
            }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }
}
