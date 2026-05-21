import Foundation
import WebKit
import AppKit

final class BrowserNavigationDelegate: NSObject, WKNavigationDelegate {
    var onDidFinish: ((URL?, String?) -> Void)?
    var onWebContentProcessTerminated: ((WKWebView) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?
    var shouldBlockInsecureHTTP: ((URL) -> Bool)?
    var onInsecureHTTPBlocked: ((URL) -> Void)?
    var onNavigationFailed: ((URL?, NSError) -> Void)?
    var onExternalScheme: ((URL) -> Void)?
    var onExternalPattern: ((URL) -> Bool)?
    var downloadDelegate: BrowserDownloadDelegate?

    private static let internalSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file"]

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinish?(webView.url, webView.title)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           !Self.internalSchemes.contains(scheme) {
            onExternalScheme?(url)
            decisionHandler(.cancel)
            return
        }
        if let url = navigationAction.request.url,
           onExternalPattern?(url) == true {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if let onOpenInNewTab {
                onOpenInNewTab(url)
            } else {
                webView.load(URLRequest(url: url))
            }
            decisionHandler(.cancel)
            return
        }
        if let url = navigationAction.request.url,
           navigationAction.targetFrame?.isMainFrame != false,
           shouldBlockInsecureHTTP?(url) == true {
            onInsecureHTTPBlocked?(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            if disposition.lowercased().hasPrefix("attachment") {
                decisionHandler(.download)
                return
            }
        }
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloadDelegate
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloadDelegate
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // Suppress user-cancelled and frame-load-interrupted errors
        guard nsError.code != NSURLErrorCancelled,
              nsError.code != 102 /* WebKitErrorFrameLoadInterruptedByPolicyChange */ else { return }
        onNavigationFailed?(webView.url, nsError)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled,
              nsError.code != 102 else { return }
        onNavigationFailed?(webView.url, nsError)
    }

    func webView(_ webView: WKWebView, authenticationChallenge challenge: URLAuthenticationChallenge, shouldAllowDeprecatedTLS decisionHandler: @escaping (Bool) -> Void) {
        decisionHandler(false)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onWebContentProcessTerminated?(webView)
    }
}
