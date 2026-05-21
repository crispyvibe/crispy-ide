# Authentication — Technical Design

## Overview

Authentication uses AWS Cognito hosted UI with Apple sign-in, OAuth 2.0 Authorization Code flow with PKCE (S256), and macOS data-protection Keychain for token persistence. `CognitoAuthService` manages the full lifecycle: sign-in initiation, callback validation, token exchange, keychain storage, and sign-out.

## Architecture

### Core Components

- `CognitoAuthService` — `ObservableObject` service (inherits `NSObject`) owning auth state (`tokenSet`, `userEmail`, `lastErrorMessage`). Initiates `ASWebAuthenticationSession`, validates callbacks, exchanges codes for tokens, and manages keychain persistence.
- `ASWebAuthenticationSession` — system-provided browser session for the Cognito hosted UI sign-in flow.
- Keychain — `GenericPassword` item scoped to the app's auth service for token storage.

### Configuration Resolution

| Key | Source | Fallback |
|---|---|---|
| Cognito domain | Info.plist `CrispyVibesCognitoDomain` | `auth.crispyvibe.com` |
| Client ID | Info.plist `CrispyVibesCognitoMacClientId` | empty string |
| Callback scheme | Info.plist `CrispyVibesAuthCallbackScheme` | bundle identifier |
| Keychain service | Info.plist `CrispyVibesAuthKeychainService` | `{bundleID}.cognito` |

## Data Flow

### Sign-In Flow

1. User taps "Continue with Apple" in Account settings.
2. `CognitoAuthService` generates a 32-byte URL-safe random PKCE code verifier and computes the SHA-256 code challenge (base64url-encoded).
3. A random `state` parameter is generated and stored.
4. `ASWebAuthenticationSession` opens `https://<domain>/oauth2/authorize` with parameters: `identity_provider=SignInWithApple`, `scope=openid email profile`, `response_type=code`, `code_challenge_method=S256`, `code_challenge`, `state`, `client_id`, `redirect_uri`.
5. User completes Apple sign-in in the system browser sheet.
6. Callback URL returns with `code` and `state` parameters.
7. `state` is validated against the stored pending state; mismatch produces "State mismatch" error.
8. Authorization code is exchanged at `https://<domain>/oauth2/token` with the PKCE code verifier.
9. Returned token set (access token, ID token, refresh token) is persisted to keychain.
10. User email is extracted from the ID token JWT payload.

### Sign-Out Flow

1. User taps "Sign Out" in Account settings.
2. Token set is deleted from keychain.
3. `tokenSet` and `userEmail` are cleared.
4. UI reverts to signed-out state.

### Presentation Anchor Resolution

`ASWebAuthenticationSession` requires a presentation anchor window. Resolution order:

1. Preferred presentation anchor (if visible)
2. Key window
3. Main window
4. First ordered visible window
5. Any window

## API / Command Contracts

### OAuth Endpoints

| Endpoint | URL |
|---|---|
| Authorize | `https://<domain>/oauth2/authorize` |
| Token | `https://<domain>/oauth2/token` |

### PKCE Parameters

- Code verifier: 32-byte cryptographically random, URL-safe base64 encoded.
- Code challenge: SHA-256 digest of verifier, base64url encoded.
- Challenge method: `S256`.

## State Management

- `CognitoAuthService` is `ObservableObject`; `tokenSet`, `userEmail`, and `lastErrorMessage` drive the Account settings UI. Inherits from `NSObject`.
- Token set persisted as a `GenericPassword` keychain item with accessibility `afterFirstUnlockThisDeviceOnly` and data-protection keychain flag enabled.
- User cancellation (`ASWebAuthenticationSessionError.canceledLogin`) is silently ignored — no error message, auth state unchanged.
- Auth errors (missing domain, missing client ID, bad callback, token exchange failure, state mismatch) set `lastErrorMessage` and display inline in the Account settings card with a warning icon.

## Dependencies (frameworks, libraries)

- `AuthenticationServices` — `ASWebAuthenticationSession`, `ASWebAuthenticationPresentationContextProviding`
- `Security` — Keychain Services for token persistence
- `CryptoKit` — SHA-256 for PKCE code challenge
- `Foundation` — JWT payload decoding (base64), URL construction

## Platform Considerations

- Data-protection keychain ensures tokens are not accessible before first device unlock.
- `afterFirstUnlockThisDeviceOnly` prevents token migration to other devices.
- Callback scheme must be registered as a URL type in Info.plist for the system to route callbacks.

## Performance Constraints

- Token exchange is a single HTTPS round-trip; no retry logic beyond PKCE validation.
- Keychain reads on launch are synchronous but bounded to a single item lookup.

## Migration / Rollout Notes

_None._
