# Agent CLI — Threat Model

## Overview

Agent CLI exposes a Unix-socket-backed control plane that lets in-app agent processes drive Crispy's UI, file system, terminals, shelf, and browser panels. Every CLI mutation routes through the same services as user clicks, so a compromised agent inheriting the channel client environment can do anything a user could do — open files, run shell input, exfiltrate text from terminals.

This document enumerates trust boundaries, attack surfaces, and mitigations.

## Trust Boundaries

| Boundary | Inside (trusted) | Outside (untrusted) |
|---|---|---|
| **Crispy process** | Swift services, `CLISocketServer`, `CLICommandRouter` | Anything reading the socket |
| **Same OS user** | Any process running as the user who launched Crispy | Other OS users (blocked by the `0600` socket) |
| **Project root** | Files under `CRISPY_PROJECT_PATH` after symlink resolution | Files outside the project for `file.*` commands |
| **Channel client env** | `CRISPY_*` env vars set by Crispy when spawning the terminal | Env vars set by agents themselves or downstream processes |
| **JSON-RPC payload** | Request fields whose schema is validated | Free-form strings (`text`, `path`, `js`, `selector`) |

## Attack Surfaces

1. **Unix domain socket** at `~/Library/Application Support/<bundle-id>/crispy.sock`
2. **CLI binary on PATH** at `<app>/Contents/Resources/bin/crispy`
3. **Environment variables** (`CRISPY_SOCKET`, `CRISPY_CONTEXT`, `CRISPY_VIBESPACE`, `CRISPY_PROJECT_PATH`)
4. **JSON-RPC parameters** — `file.*` paths, `terminal.send` text, `browser.eval` JS, etc.
5. **Surface IDs** — UUIDs leaked by `terminal.list` / `pane.list` to the calling agent

## Threats

### F044-T01: Same-user process connects to socket

- **Vector**: A same-user local process not spawned by Crispy connects to the socket to drive the IDE.
- **Impact**: Agent CLI control by a same-user process — bounded by what that process could already do as the user.
- **Likelihood**: Low–Medium — requires same-user local code execution.
- **Mitigation**: Socket file mode `0600` restricts access to the same OS user; cross-user access is blocked by the OS. The prior process-ancestry gate was **removed** (2026-05-30): it broke legitimate use (tmux, ssh, detached shells, ACP agents) while adding little real protection — a same-user process already has the user's full authority, so the CLI is not a privilege escalation against it. The residual concern is confused-deputy use of Crispy's TCC grants or app sessions; this is accepted under the same-user trust model and bounded by per-command authorization (project boundary, etc.).

### F044-T02: Compromised agent escapes project boundary

- **Vector**: A malicious `file.open` request with a path containing `..` or pointing through a symlink to surface files outside the project in the editor.
- **Impact**: Read or write any file the user account can access. Credential theft, persistence-mechanism installation.
- **Likelihood**: High — primary attack pattern against agent file ops.
- **Mitigation**: All `file.*` commands route through `ACPFileSystemHandler.resolvedPath(from:)`, which fully resolves symlinks on both the requested path and the project root, then verifies the resolved path is within the resolved root. Failures return `permission_denied` and are logged. Project root is read from authoritative app state, NOT from request params.

### F044-T03: Environment variable spoofing

- **Vector**: A child process inside an agent terminal overrides `CRISPY_PROJECT_PATH` or `CRISPY_VIBESPACE` to widen its scope (e.g. `CRISPY_PROJECT_PATH=/`).
- **Impact**: Could bypass project boundary if `_env` were trusted.
- **Likelihood**: Medium — trivially easy if `_env` were the security boundary.
- **Mitigation**: `CRISPY_*` env vars are convenience defaults, NOT authorization. The server resolves the actual project root via `terminal_id → vibespace → focused project`, never via `_env.project_path`. The `_env` values identify which terminal the agent thinks it is in; the server cross-checks against its own state. If the terminal ID does not exist in the running app, request falls back to focused state.

### F044-T04: Surface ID enumeration and impersonation

- **Vector**: An agent calls `pane.list` or `terminal.list` to discover other terminals' UUIDs, then targets them with `terminal.send` to inject keystrokes into another agent's session or the user's own terminals.
- **Impact**: Cross-session command injection.
- **Likelihood**: High in multi-agent scenarios.
- **Mitigation**: All cross-terminal mutations are logged with calling and target surface IDs via `AppDiagnostics`. **NOT prevented** in v1 — agents are trusted to operate within their vibespace, matching the existing ACP trust model. Documented in [usage-guide.md](usage-guide.md). Per-terminal ACLs are future work.

### F044-T05: Unbounded `terminal.read` exfiltration

- **Vector**: An agent reads sensitive content via `terminal.read` (scrollback may contain credentials, tokens, secrets typed earlier) and sends them to its own model API.
- **Impact**: Credential theft from terminal scrollback.
- **Likelihood**: Medium — depends on what users have typed.
- **Mitigation**: Inherent to giving agents terminal access. Crispy does not redact secrets from scrollback. Trust mode (F011 ACP) gates whether the agent runs unattended. Documented in [usage-guide.md](usage-guide.md).

