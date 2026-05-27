# App Settings — Threat Model

## Overview

App Settings manages user preferences via `@AppStorage` (UserDefaults) and a custom `AppShortcutSettingsStore` (JSON persistence). It performs no network I/O itself. The threat surface is limited to local preference tampering, sensitive value exposure in defaults, and injection via user-editable string fields that feed into shell commands or URLs.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App process ↔ UserDefaults plist | Settings are stored in the app's `~/Library/Preferences/` plist. Any process running as the same user can read/write this file. |
| Settings UI ↔ CLI command fields | The `textServiceCLICommand` and `textServiceCLIArguments` fields accept freeform text that is later used to spawn external processes. |
| Settings UI ↔ Sparkle feed URL | The `appUpdateFeedURL` field accepts a user-supplied URL that Sparkle will fetch appcast XML from. |
| Settings UI ↔ Cognito domain/client ID | Auth configuration fields are stored in UserDefaults and used to construct OAuth URLs. |

## Attack Surfaces

1. **CLI command and arguments fields** — user-editable strings (`textServiceCLICommand`, `textServiceCLIArguments`) that are passed to process execution for AI text services.
2. **Appcast feed URL** — user-editable URL stored in UserDefaults, consumed by Sparkle for update checks.
3. **UserDefaults plist on disk** — readable/writable by any process running as the same macOS user.
4. **Keyboard shortcut recording** — captures key events that could conflict with system shortcuts or be manipulated to trigger unintended actions.
5. **Cognito domain field** — freeform text used to construct HTTPS URLs for OAuth flows.

## Threats

### F036-T01: Command injection via AI service CLI fields

- **Vector:** A malicious actor (or malicious workspace config import) sets `textServiceCLICommand` to a path containing shell metacharacters, or sets `textServiceCLIArguments` to inject additional arguments.
- **Impact:** Arbitrary command execution as the user when the text service is invoked.
- **Likelihood:** Low — requires local access to UserDefaults or a social-engineering import flow.
- **Mitigation:** CLI command execution MUST use `Process.executableURL` with `Process.arguments` array (no shell interpolation). The command path MUST be validated as an existing executable. Arguments MUST NOT be concatenated into a shell string. Linked NFR: SEC-Input-Sanitization.

### F036-T02: Malicious appcast feed URL leading to rogue updates

- **Vector:** An attacker with local access modifies `appUpdateFeedURL` in UserDefaults to point to a malicious appcast, causing Sparkle to offer a tampered update.
- **Impact:** Installation of malicious code via a fake update.
- **Likelihood:** Low — Sparkle validates Ed25519 signatures on update packages.
- **Mitigation:** Sparkle's code-signing and Ed25519 signature verification MUST remain enabled. The feed URL field SHOULD display a warning when set to a non-crispyvibe.com domain. Linked NFR: SEC-Data-Protection.

### F036-T03: Sensitive configuration values exposed in UserDefaults

- **Vector:** Cognito domain, client ID, and feed URL are stored in plaintext UserDefaults. A malicious app or script running as the same user can read these values.
- **Impact:** Information disclosure of OAuth configuration (not secrets — tokens are in keychain).
- **Likelihood:** Medium — any same-user process can read defaults.
- **Mitigation:** No secrets (tokens, keys) are stored in UserDefaults — only configuration identifiers. Tokens MUST remain in the data-protection keychain. This is acceptable residual risk for non-secret config. Linked NFR: SEC-Data-Protection.

### F036-T04: Preference tampering causing denial of service

- **Vector:** An attacker modifies UserDefaults to set invalid values (e.g., font size of 0, empty shell path, malformed JSON theme palette) causing crashes or unusable UI on next launch.
- **Impact:** App becomes unusable until defaults are manually reset.
- **Likelihood:** Low — requires same-user local access.
- **Mitigation:** Settings views MUST validate and clamp numeric values to safe ranges. The app MUST fall back to default values when stored preferences fail validation. The Reset category in App Settings provides user-accessible recovery. Linked NFR: PERF-Responsiveness.

### F036-T05: Shortcut recording captures unintended key combinations

- **Vector:** A user accidentally records a shortcut that conflicts with system accessibility shortcuts or security-critical system shortcuts (e.g., screen lock).
- **Impact:** UI confusion; user unable to trigger expected system behavior.
- **Likelihood:** Low.
- **Mitigation:** Shortcut recording SHOULD reject reserved system key combinations (Cmd+Q, Cmd+H, Cmd+Tab). Conflicts with existing app shortcuts MUST be detected and reported to the user. Linked NFR: SEC-Input-Sanitization.

### F036-T06: Accidental destructive vibespace deletion via Settings → VibeSpaces

- **Vector:** A user opens Settings → VibeSpaces, multi-selects rows (Cmd-click) and clicks Delete, or clicks a row's trash icon, intending only a different action. The bulk delete is irreversible: persisted state, terminal entries, browser sessions, project configs, and shortcut overrides are all pruned. If a deleted vibespace is currently active, its in-memory session is closed first.
- **Impact:** Irreversible loss of vibespace state. No undo, no trash bin.
- **Likelihood:** Medium — destructive bulk action is one click + one alert away from a multi-select gesture that's also used for non-destructive operations.
- **Mitigation:** The Delete toolbar button MUST be disabled when selection is empty. Both toolbar Delete and per-row trash MUST present an explicit confirmation alert with single/many message variants before any state is touched. The alert's destructive button MUST be tagged `role: .destructive`; the cancel button MUST be the default. The confirmation message MUST clearly state the action is permanent. Linked NFR: SEC-Data-Protection.

### F036-T07: Project-folder Finder link opens unintended directory

- **Vector:** A vibespace's project paths are stored as plain strings; if storage is tampered with, a path could resolve to a sensitive directory. Clicking the Finder link in the VibeSpaces panel calls `NSWorkspace.shared.open(URL(fileURLWithPath:))` on the stored value.
- **Impact:** Disclosure of an unexpected directory in Finder. No code execution; `NSWorkspace.open` opens the directory listing only.
- **Likelihood:** Low — requires same-user tampering with vibespace persistence files.
- **Mitigation:** Vibespace config files use HMAC-signed JSON (REL-Persistence). Untrusted configs MUST surface a trust prompt before opening. The cell SHOULD also expose the full path via `.help(_:)` so the user can inspect before clicking. Linked NFR: SEC-Data-Protection.

## Residual Risks

- Any process running as the same macOS user can modify UserDefaults. This is an OS-level trust boundary that cannot be mitigated at the application layer without sandboxing.
- The CLI command field inherently allows executing arbitrary binaries — this is by design for user-configured AI services. The risk is limited to the user's own privilege level.
- Bulk vibespace delete is irreversible by design. Confirmation is the only safeguard; there is no trash/undo. Users who confirm in error must restore from a backup.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array used; no shell interpolation for CLI fields. |
| SEC-Data-Protection | Compliant | No secrets in UserDefaults; tokens in keychain only. |
| PERF-Responsiveness | Compliant | Settings view opens within 200ms; validation prevents crash loops. |
| A11Y | Compliant | Full-row click targets; labeled controls. |
