# Agent CLI — Technical Design

## Overview

Agent CLI is implemented as two cooperating components:

1. **`CLISocketServer`** — a Swift service inside the running Crispy app that listens on a Unix domain socket, parses JSON-RPC v2 requests, and dispatches them to existing `@MainActor` services through a single `CLICommandRouter`.
2. **`crispyvibes-cli`** — a Rust binary bundled inside the .app at `Contents/Resources/bin/crispy`, prepended to the `$PATH` of every terminal Crispy spawns. The CLI connects to the socket, sends one request, prints the response, and exits.

No new persistence, no new UI surface — every CLI operation routes through service methods the UI already calls. CLI-created artifacts are indistinguishable from user-created ones.

## Architecture

### Component Boundary

```
┌─────────────────────────────────────────────────────────────────────┐
│  Crispy.app process                                                  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  CLISocketServer (background DispatchQueue)                    │ │
│  │  • Unix socket bind, listen, accept loop                       │ │
│  │  • Per-connection: read JSON line → CLIRequest                 │ │
│  │  • Process-ancestry check via LOCAL_PEERPID                    │ │
│  │  • Dispatch hop to @MainActor                                  │ │
│  │  • Serialize response → write JSON line → close                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│         │ Task { @MainActor in router.dispatch(request) }            │
│         ▼                                                            │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  CLICommandRouter (@MainActor)                                  │ │
│  │  • Method namespace table (system.*, terminal.*, file.*, ...) │ │
│  │  • Resolves caller context from request._env or focused state  │ │
│  │  • Calls existing services                                     │ │
│  └────────────────────────────────────────────────────────────────┘ │
│         │ calls existing services                                    │
│         ▼                                                            │
│  TerminalProviding · ShelfStore · FileContentProviding · …          │
│  VibeSpaceCatalogStore · BrowserPanelViewModel                      │
└─────────────────────────────────────────────────────────────────────┘
         ▲ Unix socket: ~/Library/Application Support/<bundle-id>/crispy.sock
         │
┌─────────────────────────────────────────────────────────────────────┐
│  crispyvibes-cli (Rust binary)                                       │
│  • Resolve socket path from $CRISPY_SOCKET                          │
│  • Connect, send {id, method, params, _env}, read response          │
│  • Print JSON or human text                                          │
│  • Exit 0 on success, 1 on protocol error                            │
└─────────────────────────────────────────────────────────────────────┘
         ▲ invoked by
         │
┌─────────────────────────────────────────────────────────────────────┐
│  Agent (Claude, Codex, Kiro, …) inside a Crispy terminal             │
│   sees CRISPY_SOCKET, CRISPY_CONTEXT, CRISPY_VIBESPACE,       │
│        CRISPY_PROJECT_PATH and `crispy` on $PATH                    │
└─────────────────────────────────────────────────────────────────────┘
```

### Connection Model

The server uses a **one-shot connection per request** model: client connects, sends one JSON line, reads one JSON line, disconnects. This matches the existing persistence-helper pattern and avoids state on the server side.

Exception: `terminal.wait` and `browser.wait` keep the connection open until the wait condition is met or times out. The server installs an output observer (terminal) or page condition listener (browser) on the main actor, suspends the request task via `withCheckedContinuation`, and resumes when the condition fires.

### Concurrency

```
acceptQueue (DispatchQueue, serial)         connectionQueue (concurrent)        @MainActor
─────────────────────────────────           ─────────────────────────────       ──────────────
accept() loop                               read JSON line
                                            parse CLIRequest
                                            ancestry check
                                            ──── Task { @MainActor in ──────►   router.dispatch(request)
                                                                                 service call (e.g. shelfStore.addFiles)
                                            ◄──── await result ──────────────    return CLIResponse
                                            serialize
                                            write JSON line
                                            close fd
```

All service calls happen on `@MainActor` (matching the rest of the app). Socket I/O happens on background dispatch queues. Each connection is independent; multiple agents can issue commands concurrently.

## Data Flow

### Request lifecycle

1. **Spawn**: A Crispy terminal session injects `CRISPY_*` env vars and prepends the bundled `bin/` to `$PATH` (see [F044-R04, F044-R05](spec.md)).
2. **CLI invocation**: An agent inside the terminal runs `crispy <command>`. The Rust binary reads `$CRISPY_SOCKET` and connects.
3. **Request build**: The CLI constructs a JSON-RPC request:
   ```json
   {
     "id": "<uuid>",
     "method": "terminal.read",
     "params": { "scrollback": true },
     "_env": {
       "terminal_id": "<from CRISPY_CONTEXT>",
       "vibespace_id": "<from CRISPY_VIBESPACE>",
       "project_path": "<from CRISPY_PROJECT_PATH>"
     }
   }
   ```
