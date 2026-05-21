# Agent CLI — Terminal Commands

This document specifies the `terminal.*` commands. See [spec.md](spec.md) for cross-cutting requirements.

## Commands

- `terminal.read` — capture screen text (Ghostty only) — **deferred** (needs Ghostty screen-buffer bridge)
- `terminal.send` — inject text into a terminal
- `terminal.send_key` — send a key sequence
- `terminal.create` — spawn a new terminal
- `terminal.list` — list all terminals in a vibespace
- `terminal.close` — close a terminal
- `terminal.wait` — block until a condition is met

---

## `terminal.read`

Captures the visible screen text from a Ghostty-backed terminal, optionally including scrollback. If the terminal uses SwiftTerm, the command returns `unsupported_engine`.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `terminal_id` | string | no | Surface UUID. Defaults to caller's `CRISPY_CONTEXT`. |
| `scrollback` | boolean | no | If true, includes scrollback above the visible region. Default false. |
| `lines` | integer | no | If set, returns only the last N lines (counting from cursor). Implies `scrollback: true`. Must be > 0. |

### Result

| Field | Type | Description |
|---|---|---|
| `text` | string | UTF-8 screen text. Trailing whitespace on each line is preserved; trailing empty lines are not. |
| `lines` | integer | Number of lines returned |
| `cursor_row` | integer | 0-based row of the cursor within the returned text |
| `cursor_col` | integer | 0-based column of the cursor within the returned text |

### Requirements

#### F044-R30: Engine restriction enforced

`terminal.read` MUST return `unsupported_engine` if the resolved terminal uses the SwiftTerm engine.

#### F044-R31: No side effects

`terminal.read` MUST NOT alter cursor position, selection, scroll position, or any other terminal state observable to the user or the running shell.

#### F044-R32: Lines parameter validation

If `lines` is provided, it MUST be a positive integer. Negative or zero values MUST return `invalid_params`.

### Scenarios

#### Scenario F044-S50: Read visible screen from caller's terminal

**Given** an agent runs in a Ghostty terminal showing the output of `cargo build`
**When** the agent invokes `terminal.read` with no parameters
**Then** the response `text` field contains the visible terminal output
**And** `cursor_row`/`cursor_col` reflect the current cursor position

#### Scenario F044-S51: Read with scrollback

**Given** the terminal has 200 lines of scrollback above the visible region
**When** the agent invokes `terminal.read` with `scrollback: true`
**Then** the response includes both visible and scrollback content

#### Scenario F044-S52: Read last N lines

**Given** the terminal has produced 5000 lines of output
**When** the agent invokes `terminal.read` with `lines: 50`
**Then** the response contains exactly the last 50 lines (or fewer if the terminal has produced fewer)

#### Scenario F044-S53: Read on SwiftTerm terminal

**Given** the resolved terminal uses the SwiftTerm engine
**When** the agent invokes `terminal.read`
**Then** the response is `ok: false` with error code `unsupported_engine`
**And** the error message names the alternative (`"Use Ghostty engine to read terminal screen"`)

#### Scenario F044-S54: Read with invalid lines value

**When** the agent invokes `terminal.read` with `lines: 0`
**Then** the response is `invalid_params` with message indicating `lines` must be > 0

---

## `terminal.send`

Sends raw text to a terminal's PTY. The text is delivered byte-for-byte; agents must include their own newline if they want the shell to execute the input.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `text` | string | yes | UTF-8 text to inject |
| `terminal_id` | string | no | Surface UUID. Defaults to caller's `CRISPY_CONTEXT`. |
| `submit` | boolean | no | If true, append a newline (`\n`) after `text`. Default false. |

### Result

Empty object on success.

### Requirements

#### F044-R33: Text delivered as raw bytes

`terminal.send` MUST deliver `text` to the PTY using `TerminalSession.sendRawText` (no command queuing). Special characters in `text` are not escaped.

#### F044-R34: Submit appends LF

