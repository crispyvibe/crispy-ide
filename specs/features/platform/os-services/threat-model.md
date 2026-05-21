# OS Services — Threat Model

## Overview

OS Services integrates Crispy with the macOS Services menu, allowing external applications to send text to Crispy for processing (and potentially receive processed text back). The app registers as an `NSServicesProvider` via `NSRegisterServicesProvider`. The threat surface is limited to untrusted text input received from external applications through the Services IPC mechanism.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| External app ↔ macOS Services IPC ↔ Crispy | Text is passed from any app via the system Services menu. Crispy receives arbitrary text from untrusted sources. |
| Services provider ↔ Internal text processing | Received text is routed to internal text service pipelines (AI CLI commands, rephrase, research). |
| Services provider ↔ Pasteboard | Services may read from and write to the system pasteboard as part of the send/receive flow. |

## Attack Surfaces

1. **Inbound text from Services menu** — arbitrary text from any application, potentially containing control characters, extremely long strings, or crafted payloads.
2. **Service provider registration** — `NSRegisterServicesProvider` with a named provider. Another app could theoretically register the same service name.
3. **Pasteboard interaction** — Services read/write pasteboard types; malicious pasteboard content could be injected.

## Threats

### F037-T01: Injection via Services-provided text

- **Vector:** An external application sends crafted text through the macOS Services menu that is then passed to an AI CLI command or terminal. If the text is interpolated into a shell command, it could achieve command injection.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low — text services should use `Process.arguments` array, not shell interpolation.
- **Mitigation:** Text received from Services MUST be treated as untrusted user input. It MUST NOT be interpolated into shell command strings. When passed to CLI tools, it MUST use `Process.arguments` array or stdin piping. Linked NFR: SEC-Input-Sanitization.

### F037-T02: Denial of service via extremely large text payload

- **Vector:** An external app sends an extremely large text string (hundreds of MB) through the Services menu, causing memory pressure or UI stall in Crispy.
- **Impact:** App hang or crash from memory exhaustion.
- **Likelihood:** Low — macOS Services typically handle reasonable text sizes, but no system-level cap is enforced.
- **Mitigation:** The services provider SHOULD validate input length and reject payloads exceeding a reasonable limit (e.g., 1 MB). Processing SHOULD occur off the main thread. Linked NFR: PERF-Responsiveness.

### F037-T03: Control character injection in received text

- **Vector:** Text received via Services contains ANSI escape sequences, null bytes, or other control characters that could disrupt terminal rendering or text processing.
- **Impact:** UI corruption in terminal or editor views; potential escape sequence injection if text is pasted into a terminal.
- **Likelihood:** Low.
- **Mitigation:** Text received from Services SHOULD be sanitized to strip control characters (< 0x20 except standard whitespace) before display or terminal insertion. When routed to terminal, standard terminal escape handling applies. Linked NFR: SEC-Input-Sanitization.

## Residual Risks

- The macOS Services mechanism is inherently a cross-app communication channel. Any app can invoke registered services. This is by design and cannot be restricted at the application level.
- The scope of OS Services integration is currently minimal (spec status: pending). As the feature expands, additional threats should be assessed.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Services text treated as untrusted; no shell interpolation. |
| SEC-Data-Protection | N/A | No persistent storage of services-received text. |
| PERF-Responsiveness | Compliant | Length validation; off-main-thread processing. |
