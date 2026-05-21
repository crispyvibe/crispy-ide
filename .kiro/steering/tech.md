# Technology Stack

## Language & Frameworks

- **Language**: Swift 5
- **UI**: SwiftUI with AppKit bridges where needed
- **Platform**: macOS 26+ (Tahoe), ARM64 primary
- **Project**: Xcode project (`crispyvibes.xcodeproj`), not Swift Package Manager
- **App identity**: `Crispy` (`com.crispyvibe.app`)

## Terminal

- **Primary engine**: Ghostty (GhosttyKit) — built from source via Zig, linked as a native framework
- **Fallback engine**: SwiftTerm — pure Swift terminal emulator
- **Build dependency**: Zig toolchain (installed via `scripts/setup-dev.sh`)

## Editor & Rendering

- **Markdown/HTML**: `WKWebView` with bundled markdown runtime assets (`Resources/MarkdownRuntime/`)
- **Code editing**: Native text views with syntax theme support

## Persistence

- **Storage**: JSON files with HMAC signing for integrity
- **Keychain**: macOS Keychain for secrets and signing keys
- **No CoreData, no SwiftData** — all persistence via custom `AppPersistenceDataStore` and `WorkspacePersistenceStore`

## Authentication & Updates

- **Auth**: Amazon Cognito (`CognitoAuthService`)
- **Updates**: Sparkle framework for auto-updates

## Development Tools

- Xcode (build, run, test)
- Zig (GhosttyKit build dependency)
- `xcodebuild` for CI and UI test screenshots

## Constraints

- No SwiftData or Core Data — persistence is JSON-file based
- No Swift Package Manager for the main app — Xcode project with manual framework linking
- GhosttyKit must be built before the app can compile (handled by `setup-dev.sh`)
- All platform-specific AppKit bridges should be isolated and documented
