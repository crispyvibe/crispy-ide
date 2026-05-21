import AppKit
import AuthenticationServices
import Foundation

struct CognitoTokenSet: Codable, Equatable {
    let accessToken: String
    let idToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
}

@MainActor
final class CognitoAuthService: NSObject, ObservableObject {
    @Published private(set) var tokenSet: CognitoTokenSet?
    @Published private(set) var userEmail: String?
    @Published private(set) var lastErrorMessage: String?

    private let authCallbackScheme: String
    private let keychain: KeychainStore
    private let keychainAccount = "tokenSet"
    private var activeWebSession: ASWebAuthenticationSession?
    private var pendingCodeVerifier: String?
    private var pendingState: String?
    private weak var preferredPresentationAnchor: ASPresentationAnchor?

    override init() {
        authCallbackScheme = Self.resolveAuthCallbackScheme()
        keychain = KeychainStore(service: Self.resolveKeychainService())
        super.init()
        loadFromKeychain()
    }

    var isSignedIn: Bool { tokenSet != nil }

    func updatePresentationAnchor(_ anchor: ASPresentationAnchor?) {
        preferredPresentationAnchor = anchor
    }

    func signOut() {
        do {
            try keychain.delete(account: keychainAccount)
            lastErrorMessage = nil
            recordAuth(.notice, event: "auth_sign_out_succeeded")
        } catch {
            recordAuth(
                .error,
                event: "auth_sign_out_failed",
                metadata: authErrorMetadata(error)
            )
            lastErrorMessage = "Failed to clear credentials."
        }
        tokenSet = nil
        userEmail = nil
    }

    func signInWithApple(domain rawDomain: String, clientId rawClientId: String) {
        lastErrorMessage = nil
        activeWebSession?.cancel()
        activeWebSession = nil

        let domain = normalizeDomain(rawDomain)
        let clientId = rawClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else {
            lastErrorMessage = "Missing Cognito domain (example: auth.crispyvibe.com)."
            return
        }
        guard !clientId.isEmpty else {
            lastErrorMessage = "Missing macOS app client id (from CDK output)."
            return
        }

        let redirectURI = "\(authCallbackScheme)://callback"
        let codeVerifier = PKCE.codeVerifier()
        let codeChallenge = PKCE.codeChallenge(for: codeVerifier)
        let state = PKCE.randomState()
        let authMetadata = baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)

        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "identity_provider", value: "SignInWithApple"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authorizeURL = components.url else {
            lastErrorMessage = "Failed to build authorization URL."
            return
        }

        guard currentPresentationAnchor() != nil else {
            lastErrorMessage = "Open Settings in the app window and try sign-in again."
            recordAuth(.error, event: "auth_missing_presentation_anchor", metadata: authMetadata)
            return
        }

        recordAuth(.notice, event: "auth_sign_in_started", metadata: authMetadata)
        pendingCodeVerifier = codeVerifier
        pendingState = state

