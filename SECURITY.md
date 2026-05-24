# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release via Homebrew (`brew install --cask crispyvibe/crispy/crispy`) | ✅ |
| Previous minor releases | Security fixes only |
| Pre-release / development builds | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability in Crispy, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email: **hello@crispyvibe.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Impact assessment (if known)

We will acknowledge receipt within 48 hours and provide an initial assessment within 5 business days.

## Security Architecture

Crispy is a native macOS application (Swift/SwiftUI, macOS 26+). Key security controls:

- **Code signing and notarization** — all releases are signed with a Developer ID certificate and notarized by Apple
- **Sparkle update verification** — updates are verified with EdDSA signatures before installation
- **Config integrity** — workspace and project configuration files are HMAC-SHA256 signed; tampered configs are treated as untrusted and block startup command execution
- **Keychain storage** — HMAC signing keys and authentication tokens are stored in the macOS Keychain, scoped to the app bundle ID
- **SSH key-based auth only** — remote development uses key-based SSH authentication; password auth is intentionally unsupported
- **Atomic file writes** — persistence uses atomic writes for crash safety

For the full threat model, see [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).

## Distribution

Crispy is distributed through:
- **Homebrew Cask** — `brew install --cask crispyvibe/crispy/crispy`
- **Direct download** — signed and notarized `.dmg` from [crispyvibe.com](https://crispyvibe.com)

Always verify you are downloading from official sources.

## Scope

The following are in scope for security reports:
- The Crispy macOS application
- Workspace config integrity bypass
- Shell command injection via any input path
- SSH/SFTP connection security issues
- Authentication token handling
- Update mechanism vulnerabilities
- macOS Service handler input validation

Out of scope:
- Vulnerabilities in third-party dependencies (report to upstream maintainers)
- Issues requiring physical access to an unlocked machine
- Social engineering attacks

For detailed threat models, see `specs/security/`