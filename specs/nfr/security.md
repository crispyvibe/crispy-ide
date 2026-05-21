# NFR: Security

## Scope

Security requirements applicable to all components of the application.

## Requirements

### SEC-1: Process Isolation

- Child processes MUST run with the minimum privileges required for their function.
- No child process may inherit elevated privileges from the parent.
- IPC between processes MUST use typed, validated message contracts — no raw eval or untyped message passing.

### SEC-2: Data at Rest

- Application metadata MUST be stored in the OS-designated application data directory, not in user project directories.
- Persisted application state MUST use integrity verification (HMAC-SHA256 or equivalent) to detect tampering.
- Secrets (tokens, credentials, keys) MUST use OS-native secure storage (Keychain, Credential Manager) — never plaintext files.

### SEC-3: Content Security

- The rendering layer MUST enforce a strict content security policy: no inline scripts, no eval, no remote resource loading.
- User-provided content MUST be sanitized before rendering.
- All internal communication between UI and backend MUST go through a typed command interface.

### SEC-3a: Input Sanitization

- All text received from keyboard, clipboard, file reads, and drag-and-drop MUST be validated before processing.
- Clipboard paste into non-terminal contexts MUST strip control characters and escape sequences.
- File content rendered in previews (markdown, HTML, SVG) MUST be sanitized to remove embedded scripts, event handlers, and data URIs with executable content.
- File names and paths received from external sources (drag-and-drop, OS open events) MUST be validated for path traversal sequences (`../`, null bytes, overlong encodings).
- Terminal input is exempt from stripping (terminals require raw control sequences), but MUST be scoped to the target PTY session only.

### SEC-4: Supply Chain

- All dependencies MUST be audited for known vulnerabilities on every CI run.
- License compliance MUST be enforced via an allowlist.
- Lock files MUST be committed and changes reviewed in PRs.

### SEC-5: Code Execution Boundaries

- The application MUST NOT execute code from opened projects without explicit user action.
- No auto-discovery or auto-execution of project-level configuration files.
- Any future extension/plugin system MUST require explicit user approval.

### SEC-6: Network

- Core functionality MUST work fully offline.
- Any network-capable feature MUST be opt-in and clearly indicated.
- Downloaded artifacts (updates, extensions) MUST be signature-verified.

### SEC-7: File System Scope

- File operations MUST be scoped to user-opened directories.
- Symlink traversal MUST NOT escape the scoped boundary.
- Temporary files MUST use OS-designated temp directories with restrictive permissions.

## Verification

- Automated dependency audit in CI.
- CSP violation reporting in development builds.
- Integration tests for data integrity verification.
- Security review checklist per release.
