---
title: "Authentication"
feature: "F035"
domain: "platform"
audience: "user"
version: "1.0"
sidebar:
  label: "Authentication"
  order: 2
---

# Authentication

## Overview

Crispy uses Sign in with Apple via Amazon Cognito to authenticate users for cloud-backed features. Tokens are securely stored in the macOS data-protection keychain, and the entire sign-in flow uses PKCE (SHA-256) for security.

## Getting Started

1. Open **Settings** (Crispy menu → Settings…, or Cmd+,).
2. Navigate to the **Account** category.
3. Click **Continue with Apple** to initiate sign-in.
4. Complete the Apple sign-in prompt in the browser sheet that appears.
5. Once authenticated, your email is displayed in the Account settings card.

## Workflows

### Signing In

1. Open Settings → Account.
2. Click the **Continue with Apple** button.
3. A system authentication sheet opens showing the Cognito hosted UI with Apple sign-in.
4. Authenticate with your Apple ID (Face ID, Touch ID, or password).
5. On success, the Account card updates to show "Signed in as {your email}" with a checkmark seal icon.
6. Tokens are persisted to the keychain — you remain signed in across app restarts.

### Signing Out

1. Open Settings → Account.
2. Click the **Sign Out** button.
3. Tokens are deleted from the keychain.
4. The Account card reverts to showing the "Continue with Apple" button.

### Handling Sign-In Errors

1. If sign-in fails at any stage, an error message appears below the sign-in button with a warning triangle icon.
2. Common errors include:
   - Missing Cognito domain or client ID (configuration issue)
   - Network failures during token exchange
   - State mismatch (security validation failure)
3. If you cancel the sign-in window, no error is shown — the auth state remains unchanged.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Settings | Cmd+, |

No dedicated shortcut for sign-in — access via Settings → Account.

## Settings

| Setting | Location | Description |
|---------|----------|-------------|
| Account status | Settings → Account | Shows signed-in email or sign-in button |
| Cognito domain | App configuration | Set via `CrispyVibesAuthCallbackScheme` in Info.plist |
| Keychain service | App configuration | Set via `CrispyVibesAuthKeychainService` in Info.plist |

## Tips

- Sign-in uses the OAuth 2.0 authorization code flow with PKCE (SHA-256, 32-byte verifier) for maximum security.
- The callback scheme is resolved from the `CrispyVibesAuthCallbackScheme` Info.plist key, falling back to the bundle identifier.
- The keychain service name is resolved from `CrispyVibesAuthKeychainService`, falling back to `{bundleID}.cognito`.
- Tokens are stored with `afterFirstUnlockThisDeviceOnly` accessibility, meaning they are available after the first device unlock but never synced to other devices.
- The presentation anchor for the sign-in sheet resolves through a priority chain: preferred window → key window → main window → first visible ordered window → any window.
- The OAuth scope includes `openid`, `email`, and `profile`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Missing Cognito domain" error | The app's Cognito domain is not configured. This is a build configuration issue — contact the developer. |
| "Missing macOS app client id" error | The Cognito client ID is not configured in the app build. |
| "State mismatch" error | The OAuth state parameter didn't match. Try signing in again — this can happen if the flow was interrupted. |
| "Token exchange failed" error | Network issue during the code-to-token exchange. Check your internet connection and try again. |
| "Credential save failed" error | The keychain write failed. Check that the app has keychain access in System Settings → Privacy & Security. |
| Sign-in window doesn't appear | Ensure the app window is visible. The sign-in sheet requires a presentation anchor (visible window). The error "Open Settings in the app window and try sign-in again" indicates no suitable window was found. |
| Cancelling sign-in shows no feedback | This is expected behavior — cancellation is silently ignored without changing auth state. |
