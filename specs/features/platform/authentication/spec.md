# Authentication — Spec

Status: draft

## Overview

Authentication provides Cognito-based Apple sign-in, token management, account settings UI, and security controls including PKCE, keychain storage, and presentation anchor resolution.

## Dependencies

_None._

## Requirements

### F035-R01: Cognito Apple Sign-In

Users MUST be able to sign in with Apple via Cognito hosted UI using ASWebAuthenticationSession with PKCE.

### F035-R02: Token Persistence

Access, ID, and refresh tokens MUST be persisted to the data-protection keychain after successful sign-in.

### F035-R03: Account Settings UI

Account settings MUST show signed-in state with email and sign-out, or signed-out state with sign-in button.

### F035-R04: Auth Security

PKCE MUST use SHA-256, tokens MUST use data-protection keychain, and callback scheme MUST resolve from Info.plist.

## Scenarios

### Scenario F035-S01: User signs in with Apple via Cognito hosted UI

**Given** the user is not signed in
**And** the Account settings pane is open
**When** the user clicks "Continue with Apple"
**Then** an ASWebAuthenticationSession opens the Cognito `/oauth2/authorize` endpoint
**And** the identity_provider is set to SignInWithApple
**And** the OAuth scope includes openid, email, and profile

### Scenario F035-S02: Authorization code is exchanged for tokens using PKCE

**Given** the user completed the Apple sign-in prompt
**When** the Cognito callback returns an authorization code
**Then** the code is exchanged at the `/oauth2/token` endpoint with the PKCE code verifier
**And** the returned access token, id token, and refresh token are persisted to the keychain
**And** the user email is extracted from the id token JWT payload

### Scenario F035-S03: OAuth state parameter is validated on callback

**Given** a sign-in flow is in progress with a generated random state
**When** the callback URL is received
**Then** the returned state must match the pending state
**And** a mismatch results in a "State mismatch" error without token exchange

### Scenario F035-S04: Sign-in errors are surfaced in the account settings UI

**Given** a sign-in attempt fails at any stage (missing domain, missing client id, bad callback, token exchange failure)
**When** the error is captured
**Then** `lastErrorMessage` is set on CognitoAuthService
**And** the account settings card displays the error with a warning icon

### Scenario F035-S05: User-cancelled sign-in is silently ignored

**Given** the ASWebAuthenticationSession is active
**When** the user cancels the sign-in window
**Then** no error message is shown
**And** the auth state remains unchanged

### Scenario F035-S06: Account settings card shows signed-in state

**Given** the user is signed in
**When** the Account settings pane renders
**Then** a checkmark seal icon and "Signed in as {email}" are displayed
**And** a "Sign Out" button is available

### Scenario F035-S07: Account settings card shows signed-out state

**Given** the user is not signed in
**When** the Account settings pane renders
**Then** a "Continue with Apple" primary button is displayed
**And** no sign-out control is shown

### Scenario F035-S08: User signs out from account settings

**Given** the user is signed in
**When** the user clicks "Sign Out"
**Then** the token set is deleted from the keychain
**And** `tokenSet` and `userEmail` are cleared
**And** the UI reverts to the signed-out state

### Scenario F035-S09: PKCE code verifier and challenge use SHA-256

**Given** a sign-in flow is initiated
**When** the PKCE code verifier is generated
**Then** it is a 32-byte URL-safe random string
**And** the code challenge is the base64url-encoded SHA-256 digest of the verifier
**And** the challenge method sent to Cognito is S256

### Scenario F035-S10: Tokens are stored in the data-protection keychain

**Given** a successful token exchange
**When** the token set is persisted
**Then** it is written to a GenericPassword keychain item scoped to the app's auth service
**And** the item accessibility is set to afterFirstUnlockThisDeviceOnly
**And** the data-protection keychain flag is enabled

### Scenario F035-S11: Auth callback scheme and keychain service are resolved from Info.plist

**Given** the app launches
**When** CognitoAuthService initializes
**Then** the callback scheme is read from the CrispyVibesAuthCallbackScheme Info.plist key (falling back to bundle identifier)
**And** the keychain service is read from the CrispyVibesAuthKeychainService Info.plist key (falling back to "{bundleID}.cognito")

### Scenario F035-S12: Presentation anchor resolves to the best available window

**Given** a sign-in flow requires a presentation anchor
**When** the ASWebAuthenticationSession requests an anchor
**Then** the preferred presentation anchor is used if visible
**And** falls back through key window, main window, first ordered visible window, then any window

## Acceptance Criteria

- Sign-in flow completes end-to-end with Apple via Cognito.
- Tokens persist in data-protection keychain across app restarts.
- PKCE uses SHA-256 with 32-byte verifier.
- Sign-in errors display in account settings UI.
- User cancellation produces no error.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/auth/feature.md (AUTH-001–012) | — |
