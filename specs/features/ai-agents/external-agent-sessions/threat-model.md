# External Agent Sessions — Threat Model

## Overview

This feature reads third-party agent session files from the local filesystem. The primary trust boundary is between Crispy and provider-owned files that may contain arbitrary content (prompts, code, secrets, tool output). The Rust helper parses untrusted JSONL data and, for OpenCode, an untrusted SQLite database. External data stores are read strictly read-only — file-based providers are opened read-only and OpenCode's live SQLite database is read from a temporary read-only snapshot copy, never written. In addition to copying resume commands, the feature can now run a provider's resume command in a new terminal tab, so the session identifier that is interpolated into that command is a new consideration.

## Trust Boundaries

1. **Crispy app ↔ Provider session files/databases**: Provider files and OpenCode's SQLite database are untrusted input. Crispy reads but never writes — the live SQLite DB is copied to a temp snapshot and opened read-only.
2. **Swift process ↔ Rust helper subprocess**: Communication via stdout JSON. Helper runs with same user privileges.
3. **Parsed transcript content ↔ SwiftUI rendering**: Transcript text is rendered as plain text, not interpreted as code or HTML.

## Attack Surfaces

- Provider session files on disk (attacker could plant malicious content)
- OpenCode SQLite database (untrusted DB content and structure)
- Rust helper binary (supply chain integrity)
- JSON decoding of helper output
- Transcript text rendering in SwiftUI
- Resume command constructed from a session id and executed in a terminal

## Threats

### F047-T01: Malicious content in provider session files

- **Vector**: An attacker with local file access plants crafted JSONL in provider directories containing prompt injection, misleading instructions, or exfiltration payloads.
- **Impact**: Medium — content is displayed read-only; no execution or import occurs.
- **Likelihood**: Low — requires local filesystem access.
- **Mitigation**: All transcript content is rendered as plain text via `ACPSelectableText`. No HTML interpretation, no link auto-opening, no command execution. Resume commands are copied, not executed.

### F047-T02: Path traversal in provider file scanning

- **Vector**: Symlinks or crafted directory structures under provider roots could cause the helper to read files outside intended directories.
- **Impact**: Medium — could expose file contents from unexpected paths.
- **Likelihood**: Low — requires local filesystem manipulation.
- **Mitigation**: Rust helper resolves provider roots before scanning. Only files matching expected patterns (`.jsonl`, `.json`) under known provider directories are read.

### F047-T03: Denial of service via large or malformed files

- **Vector**: Extremely large session files or deeply nested JSON could exhaust memory or CPU in the helper.
- **Impact**: Low — helper crash does not crash the app; UI shows error state.
- **Likelihood**: Low — requires local file manipulation.
- **Mitigation**: Helper uses streaming/bounded parsing. Scan limit caps results at 500. Preview caps rendered entries at 200. Helper failures are caught and surfaced as `ServiceError.helperFailed`.

### F047-T04: Helper binary tampering

- **Vector**: An attacker replaces the bundled Rust helper with a malicious binary.
- **Impact**: High — arbitrary code execution with user privileges.
- **Likelihood**: Very low — requires write access to the app bundle (code-signed).
- **Mitigation**: App bundle is code-signed and notarized. macOS Gatekeeper validates bundle integrity. Helper is resolved only from within `Bundle.main`.

### F047-T05: Sensitive data exposure in transcripts

- **Vector**: Provider transcripts may contain secrets (API keys, passwords, tokens) from past agent sessions.
- **Impact**: Medium — secrets visible in the preview panel to anyone with screen access.
- **Likelihood**: Medium — common for agent sessions to contain sensitive output.
- **Mitigation**: Preview is local-only, never uploaded. No persistent index is created. Content is not logged beyond diagnostic metadata. Users are responsible for their local session content.

### F047-T06: Mutation or corruption of the OpenCode SQLite database

- **Vector**: Opening a live SQLite database for reading while OpenCode is running (or opening it read-write) could lock, corrupt, or mutate the user's real session data, including its `-wal`/`-shm` journal state.
- **Impact**: Medium — loss or corruption of the user's OpenCode session history.
- **Likelihood**: Low — only occurs if the DB were opened in place read-write.
- **Mitigation**: The helper never opens the original database for writing. It copies `opencode.db` plus its `-wal`/`-shm` sidecars into a temp directory, opens the copy read-only, runs all queries against the snapshot, and deletes the snapshot when finished. The original files are only ever read for copying.

### F047-T07: Command injection via session id in resume command

- **Vector**: A crafted or malformed session id could contain shell metacharacters that, when interpolated into a resume command (`opencode --session <id>`, `codex resume <id>`, etc.) and run in a terminal via "Open in Terminal", execute unintended commands.
- **Impact**: High — arbitrary command execution in the user's terminal with user privileges.
- **Likelihood**: Low — session ids originate from provider stores the user already controls, but ids are still untrusted input.
- **Mitigation**: The session id is treated as untrusted. Resume commands are built with the id as a single, quoted/escaped argument (not string-concatenated into a shell line), so metacharacters cannot break out of the argument. "Open in Terminal" runs only the provider's fixed resume command with the id as one argument; it never evaluates arbitrary text from the session content.



- Transcript content may contain sensitive information visible to anyone with physical access to the machine.
- Provider file format changes could cause silent parse failures (mitigated by diagnostic surfacing).

## NFR Compliance

- **SEC-1**: No network transmission of external transcript data.
- **SEC-3a**: Provider files are read-only; no mutation. OpenCode's SQLite DB is read from a temporary read-only snapshot copy.
- **REL-1**: Malformed files do not crash the app or helper.
- **OBS-1**: Parse failures are recorded to AppDiagnostics with full context.
