# Worker — Threat Model

## Overview

Worker provides the out-of-process pane worker execution model for filesystem, git, editor, and terminal operations. Workers spawn as subprocesses of the app executable, communicate via JSON over stdin/stdout, and execute filesystem operations and git CLI commands. The threat surface includes command injection via git arguments, path traversal in file operations, subprocess resource exhaustion, and information disclosure through error messages.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App process ↔ Worker subprocess | The app spawns itself with `--pane-task <kind>` and communicates via newline-delimited JSON over stdin/stdout pipes. |
| Worker subprocess ↔ Filesystem | Workers perform file create/rename/move/copy/delete and directory listing operations on user-specified paths. |
| Worker subprocess ↔ git CLI | Workers invoke `/usr/bin/env git` with constructed argument arrays for status, diff, branch, commit, push, pull, fetch, checkout, clone, and discovery operations. |
| Worker subprocess ↔ GitHub CLI | `gitHubCloneOptions` invokes `gh` CLI to list repositories. |
| PaneWorkerClient (actor) ↔ PaneWorkerPersistentSession | Long-lived subprocess with request/response multiplexing and generation guards. |

## Attack Surfaces

1. **Git command arguments** — paths and branch names from user/UI input are passed as arguments to `git` via `Process.arguments` array through `runGitCommand`.
2. **File operation paths** — `rootPath`, `relativePath`, `destinationPath` arguments from the UI are used in `FileManager` operations.
3. **Worker subprocess lifecycle** — spawned processes that hang or crash; timeout and generation guard mechanisms.
4. **JSON stdin/stdout protocol** — request/response envelopes parsed from subprocess output.
5. **Git clone URL** — user-provided repository URL passed to `git clone`.
6. **File content read/write** — `readFile` decodes arbitrary file content; `writeFile` persists content atomically.
7. **GitHub CLI invocation** — `gh` CLI executed to list repositories; output parsed as JSON.

## Threats

### F013-T01: Command injection via git arguments

- **Vector:** A malicious branch name, file path, or commit message containing shell metacharacters or git option-like prefixes (e.g., `--upload-pack=evil`) is passed to a git command.
- **Impact:** Arbitrary command execution as the user if arguments are shell-interpreted, or git option injection if not properly separated.
- **Likelihood:** Low — `runGitCommand` uses `runToolCommand` which sets `process.arguments = [tool] + arguments` (no shell interpretation). However, git itself interprets `--` prefixed arguments.
- **Mitigation:** All git invocations MUST use `Process.arguments` array (confirmed: `process.executableURL = envExecutableURL; process.arguments = [tool] + arguments`). Branch names and paths that start with `-` MUST be prefixed with `--` separator in the argument list to prevent git option injection. `sanitizedPathComponent()` is used for rename operations. Linked NFR: SEC-Input-Sanitization.

### F013-T02: Path traversal in file operations

- **Vector:** A crafted `relativePath` argument containing `../` sequences could escape the project root, allowing file creation, rename, move, or deletion outside the intended directory.
- **Impact:** Arbitrary file manipulation within the user's permission scope.
- **Likelihood:** Low — file operations use `URL(fileURLWithPath:)` which resolves relative components, and `standardizedFileURL` normalizes paths.
- **Mitigation:** `moveItem` and `copyItem` use `standardizedFileURL` for both source and destination. `transferItem` validates that the destination is an existing directory. Self-move detection prevents moving a directory into itself. `renameItem` uses `sanitizedPathComponent()` to strip path separators from the new name. File operations SHOULD validate that resolved paths remain within the project root. Linked NFR: SEC-Input-Sanitization.

### F013-T03: Subprocess resource exhaustion

- **Vector:** A worker subprocess hangs (e.g., git command waiting for credentials, network-based git operation stalling) consuming a process slot and blocking subsequent operations.
- **Impact:** Pane becomes unresponsive; status shows "unavailable".
- **Likelihood:** Medium — git push/pull/fetch/clone require network access and may prompt for credentials.
- **Mitigation:** All worker requests have configurable timeouts (default 8s). `executeViaSubprocess` uses a racing task group — timeout fires and terminates the process via `invalidatePersistentSession`. Terminated processes receive SIGTERM then SIGKILL after 1 second (confirmed in `runToolCommand` defer block). Generation guards prevent stale processes from delivering results. Linked NFR: PERF-Responsiveness.

### F013-T04: Git clone URL injection

