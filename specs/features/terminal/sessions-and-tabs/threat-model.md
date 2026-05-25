# Terminal Sessions & Tabs — Threat Model

## Overview

Terminal Sessions & Tabs manages shell process lifecycle, environment construction, command dispatch, interactive target detection (URLs, file paths), file drop handling, clipboard operations, and session persistence/restore. It performs no network I/O itself (remote SSH is delegated to the Remote feature). The threat surface centers on shell injection via command dispatch, environment variable manipulation, path traversal through interactive targets and file drops, credential leakage in compose history, and resource exhaustion from unbounded session creation.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app process ↔ Shell process | `TerminalSession.startProcess()` spawns a child process via `TerminalSessionEngine.startProcess(executable:args:environment:currentDirectory:)`. The executable path and arguments are passed as discrete array elements, not shell-interpreted strings. |
| Crispy app process ↔ tmux CLI | When tmux is enabled, `TmuxService.launchArguments()` constructs the argument array. Session names are Crispy-generated UUIDs with a fixed prefix. |
| Terminal output ↔ Interactive target detector | `TerminalInteractiveTargetDetector` parses raw terminal grid text to identify URLs and file paths. Detected targets are used to open files, reveal directories, or navigate to URLs. |
| File drop pasteboard ↔ Terminal input | `TerminalFileDropSupport` reads file URLs from `NSPasteboard` and converts them to shell-escaped path strings injected into the terminal. |
| Compose history ↔ Terminal session | `ComposeHistoryStore` records finalized command text from `recordSentInput()`. The insight observer validates screen visibility before recording. |
| Persistence JSON ↔ Session restore | `TerminalSessionEntry` is decoded from vibespace JSON to restore tabs. Fields include `tmuxSessionName` and working directory paths. |
| Shell environment ↔ Child process | `buildTerminalEnvironment()` constructs environment variables including `PATH`, `CRISPY_SOCKET`, and `CRISPY_PROJECT_PATH`. These are inherited by the spawned shell. |

## Attack Surfaces

1. **Command dispatch pipeline** — `enqueueCommand()` / `dispatchCommand()` sends text to the terminal via `engine.send(text:)`. Commands are newline-terminated strings injected into the running shell.
2. **Interactive target detection** — Parses terminal grid output for URLs and file paths. Malicious terminal output could craft targets that resolve to sensitive paths or exploit URL scheme handlers.
3. **File drop path injection** — Converts dropped file URLs to shell-escaped strings. Malformed filenames could escape the quoting.
4. **Shell resolution chain** — Resolves shell executable from multiple sources (project override, vibespace default, app default, `$SHELL`, `/bin/zsh`). A compromised preference could point to a malicious binary.
5. **Environment variable construction** — `buildTerminalEnvironment()` prepends bundled CLI bin to PATH and injects `CRISPY_SOCKET` path. PATH manipulation could redirect command resolution.
6. **Session persistence** — Working directory paths and tmux session names decoded from JSON. Path traversal or symlink attacks during restore.
7. **Compose history / insight recording** — Records typed commands including potentially sensitive input.
8. **Shortcut command definitions** — User-defined shortcuts stored in UserDefaults as JSON. Command text is dispatched verbatim to the terminal.

## Threats

### F001-T01: Command injection via shortcut definitions

- **Vector:** User-defined shortcut commands are stored in UserDefaults JSON and dispatched verbatim via `dispatchCommand()` which calls `engine.send(text: "\(command)\n")`. If another app or profile sync mechanism writes to the UserDefaults plist, arbitrary commands execute in the user's shell.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low — requires write access to the app's UserDefaults plist or a compromised preferences sync.
- **Mitigation:** Shortcut commands are trimmed and validated for non-empty content in `TerminalShortcutStore.normalized()`. UserDefaults are sandboxed to the app container. No external API accepts shortcut definitions. Linked NFR: SEC-Input-Sanitization.

### F001-T02: Path traversal via interactive file target detection

