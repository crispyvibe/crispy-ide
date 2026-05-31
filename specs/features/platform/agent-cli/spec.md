# Agent CLI — Spec

Status: implemented

## Overview

Agent CLI provides a programmatic control surface for AI agents running inside Crispy terminals. Agents invoke the bundled `crispy` command-line tool, which connects to a Unix domain socket served by the running app and dispatches commands to existing services through a JSON-RPC v2 protocol. This lets agents read terminal state, send input to terminals, open files, manage the shelf, control browser panels, and inspect VibeSpace topology — all without spawning a separate agent process or duplicating IDE logic.

The CLI is consumed primarily by AI coding agents (Claude Code, Codex, Kiro, OpenCode, etc.) that run inside Crispy terminal sessions, and is exposed to those processes via PATH injection and discovery environment variables. Authorization is the socket's owner-only (`0600`) permission: any process running as the same OS user can connect — including shells under tmux/ssh and ACP agents — while other OS users are blocked by the filesystem. (Revised from the original app-descendant-only model; see Change History and F044-R02.)

## Implementation Status

The CLI ships in stages. Foundation (transport, authorization, env injection, PATH integration) and the read-only / mutation commands needed for the core agent loop are live. Browser automation and vibespace inspection commands are spec'd but deferred.

| Category | Commands | Status |
|---|---|---|
| System | `ping`, `whoami`, `help` | shipped |
| Shelf | `shelf.add`, `shelf.list`, `shelf.remove` | shipped |
| Files | `file.open` | shipped |
| Shortcuts | `shortcut.list`, `shortcut.add`, `shortcut.remove` | shipped |
| Terminal | `terminal.list`, `terminal.create`, `terminal.send`, `terminal.send_key`, `terminal.close`, `terminal.wait` | shipped |
| Terminal | `terminal.read` | deferred — needs Ghostty screen-buffer bridge (see [F044-R30](commands-terminal.md)) |
| Browser | `browser.list`, `browser.open`, `browser.close` | shipped |
| Browser | `browser.snapshot`, `browser.navigate`, `browser.back`, `browser.forward`, `browser.reload`, `browser.eval`, `browser.click`, `browser.type`, `browser.wait`, `browser.screenshot`, `browser.console`, `browser.dialog` | deferred |
| VibeSpace | `vibespace.list`, `vibespace.current`, `pane.list` | deferred |

## Dependencies

- **F001 (Terminal Sessions & Tabs)** — terminal commands route to `TerminalProviding`/`TerminalSession`
- **F011 (ACP)** — file commands reuse `ACPFileSystemHandler` path-boundary logic
- **F012 (Browser)** — browser commands route to the embedded browser panel
- **F020 (VibeSpace Lifecycle)** — vibespace and pane commands route to `VibeSpaceCatalogStore`
- **F033 (Shelf)** — shelf commands route to `ShelfStore`
- **SEC-1, SEC-3** — socket access control, command authorization

## Glossary

| Term | Definition |
|------|-----------|
| Surface | A terminal or browser tab inside a pane. Surface ID is a UUID. |
| Pane | A split container holding terminals, browser panels, or editor tabs inside a vibespace. |
| Channel client | Any process — typically an agent — invoking the `crispy` CLI. |
| Caller terminal | The terminal the channel client is running inside, identified by the `CRISPY_CONTEXT` env var. |
| Channel context | The implicit (vibespace, project, terminal) tuple a channel client inherits from environment variables. |

## Requirements

### Transport & Discovery

#### F044-R01: Unix Domain Socket Transport

The app MUST listen on a Unix domain socket at a bundle-ID-scoped path under `~/Library/Application Support/<bundle-id>/crispy.sock`. Connections MUST use newline-delimited JSON. Socket file permissions MUST be `0600`.

#### F044-R02: Owner-Only Socket Authorization

Authorization MUST be the socket file's owner-only (`0600`) permission: only the same OS user can connect. The CLI MUST be usable by any same-user process — shells under tmux/ssh, ACP agents, and other tooling — without a process-ancestry or token gate. (Supersedes the prior process-ancestry check; see Change History and threat-model F044-T01.)

#### F044-R03: Bundle Isolation

Each app build (Production, Local, Nightly) MUST use a distinct socket path scoped by bundle identifier so that multiple Crispy instances on the same machine do not collide.

#### F044-R04: Environment Variable Injection