### F044-T06: `browser.eval` arbitrary JavaScript

- **Vector**: An agent evaluates JS that reads cookies, localStorage, or other browser-scoped credentials from a page the user is signed in to.
- **Impact**: Cookie/token exfiltration from the embedded browser context.
- **Likelihood**: High — browser automation regularly uses `eval`.
- **Mitigation**: Browser panels are isolated per-vibespace. However, within the same vibespace, browser commands (including `eval`) can read any state in any panel. Users should treat any browser panel an agent has touched as compromised. Documented warning in [usage-guide.md](usage-guide.md).

### F044-T07: Resource exhaustion via wait commands

- **Vector**: Agent invokes `terminal.wait` with `timeout: 600` repeatedly, holding many connections open.
- **Impact**: DoS against legitimate CLI requests.
- **Likelihood**: Low accidentally; medium if malicious.
- **Mitigation**: Hard cap of 600 seconds per wait (parameter validation). Per-connection timeout of 700s at server level (defends against buggy clients). `listen(fd, 16)` bounds backlog.

### F044-T08: Malformed input causing parser crash

- **Vector**: Client sends arbitrary bytes to crash `JSONDecoder` or downstream handlers.
- **Impact**: Server crash or hung connection on main actor.
- **Likelihood**: Low — `JSONDecoder` is hardened.
- **Mitigation**: All decoder failures caught, converted to `invalid_params`. Connection-level errors close the connection without affecting other in-flight connections. Per-connection work happens off-main; only dispatch hop is on `@MainActor`.

### F044-T09: PATH injection via overridden CLI binary

- **Vector**: A process replaces or wraps the bundled `crispy` binary, then waits for an agent to invoke it. The wrapper exfiltrates requests.
- **Impact**: Man-in-the-middle on agent CLI traffic.
- **Likelihood**: Low — requires write access inside the .app bundle, which macOS code-signing prevents.
- **Mitigation**: Standard macOS code-signing protects the bundle. The bundled CLI directory is prepended to PATH but absolute paths in user shell config can override (out of scope — user trust).

### F044-T10: Stale socket file blocks startup

- **Vector**: A previous Crispy crash leaves the socket file behind; on next launch, `bind(2)` fails because the path is in use.
- **Impact**: CLI does not work after a crash until manual cleanup.
- **Likelihood**: Medium — inherent to Unix sockets across crashes.
- **Mitigation**: On startup, `CLISocketServer` removes any stale socket file at the configured path before `bind`. Safe because the directory is bundle-ID-scoped. If `bind` still fails, the server logs an error and the CLI feature degrades gracefully — agents see `not_connected`.

### F044-T11: Cross-project todo disclosure via `todo.list --scope vibespace`

- **Vector**: An agent scoped to one project calls `todo.list --scope vibespace` to read every todo across sibling projects and vibespace-level todos, widening the context it can see beyond its own project.
- **Impact**: Information disclosure of todo titles/bodies from sibling projects within the same vibespace.
- **Likelihood**: Low–Medium — requires the agent to opt into `scope=vibespace`; the default (`scope=project`) never crosses the project boundary.
- **Mitigation**: `scope=vibespace` is bounded to the *active* vibespace only — it cannot reach todos in other vibespaces or other app instances. The default scope is `project`, which requires a resolvable project and does not widen silently (F044-R90, F044-R91). Cross-project visibility within a vibespace is accepted under the same-user, in-vibespace trust model (see F044-T04): the app's own Todos Project/All toggle already exposes the same data to the user. No secrets are stored in todos by design; users should not paste credentials into todo bodies.

## Residual Risks

- **R1: In-vibespace agent isolation.** Multiple agents in the same vibespace can affect each other's terminals (F044-T04). v1 mitigation is documentation only. Future: per-terminal ACLs.
- **R2: Scrollback secrets.** `terminal.read` returns whatever is on screen, including secrets typed historically. Mitigation is user awareness.
- **R3: Browser panel cookie exposure.** Agents with browser access can read any state in panels in their vibespace.

## NFR Compliance

| NFR | Reference | Compliance |
|---|---|---|
| **SEC-1** Authentication | `nfr/security.md` | Met via owner-only `0600` socket (same-user); process-ancestry gate removed (F044-T01). |
| **SEC-2** Input validation | `nfr/security.md` | All commands validate params; malformed JSON closes connection. |
| **SEC-3** Authorization | `nfr/security.md` | Project boundary on file ops; bundle-isolated socket; not trusted-by-default. |
| **OBS-1** Logging | `nfr/observability.md` | All connection rejections, mutations, and cross-terminal targets logged via `AppDiagnostics`. |
| **OBS-3** Error visibility | `nfr/observability.md` | Errors surfaced as structured codes; also logged server-side. |
| **REL-2** Fault tolerance | `nfr/reliability.md` | Per-connection failures isolated; stale socket files cleaned at startup. |
