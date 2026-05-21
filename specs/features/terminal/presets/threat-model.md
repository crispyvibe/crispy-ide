# Terminal Presets — Threat Model

## Overview

Terminal Presets provides a launcher for AI coding tools (Kiro, Claude, Codex, Gemini, OpenCode, Copilot) and user-defined shortcuts. It performs executable availability diagnostics against PATH and fallback directories, then dispatches preset commands into interactive terminal sessions. The threat surface centers on executable path resolution trust, command injection via preset definitions, PATH manipulation affecting diagnostics, and the Full Trust mode escalation boundary.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app process ↔ Shell (via terminal session) | Preset commands are dispatched via `session.sendUICommand(command)` which enqueues text for delivery to the running shell. The shell interprets the command — Crispy does not execute it directly. |
| Preset definition (hardcoded) ↔ Command dispatch | Built-in preset definitions are compile-time constants in `TerminalPresetDefinition`. Their `defaultCommand` and `fullTrustCommand` strings are trusted app code. |
| PATH diagnostics ↔ FileManager | `TerminalPresetAvailabilityDiagnostics` checks `FileManager.isExecutableFile(atPath:)` for each candidate path. The PATH is resolved via `CommandPathResolver.searchPaths()`. |
| UserDefaults ↔ Diagnostics cache | Detected installed tool IDs are cached in UserDefaults with a version key. Stale or tampered cache could show/hide presets incorrectly. |
| Launch mode (Standard/Full Trust) ↔ Command selection | The `TerminalPresetLaunchMode` determines which command string is dispatched. Full Trust mode uses a different (more permissive) command variant. |

## Attack Surfaces

1. **Preset command strings dispatched to shell** — `launchPreset()` calls `session.sendUICommand(command)` where `command` is `preset.command(for: mode)`. The command is interpreted by the user's interactive shell.
2. **Executable availability diagnostics** — `detectInstalledPresetIDs()` extracts the first whitespace-delimited token from `defaultCommand` and checks if it exists on PATH. A malicious binary at a higher-priority PATH location could satisfy the check.
3. **PATH resolution via `CommandPathResolver.searchPaths()`** — The search paths include user-writable directories (e.g., `~/.local/bin`, Homebrew paths). Symlink or binary substitution attacks are possible.
4. **UserDefaults diagnostics cache** — Cached installed tool IDs in UserDefaults could be manipulated to force-show a preset that is not actually installed, or hide one that is.
5. **Full Trust mode command escalation** — `fullTrustCommand` may grant broader permissions to AI tools (e.g., `--dangerously-skip-permissions`). The mode selector persists in app storage.
6. **UI test override environment variable** — `CRISPYVIBES_UI_TEST_TERMINAL_TOOLS` can override detected presets. Only active when `CRISPYVIBES_UI_TEST_MODE=1`.

## Threats

### F005-T01: Command injection via crafted preset command in shell context

- **Vector:** Preset commands are dispatched as text into an interactive shell. If a preset command contained shell metacharacters (`;`, `&&`, `$(...)`, backticks), they would be interpreted by the shell.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Very low for built-in presets (hardcoded at compile time). Not applicable to user-defined presets since users intentionally write their own commands.
- **Mitigation:** Built-in preset commands are compile-time constants reviewed in code. They contain only the tool executable name and flags (e.g., `kiro`, `claude --dangerously-skip-permissions`). No user input is interpolated into preset command strings. The comment in `launchPreset()` explicitly notes that shell PATH resolution is delegated to the interactive shell. Linked NFR: SEC-Input-Sanitization.

### F005-T02: Malicious binary satisfying PATH diagnostics

