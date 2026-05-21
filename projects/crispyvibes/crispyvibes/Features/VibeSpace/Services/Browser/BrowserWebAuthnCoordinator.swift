import Foundation
import WebKit
import AuthenticationServices

/// Bridges WebAuthn credential requests from web content to the native passkey system.
/// Injects JS that intercepts navigator.credentials.create/get and routes through
/// a WKScriptMessageHandler to the native ASAuthorizationController.
@MainActor
final class BrowserWebAuthnCoordinator: NSObject {
    private weak var webView: WKWebView?
    private let messageHandlerName = "__crispyvibesWebAuthn"

    func install(on webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.add(LeakAvoider(delegate: self), name: messageHandlerName)
        let script = WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
    }

    func uninstall() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        webView = nil
    }

    // MARK: - JS Bridge

    static let bridgeJS = """
    (() => {
        if (!window.PublicKeyCredential) return;
        const origCreate = navigator.credentials.create.bind(navigator.credentials);
        const origGet = navigator.credentials.get.bind(navigator.credentials);

        navigator.credentials.create = function(options) {
            if (!options?.publicKey) return origCreate(options);
            return new Promise((resolve, reject) => {
                const id = Math.random().toString(36).slice(2);
                window.__crispyvibesWebAuthnCallbacks = window.__crispyvibesWebAuthnCallbacks || {};
                window.__crispyvibesWebAuthnCallbacks[id] = { resolve, reject };
                window.webkit.messageHandlers.__crispyvibesWebAuthn.postMessage({
                    type: 'create',
                    id: id,
                    rpId: options.publicKey.rp?.id || location.hostname,
                    rpName: options.publicKey.rp?.name || '',
                    userName: options.publicKey.user?.name || '',
                    userDisplayName: options.publicKey.user?.displayName || '',
                    challenge: btoa(String.fromCharCode(...new Uint8Array(options.publicKey.challenge)))
                });
            });
        };

        navigator.credentials.get = function(options) {
            if (!options?.publicKey) return origGet(options);
            return new Promise((resolve, reject) => {
                const id = Math.random().toString(36).slice(2);
                window.__crispyvibesWebAuthnCallbacks = window.__crispyvibesWebAuthnCallbacks || {};
                window.__crispyvibesWebAuthnCallbacks[id] = { resolve, reject };
                window.webkit.messageHandlers.__crispyvibesWebAuthn.postMessage({
                    type: 'get',
                    id: id,
                    rpId: options.publicKey.rpId || location.hostname,
                    challenge: btoa(String.fromCharCode(...new Uint8Array(options.publicKey.challenge)))
                });
            });
        };
    })();
    """

    // MARK: - Native Auth

    private func handleCreate(callbackID: String, rpID: String, userName: String, challenge: String) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        guard let challengeData = Data(base64Encoded: challenge) else {
            rejectCallback(callbackID, error: "Invalid challenge")
            return
        }
        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: userName,
            userID: Data(userName.utf8)
        )
        performAuth(request: request, callbackID: callbackID)
    }

    private func handleGet(callbackID: String, rpID: String, challenge: String) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        guard let challengeData = Data(base64Encoded: challenge) else {
            rejectCallback(callbackID, error: "Invalid challenge")
            return
        }
        let request = provider.createCredentialAssertionRequest(challenge: challengeData)
        performAuth(request: request, callbackID: callbackID)
    }

    private var pendingCallbackID: String?

    private func performAuth(request: ASAuthorizationRequest, callbackID: String) {
        pendingCallbackID = callbackID
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    private func resolveCallback(_ callbackID: String, credential: String) {
        webView?.evaluateJavaScript("""
        (() => {
            const cb = window.__crispyvibesWebAuthnCallbacks?.['\(callbackID)'];
            if (cb) { cb.resolve(\(credential)); delete window.__crispyvibesWebAuthnCallbacks['\(callbackID)']; }
        })();
        """)
    }

    private func rejectCallback(_ callbackID: String, error: String) {
        webView?.evaluateJavaScript("""
        (() => {
            const cb = window.__crispyvibesWebAuthnCallbacks?.['\(callbackID)'];
            if (cb) { cb.reject(new DOMException('\(error)', 'NotAllowedError')); delete window.__crispyvibesWebAuthnCallbacks['\(callbackID)']; }
        })();
        """)
    }
}

// MARK: - WKScriptMessageHandler

extension BrowserWebAuthnCoordinator: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let callbackID = body["id"] as? String else { return }
            let rpID = body["rpId"] as? String ?? ""
            let challenge = body["challenge"] as? String ?? ""
            switch type {
            case "create":
                handleCreate(callbackID: callbackID, rpID: rpID, userName: body["userName"] as? String ?? "", challenge: challenge)
            case "get":
                handleGet(callbackID: callbackID, rpID: rpID, challenge: challenge)
            default:
                rejectCallback(callbackID, error: "Unknown WebAuthn type")
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension BrowserWebAuthnCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let callbackID = pendingCallbackID else { return }
            pendingCallbackID = nil
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                let response = """
                { id: '\(credential.credentialID.base64EncodedString())',
                  rawId: Uint8Array.from(atob('\(credential.credentialID.base64EncodedString())'), c => c.charCodeAt(0)),
                  type: 'public-key',
                  response: { attestationObject: '\(credential.rawAttestationObject?.base64EncodedString() ?? "")' } }
                """
                resolveCallback(callbackID, credential: response)
                return
            }
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                let response = """
                { id: '\(credential.credentialID.base64EncodedString())',
                  rawId: Uint8Array.from(atob('\(credential.credentialID.base64EncodedString())'), c => c.charCodeAt(0)),
                  type: 'public-key',
                  response: { authenticatorData: '\(credential.rawAuthenticatorData.base64EncodedString())',
                              signature: '\(credential.signature.base64EncodedString())' } }
                """
                resolveCallback(callbackID, credential: response)
                return
            }
            rejectCallback(callbackID, error: "Unsupported credential type")
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            guard let callbackID = pendingCallbackID else { return }
            pendingCallbackID = nil
            rejectCallback(callbackID, error: error.localizedDescription)
        }
    }
}

/// Prevents WKScriptMessageHandler retain cycle with WKWebView.
private final class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