        let session = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: authCallbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleAuthCallback(
                    callbackURL,
                    error: error,
                    domain: domain,
                    clientId: clientId,
                    redirectURI: redirectURI
                )
            }
        }
        session.presentationContextProvider = self
        NSApp.activate(ignoringOtherApps: true)
        activeWebSession = session

        if !session.start() {
            lastErrorMessage = "Failed to open the sign-in window."
            recordAuth(.error, event: "auth_session_start_failed", metadata: authMetadata)
            activeWebSession = nil
            pendingCodeVerifier = nil
            pendingState = nil
        }
    }

    private func currentPresentationAnchor() -> ASPresentationAnchor? {
        if let preferredPresentationAnchor, preferredPresentationAnchor.isVisible {
            return preferredPresentationAnchor
        }

        if let keyWindow = NSApp.keyWindow, keyWindow.isVisible {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
            return mainWindow
        }

        if let orderedVisibleWindow = NSApp.orderedWindows.first(where: \.isVisible) {
            return orderedVisibleWindow
        }

        return NSApp.windows.first(where: \.isVisible)
    }

    private func handleAuthCallback(
        _ callbackURL: URL?,
        error: Error?,
        domain: String,
        clientId: String,
        redirectURI: String
    ) async {
        defer {
            activeWebSession = nil
        }

        if let error {
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin {
                recordAuth(
                    .notice,
                    event: "auth_session_cancelled",
                    metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                )
                return
            }
            recordAuth(
                .error,
                event: "auth_session_failed",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                    .merging(authErrorMetadata(error), uniquingKeysWith: { _, new in new })
            )
            lastErrorMessage = "Sign-in failed."
            return
        }

        guard let callbackURL else {
            recordAuth(
                .error,
                event: "auth_callback_missing_url",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            lastErrorMessage = "Missing callback URL."
            return
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            recordAuth(
                .error,
                event: "auth_callback_invalid_url",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            lastErrorMessage = "Invalid callback URL."
            return
        }

        let queryItems = components.queryItems ?? []
        let code = queryItems.first(where: { $0.name == "code" })?.value
        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        let errorCode = queryItems.first(where: { $0.name == "error" })?.value
        let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value

        if let errorCode {
            recordAuth(
                .error,
                event: "auth_callback_error",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                    .merging(
                        [
                            "error_code": sanitizeDiagnosticValue(errorCode),
                            "error_description": sanitizeDiagnosticValue(errorDescription ?? "")
                        ],
                        uniquingKeysWith: { _, new in new }
                    )
            )
            lastErrorMessage = errorDescription ?? errorCode
            return
        }

        guard let code else {
            recordAuth(
                .error,
                event: "auth_callback_missing_code",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            lastErrorMessage = "Missing authorization code."
            return
        }

        guard let expectedState = pendingState, returnedState == expectedState else {
            recordAuth(
                .error,
                event: "auth_callback_state_mismatch",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            lastErrorMessage = "State mismatch."
            return
        }

        guard let codeVerifier = pendingCodeVerifier else {
            recordAuth(
                .error,
                event: "auth_callback_missing_code_verifier",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            lastErrorMessage = "Missing code verifier."
            return
        }

        pendingState = nil
        pendingCodeVerifier = nil

        do {
            recordAuth(
                .notice,
                event: "auth_callback_code_received",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            let tokenSet = try await exchangeCodeForTokens(
                domain: domain,
                clientId: clientId,
                code: code,
                codeVerifier: codeVerifier,
                redirectURI: redirectURI
            )
            try persistToKeychain(tokenSet)
            recordAuth(
                .notice,
                event: "auth_tokens_persisted",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            self.tokenSet = tokenSet
            self.userEmail = Self.extractEmail(from: tokenSet.idToken)
        } catch {
            recordAuth(
                .error,
                event: "auth_sign_in_failed",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                    .merging(authErrorMetadata(error), uniquingKeysWith: { _, new in new })
            )
            lastErrorMessage = signInFailureMessage(for: error)
        }
    }

    private func exchangeCodeForTokens(
        domain: String,
        clientId: String,
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> CognitoTokenSet {
        guard let tokenURL = URL(string: "https://\(domain)/oauth2/token") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded([
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            recordAuth(
                .error,
                event: "auth_token_exchange_invalid_response",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
            )
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            recordAuth(
                .error,
                event: "auth_token_exchange_failed",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                    .merging(
                        [
                            "http_status": String(httpResponse.statusCode),
                            "response_body": sanitizeDiagnosticValue(String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
                        ],
                        uniquingKeysWith: { _, new in new }
                    )
            )
            throw URLError(.badServerResponse)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let id_token: String
            let refresh_token: String?
            let expires_in: Int
            let token_type: String
        }

        let parsed: TokenResponse
        do {
            parsed = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            recordAuth(
                .error,
                event: "auth_token_decode_failed",
                metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                    .merging(authErrorMetadata(error), uniquingKeysWith: { _, new in new })
            )
            throw error
        }
        recordAuth(
            .notice,
            event: "auth_token_exchange_succeeded",
            metadata: baseAuthMetadata(domain: domain, clientId: clientId, redirectURI: redirectURI)
                .merging(["http_status": String(httpResponse.statusCode)], uniquingKeysWith: { _, new in new })
        )
        return CognitoTokenSet(
            accessToken: parsed.access_token,
            idToken: parsed.id_token,
            refreshToken: parsed.refresh_token,
            expiresIn: parsed.expires_in,
            tokenType: parsed.token_type
        )
    }

    private static func resolveAuthCallbackScheme() -> String {
        let infoKey = "CrispyVibesAuthCallbackScheme"
        if let scheme = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !scheme.isEmpty {
            return scheme
        }
        return Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
    }

    private static func resolveKeychainService() -> String {
        let infoKey = "CrispyVibesAuthKeychainService"
        if let service = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !service.isEmpty {
            return service
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
        return "\(bundleID).cognito"
    }

    private func normalizeDomain(_ rawDomain: String) -> String {
        var trimmed = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") {
            trimmed.removeFirst("https://".count)
        } else if trimmed.hasPrefix("http://") {
            trimmed.removeFirst("http://".count)
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func formURLEncoded(_ fields: [String: String]) -> Data? {
        let pairs = fields
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                let encodedKey = urlEncode(key)
                let encodedValue = urlEncode(value)
                return "\(encodedKey)=\(encodedValue)"
            }
        return pairs.joined(separator: "&").data(using: .utf8)
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func extractEmail(from idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        guard let data = Data(base64URLEncoded: payload) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    private func loadFromKeychain() {
        do {
            guard let data = try keychain.read(account: keychainAccount) else { return }
            let tokenSet = try JSONDecoder().decode(CognitoTokenSet.self, from: data)
            self.tokenSet = tokenSet
            self.userEmail = Self.extractEmail(from: tokenSet.idToken)
        } catch {
            tokenSet = nil
            userEmail = nil
        }
    }

    private func persistToKeychain(_ tokenSet: CognitoTokenSet) throws {
        let data = try JSONEncoder().encode(tokenSet)
        try keychain.write(data, account: keychainAccount)
    }

    private func recordAuth(
        _ level: DiagnosticsLevel,
        event: String,
        metadata: [String: String] = [:]
    ) {
        AppDiagnostics.record(category: .auth, level: level, event: event, metadata: metadata)
    }

    private func baseAuthMetadata(domain: String, clientId: String, redirectURI: String) -> [String: String] {
        [
            "domain": sanitizeDiagnosticValue(domain),
            "client_id": clientIdDiagnosticToken(clientId),
            "callback_scheme": sanitizeDiagnosticValue(authCallbackScheme),
            "redirect_uri": sanitizeDiagnosticValue(redirectURI),
            "keychain_backend": "standard",
        ]
    }

    private func signInFailureMessage(for error: Error) -> String {
        if case KeychainStore.KeychainError.unhandled = error {
            return "Credential save failed."
        }
        return "Token exchange failed."
    }

    private func authErrorMetadata(_ error: Error) -> [String: String] {
        var metadata = [
            "error_class": String(describing: type(of: error)),
            "error": sanitizeDiagnosticValue(String(describing: error)),
        ]

        if let urlError = error as? URLError {
            metadata["url_error_code"] = String(urlError.code.rawValue)
        }

        if case let KeychainStore.KeychainError.unhandled(status) = error {
            metadata["keychain_status"] = String(status)
        }

        return metadata
    }

    private func clientIdDiagnosticToken(_ clientId: String) -> String {
        guard clientId.count > 6 else { return "len:\(clientId.count)" }
        return "..." + clientId.suffix(6)
    }

    private func sanitizeDiagnosticValue(_ value: String, limit: Int = 600) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "...<truncated>"
    }
}

extension CognitoAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        currentPresentationAnchor()
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.orderedWindows.first(where: \.isVisible)
            ?? NSApp.windows.first
            ?? NSWindow()
    }
}

#if DEBUG
extension CognitoAuthService {
    func _test_normalizeDomain(_ rawDomain: String) -> String {
        normalizeDomain(rawDomain)
    }

    func _test_formURLEncodedString(_ fields: [String: String]) -> String? {
        guard let encoded = formURLEncoded(fields) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    static func _test_extractEmail(from idToken: String) -> String? {
        extractEmail(from: idToken)
    }

    func _test_setPendingState(_ state: String?, codeVerifier: String?) {
        pendingState = state
        pendingCodeVerifier = codeVerifier
    }

    func _test_handleAuthCallback(
        _ callbackURL: URL?,
        error: Error?,
        domain: String,
        clientId: String,
        redirectURI: String
    ) async {
        await handleAuthCallback(
            callbackURL,
            error: error,
            domain: domain,
            clientId: clientId,
            redirectURI: redirectURI
        )
    }

    static func _test_resolveAuthCallbackScheme() -> String {
        resolveAuthCallbackScheme()
    }

    static func _test_resolveKeychainService() -> String {
        resolveKeychainService()
    }

    static func _test_keychainBackend() -> String {
        "standard"
    }
}
#endif