4. **Server accept**: `CLISocketServer.acceptLoop` accepts the connection and verifies the peer is a descendant of Crispy via `LOCAL_PEERPID` + `proc_pidpath` ancestry walk.
5. **Dispatch**: `CLICommandRouter.dispatch(_:)` resolves implicit context (`terminal_id` from params or `_env`), looks up the method handler, and calls it on `@MainActor`.
6. **Service call**: Handler calls existing services (e.g. `terminalProvider.session(for:)?.sendRawText(text)`).
7. **Response**: Handler returns a `CLIResponse.ok(...)` or `.error(code:message:)`. The server serializes it as one JSON line, writes it to the socket, and closes the connection.
8. **CLI output**: The Rust binary prints the response (JSON if `--json`, otherwise human-readable) and exits.

### Wait command flow

For `terminal.wait` and `browser.wait`:

1. Steps 1–5 same as above.
2. Handler installs an observer on `@MainActor` (e.g. `session.onOutputReceived`).
3. Handler suspends via `withCheckedContinuation`.
4. The observer fires when output matching the condition arrives. The continuation resumes with the match result.
5. A timer task races against the continuation; if the timer fires first, the continuation resumes with `timeout`.
6. Response sent and connection closed.

### Surface persistence

CLI-initiated mutations route through the same service methods user clicks invoke. For example, `terminal.create`:

```swift
// CLICommandRouter.handleTerminalCreate
let provider = vibespaceCatalogStore.terminalProvider(for: vibespaceID)
let surfaceID = provider.createTab(
    directoryURL: cwd,
    customName: name,
    origin: .agentCLI(callerSurfaceID: callerSurfaceID)
)
return .ok(["terminal_id": surfaceID, ...])
```

The new `.agentCLI(callerSurfaceID:)` origin is added to the existing `TerminalOrigin` enum (alongside `.preset`, `.adHoc`, `.acp(sessionID:)`) so persistence and session restore handle CLI-created terminals natively.

## API / Command Contracts

### Method Namespace

Methods are dotted: `<category>.<action>`. Categories: `system`, `terminal`, `file`, `shelf`, `browser`, `vibespace`, `pane`. Each category has its own spec doc — see [spec.md](spec.md) for the full index.

### Request Schema

```swift
struct CLIRequest: Decodable {
    let id: String              // UUID
    let method: String          // dotted method name
    let params: JSONValue       // method-specific
    let _env: ChannelClientEnv  // injected by CLI from process env
}

struct ChannelClientEnv: Decodable {
    let terminal_id: String?
    let vibespace_id: String?
    let project_path: String?
}
```

### Response Schema

```swift
enum CLIResponse: Encodable {
    case ok(result: JSONValue, id: String)
    case error(code: String, message: String, id: String)
}
```

Wire format: one JSON object per line, newline-delimited.

### Error Codes

