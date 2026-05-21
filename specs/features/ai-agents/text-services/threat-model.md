# Text Services — Threat Model

## Overview

Text Services registers macOS system services (rephrase, research, openInTerminal) that invoke external CLI tools with user-selected text. The primary threat surface is process spawning: user text is passed as a CLI argument, and the CLI executable path is user-configured. The feature performs no direct network I/O itself, but invoked CLI tools may connect to remote AI services.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| macOS Services framework ↔ Crispy app | Text arrives via `NSPasteboard` from any app. Crispy cannot trust the content or length of incoming text. |
| Crispy app ↔ External CLI process | `TextProcessorService` spawns a child process via `/usr/bin/env` with `Process.arguments` array. The CLI executable is resolved from user configuration (`AppPreferences`). |
| CLI stdout ↔ Pasteboard | CLI output is parsed, stripped of ANSI sequences, and written back to the system pasteboard. |
| Environment variables ↔ CLI process | PATH is extended; agent name and timeout are read from environment variables. |

## Attack Surfaces

1. **User-selected text passed as CLI argument** — arbitrary text from any application is appended to the `Process.arguments` array as the final argument (the prompt).
2. **Configured CLI executable path** — stored in `UserDefaults`; a malicious preference write could point to an arbitrary binary.
3. **Prompt template with `{{text}}` placeholder** — user text is interpolated into the template string before being passed as a single argument.
4. **CLI output written to pasteboard** — response text replaces pasteboard contents; malicious CLI output could inject content.
5. **Environment variable `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS`** — controls process timeout; extreme values could cause resource issues.
6. **openInTerminal file/folder URL handling** — URLs from pasteboard are used to open terminal sessions.

## Threats

### F029-T01: Command injection via selected text

- **Vector:** Selected text containing shell metacharacters is passed to the CLI. If the invocation used shell interpolation (`bash -c "..."`) instead of `Process.arguments`, arbitrary commands could execute.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low — current implementation uses `Process.arguments` array via `ManagedProcessRunner`, which does not invoke a shell. The prompt is a single array element.
- **Mitigation:** CLI invocation MUST use `Process.arguments` array exclusively. Code review MUST reject any change introducing shell string interpolation. The prompt is always the last element of the arguments array, never interpolated into other arguments. Linked NFR: SEC-Input-Sanitization.

### F029-T02: Arbitrary binary execution via tampered CLI configuration

- **Vector:** An attacker with access to `UserDefaults` (or the preferences plist) changes the configured CLI command to a malicious binary.
- **Impact:** Arbitrary code execution when the user next invokes rephrase/research.
- **Likelihood:** Very low — requires local file access as the same user, at which point the attacker already has full control.
- **Mitigation:** CLI configuration is user-controlled by design. The app resolves the command via `/usr/bin/env` which searches PATH. No additional validation is feasible without breaking legitimate custom CLI configurations. Document that users should only configure trusted CLI tools. Linked NFR: SEC-Input-Sanitization.

### F029-T03: Resource exhaustion via large text chunking

- **Vector:** Text exceeding 4000 characters is split into up to 6 chunks, each spawning a separate CLI process. Extremely large selections (24,000+ chars) spawn 6 concurrent processes with 20-second timeouts each.
- **Impact:** CPU and memory pressure; potential main-thread stall if not properly dispatched.
- **Likelihood:** Low — chunk count is capped at 6; timeout is bounded.
- **Mitigation:** Chunk count is hard-capped at `maximumPromptChunkCount = 6`. Each process respects the configurable timeout (default 20s). Processes are spawned via `ManagedProcessRunner` which terminates on timeout. Total text processed is capped at ~24,000 characters. Linked NFR: PERF-Responsiveness.

### F029-T04: Pasteboard data leakage from CLI output

- **Vector:** A malicious or compromised CLI tool returns crafted output that, when placed on the pasteboard, could be pasted into sensitive contexts (e.g., terminal commands, code editors) without the user realizing the content was modified.
- **Impact:** User unknowingly pastes malicious content.
- **Likelihood:** Low — user explicitly invoked the service and sees the result.
- **Mitigation:** ANSI sequences are stripped from output. The response is extracted from a specific region (after the last `>` marker, before timing metadata). Only non-empty extracted text replaces the pasteboard. The user must explicitly paste the result. Linked NFR: SEC-Data-Protection.

### F029-T05: Path traversal via openInTerminal URL

- **Vector:** A crafted file URL passed via pasteboard to `openInTerminal` could reference a path outside the user's expected workspace (e.g., `/etc/`, `/tmp/malicious/`).
- **Impact:** Terminal opens at an unexpected directory; user may execute commands in a wrong context.
- **Likelihood:** Low — URLs are validated with `standardizedFileURL` and `fileExists` check. Only existing paths are accepted.
- **Mitigation:** URLs are normalized via `standardizedFileURL` (resolves symlinks and `..` components). Only URLs that pass `FileManager.fileExists` are accepted. The terminal opens at the path but does not execute any commands automatically. Linked NFR: SEC-Input-Sanitization.

### F029-T06: Timeout bypass via environment variable manipulation

- **Vector:** Setting `CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS` to an extremely large value (e.g., 999999) causes CLI processes to run indefinitely, consuming resources.
- **Impact:** Resource exhaustion; unresponsive service.
- **Likelihood:** Very low — requires environment variable access as the same user.
- **Mitigation:** The timeout is read from the environment but the process is still killable. Consider adding an upper bound cap (e.g., 120 seconds) regardless of environment variable value. Linked NFR: PERF-Responsiveness.

## Residual Risks

- The configured CLI tool itself may perform network I/O, send data to third-party services, or behave maliciously. This is outside Crispy's control — the user is responsible for configuring trusted tools.
- A user with write access to `~/Library/Preferences/` can manipulate any UserDefaults-stored configuration. This is inherent to macOS app architecture.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array; no shell interpolation; URL normalization. |
| SEC-Data-Protection | Compliant | ANSI stripping; bounded output extraction; no secrets persisted. |
| PERF-Responsiveness | Compliant | Timeout enforced; chunk count capped at 6. |
| A11Y | Compliant | Services accessible via macOS accessibility APIs. |
| OBS | Compliant | Service invocations logged via OSLog. |
