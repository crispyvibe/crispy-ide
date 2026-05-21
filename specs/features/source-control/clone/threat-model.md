# Clone Repository — Threat Model

## Overview

Clone Repository provides the ability to clone a Git repository from the source control sidebar. It integrates with GitHub CLI (`gh`) for repository browsing when available, and uses `git clone` to fetch repositories to a user-chosen destination. The cloned folder is added to the active vibespace as a new project. This feature performs network I/O (git clone fetches from remote servers) and spawns external processes (`git`, `gh`).

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| User input ↔ Clone command | Repository URL is provided by the user (pasted or selected from GitHub CLI list). The URL is passed as an argument to `git clone`. |
| Crispy app ↔ `git` CLI | `git clone` is spawned via `Process` with arguments array. The repository URL and destination path are passed as separate arguments. |
| Crispy app ↔ `gh` CLI | GitHub CLI is invoked to list repositories and check auth status. Output is parsed as JSON. |
| Network ↔ Git protocol | `git clone` connects to remote servers via HTTPS or SSH protocols. |
| Cloned content ↔ Vibespace | The cloned directory is added as a project root. Its contents (including `.git/hooks`) become part of the workspace. |

## Attack Surfaces

1. **Repository URL** — user-provided URL passed to `git clone`. Could be a malicious server or contain shell metacharacters.
2. **Destination directory name** — derived from the repository URL or explicitly provided. Used to construct the clone target path.
3. **GitHub CLI output parsing** — JSON output from `gh repo list` is decoded. Malformed output could cause parsing errors.
4. **Cloned repository content** — the cloned repo may contain malicious git hooks, symlinks, or `.gitattributes` filter configurations that execute on checkout.
5. **Git credential prompts** — `git clone` may prompt for credentials if the repository requires authentication.

## Threats

### F027-T01: Command injection via repository URL

- **Vector:** A crafted repository URL containing shell metacharacters is passed to `git clone`. If the URL were interpolated into a shell command string, arbitrary commands could execute.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low — the implementation uses `Process.arguments` array (via `runGitCommand`), passing the URL as a discrete argument element. No shell interpolation occurs.
- **Mitigation:** Repository URL is passed as a separate element in the `Process.arguments` array: `["clone", "--", repositoryURL, destinationURL.path]`. The `--` separator prevents the URL from being interpreted as a git option. No shell string interpolation is used. Linked NFR: SEC-Input-Sanitization.

### F027-T02: Malicious git hooks in cloned repository

- **Vector:** A cloned repository contains executable git hooks (`.git/hooks/post-checkout`, `pre-commit`, etc.) that execute arbitrary code. These hooks run automatically during git operations after the clone.
- **Impact:** Arbitrary code execution when the user performs git operations (commit, checkout, merge) in the cloned project.
- **Likelihood:** Medium — this is a well-known attack vector for malicious repositories. The hooks execute with the user's full permissions.
- **Mitigation:** This is a fundamental git security issue, not specific to Crispy. Git hooks execute by design. Users SHOULD only clone repositories from trusted sources. Consider displaying a warning when a newly cloned repository contains executable hooks. Crispy does not execute hooks itself — they run when the user performs git operations. Linked NFR: SEC-Input-Sanitization.

### F027-T03: Path traversal via destination directory name

- **Vector:** The destination directory name is derived from the repository URL (last path component) or explicitly provided by the user. A crafted name containing `../` could place the clone outside the intended parent directory.
- **Impact:** Repository cloned to an unintended location.
- **Likelihood:** Low — `cloneDestinationDirectoryName` extracts the last path component. `URL.appendingPathComponent` is used for path construction. The destination parent is validated as an existing directory.
- **Mitigation:** Destination parent URL is normalized via `standardizedFileURL`. The destination name is appended via `appendingPathComponent` (which handles path separators). Existence check prevents overwriting existing directories. The parent directory must already exist and be a directory. Linked NFR: SEC-Input-Sanitization.

### F027-T04: Denial of service via large repository clone

- **Vector:** User clones an extremely large repository (multi-GB). The clone operation runs for an extended period, consuming disk space and network bandwidth.
- **Impact:** Disk space exhaustion; prolonged network usage; UI shows busy state.
- **Likelihood:** Low — the user explicitly chose to clone the repository. The 90-second timeout (`gitCloneCommandTimeout`) limits duration.
- **Mitigation:** Clone has a 90-second timeout. If the timeout is exceeded, the process is terminated. The user selects the destination directory (controlling disk usage). Clone errors surface user-facing dismissible alerts. Linked NFR: PERF-Responsiveness.

### F027-T05: GitHub CLI credential exposure

- **Vector:** `gh auth status` and `gh repo list` are invoked to check authentication and list repositories. If the GitHub CLI stores credentials insecurely or its output contains tokens, these could be exposed.
- **Impact:** GitHub credential disclosure.
- **Likelihood:** Very low — `gh` manages its own credential storage (typically macOS Keychain). Crispy only reads the JSON repository list output, not auth tokens.
- **Mitigation:** Crispy invokes `gh` with specific subcommands (`auth status`, `repo list`) and parses only the structured JSON output. No credential-related output is captured or displayed. The `gh` CLI manages its own secure credential storage. Linked NFR: SEC-Data-Protection.

## Residual Risks

- Cloned repositories may contain any content, including malicious code. This is inherent to git and not specific to Crispy.
- Git hooks in cloned repositories execute with user permissions during subsequent git operations. This is standard git behavior.
- Network-level attacks (MITM on HTTPS, DNS spoofing) are mitigated by git's own transport security (certificate validation for HTTPS, host key verification for SSH).

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array; `--` separator; path normalization. |
| SEC-Data-Protection | Compliant | No credentials stored; gh manages its own auth. |
| PERF-Responsiveness | Compliant | 90-second timeout; progress feedback. |
| A11Y | Compliant | Clone progress accessible; error alerts dismissible. |
| OBS | Compliant | Clone operations logged. |