- **Vector:** A malicious process writes terminal output containing crafted file paths (e.g., `../../../../etc/passwd` or symlinks to sensitive locations). `TerminalInteractiveTargetDetector` resolves these against `currentDirectory` and presents them as clickable targets.
- **Impact:** User inadvertently opens or reveals sensitive files outside the project scope.
- **Likelihood:** Medium — terminal output is attacker-controllable in scenarios like `curl | sh`, CI logs, or SSH sessions.
- **Mitigation:** File targets are resolved via `URL.standardizedFileURL` which canonicalizes path components. The detector caps token length at 512 characters (`maximumInteractiveTokenLength`). Opening a file uses the standard editor infrastructure which respects macOS sandbox and file permissions. Users must explicitly click to act on targets. Linked NFR: SEC-Input-Sanitization.

### F001-T03: Shell escape bypass in file drop handling

- **Vector:** A file with a crafted name (e.g., containing single quotes, backticks, or `$(...)`) is dropped onto the terminal. If `ShellEscaping.singleQuote()` has a bug, the filename could break out of quoting and execute arbitrary commands.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low — `ShellEscaping.singleQuote()` wraps in single quotes where only `'` needs escaping (replaced with `'"'"'`). Single-quote escaping is the most robust shell quoting method.
- **Mitigation:** `TerminalFileDropSupport.escapedDroppedPath()` uses `ShellEscaping.singleQuote()` for all paths. Paths are standardized via `url.standardizedFileURL.path` before escaping. The trailing space prevents accidental concatenation with subsequent input. Linked NFR: SEC-Input-Sanitization.

### F001-T04: Malicious shell executable via preference override

- **Vector:** The shell resolution chain (`TerminalShellResolver.resolve()`) checks project override → vibespace default → app default → `$SHELL` → `/bin/zsh`. A compromised vibespace JSON file could specify a malicious executable path as the project shell override.
- **Impact:** Arbitrary code execution when a terminal tab is created.
- **Likelihood:** Low — vibespace JSON is stored in the user's Application Support directory with HMAC integrity signing.
- **Mitigation:** Shell resolution validates that candidates are executable files via `FileManager.isExecutableFile(atPath:)`. Unavailable candidates fall through to the next level. The HMAC signing on persistence files detects tampering. Linked NFR: SEC-Data-Protection.

### F001-T05: Environment variable injection via CRISPY_SOCKET path

- **Vector:** `injectAgentCLIEnvironment()` sets `CRISPY_SOCKET` to a path under Application Support. If an attacker can create a symlink at that path pointing to a world-writable socket, they could intercept Agent CLI commands.
- **Impact:** Interception of local IPC commands between terminal and Crispy app.
- **Likelihood:** Very low — Application Support directory is user-owned with standard macOS permissions.
- **Mitigation:** The socket path is derived from `Bundle.main.bundleIdentifier` and placed in the user's Application Support directory. macOS file permissions prevent other users from writing to this location. Linked NFR: SEC-Data-Protection.

### F001-T06: Credential capture in compose history

- **Vector:** Compose history records finalized command text submitted from either of two paths: (a) **keystroke path** — characters typed directly into the terminal surface and finalized on Enter by `TerminalInsightObserver.recordTypedKeystroke`; (b) **compose-UI path** — whole commands submitted from a SwiftUI compose field (VibeCast, Spotlight compose, inline triggers) via `TerminalSession.recordSentInput` → `TerminalInsightObserver.recordSubmittedFromComposeUI`. If a user types a password at a visible prompt with echo enabled, or pastes a credential into a compose field, it could be captured in history.
- **Impact:** Credential disclosure within the app's in-memory state.
- **Likelihood:** Medium — some CLI tools prompt for passwords with echo enabled (e.g., `mysql -p`); developers also paste credentials into compose UIs.
- **Mitigation:** The two paths have different invariants and different mitigations:
    - **Keystroke path**: `TerminalInsightObserver.recordTypedKeystroke` defers classification on Enter and verifies that the typed text was rendered on the surface before publishing `.visible(text)`. The check runs immediately and, if the surface has not yet rendered the echoed characters, retries six times at 150 ms intervals up to a 1 s budget. If the surface never showed the text within the budget — the canonical signature of an echo-disabled prompt (`stty -echo`, `read -s`, `sudo` password prompt) — the observer publishes `.sensitive` and the typed bytes are never exposed downstream.
    - **Compose-UI path**: `TerminalInsightObserver.recordSubmittedFromComposeUI` classifies the submitted command as `.visible` by trust boundary — the user authored the text in a visible SwiftUI field and explicitly pressed Send, so a separate surface-inspection check would only false-positive. This is documented as a deliberate trust assumption: any credential pasted into a compose field is treated as visible-by-intent and may appear in compose history and the AI summary.
    - Compose history is fed from a single Combine subscription on `TerminalInsightObserver.$lastRecordedInput` held by `TerminalSession`. Sensitive classifications are dropped at the subscription site by construction — there is no raw-text fallback path. The compose history store is in-memory per session and not persisted to disk. Linked NFR: SEC-Data-Protection.