When `submit: true`, exactly one `\n` (LF) byte MUST be appended to the text before sending. CR or CRLF variants MUST NOT be used.

#### F044-R35: Empty text rejected

`terminal.send` MUST return `invalid_params` if `text` is missing. Empty string `""` IS valid (no-op send) and MUST succeed.

### Scenarios

#### Scenario F044-S60: Send text to caller's terminal

**Given** an agent's terminal is sitting at a shell prompt
**When** the agent invokes `terminal.send` with `text: "ls -la"` and `submit: true`
**Then** the shell receives `ls -la\n` and executes it

#### Scenario F044-S61: Send text without submit

**When** the agent invokes `terminal.send` with `text: "ls -la"` and `submit: false`
**Then** the text appears at the cursor but is not executed
**And** the user could press Enter manually to run it

#### Scenario F044-S62: Send text with embedded newlines

**When** the agent invokes `terminal.send` with `text: "echo one\necho two\n"` and `submit: false`
**Then** both commands are received by the shell exactly as provided

---

## `terminal.send_key`

Sends a named key event (e.g. `Enter`, `Ctrl+C`, `Tab`, arrow keys). This is the structured alternative to embedding raw escape sequences in `terminal.send`.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | Key name. See key catalog below. |
| `terminal_id` | string | no | Defaults to caller's `CRISPY_CONTEXT`. |

### Key Catalog