See [spec.md](spec.md#error-codes) for the canonical list. Adding a new error code requires updating that table.

## State Management

### CLISocketServer

| Property | Lifetime | Purpose |
|---|---|---|
| `socketPath: URL` | startup | Resolved at app launch from `AppPersistenceDataStore.applicationSupportURL` |
| `listenFD: Int32` | server lifetime | Unix socket file descriptor; closed on shutdown |
| `acceptQueue: DispatchQueue` | server lifetime | Serial background queue for the accept loop |
| `connectionQueue: DispatchQueue` | server lifetime | Concurrent queue for per-connection work |
| `running: Atomic<Bool>` | server lifetime | Coordinates clean shutdown |

### CLICommandRouter

Stateless. Holds references to existing service instances injected at construction.

### Per-Connection State

None persisted. Each connection's request lives only in the dispatch task's stack.

## Dependencies (frameworks, libraries)

### Swift side
- `Foundation` — `JSONDecoder`/`JSONEncoder`, `DispatchQueue`, `Task`
- `Darwin` — `socket(2)`, `bind(2)`, `listen(2)`, `accept(2)`, `getsockopt(SOL_LOCAL, LOCAL_PEERPID)`, `proc_pidpath`
- Existing services through `AppContainer`: `TerminalProviding`, `ShelfStore`, `FileContentProviding`, `VibeSpaceCatalogStore`, `BrowserPanelViewModel`

No new SwiftPM packages.

### Rust side (`crispyvibes-cli`)

```toml
[dependencies]
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1", features = ["v4"] }
```

No async runtime. Synchronous `UnixStream` is sufficient since each invocation is one request/response.

## Platform Considerations

### Socket Path Resolution

The socket path is bundle-ID-scoped (see [F044-R03](spec.md)):

```
~/Library/Application Support/<bundle-id>/crispy.sock
```

For example:
- `com.crispyvibe.app` → `~/Library/Application Support/com.crispyvibe.app/crispy.sock`
- `com.crispyvibe.app.local` → `~/Library/Application Support/com.crispyvibe.app.local/crispy.sock`

This ensures `Crispy.app` and `CrispyLocal.app` running on the same machine each have their own socket and never cross-talk.

### Sandboxing

The macOS App Sandbox does NOT block Unix domain sockets created in the app's container directory (which `~/Library/Application Support/<bundle-id>/` is). No additional entitlements needed.

### Process Ancestry

`getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, ...)` returns the connecting process's PID. We then walk up the parent chain via `proc_pidinfo(...)` until we find Crispy's own PID or hit PID 1. If Crispy's PID never appears, the connection is rejected and the socket closed before any request is read.

### Ghostty Engine Bridge

`terminal.read` requires a screen-buffer read API on the terminal engine. Ghostty's libghostty (linked as `GhosttyKit.xcframework`) does not expose this directly — we add a Swift bridge through the existing `GhosttyTerminalEngine` that calls into Ghostty's terminal API to capture the screen as text. SwiftTerm-backed surfaces return `unsupported_engine` (see [F044-R30](commands-terminal.md)).

## Performance Constraints

| Path | Budget | Notes |
|---|---|---|
| `ping` round-trip | < 5ms | Includes connect, ancestry check, dispatch, response. Validated by an integration test. |
| `terminal.read` (visible only) | < 20ms | Ghostty buffer read is cheap; bottleneck is JSON serialization for large screens. |
| `terminal.read` (full scrollback) | < 100ms for 4000 lines | Within existing scrollback persistence target. |
| `pane.list` | < 10ms | Snapshots of in-memory state. |

The server MUST NOT block the main actor for more than a single dispatch hop. Any I/O (file reads, browser eval) happens off-main where possible, hopping back to main only for the final mutation.

### CLI startup time

The Rust CLI startup is ~2–5ms (static binary, no runtime init). This is critical because agents call `crispy` thousands of times per session.

## Migration / Rollout Notes

### App-side rollout

1. Add `CLISocketServer`, `CLICommandRouter` services. Wire through `AppContainer.makeDefault()`.
2. Add `.agentCLI(callerSurfaceID:)` origin to `TerminalOrigin`.
3. Inject `CRISPY_*` env vars in `TerminalSession.startProcess()`.
4. Prepend `<app>/Contents/Resources/bin` to `$PATH` in the same code path.
5. Add Ghostty screen-read bridge for `terminal.read`.
6. Start server in `AppDelegate.applicationDidFinishLaunching`. Stop in `applicationWillTerminate`.

### Rust-side rollout

1. Add `crispyvibes-cli` crate to the existing Rust workspace at `projects/crispyvibes/rust/`.
2. Wire it into the existing Xcode build phase that compiles the other helpers.
3. Configure the build phase to copy the binary to `<app>/Contents/Resources/bin/crispy`.

### Backward compatibility

There is no prior version. The `CRISPY_*` env vars and `crispy` binary are new — agents that don't know about them are unaffected.

### Disablement

The socket server can be disabled via `CrispyVibesEnableAgentCLI` Info.plist key (matching the pattern used for `CrispyVibesEnableSparkleUpdater`). When disabled, the socket is never bound, the env vars are not injected, and the binary is still bundled but never invoked.

## Open Implementation Questions

### Should the CLI binary cache the socket connection across multiple invocations?

Currently NO — each `crispy` invocation opens a new connection, sends one request, disconnects. This matches `git`, `kubectl`, and similar tools. A long-running agent making thousands of calls pays ~3ms per call for connection setup.

If profiling shows this is a bottleneck, an option is to support a persistent connection mode where one CLI invocation acts as a multiplexer for the agent's child shell processes. Out of scope for v1.

### Where do we surface server-side errors to the user?

The server logs through `AppDiagnostics` (existing pattern, same as Sparkle). Connection rejections, malformed requests, and internal errors all appear in diagnostic logs but do not pop UI. Adding a "CLI activity" panel in Settings is future work.
