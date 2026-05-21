# Git Operations — Threat Model

## Overview

Git Operations provides vibespace-scoped source control: repository discovery, status display, stage/unstage/commit/push/pull/fetch/discard actions, branch management, and commit history. All git operations are executed by spawning the system `git` CLI via `PaneWorkerExecutor`. The feature performs network I/O indirectly through `git push`, `git pull`, and `git fetch` which connect to remote servers. Repository discovery scans project directories for `.git` folders.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app ↔ `git` CLI | Git commands are spawned via `Process` with arguments arrays. File paths and branch names are passed as discrete arguments. |
| Git CLI ↔ Remote servers | Push, pull, and fetch connect to configured remotes via HTTPS or SSH. |
| File system ↔ Repository discovery | Discovery scans project roots recursively (up to configurable depth) looking for `.git` directories. |
| Git output ↔ UI rendering | Git command output (status, log, diff) is parsed and rendered in the sidebar. |
| Commit message ↔ Git CLI | User-provided commit messages are passed as arguments to `git commit`. |

## Attack Surfaces

1. **Git command arguments** — file paths, branch names, and commit messages are passed to git CLI. These originate from file system state and user input.
2. **Repository discovery scanning** — recursive directory scanning could encounter symlinks, extremely deep trees, or adversarial directory structures.
3. **Git output parsing** — status output, diff content, and log entries are parsed for display. Malformed output could cause parsing errors or UI issues.
4. **Discard operations** — `git checkout --` and `git reset` modify the working tree, potentially destroying uncommitted work.
5. **Branch checkout** — switching branches modifies the working tree and may trigger git hooks.
6. **Push/pull/fetch** — network operations that interact with remote servers.
7. **Commit message** — user-provided text passed as `-m` argument to git.

## Threats

### F026-T01: Command injection via file path in git arguments

- **Vector:** A file with a name containing shell metacharacters or git option prefixes (e.g., `--exec=malicious`) is staged, unstaged, or discarded. If the path is not properly handled, it could be interpreted as a git option.
- **Impact:** Arbitrary command execution or unintended git behavior.
- **Likelihood:** Low — the implementation uses `Process.arguments` array, not shell interpolation. However, git itself interprets arguments starting with `--`.
- **Mitigation:** Git commands use `Process.arguments` array (no shell). File paths are passed after `--` separator where applicable to prevent interpretation as options. `normalizedRelativeGitPath` trims whitespace and normalizes separators. Linked NFR: SEC-Input-Sanitization.

### F026-T02: Repository discovery symlink loop or depth bomb

- **Vector:** A project directory contains symlinks creating circular references or extremely deep nested structures. Repository discovery scans recursively, potentially entering infinite loops or consuming excessive resources.
- **Impact:** CPU exhaustion; app hang during discovery.
- **Likelihood:** Low — discovery has configurable depth limit and max repository count.
- **Mitigation:** Discovery is bounded by `gitRepositoryScanMaxDepth` (default 8) and `gitRepositoryScanMaxRepositories` (default 64). A set of skipped directory names (`node_modules`, `DerivedData`, `.build`, etc.) prevents scanning known-large directories. Discovery runs asynchronously without blocking UI. Linked NFR: PERF-Responsiveness.

### F026-T03: Unintended data loss via Discard All

- **Vector:** User triggers "Discard All Changes" which reverts all working tree modifications. If triggered accidentally or on the wrong repository (in a multi-repo vibespace), uncommitted work is permanently lost.
- **Impact:** Irreversible loss of all uncommitted changes in the target repository.
- **Likelihood:** Medium — the action requires confirmation, but users may click through dialogs. Multi-repo vibespaces increase the risk of targeting the wrong repository.
- **Mitigation:** Discard All MUST require explicit confirmation (F026-R06). The confirmation dialog is scoped to the specific repository section. Mutations are isolated per repository — discarding in one repo does not affect siblings (F026-R12). Consider showing the number of affected files in the confirmation prompt. Linked NFR: SEC-Data-Protection.

### F026-T04: Git hook execution on branch checkout

- **Vector:** Checking out a branch triggers `post-checkout` hooks. A malicious repository (e.g., from a clone) could have hooks that execute arbitrary code.
- **Impact:** Arbitrary command execution with user permissions.
- **Likelihood:** Medium — git hooks are a known attack vector. Users may check out branches in repositories cloned from untrusted sources.
- **Mitigation:** This is fundamental git behavior, not specific to Crispy. Crispy invokes `git checkout` which triggers hooks by design. Users SHOULD review hooks in untrusted repositories. Crispy does not bypass or modify hook execution. Linked NFR: SEC-Input-Sanitization.

### F026-T05: Credential prompt blocking during push/pull/fetch

- **Vector:** `git push`, `git pull`, or `git fetch` encounters a repository requiring authentication. Git prompts for credentials on stdin, but the process is spawned non-interactively, causing it to hang until timeout.
- **Impact:** Operation hangs; UI shows loading state until timeout.
- **Likelihood:** Medium — common when SSH keys are not configured or HTTPS credentials are not cached.
- **Mitigation:** Git commands have bounded timeouts (`gitCommandTimeout` = 15s for most operations). The process is terminated on timeout. Error output is captured and displayed to the user. Consider setting `GIT_TERMINAL_PROMPT=0` in the process environment to prevent interactive prompts. Linked NFR: PERF-Responsiveness.

### F026-T06: Git output injection in status display

- **Vector:** A file with a crafted name containing ANSI escape sequences or control characters appears in `git status` output. When rendered in the sidebar, these could cause UI rendering issues.
- **Impact:** UI corruption; potential for misleading file names in the status display.
- **Likelihood:** Low — file names with control characters are unusual but possible.
- **Mitigation:** Git output is parsed line-by-line with status code extraction. File paths from git output are used for display and as arguments to subsequent commands. SwiftUI `Text` views render strings without interpreting escape sequences. Consider stripping control characters from displayed file names. Linked NFR: SEC-Input-Sanitization.

### F026-T07: Commit message injection

- **Vector:** A commit message containing git-interpreted sequences or extremely long content is passed to `git commit -m`. While `Process.arguments` prevents shell injection, git itself has a maximum argument length.
- **Impact:** Commit failure for very long messages; no security impact.
- **Likelihood:** Very low — commit messages are user-provided and validated as non-empty.
- **Mitigation:** Commit requires a non-empty message (F026-R04). The message is passed as a single argument element via `Process.arguments`. Git handles message content safely. No additional validation needed beyond non-empty check. Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- Git hooks execute with user permissions during checkout, commit, push, and merge operations. This is inherent to git.
- Network operations (push/pull/fetch) connect to remote servers configured in the repository. Crispy does not validate remote URLs.
- Git credential management is delegated to the system git configuration (credential helpers, SSH agent).

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array; `--` separator; path normalization. |
| SEC-Data-Protection | Compliant | Discard confirmation; per-repo isolation; draft isolation. |
| PERF-Responsiveness | Compliant | Bounded timeouts; async discovery; scan depth limits. |
| A11Y | Compliant | Keyboard navigation; error states with retry. |
| OBS | Compliant | All git operations logged. |