### F001-T07: Resource exhaustion via unbounded tab creation

- **Vector:** A script or automation rapidly creates terminal tabs (e.g., via shortcut commands or programmatic API), spawning many shell processes and consuming system resources.
- **Impact:** Memory exhaustion, process table saturation, UI unresponsiveness.
- **Likelihood:** Low — tab creation requires user interaction or explicit shortcut invocation.
- **Mitigation:** Each tab creation is mediated through `TerminalViewModel` which is `@MainActor`-bound, serializing creation. Shell processes are tracked and terminated on tab close. Project restart terminates all sessions. No external API allows unbounded tab creation. Linked NFR: PERF-Responsiveness.

### F001-T08: ANSI escape sequence injection via terminal title callback

- **Vector:** A malicious process sets the terminal title (via OSC escape sequences) to a string containing misleading text (e.g., fake directory paths or phishing content). `onTitleChanged` propagates this to the tab display title.
- **Impact:** UI spoofing — user sees a misleading tab title suggesting they are in a different directory or context.
- **Likelihood:** Medium — any process running in the terminal can set the title via standard escape sequences.
- **Mitigation:** Tab titles are rendered as plain `Text` in SwiftUI which does not interpret escape sequences or HTML. The title is used for display only and does not influence file operations or command routing. Directory metadata is updated separately via `onDirectoryChanged` from shell integration, not from the title. Linked NFR: SEC-Input-Sanitization.

### F001-T09: Stale session restore from tampered persistence

- **Vector:** An attacker modifies the vibespace JSON to inject working directory paths pointing to sensitive locations. On restore, tabs are created with those directories as CWD.
- **Impact:** Shell processes start in attacker-chosen directories, potentially exposing sensitive files in the working context.
- **Likelihood:** Very low — persistence files are HMAC-signed; tampering invalidates the signature.
- **Mitigation:** Vibespace persistence uses JSON + HMAC signing for integrity. `TerminalSessionEntry` paths are validated during restore — missing directories trigger fallback to project root (F001-R26). The shell process inherits standard user permissions regardless of CWD. Linked NFR: SEC-Data-Protection.

## Residual Risks

- Terminal output is inherently attacker-controllable (any running process can write to stdout). Interactive target detection operates on this untrusted data but requires explicit user click to act.
- The compose history store records commands in memory. A memory dump or debugging tool could extract recent command history. This is equivalent to shell history file exposure.
- Compose-UI submissions are treated as visible-by-trust-boundary; users who paste credentials into VibeCast, Spotlight compose, or inline triggers accept that the content reaches compose history and the AI summary feature like any other typed command.
- A keystroke command that races the streaming-output detection threshold (e.g., a TUI launching with rapid full-redraws within ~0.25 s of Enter) may have its in-flight classification cancelled and therefore miss compose history. Users can retype the command; this trade-off favors the security floor over up-arrow recall completeness.
- Shell processes run with full user privileges. Crispy does not sandbox child processes beyond standard macOS protections.
- `sendRawTextWithEnter()` injects text directly into the terminal PTY. Any caller with access to a `TerminalSession` reference can execute commands. Access is restricted to `@MainActor` code paths within the app.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Shell escaping via `ShellEscaping.singleQuote()`; process arguments as arrays; interactive target token length capped. |
| SEC-Data-Protection | Compliant | HMAC-signed persistence; compose history in-memory only; insight observer validates echo state. |
| PERF-Responsiveness | Compliant | Shell resolution off main actor; command dispatch uses readiness heuristics; idle reset via `DispatchWorkItem`. |
| A11Y | Compliant | Focus coordinator ensures keyboard routability; interactive targets have hover highlights. |
| OBS | Compliant | All lifecycle events logged via `AppDiagnostics` and `TerminalLifecycleLogger`; command hashes logged (not plaintext). |
