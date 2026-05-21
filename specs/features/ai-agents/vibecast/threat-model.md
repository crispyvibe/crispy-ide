# VibeCast — Threat Model

## Overview

VibeCast is a broadcast compose-and-send interface that dispatches text to terminal tabs. It sends raw text (with Enter) to terminal sessions, maintains an in-memory message history, and invokes an external CLI for rephrase. The primary threat surface is text injection into terminal sessions — VibeCast acts as a programmatic keyboard for terminals.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| VibeCast compose UI ↔ Terminal sessions | Compose text is sent to terminal sessions via `sendRawTextWithEnter`. The terminal interprets the text as if typed by the user. |
| VibeCast ↔ Rephrase CLI | `VibeCastRephraseService` spawns an external CLI process via `/usr/bin/env` with `Process.arguments`. |
| User input ↔ Message history | Messages are stored in-memory (up to 500). No disk persistence of message content. |

## Attack Surfaces

1. **Compose text sent to terminals** — arbitrary text is delivered to terminal sessions as raw input followed by Enter. The terminal shell interprets this as a command.
2. **Broadcast to all terminals** — a single compose action sends text to every open terminal tab simultaneously.
3. **Rephrase CLI invocation** — compose text is passed as a CLI argument to an external tool; output replaces compose text.
4. **Message history (in-memory)** — stores up to 500 messages with text content, target tab names, and timestamps.
5. **Target terminal auto-sync** — when terminals close, VibeCast falls back to the first available tab, which could be an unintended target.

## Threats

### F028-T01: Unintended command execution via broadcast

- **Vector:** User composes a destructive command (e.g., `rm -rf /`) and triggers broadcast, sending it to all terminal tabs simultaneously. Each terminal executes the command independently.
- **Impact:** Destructive operations executed across all active terminal sessions.
- **Likelihood:** Medium — broadcast is a deliberate user action, but the blast radius is high. A misclick or muscle-memory shortcut could trigger unintended broadcast.
- **Mitigation:** Broadcast action SHOULD require a distinct gesture from single-target send (it does — separate action). Consider adding a confirmation prompt for broadcast when compose text contains potentially destructive patterns. Message delivery is logged. Linked NFR: SEC-Input-Sanitization.

### F028-T02: Target auto-fallback sends to wrong terminal

- **Vector:** The selected target terminal closes while the user is composing. VibeCast auto-syncs to the first available tab. The user sends without noticing the target changed, executing a command in an unintended context (e.g., production server terminal).
- **Impact:** Command executed in wrong environment; potential data loss or unintended side effects.
- **Likelihood:** Medium — terminal tabs close frequently; target change is indicated in UI but may be missed.
- **Mitigation:** Target changes MUST be visually prominent (target name displayed in compose area). Consider a brief toast notification when auto-fallback occurs. The user must still press Send explicitly. Linked NFR: SEC-Input-Sanitization.

### F028-T03: Command injection via rephrase CLI output

- **Vector:** A compromised or malicious rephrase CLI returns crafted output that, when placed in the compose field and sent to a terminal, executes unintended commands (e.g., injecting `; malicious-command` into the rephrased text).
- **Impact:** Arbitrary command execution in the target terminal.
- **Likelihood:** Low — user reviews compose text before sending; rephrase output is visible in the compose field.
- **Mitigation:** Rephrase output is stripped of ANSI/terminal control sequences via `stripTerminalFormatting`. Output is placed in the compose field for user review before sending — it is never auto-sent. The user must explicitly trigger send after reviewing. Linked NFR: SEC-Input-Sanitization.

### F028-T04: Sensitive data exposure in message history

- **Vector:** User sends passwords, tokens, or secrets via VibeCast to terminal sessions (e.g., `export API_KEY=secret`). These are stored in the in-memory message history and visible in the VibeCast UI.
- **Impact:** Secrets visible in message history to anyone with screen access.
- **Likelihood:** Medium — developers frequently pass secrets to terminals.
- **Mitigation:** Message history is in-memory only (not persisted to disk). History is capped at 500 messages and cleared on app termination. Consider adding a "clear history" action. Linked NFR: SEC-Data-Protection.

### F028-T05: Resource exhaustion via rapid message sending

- **Vector:** A user or automation rapidly sends messages, filling the 500-message history and generating high terminal I/O.
- **Impact:** Memory pressure from message objects; terminal sessions overwhelmed with input.
- **Likelihood:** Low — requires deliberate rapid action.
- **Mitigation:** Message history is hard-capped at 500 entries with FIFO eviction. Terminal sessions handle input at their own rate (backpressure from PTY). Linked NFR: PERF-Responsiveness.

### F028-T06: Rephrase CLI process timeout and resource consumption

- **Vector:** The rephrase CLI hangs or runs indefinitely, blocking the rephrase action and consuming system resources.
- **Impact:** `isRephrasing` state stuck; process consuming CPU/memory.
- **Likelihood:** Low — timeout is enforced.
- **Mitigation:** `ManagedProcessRunner` enforces a 20-second timeout (`timeoutSeconds`). On timeout, the process is terminated and `isRephrasing` is reset to false. The rephrase runs on a detached task with `[weak self]` to avoid retain cycles. Linked NFR: PERF-Responsiveness.

## Residual Risks

- VibeCast is fundamentally a "type text into terminal" tool. Any text the user sends is executed by the shell. This is by design — the same risk exists with manual typing.
- The rephrase CLI may send compose text to external AI services. This is the user's configured tool and outside Crispy's control.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | ANSI stripping on rephrase output; no shell interpolation in CLI invocation. |
| SEC-Data-Protection | Compliant | In-memory only; no disk persistence of messages. |
| PERF-Responsiveness | Compliant | History capped; CLI timeout enforced; detached task execution. |
| A11Y | Compliant | Keyboard cycling accessible; compose area focusable. |
| OBS | Compliant | Message sends logged. |