- **Vector:** A user-provided clone URL like `--upload-pack=malicious` or a URL with embedded credentials (`https://user:pass@host/repo`) is passed to `git clone`.
- **Impact:** Option injection could execute arbitrary commands via git's `--upload-pack` or `--config` options. Embedded credentials in URLs are logged by git.
- **Likelihood:** Low — clone URLs typically come from the GitHub CLI listing or user input in the clone sheet.
- **Mitigation:** Clone arguments MUST use `--` separator before the URL to prevent option injection. The URL SHOULD be validated as a proper URL (scheme + host) before passing to git. `gitCloneRepository` receives source URL and destination path as separate arguments. Linked NFR: SEC-Input-Sanitization.

### F013-T05: Information disclosure via error messages

- **Vector:** Worker error responses include `error.localizedDescription` which may contain file paths, git output with sensitive branch names, or system error details.
- **Impact:** Path and configuration disclosure in UI error messages.
- **Likelihood:** Low — errors are displayed in the app UI, not transmitted externally.
- **Mitigation:** Error messages are user-facing within the local app only. `PaneWorkerResponse` includes the error string for UI display. Paths in errors are not sanitized (acceptable for local-only display). For diagnostics export, the `MeasuredPaneWorker` records error descriptions which are subject to the diagnostics path sanitization. Linked NFR: SEC-Data-Protection.

### F013-T06: Malicious JSON response from compromised subprocess

- **Vector:** If the worker subprocess is somehow compromised (e.g., via a malicious git hook that writes to stdout), it could send crafted JSON responses that cause unexpected behavior in the parent process.
- **Impact:** Incorrect file tree display, false git status, or unexpected UI state.
- **Likelihood:** Very low — the subprocess is the same app executable; git hooks could write to stderr but not to the worker's stdout pipe.
- **Mitigation:** Worker subprocess stdout is the only communication channel. The parent validates response structure via `Codable` decoding (`PaneWorkerSessionResponseEnvelope`). Request IDs are matched (`responseEnvelope.requestID == requestID`). Invalid responses throw `PaneWorkerError.invalidResponse`. Generation guards reject responses from stale sessions. Linked NFR: SEC-Input-Sanitization.

### F013-T07: File content disclosure via readFile

- **Vector:** `readFile` decodes file content in multiple encodings (UTF-8, UTF-16, ISO Latin-1) and returns the full text. If the path argument is manipulated, arbitrary readable files could be returned.
- **Impact:** Disclosure of file contents within the app (local only).
- **Likelihood:** Low — paths come from the file explorer UI which shows the project tree.
- **Mitigation:** `readFile` operates on paths provided by the UI layer. The worker does not validate paths against a project root (by design — editor needs to read any file the user opens). Access is limited to the user's filesystem permissions. This is acceptable for a local IDE. Linked NFR: SEC-Data-Protection.

### F013-T08: Git credential prompt blocking worker

- **Vector:** A git push/pull/fetch operation encounters a repository requiring authentication. Git prompts for credentials on stdin, but the worker's stdin is the JSON request pipe, causing a deadlock.
- **Impact:** Worker hangs until timeout; pane shows unavailable.
- **Likelihood:** Medium — common for HTTPS remotes without credential helpers.
- **Mitigation:** Worker timeout (default 8s) terminates hung processes. `runToolCommand` does not connect stdin to a terminal (git detects non-interactive and fails rather than prompting in most configurations). The `GIT_TERMINAL_PROMPT=0` environment variable SHOULD be set for worker git processes to prevent credential prompts. Linked NFR: PERF-Responsiveness.

## Residual Risks

- Workers run as the same user with full filesystem access. Path validation against project root is not enforced because the IDE legitimately needs to access files outside project boundaries (shelf files, SSH keys for remote, etc.).
- Git hooks (`.git/hooks/`) execute arbitrary code when git commands trigger them. This is inherent to git and not specific to the worker feature. Users should audit hooks in cloned repositories.
- The persistent session subprocess reuse means a corrupted subprocess state could affect multiple subsequent requests until the session is invalidated (mitigated by transport failure detection and retry).

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array; sanitizedPathComponent; no shell interpolation. |
| SEC-Data-Protection | Compliant | No secrets in worker protocol; errors local-only. |
| PERF-Responsiveness | Compliant | Timeouts enforced; SIGTERM+SIGKILL escalation; generation guards. |
| OBS | Compliant | MeasuredPaneWorker records os_signpost and operation metrics. |
