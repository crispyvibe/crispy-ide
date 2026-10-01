# External Agent Sessions — Threat Model

## Overview

This feature reads third-party agent session files from the local filesystem. The primary trust boundary is between Crispy and provider-owned files that may contain arbitrary content (prompts, code, secrets, tool output). The Rust helper parses untrusted JSONL data and, for OpenCode and Kiro classic, untrusted SQLite databases, plus untrusted metadata emitted by the installed Kiro CLI. External data stores are read strictly read-only — file-based providers are opened read-only and OpenCode and Kiro classic live SQLite databases are read from temporary read-only snapshot copies, never opened by SQLite in place or written. In addition to copying resume commands, the feature can now run a provider's resume command in a new terminal tab, so the session identifier that is interpolated into that command is a new consideration.

## Trust Boundaries

1. **Crispy app ↔ Provider session files/databases**: Provider files and the OpenCode/Kiro classic SQLite databases are untrusted input. Crispy reads but never writes — live SQLite files and sidecars are copied to temporary snapshots and only the copies are opened read-only.
2. **Rust helper ↔ Installed Kiro CLI**: The helper executes an absolute `kiro-cli` resolved from constrained PATH/default locations without a shell and treats stdout as untrusted JSON.
3. **Swift process ↔ Rust helper subprocess**: Communication via stdout JSON. Helper runs with same user privileges.
4. **Parsed transcript content ↔ SwiftUI rendering**: Transcript text is rendered as plain text, not interpreted as code or HTML.

## Attack Surfaces

- Provider session files on disk (attacker could plant malicious content)
- OpenCode and Kiro classic SQLite databases (untrusted DB content and structure)
- Installed Kiro executable resolution and listing JSON
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
- **Mitigation**: Directory discovery uses `DirEntry.file_type()` and does not traverse symlinked directories or collect symlinked session files. Kiro CLI stdout is untrusted: V2 session IDs must be one normal path component before a path is constructed; existing transcript candidates are canonicalized and required to remain beneath the configured V2 root; symlinked and non-regular transcript files are rejected; and V2 metadata/JSONL opens use `O_NOFOLLOW`. Source-aware V2 and classic loads re-resolve their configured storage roots instead of trusting caller-provided source paths. Only files matching expected provider patterns are read.

### F047-T03: Denial of service via large or malformed files

- **Vector**: Extremely large session files or deeply nested JSON could exhaust memory or CPU in the helper.
- **Impact**: Low — helper crash does not crash the app; UI shows error state.
- **Likelihood**: Low — requires local file manipulation.
- **Mitigation**: Helper uses streaming/bounded parsing. Scan limit caps results at 500. Preview caps rendered entries at 200. Kiro classic search takes one snapshot and scans `conversations_v2` once for all candidate IDs; malformed rows emit isolated diagnostics while valid rows continue. Superseded Swift search tasks terminate and reap their helper process, preventing detached searches from accumulating. Helper failures are caught and surfaced as `ServiceError.helperFailed`.

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

### F047-T08: Kiro executable substitution or shell injection

- **Vector**: A malicious PATH entry supplies a fake `kiro-cli`, or metadata values attempt shell metacharacter injection.
- **Impact**: High — a substituted executable runs with user privileges.
- **Likelihood**: Low — requires modifying the user environment or executable locations.
- **Mitigation**: Resolve an existing executable to an absolute path from PATH plus a fixed GUI-safe location set and invoke it directly with fixed argv; never invoke a shell. Treat stdout as untrusted JSON and never execute metadata fields.

### F047-T09: Kiro classic database mutation or snapshot residue

- **Vector**: SQLite opens the live database/sidecars, or a failed operation leaves transcript-bearing snapshots in the temporary directory.
- **Impact**: Medium — provider data could be locked/corrupted or sensitive copies could persist.
- **Likelihood**: Low.
- **Mitigation**: Copy the DB and available `-wal`/`-shm` sidecars first, open only the copy with read-only/query-only flags, and use RAII cleanup on every normal/error return. Tests verify original bytes are unchanged and snapshot directories are removed.

### F047-T10: Unsupported future Kiro source misparse

- **Vector**: A future/V3 source is interpreted as V2 or classic without a verified fixture.
- **Impact**: Medium — wrong session identity, misleading transcript, or unintended file access.
- **Likelihood**: Medium as Kiro evolves.
- **Mitigation**: Allowlist only observed `v2` and `classic`; skip all other source values and emit one aggregate diagnostic. No V3 support is claimed.

### F047-T11: Over-broad internal-session filtering

- **Vector**: Repeated Kiro titles are deduplicated or filtered by display title, hiding legitimate conversations that happen to share the same title.
- **Impact**: Medium — valid external sessions disappear from the Conversations list with no parse error.
- **Likelihood**: Medium because one-shot title helpers intentionally share a prompt-derived title.
- **Mitigation**: Never deduplicate Kiro sessions by title. Exclude only one-turn sessions whose stored first user prompt matches the current explicit Crispy marker or a known exact legacy app-owned title-generation prelude. Regression coverage keeps a legitimate same-title session and a continued multi-turn session visible.

## Residual Risks
- Transcript content may contain sensitive information visible to anyone with physical access to the machine.
- Provider file format changes could cause parse failures; diagnostics are surfaced and unknown Kiro sources are rejected rather than heuristically parsed.

## NFR Compliance

- **SEC-1**: No network transmission of external transcript data.
- **SEC-3a**: Provider files are read-only; no mutation. OpenCode and Kiro classic SQLite DBs are read from temporary read-only snapshot copies.
- **REL-1**: Malformed files do not crash the app or helper.
- **OBS-1**: Parse failures are recorded to AppDiagnostics with full context.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-09-30 | Added Kiro CLI executable/metadata controls, classic snapshot cleanup, unsupported-source rejection, single-pass corrupt-row-isolated search, cancellation/reaping of stale helpers, and prompt-fingerprint filtering safeguards | Kiro |
