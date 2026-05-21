# External Agent Sessions — Threat Model

## Overview

This feature reads third-party agent session files from the local filesystem. The primary trust boundary is between Crispy and provider-owned files that may contain arbitrary content (prompts, code, secrets, tool output). The Rust helper parses untrusted JSONL data.

## Trust Boundaries

1. **Crispy app ↔ Provider session files**: Provider files are untrusted input. Crispy reads but never writes.
2. **Swift process ↔ Rust helper subprocess**: Communication via stdout JSON. Helper runs with same user privileges.
3. **Parsed transcript content ↔ SwiftUI rendering**: Transcript text is rendered as plain text, not interpreted as code or HTML.

## Attack Surfaces

- Provider session files on disk (attacker could plant malicious content)
- Rust helper binary (supply chain integrity)
- JSON decoding of helper output
- Transcript text rendering in SwiftUI

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

## Residual Risks

- Transcript content may contain sensitive information visible to anyone with physical access to the machine.
- Provider file format changes could cause silent parse failures (mitigated by diagnostic surfacing).

## NFR Compliance

- **SEC-1**: No network transmission of external transcript data.
- **SEC-3a**: Provider files are read-only; no mutation.
- **REL-1**: Malformed files do not crash the app or helper.
- **OBS-1**: Parse failures are recorded to AppDiagnostics with full context.
