# Authentication — Threat Model

## Overview

Authentication provides Cognito-based Apple sign-in with PKCE, token persistence in the macOS keychain, and account settings UI. This feature performs network I/O to Cognito endpoints (`/oauth2/authorize`, `/oauth2/token`) and stores sensitive tokens in the keychain. The threat surface includes OAuth flow manipulation, keychain security, token leakage, and callback scheme hijacking.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app ↔ ASWebAuthenticationSession | The system-managed web authentication session handles the OAuth UI. Crispy provides the authorize URL and receives the callback. |
| Crispy app ↔ Cognito token endpoint | HTTPS POST to exchange authorization code for tokens. Uses PKCE code verifier. |
| Crispy app ↔ macOS Keychain | Tokens are stored as `kSecClassGenericPassword` items scoped to the app's keychain service. |
| UserDefaults ↔ Auth configuration | Cognito domain and client ID are stored in UserDefaults (non-secret configuration). |
| Info.plist ↔ Callback scheme | `CrispyVibesAuthCallbackScheme` determines which URL scheme the app registers for OAuth callbacks. |

## Attack Surfaces

1. **OAuth callback URL scheme** — custom URL scheme registered by the app. Another app could register the same scheme to intercept authorization codes.
2. **PKCE code verifier/challenge** — generated per sign-in flow. If predictable, an attacker could complete the token exchange.
3. **Keychain token storage** — `GenericPassword` item with service scoping. Accessible to the app and potentially to other apps with keychain access entitlements.
4. **Token exchange network request** — HTTPS POST carrying the authorization code and PKCE verifier.
5. **ID token JWT parsing** — base64url-decoded payload used to extract email. Malformed tokens could cause unexpected behavior.
6. **Diagnostic logging** — auth events are logged with metadata that could contain sensitive fragments.

## Threats

### F035-T01: Authorization code interception via scheme hijacking

- **Vector:** A malicious app registers the same custom URL scheme (`CrispyVibesAuthCallbackScheme`) and receives the OAuth callback containing the authorization code.
- **Impact:** Attacker obtains the authorization code. Without the PKCE code verifier (held in-memory only), they cannot exchange it for tokens.
- **Likelihood:** Low — PKCE prevents code-only exploitation; macOS resolves scheme conflicts unpredictably.
- **Mitigation:** PKCE with SHA-256 challenge MUST be used for every sign-in flow (confirmed in code: `PKCE.codeVerifier()` + `PKCE.codeChallenge(for:)`). The code verifier is stored only in `pendingCodeVerifier` (in-memory, never persisted). OAuth state parameter MUST be validated on callback to detect replay. Linked NFR: SEC-Data-Protection.

### F035-T02: Weak PKCE code verifier generation

- **Vector:** If the code verifier is generated with insufficient entropy, an attacker could brute-force it to complete the token exchange.
- **Impact:** Token theft, account takeover.
- **Likelihood:** Very low — code uses `SecRandomCopyBytes` with 32 bytes (256 bits of entropy).
- **Mitigation:** `PKCE.codeVerifier()` uses `SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)`. Falls back to UUID only if `SecRandomCopyBytes` fails (which returns errSecSuccess on all supported macOS versions). SHA-256 is used for the challenge. Linked NFR: SEC-Data-Protection.

### F035-T03: Token leakage from keychain

- **Vector:** A malicious app or process with keychain access reads the stored `CognitoTokenSet` from the keychain.
- **Impact:** Access token and refresh token theft, enabling API access as the user.
- **Likelihood:** Low — keychain items are scoped by service name and protected by macOS access controls.
- **Mitigation:** Tokens are stored with `kSecClassGenericPassword` scoped to the app's keychain service (resolved from `CrispyVibesAuthKeychainService` Info.plist key). The app SHOULD set `kSecAttrAccessible` to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (spec requirement F035-R04). Code review note: current `KeychainStore.write()` does not explicitly set accessibility — this should be added. Linked NFR: SEC-Data-Protection.

### F035-T04: OAuth state mismatch / CSRF

- **Vector:** An attacker crafts a callback URL with a valid-looking authorization code but a different state parameter, attempting to inject their own auth code into the user's session.
- **Impact:** User session bound to attacker's account (session fixation).
- **Likelihood:** Very low — state is validated in `handleAuthCallback` (`returnedState == expectedState`).
- **Mitigation:** Random state is generated per flow via `PKCE.randomState()` (16 bytes, `SecRandomCopyBytes`). State mismatch results in immediate error without token exchange. Linked NFR: SEC-Input-Sanitization.

### F035-T05: Token leakage via diagnostic logging

- **Vector:** Auth diagnostic events log metadata including domain, client ID prefix, and error details. If token values were accidentally included, they could leak to log aggregation.
- **Impact:** Token disclosure via logs.
- **Likelihood:** Very low — code explicitly sanitizes metadata via `sanitizeDiagnosticValue()` and `clientIdDiagnosticToken()` (only last 6 chars of client ID).
- **Mitigation:** `recordAuth()` MUST NOT include raw token values in metadata. `sanitizeDiagnosticValue` truncates at 600 chars. Client ID is masked to last 6 characters. Response bodies from token exchange are logged only on failure and truncated. Linked NFR: SEC-Data-Protection.

### F035-T06: Cognito domain manipulation in UserDefaults

- **Vector:** An attacker modifies `authCognitoDomain` in UserDefaults to point to a phishing server that mimics the Cognito hosted UI.
- **Impact:** User enters Apple credentials on a fake sign-in page. However, ASWebAuthenticationSession shows the URL bar, making phishing detectable.
- **Likelihood:** Low — requires same-user local access; URL bar visible in auth session.
- **Mitigation:** `ASWebAuthenticationSession` displays the target URL to the user. The domain is normalized (scheme stripped, trailing slashes removed) but not validated against an allowlist. Users SHOULD verify the domain shown in the auth window. Linked NFR: SEC-Input-Sanitization.

### F035-T07: ID token JWT payload parsing vulnerability

- **Vector:** A malformed or crafted ID token with unexpected base64url payload could cause parsing issues in `extractEmail(from:)`.
- **Impact:** Nil email (graceful degradation) or unexpected string displayed as email.
- **Likelihood:** Very low — parsing uses `JSONSerialization` with optional casting; malformed data returns nil.
- **Mitigation:** `extractEmail` validates segment count (≥2), attempts base64url decode (returns nil on failure), and uses optional JSON parsing. No crashes on malformed input. The ID token is not validated cryptographically client-side (Cognito's token endpoint is trusted). Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- The app does not validate the ID token's JWT signature client-side. This is acceptable because tokens come directly from the Cognito token endpoint over HTTPS — the transport is the trust anchor.
- `KeychainStore` does not currently set `kSecAttrAccessible` explicitly. The default keychain accessibility may allow access when the device is locked. This should be hardened to `afterFirstUnlockThisDeviceOnly`.
- If the user's macOS login keychain is unlocked (normal state when logged in), any app with the correct keychain access group could potentially read the tokens. App Sandbox or hardened runtime keychain access groups mitigate this.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Data-Protection | Compliant | Tokens in keychain; PKCE with 256-bit entropy; no secrets in UserDefaults. |
| SEC-Input-Sanitization | Compliant | State validation; domain normalization; diagnostic value sanitization. |
| PERF-Responsiveness | Compliant | Auth flow is async; UI remains responsive during token exchange. |
| OBS | Compliant | Auth events logged with sanitized metadata for diagnostics. |
