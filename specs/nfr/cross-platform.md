# NFR: Cross-Platform Support

## Scope

Requirements for supporting multiple operating systems with a single codebase.

## Requirements

### OS-1: Target Platforms

- **macOS**: macOS 26 (Tahoe) and later. ARM64 (Apple Silicon) primary.
- **Windows**: Windows 10 1903+ (x86_64 primary, ARM64 secondary).
- **Linux**: Not in initial scope. Architecture MUST NOT preclude future support.

### OS-2: Platform Abstraction

- All platform-specific behavior MUST be isolated behind shared trait interfaces.
- Platform implementations MUST live in conditionally compiled modules.
- Core application logic MUST compile and pass tests on all supported platforms with zero platform-specific code.

### OS-3: File System

- Path handling MUST use platform-agnostic abstractions — never hardcoded separators or directory paths.
- Application data, configuration, and temporary files MUST use OS-designated standard directories.

### OS-4: Credential Storage

- Secrets MUST use OS-native secure storage via a unified trait abstraction.

### OS-5: Packaging and Distribution

- Each platform MUST produce a native installer/package format.
- Auto-update MUST use platform-appropriate mechanisms with signature verification.

### OS-6: UI Consistency

- The UI rendering layer MUST be tested on all supported platform WebView engines.
- Native window chrome MUST follow platform conventions (title bar, window controls).
- Keyboard shortcuts MUST respect platform modifier conventions (⌘ on macOS, Ctrl on Windows).

### OS-7: CI

- CI MUST build and test on all supported platforms.
- Platform-specific tests MUST be tagged and run only on their target OS.
- Release artifacts MUST be produced for all supported platform/architecture combinations.

## Verification

- CI matrix covers all supported OS + architecture combinations.
- Cross-platform integration tests for: persistence, process spawning, credential storage, path handling.
- Manual smoke test on each platform before release.