Every terminal session spawned by Crispy MUST inject the following environment variables into the child shell process:
- `CRISPY_SOCKET` — absolute path to the active socket
- `CRISPY_CONTEXT` — tagged caller ID: `terminal.<uuid>` for an agent running inside a Crispy terminal, or `acpchat.<uuid>` for an ACP-spawned agent
- `CRISPY_VIBESPACE` — tagged ID of the focused vibespace at process spawn time (e.g. `vibespace.<uuid>`)
- `CRISPY_PROJECT_PATH` — absolute path of the focused project at process spawn time

#### F044-R05: PATH Injection

Every terminal session spawned by Crispy MUST prepend the bundled CLI binary directory (`<app>/Contents/Resources/bin`) to `$PATH` so that agents can invoke `crispy` without configuration.

### Protocol

#### F044-R06: JSON-RPC v2 Request Format

Each request MUST be a single JSON object on one line containing `id` (string UUID), `method` (dotted namespace, e.g. `terminal.read`), and `params` (object). The server MUST reject requests with malformed JSON, missing required fields, or unrecognized methods.

#### F044-R07: Response Format

Each response MUST be a single JSON object on one line containing the same `id` as the request, `ok` (boolean), and either `result` (object on success) or `error` (object with `code` and `message` on failure). Embedded newlines in string values MUST be escaped.

#### F044-R08: Connection Lifecycle

The default connection model is one request per connection: client connects, sends one request, reads one response, disconnects. Long-running commands (e.g. `terminal.wait`) MAY hold the connection open until the condition completes or the request times out.

### Authorization

#### F044-R09: Caller-Implicit Context

Commands that operate on a terminal, vibespace, or project MUST resolve identifiers from request parameters first, then fall back to the channel client's environment variables (`CRISPY_CONTEXT`, `CRISPY_VIBESPACE`, `CRISPY_PROJECT_PATH`). If neither yields a valid identifier, the command MUST fail with `invalid_params`.

#### F044-R10: Project Boundary Enforcement

File commands (currently just `file.open`) MUST resolve the target path relative to the channel client's `CRISPY_PROJECT_PATH` and reject paths that escape the project root after symlink resolution.

#### F044-R11: Persistence Parity

CLI-initiated mutations (terminal create/close, shelf add/remove, browser open) MUST go through the same service methods used by user interactions. CLI-created artifacts MUST persist across app restarts identically to user-created ones.

### Behavior

#### F044-R12: Idempotency on Read

Read commands (`*.read`, `*.list`, `*.snapshot`, `system.*`) MUST be free of observable side effects.

#### F044-R13: Backpressure

The server MUST handle concurrent connections without blocking the main UI actor. Per-connection work MUST hop to the main actor only for the actual service call, then hop back to a background queue for I/O.

#### F044-R14: Unrecognized Methods

Unrecognized methods MUST return error code `unknown_method` with the requested method name in the message.

#### F044-R15: Timeout Bounds

Wait-style commands MUST accept a `timeout` parameter (seconds, default per command) and MUST return a `timeout` error if the condition is not met before the deadline.

## Command Categories

Detailed per-command requirements and scenarios live in category-specific docs:

| Category | Doc | Commands |
|---|---|---|
| System | [commands-system.md](commands-system.md) | `ping`, `whoami`, `help` |
| Terminal | [commands-terminal.md](commands-terminal.md) | `terminal.read`, `terminal.send`, `terminal.send_key`, `terminal.create`, `terminal.list`, `terminal.close`, `terminal.wait` |
| Files | [commands-files.md](commands-files.md) | `file.open` |
| Shelf | [commands-shelf.md](commands-shelf.md) | `shelf.add`, `shelf.list`, `shelf.remove` |
| Browser | [commands-browser.md](commands-browser.md) | `browser.open`, `browser.snapshot`, `browser.navigate`, `browser.back`, `browser.forward`, `browser.reload`, `browser.eval`, `browser.click`, `browser.type`, `browser.wait`, `browser.screenshot`, `browser.console`, `browser.dialog` |
| Shortcuts | [commands-shortcuts.md](commands-shortcuts.md) | `shortcut.list`, `shortcut.add` |
| VibeSpace | [commands-vibespace.md](commands-vibespace.md) | `vibespace.list`, `vibespace.current`, `pane.list`, `vibespace.addProject`, `vibespace.removeProject`, `vibespace.parkProject` |

## Error Codes

