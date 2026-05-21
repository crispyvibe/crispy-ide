# Terminal Scroll Assist — Threat Model

## Overview

Scroll Assist reads the user's own terminal scrollback and shells out to the local `tmux` binary. It performs no network I/O, accepts no remote input, and stores no data. The threat surface is limited to local input handling: ensuring that user-typed search queries and recorded command history do not become injection vectors.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Crispy app process ↔ tmux CLI | Scroll Assist invokes `tmux send-keys -X search-forward <query>`. The query must be passed as a separate argument (never interpolated into a shell string). |
| Scroll Assist UI ↔ Ghostty surface | Calls into GhosttyKit are FFI; inputs are Swift strings converted via `withCString`. No string is interpreted as a Ghostty action format outside the documented `scroll_to_row:N` form. |
| `ComposeHistoryStore` ↔ Scroll Assist | Read-only access. No mutation or admin paths. |

## Attack Surfaces

1. **Search query field** — accepts arbitrary user text, used as `search-forward` argument to tmux and as a substring search in Ghostty buffer text.
2. **Recorded command history** — replayed as scroll target text. Originates from the user's own input, but may contain control characters or escape sequences captured from prior sessions.
3. **Tmux session name** — passed as `-t` target. Originates from `TmuxService.generateSessionName()` (controlled by Crispy) but theoretically extensible if remote sessions are added later.

## Threats

### F046-T01: Shell injection via search query

- **Vector:** Search query interpolated into a shell command string.
- **Impact:** Arbitrary command execution as the user.
- **Likelihood:** Low (current design uses `Process.arguments` array, which is not shell-interpreted), but easy to regress.
- **Mitigation:** Search queries MUST be passed as discrete elements of `Process.arguments`. Code review MUST reject any change that uses `bash -c` or string interpolation when invoking `tmux`. Linked NFR: SEC-Input-Sanitization.

### F046-T02: ANSI / control sequence injection via match preview

- **Vector:** A scrollback line containing control sequences (e.g., bell, OSC) is rendered in the search results list. SwiftUI `Text` renders the raw string but a future change to use NSAttributedString or Markdown could re-interpret sequences.
- **Impact:** Annoying UI redraws, potential phishing (carriage returns hiding text). No code execution.
- **Likelihood:** Low.
- **Mitigation:** Strip control characters (`<` 0x20 except whitespace) from `match.lineText` before rendering. Truncate to 200 characters per row.

### F046-T03: Disclosure of pre-screen-lock content

- **Vector:** Crispy may present a search overlay over a terminal that contains sensitive data (passwords, tokens). If Scroll Assist persists a search query or history in any disk location, it could leak.
- **Impact:** Disclosure of sensitive content.
- **Likelihood:** Low — design is in-memory only.
- **Mitigation:** Scroll Assist MUST NOT persist search queries, match results, or scrollback snapshots to disk or any external service. Linked NFR: SEC-Data-Protection.

### F046-T04: Tmux pane targeted via attacker-controlled name

- **Vector:** If a remote attacker can influence the `tmuxSessionName` on a session (e.g., through SSH session takeover), they could direct copy-mode commands against an unintended pane.
- **Impact:** UI confusion, potentially scrolling a different terminal than expected.
- **Likelihood:** Very low — sessions are local-only today; tmux session names are generated locally.
- **Mitigation:** Validate that `tmuxSessionName` exists in the local tmux server before issuing commands (`has-session -t`). Reject names containing shell metacharacters. Linked NFR: SEC-Input-Sanitization.

### F046-T05: Resource exhaustion via large scrollback

- **Vector:** A user runs a session with a very large scrollback (`history-limit 100000+`) and triggers a search.
- **Impact:** Main-actor stall while reading and parsing the buffer.
- **Likelihood:** Low for typical use, possible in CI/log-streaming workflows.
- **Mitigation:** Cap the search match list at 200 entries. Run the tmux capture-pane shell-out off the main actor. Linked NFR: PERF-Responsiveness.

### F046-T06: Credential capture via input recording

- **Vector:** User types a password or secret key at a hidden prompt (e.g., `sudo`, `ssh`, `read -s`, GPG passphrase). If input recording blindly captures all keystrokes, the secret is stored in `ComposeHistoryStore` and surfaced via insights/history navigation.
- **Impact:** Credential disclosure within the app's in-memory state; visible in context summary, D-pad history navigation, and any future persistence layer.
- **Likelihood:** High without mitigation — password prompts are a daily occurrence.
- **Mitigation:** `TerminalInsightObserver.recordInput()` validates screen visibility before publishing. On Enter, it reads `engine.lastVisibleContents` (the current terminal render buffer) and checks if the typed text appears on screen. Terminals disable echo for secret input (`stty -echo`, `read -s`), so hidden text never appears in the render buffer and is never recorded. The `readVisibleScreen` closure uses `[weak self]` to avoid retain cycles. If the observer or engine is unavailable, the check allows through (graceful degradation — matches pre-mitigation behavior). Linked NFR: SEC-Data-Protection.

## Residual Risks

- A user with shell access to the Crispy host can manipulate `ComposeHistoryStore` only by changing their own typed history. No additional risk beyond what the user already has.
- Scroll Assist does not authenticate the source of the terminal session; if a malicious process spawns a fake tmux pane and Crispy attaches to it, Scroll Assist will operate on that pane. This is an environmental issue not specific to this feature.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Process.arguments array used; no string interpolation. |
| SEC-Data-Protection | Compliant | In-memory only; no persistence. |
| PERF-Responsiveness | Compliant | Capture-pane runs detached; match list capped. |
| A11Y | Partial | Initial implementation is mouse-only; keyboard activation is a follow-up item. |
| OBS | Compliant | Existing terminal logging unchanged; no new event categories needed. |
