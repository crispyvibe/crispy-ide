# App Updates — Technical Design

## Overview

Crispy uses Sparkle (`SPUStandardUpdaterController`) as the sole in-app update mechanism. The app consumes a configurable Sparkle appcast feed URL, and update ordering is determined by the monotonic build number (`CFBundleVersion`). The display version (`CFBundleShortVersionString`) is cosmetic and may stay stable across releases.

## Architecture

### Sparkle Integration

- `SPUStandardUpdaterController` is initialized at app launch with `startingUpdater: true`.
- `AppDelegate` conforms to `SPUUpdaterDelegate` and provides the feed URL via `feedURLString(for:)`.
- Sparkle can be disabled entirely via Info.plist key `CrispyVibesEnableSparkleUpdater` (boolean or string `"0"`/`"false"`/`"no"` to disable).

### Feed URL Resolution

1. UserDefaults key `appUpdateFeedURL` (trimmed; empty falls through).
2. Info.plist key `CrispyVibesAppUpdateFeedURL`.
3. Hardcoded fallback: `https://crispyvibe.com/updates/macos/appcast.xml`.
4. URL must have a scheme to be valid.

Sparkle uses the resolved URL directly as its appcast feed.

## Data Flow

### Auto-Check Flow

1. App launch initializes `SPUStandardUpdaterController` with `startingUpdater: true`.
2. Sparkle manages automatic update scheduling based on its own preferences and configured interval.
3. Sparkle fetches the appcast, compares the remote build to the installed build, and presents update UI when appropriate.

### Manual Check Flow

1. User clicks "Check Now" in Settings → Updates.
2. `.checkForAppUpdates` notification is posted.
3. `AppDelegate` calls `performSparkleManualUpdateCheck()`.
4. Sparkle performs a manual check and owns the user-facing result UI.

### Runtime Reconfiguration

- `UserDefaults.didChangeNotification` detects changes to auto-check toggle or feed URL.
- Sparkle updater is reconfigured and its update cycle is reset.

## API / Command Contracts

### Notification

- `.checkForAppUpdates` — triggers manual Sparkle update check.

## State Management

| Key | Storage | Purpose |
|---|---|---|
| `autoUpdateChecksEnabled` | UserDefaults | Auto-check toggle (default: true) |
| `appUpdateFeedURL` | UserDefaults | User-configured feed URL override |

## Dependencies (frameworks, libraries)

- `Sparkle` — `SPUStandardUpdaterController`, `SPUUpdaterDelegate`
- `Foundation` — `UserDefaults`, `NotificationCenter`

## Platform Considerations

- Sparkle handles code signing verification, delta updates, and installation prompts natively on macOS.
- Feed URL validation requires a scheme; schemeless URLs are rejected.
- `CFBundleVersion` is the canonical update-order value. `CFBundleShortVersionString` is for display only.

## Performance Constraints

- Sparkle owns update cadence and network scheduling.
- CrispyVibes should not reintroduce a parallel appcast/JSON polling loop in the app process.

## Migration / Rollout Notes

- Legacy JSON update metadata remains published for website and packaging workflows, but it is no longer used by the live app runtime.