| Code | Meaning |
|---|---|
| `unknown_method` | The method name is not recognized |
| `invalid_params` | Required parameter missing or malformed |
| `terminal_not_found` | Referenced terminal ID does not exist |
| `vibespace_not_found` | Referenced vibespace ID does not exist |
| `pane_not_found` | Referenced pane ID does not exist |
| `file_not_found` | File path does not exist |
| `permission_denied` | Path escapes project root or operation not permitted |
| `unsupported_engine` | Operation requires Ghostty engine but terminal is on SwiftTerm |
| `timeout` | Wait condition not met before deadline |
| `not_connected` | Required subsystem (browser, terminal) not available |
| `internal_error` | Unhandled server error |

## Scenarios

Cross-cutting transport and authorization scenarios are defined here. Per-command scenarios live in the category docs.

### Scenario F044-S01: Agent process inside Crispy terminal connects to socket

**Given** a terminal is opened in Crispy
**And** the spawned shell has `CRISPY_SOCKET`, `CRISPY_CONTEXT`, `CRISPY_VIBESPACE`, and `CRISPY_PROJECT_PATH` set
**When** an agent process running in that terminal invokes `crispy ping`
**Then** the CLI connects to the socket at `$CRISPY_SOCKET`
**And** receives a successful response containing `version` and `app`

### Scenario F044-S02: Same-user vs other-user access

**Given** the Crispy app is running and the socket file exists with `0600` permissions
**When** a process owned by a *different* OS user attempts to connect
**Then** the OS denies access at the socket file permission level
**And When** a same-user process that Crispy did not spawn (e.g. a shell under tmux, or an ACP agent) connects
**Then** the connection is accepted and served

### Scenario F044-S03: Channel client omits terminal_id parameter

**Given** an agent runs inside a Crispy terminal with `CRISPY_CONTEXT` set
**When** the agent invokes a command like `terminal.read` without an explicit `terminal_id` parameter
**Then** the server resolves the target terminal from `CRISPY_CONTEXT` provided by the client
**And** the command operates on the caller's surface

### Scenario F044-S04: Channel client outside any terminal omits terminal_id

**Given** the channel client has no `CRISPY_CONTEXT` env var (e.g. invoked from a script outside a Crispy terminal but with auth somehow allowed)
**When** a command requiring a surface is invoked without `terminal_id`
**Then** the server returns `invalid_params` with message `"terminal_id required"`

### Scenario F044-S05: Two Crispy app instances on the same machine

**Given** both `Crispy.app` and `CrispyLocal.app` are running on the same machine
**When** terminals from each spawn child processes that invoke `crispy`
**Then** each child connects to its own bundle-ID-scoped socket
**And** commands are routed to the correct app instance

### Scenario F044-S06: App restarts; CLI-created artifacts persist

**Given** an agent has used the CLI to create a terminal, add files to the shelf, and open a browser panel
**When** the user quits and relaunches the Crispy app
**Then** the created terminal, shelf entries, and browser panel reappear in the same vibespace exactly as if the user had created them manually

### Scenario F044-S07: Unrecognized method

**Given** the socket server is running
**When** a client sends a request with method `terminal.fly`
**Then** the server responds with `ok: false` and error code `unknown_method`
**And** the connection is closed cleanly

### Scenario F044-S08: Malformed JSON

**Given** the socket server is running
**When** a client sends a non-JSON line followed by a newline
**Then** the server closes the connection
**And** logs the parse failure with the socket peer PID

### Scenario F044-S09: Concurrent commands from the same agent

**Given** an agent invokes two `crispy` commands simultaneously from two parallel shell processes
**When** both connect at roughly the same time
**Then** the server accepts both connections
**And** dispatches each request on its own task without blocking the other

## Acceptance Criteria

- All requirements F044-R01 through F044-R15 implemented and covered by tests
- Each command category doc has at least one happy-path and one error scenario per command
- Build succeeds on `crispyvibes-local` scheme with the new `CLISocketServer` service wired through `AppContainer`
- A reference Rust CLI (`crispyvibes-cli` crate) builds and successfully invokes `ping` and `identify` against the running app
- `terminal.read`, `terminal.send`, `file.open`, `shelf.add`, and `browser.open` work end-to-end from a real agent process
- Same-user access verified: a non-app-spawned same-user process connects and is served; cross-user access is blocked by the `0600` socket permission

## Open Questions

None at this time.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-14 | Initial draft extracted from prior planning notes | Manu |
| 2026-05-17 | Marked feature implemented; added per-category implementation status table; retired planning docs | Manu |
| 2026-05-30 | Replaced process-ancestry authorization (F044-R02) with owner-only `0600` socket access so any same-user process (incl. ACP agents, tmux/ssh shells) can use the CLI; removed `CLIProcessAncestry` and the bypass flag. See F051 (Remote Agent CLI). | Manu |
