import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class CognitoAuthServiceTests: XCTestCase {
    func testTokenSetCodableRoundTrip() throws {
        let original = CognitoTokenSet(
            accessToken: "access-token",
            idToken: "id-token",
            refreshToken: "refresh-token",
            expiresIn: 3600,
            tokenType: "Bearer"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CognitoTokenSet.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testSignInValidationRejectsMissingDomainAndClientID() {
        let service = CognitoAuthService()

        service.signInWithApple(domain: "   ", clientId: "client-id")
        XCTAssertEqual(
            service.lastErrorMessage,
            "Missing Cognito domain (example: auth.crispyvibe.com)."
        )

        service.signInWithApple(domain: "https://", clientId: "client-id")
        XCTAssertEqual(
            service.lastErrorMessage,
            "Missing Cognito domain (example: auth.crispyvibe.com)."
        )

        service.signInWithApple(domain: "auth.example.com", clientId: "   ")
        XCTAssertEqual(
            service.lastErrorMessage,
            "Missing macOS app client id (from CDK output)."
        )
    }

    func testSignOutClearsPublishedSessionState() {
        let service = CognitoAuthService()
        service.signOut()

        XCTAssertFalse(service.isSignedIn)
        XCTAssertNil(service.tokenSet)
        XCTAssertNil(service.userEmail)
    }

    func testHelperNormalizationAndFormEncoding() {
        let service = CognitoAuthService()

        XCTAssertEqual(
            service._test_normalizeDomain(" https://auth.example.com/// "),
            "auth.example.com"
        )
        XCTAssertEqual(
            service._test_normalizeDomain("http://example.com/"),
            "example.com"
        )
        XCTAssertEqual(
            service._test_formURLEncodedString([
                "scope": "openid email",
                "client_id": "my+client",
                "redirect_uri": "crispyvibes://callback?x=1&y=2"
            ]),
            "client_id=my%2Bclient&redirect_uri=crispyvibes://callback?x%3D1%26y%3D2&scope=openid%20email"
        )
    }

    func testExtractEmailFromJWTLikeTokenPayload() {
        let header = base64URLEncodedString(Data("{}".utf8))
        let payload = base64URLEncodedString(Data("{\"email\":\"unit@test.local\"}".utf8))
        let token = "\(header).\(payload).sig"

        XCTAssertEqual(CognitoAuthService._test_extractEmail(from: token), "unit@test.local")
        XCTAssertNil(CognitoAuthService._test_extractEmail(from: "invalid"))
    }

    func testHandleAuthCallbackValidationAndFailureBranches() async {
        let service = CognitoAuthService()

        service._test_setPendingState("state", codeVerifier: "verifier")
        await service._test_handleAuthCallback(
            nil,
            error: nil,
            domain: "auth.example.com",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "Missing callback URL.")

        service._test_setPendingState("state", codeVerifier: "verifier")
        await service._test_handleAuthCallback(
            URL(string: "crispyvibes://callback?error=access_denied&error_description=Denied"),
            error: nil,
            domain: "auth.example.com",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "Denied")

        service._test_setPendingState("state", codeVerifier: "verifier")
        await service._test_handleAuthCallback(
            URL(string: "crispyvibes://callback?state=state"),
            error: nil,
            domain: "auth.example.com",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "Missing authorization code.")

        service._test_setPendingState("expected", codeVerifier: "verifier")
        await service._test_handleAuthCallback(
            URL(string: "crispyvibes://callback?code=abc&state=other"),
            error: nil,
            domain: "auth.example.com",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "State mismatch.")

        service._test_setPendingState("expected", codeVerifier: nil)
        await service._test_handleAuthCallback(
            URL(string: "crispyvibes://callback?code=abc&state=expected"),
            error: nil,
            domain: "auth.example.com",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "Missing code verifier.")

        service._test_setPendingState("expected", codeVerifier: "verifier")
        await service._test_handleAuthCallback(
            URL(string: "crispyvibes://callback?code=abc&state=expected"),
            error: nil,
            domain: "bad domain",
            clientId: "client-id",
            redirectURI: "crispyvibes://callback"
        )
        XCTAssertEqual(service.lastErrorMessage, "Token exchange failed.")
    }

    func testResolvedDefaultsForSchemeAndKeychainServiceAreStable() {
        let callbackScheme = CognitoAuthService._test_resolveAuthCallbackScheme()
        let keychainService = CognitoAuthService._test_resolveKeychainService()

        XCTAssertFalse(callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(keychainService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(keychainService.hasSuffix(".cognito"))
        XCTAssertEqual(CognitoAuthService._test_keychainBackend(), "standard")
    }

    private func base64URLEncodedString(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