| Key | Bytes Sent |
|---|---|
| `Enter` | `\r` |
| `Tab` | `\t` |
| `Escape` | `\u{1B}` |
| `Backspace` | `\u{7F}` |
| `Delete` | `\u{1B}[3~` |
| `Up` | `\u{1B}[A` |
| `Down` | `\u{1B}[B` |
| `Right` | `\u{1B}[C` |
| `Left` | `\u{1B}[D` |
| `Home` | `\u{1B}[H` |
| `End` | `\u{1B}[F` |
| `PageUp` | `\u{1B}[5~` |
| `PageDown` | `\u{1B}[6~` |
| `Ctrl+A` … `Ctrl+Z` | corresponding control codes (`\u{01}`..`\u{1A}`) |
| `Ctrl+[`, `Ctrl+\`, `Ctrl+]`, `Ctrl+^`, `Ctrl+_` | `\u{1B}`, `\u{1C}`, `\u{1D}`, `\u{1E}`, `\u{1F}` |

### Result

Empty object on success.

### Requirements

#### F044-R36: Key name catalog is exhaustive

`terminal.send_key` MUST accept exactly the key names enumerated above. Unknown key names MUST return `invalid_params`.

#### F044-R37: Case-insensitive key names

Key names MUST be matched case-insensitively (`"Enter"` and `"enter"` both work). `Ctrl+` prefix MUST be matched as `"ctrl+"` (lowercased) when normalizing.

### Scenarios

#### Scenario F044-S70: Interrupt running process

**Given** a long-running command is executing in the agent's terminal
**When** the agent invokes `terminal.send_key` with `key: "Ctrl+C"`
**Then** the shell receives byte `\u{03}`
**And** the running process receives SIGINT

#### Scenario F044-S71: Submit a typed command

**Given** the agent has previously sent `"npm test"` without submit
**When** the agent invokes `terminal.send_key` with `key: "Enter"`
**Then** the shell receives `\r` and executes the command

#### Scenario F044-S72: Unknown key

**When** the agent invokes `terminal.send_key` with `key: "F13"`
**Then** the response is `invalid_params` with message naming the unknown key

---

## `terminal.create`

Spawns a new terminal in the channel client's vibespace. The new terminal appears in the UI exactly as if the user clicked "New Terminal" in that vibespace.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `cwd` | string | no | Initial working directory (absolute path). Defaults to caller's `CRISPY_PROJECT_PATH`. |
| `name` | string | no | Custom display name for the tab. |

### Result

| Field | Type | Description |
|---|---|---|
| `terminal_id` | string | UUID of the new terminal |
| `pane_id` | string | UUID of the pane that received the new tab |
| `vibespace_id` | string | UUID of the vibespace that now owns the terminal |

### Requirements

#### F044-R38: Create routes through TerminalProviding

`terminal.create` MUST call `TerminalProviding.createTab(directoryURL:customName:origin:)` on the resolved vibespace's terminal provider with `origin: .agentCLI(callerTerminalID:)` so the terminal is persisted and recoverable on app restart (see [spec.md F044-R11](spec.md)).

#### F044-R39: cwd validation

If `cwd` is provided, it MUST be an absolute path. Relative paths MUST return `invalid_params`. The path is not required to exist; the shell will report the error if it does not.

### Scenarios

#### Scenario F044-S80: Create terminal with default cwd

**Given** the agent runs in a project at `/projects/foo`
**When** the agent invokes `terminal.create` with no parameters
**Then** a new terminal opens with cwd `/projects/foo`
**And** the response includes the new `terminal_id` and `pane_id`
**And** the new terminal appears in the vibespace sidebar

#### Scenario F044-S81: Create terminal with custom cwd and name

**When** the agent invokes `terminal.create` with `cwd: "/projects/bar"` and `name: "build"`
**Then** the new terminal has cwd `/projects/bar` and tab title "build"

#### Scenario F044-S82: Create with relative cwd

**When** the agent invokes `terminal.create` with `cwd: "./subdir"`
**Then** the response is `invalid_params` with message "cwd must be an absolute path"

#### Scenario F044-S83: Surface persists across app restart

**Given** the agent has created a terminal via `terminal.create`
**When** the user quits and relaunches the app
**Then** the terminal reappears in the same vibespace with its tab title and cwd preserved

---

## `terminal.list`

Lists all terminals in the channel client's vibespace.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `vibespace_id` | string | no | Defaults to caller's `CRISPY_VIBESPACE`. |

### Result

| Field | Type | Description |
|---|---|---|
| `terminals` | array of TerminalDescriptor | All terminals in the vibespace |

`TerminalDescriptor`:

| Field | Type | Description |
|---|---|---|
| `terminal_id` | string | UUID |
| `pane_id` | string | UUID of containing pane |
| `title` | string | Tab title (custom name or shell-reported title) |
| `cwd` | string | Current working directory of the shell |
| `engine` | string | `"ghostty"` or `"swiftterm"` |
| `focused` | boolean | True if this is the focused terminal in the vibespace |
| `is_caller` | boolean | True if this is the caller's own terminal |

### Requirements

#### F044-R3A: List excludes browser panels

`terminal.list` MUST return only terminals. Browser panels MUST NOT appear. (For browser panels, see `pane.list`.)

### Scenarios

#### Scenario F044-S85: List in current vibespace

**Given** the agent's vibespace has 3 terminals (one is the caller's, one is focused)
**When** the agent invokes `terminal.list`
**Then** the response includes 3 entries
**And** exactly one entry has `is_caller: true`
**And** exactly one entry has `focused: true` (may or may not be the caller)

#### Scenario F044-S86: List with no terminals

**Given** the vibespace has no terminals (only browser panels)
**When** the agent invokes `terminal.list`
**Then** the response is `terminals: []`

---

## `terminal.close`

Closes a terminal. The shell process is terminated and the tab disappears from the vibespace.

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `terminal_id` | string | no | UUID of the terminal to close. Defaults to caller's `CRISPY_CONTEXT`. |

### Result

Empty object on success.

### Requirements

#### F044-R3B: Close routes through TerminalProviding

`terminal.close` MUST call `TerminalProviding.closeTab(_:)` on the terminal's owning provider so persistence and UI state stay consistent.

#### F044-R3C: Closing caller terminal is allowed but warned

If `terminal_id` resolves to the caller's own terminal, the command MUST proceed (closing the terminal mid-call). The caller's CLI process will receive a write error when it tries to read the response — this is expected behavior. The CLI binary SHOULD detect this and exit silently rather than crashing.

### Scenarios

#### Scenario F044-S90: Close another terminal

**Given** the agent's vibespace has a second terminal at `terminal_id: "abc"`
**When** the agent invokes `terminal.close` with `terminal_id: "abc"`
**Then** the terminal is closed and removed from the vibespace
**And** the response is `ok: true`

#### Scenario F044-S91: Close caller's own terminal

**Given** the agent invokes `terminal.close` without `terminal_id`
**When** the server processes the request
**Then** the caller's terminal is closed
**And** the CLI binary exits without error

#### Scenario F044-S92: Close non-existent terminal

**When** the agent invokes `terminal.close` with `terminal_id: "nonexistent-uuid"`
**Then** the response is `terminal_not_found`

---

## `terminal.wait`

Blocks until a condition is met on a terminal, then returns. Used by agents that run a command and need to know when it completes (without polling `terminal.read` in a loop).

### Parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `terminal_id` | string | no | Defaults to caller's `CRISPY_CONTEXT`. |
| `text` | string | no | Wait until this exact substring appears in the terminal's output stream after the call begins. |
| `regex` | string | no | Wait until this Swift `NSRegularExpression`-compatible pattern matches. |
| `exit` | boolean | no | If true, wait until the terminal's process exits. |
| `timeout` | number | no | Seconds to wait before giving up. Default 30. Maximum 600. |

Exactly one of `text`, `regex`, or `exit` MUST be specified.

### Result

| Field | Type | Description |
|---|---|---|
| `matched` | boolean | True if the condition was met before timeout |
| `text` | string \| null | Match text (when `text`/`regex` triggered) |
| `match_groups` | array of string \| null | Capture groups (when `regex` triggered) |
| `exit_code` | integer \| null | Process exit code (when `exit` triggered) |

### Requirements

#### F044-R3D: One condition per call

If zero or more than one of `text`, `regex`, `exit` is specified, `terminal.wait` MUST return `invalid_params`.

#### F044-R3E: Timeout bounded

`timeout` MUST be in the range `(0, 600]` seconds. Out-of-range values return `invalid_params`.

#### F044-R3F: Output observation is buffered

The wait condition is evaluated against output produced **after** the request begins. The server MUST install an output observer at the start of the request so output between request begin and condition match is not missed.

#### F044-R3G: Connection held until completion

The socket connection MUST remain open until either the condition matches, the timeout fires, or the process exits. The server MUST NOT close the connection prematurely.

### Scenarios

#### Scenario F044-S95: Wait for build success message

**Given** the agent has just sent `"cargo build\n"` to a terminal
**When** the agent invokes `terminal.wait` with `text: "Compiling foo"` and `timeout: 60`
**Then** when "Compiling foo" appears in the terminal output, the response is `matched: true` and `text: "Compiling foo"`

#### Scenario F044-S96: Wait for regex match

**When** the agent invokes `terminal.wait` with `regex: "^Tests passed: (\\d+)"` and `timeout: 30`
**And** the terminal outputs `"Tests passed: 42"`
**Then** the response is `matched: true`, `text: "Tests passed: 42"`, `match_groups: ["42"]`

#### Scenario F044-S97: Wait for process exit

**Given** a long-running script is executing
**When** the agent invokes `terminal.wait` with `exit: true` and `timeout: 600`
**Then** when the script finishes, the response is `matched: true` and `exit_code: 0`

#### Scenario F044-S98: Timeout

**When** the agent invokes `terminal.wait` with `text: "never appears"` and `timeout: 5`
**Then** after 5 seconds the response is `matched: false`
**And** error code is `timeout`

#### Scenario F044-S99: Invalid combination

**When** the agent invokes `terminal.wait` with both `text: "foo"` and `exit: true`
**Then** the response is `invalid_params` with message naming the conflict