- **Vector:** An attacker places a malicious executable named `kiro`, `claude`, etc. in a directory that appears early in `CommandPathResolver.searchPaths()` (e.g., `~/.local/bin`). The diagnostics report the tool as "installed" and the user launches it.
- **Impact:** Arbitrary code execution when the user launches the preset.
- **Likelihood:** Low — requires write access to a PATH directory. This is a general PATH trust issue, not specific to Crispy.
- **Mitigation:** Crispy's diagnostics only check existence and executability — they do not verify binary signatures or provenance. This matches the behavior of running the same command in any terminal. The GUI comment in `launchPreset()` explicitly delegates PATH resolution to the shell, noting that the GUI's PATH misses version-manager installs. Users who install tools accept PATH trust. Linked NFR: SEC-Input-Sanitization.

### F005-T03: Full Trust mode unintentional escalation

- **Vector:** A user switches to "Full Trust" mode and forgets to switch back. Subsequent preset launches use `fullTrustCommand` which may grant AI tools broader filesystem or execution permissions (e.g., `--dangerously-skip-permissions`).
- **Impact:** AI coding tools operate with elevated trust, potentially making destructive changes without confirmation.
- **Likelihood:** Medium — the mode persists in app storage across restarts. Users may not notice the mode indicator.
- **Mitigation:** The mode selector is visible in the terminal tab bar UI. Presets without a `fullTrustCommand` are disabled in Full Trust mode (`supportsFullTrust` check). The mode name "Full Trust" is intentionally alarming. An error message is shown if a preset doesn't support the selected mode. Linked NFR: SEC-Data-Protection.

### F005-T04: Diagnostics cache poisoning via UserDefaults manipulation

- **Vector:** An attacker or malicious profile modifies UserDefaults to inject tool IDs into the cached installed tools list, causing presets to appear available when the actual binary is missing or different.
- **Impact:** User attempts to launch a preset that doesn't exist (benign — shell returns "command not found") or a different binary runs under the expected name.
- **Likelihood:** Very low — requires write access to the app's UserDefaults plist.
- **Mitigation:** The diagnostics cache includes a version key (`currentVersion = 2`). Version mismatch triggers re-detection. The cache only affects UI visibility — actual execution depends on the shell finding the binary. A missing binary produces a shell error, not a crash. Linked NFR: SEC-Data-Protection.

### F005-T05: UI test environment variable override in production

- **Vector:** If `CRISPYVIBES_UI_TEST_MODE=1` and `CRISPYVIBES_UI_TEST_TERMINAL_TOOLS` are set in the production environment, the diagnostics bypass real detection and show arbitrary preset IDs.
- **Impact:** Presets shown as available when they are not (benign shell error on launch).
- **Likelihood:** Very low — these environment variables are only set in Xcode test schemes. Production app launches do not inherit them.
- **Mitigation:** The override requires both `CRISPYVIBES_UI_TEST_MODE=1` AND a specific tools override variable. Normal app launches via Finder/Dock do not inherit arbitrary environment variables. The override only affects UI display, not command content. Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- Preset commands are executed in the user's interactive shell with full user privileges. Crispy cannot sandbox or restrict what the launched AI tool does once running.
- The Full Trust mode is a user choice. Crispy warns via naming but cannot prevent a user from operating in Full Trust mode indefinitely.
- PATH trust is a system-level concern. Any binary on PATH is trusted equally by the shell, regardless of whether Crispy or the user invoked it.
- Built-in preset definitions are not updatable without an app update. A compromised app binary could contain malicious preset commands, but this applies to any compiled code.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Preset commands are compile-time constants; no user input interpolation; executable names extracted via whitespace split only. |
| SEC-Data-Protection | Compliant | Mode persisted in app storage (UserDefaults); diagnostics cache versioned; no secrets stored. |
| PERF-Responsiveness | Compliant | Diagnostics complete within 500ms per acceptance criteria; results cached in UserDefaults. |
| A11Y | Partial | Error banner is dismissible per spec; keyboard navigation of preset menu is standard SwiftUI. |
| OBS | Compliant | Preset launches logged via terminal lifecycle events. |
