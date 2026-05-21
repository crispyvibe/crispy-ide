# Browser CLI Commands — Technical Design

## Overview

Wire 51 browser commands through the Agent CLI socket to the existing `BrowserAgentAPI` Playwright-style automation layer. The infrastructure is fully built — this work is pure routing.

## Architecture

### Dispatch Path

```
crispy browser <subcommand> [--browser_id <id>] [args...]
       │
       ▼
CLICommandRouter.handleBrowser(request)
       │
       ├─ browser.list / browser.open / browser.close  →  DockedBrowserCoordinator directly
       │
       └─ all other 48 methods  →  coordinator.agentAPI(for: tileID)?.dispatch(method:params:)
                                          │
                                          ▼
                                    BrowserAgentAPI.dispatch(method:params:)
                                          │
                                          ▼
                                    WKWebView.evaluateJavaScript (existing)
```

### Key Insight: Single Dispatch Point

`BrowserAgentAPI.dispatch(method:params:)` already handles all 48 per-tab commands with a switch statement. The CLI handler doesn't need 48 separate methods — it just:
1. Resolves `browser_id` → `UUID`
2. Gets `BrowserAgentAPI` from coordinator
3. Forwards `(method, params)` verbatim
4. Converts `BrowserAgentAPI.Result` → `CLIResponse`

### Code Strategy

Given 51 commands but only 1 dispatch path, the implementation is:

| Component | New Code | Strategy |
|-----------|----------|----------|
| `CLICommandRouterBrowserHandlers.swift` | ~120 LOC | One `handleBrowser` method that forwards to `BrowserAgentAPI.dispatch`. Three special-case methods for `list`, `open`, `close`. |
| `CLICommandRouter.swift` (registry) | ~200 LOC | 51 `CommandRegistration` entries. These are data declarations (method name, param descriptors for `help`), not logic. |
| `crispyvibes-cli/src/main.rs` | ~150 LOC | `BrowserCommand` enum with subcommands. Most map directly to `browser.<method>` with params forwarded as JSON. |
| `AppContainer.swift` | 2 LOC | Wire `DockedBrowserCoordinator` into `CLICommandRouter`. |

**Total: ~470 LOC across 4 files. No new types, no new patterns.**

## Wiring

### CLICommandRouter gets DockedBrowserCoordinator

```swift
// CLICommandRouter.swift
var dockedBrowserCoordinator: DockedBrowserCoordinator?

func attachDockedBrowserCoordinator(_ coordinator: DockedBrowserCoordinator) {
    self.dockedBrowserCoordinator = coordinator
}
```

Wired in `AppContainer.makeContentViewDependencies()` alongside the existing `attachVibeSpaceCatalogStore`.

### Handler: Generic Browser Dispatch

```swift
// CLICommandRouterBrowserHandlers.swift
extension CLICommandRouter {
    func handleBrowser(_ request: CLIRequest) async -> CLIResponse {
        let method = request.method

        // Management commands (not per-tab)
        switch method {
        case "browser.list": return handleBrowserList(request)
        case "browser.open": return await handleBrowserOpen(request)
        case "browser.close": return handleBrowserClose(request)
        default: break
        }

        // Per-tab commands: resolve browser_id → agentAPI → dispatch
        guard let browserID = request.params?["browser_id"]?.stringValue,
              let uuid = CLITaggedID.extractID(from: browserID, expectedKind: "browser") ?? UUID(uuidString: browserID),
              let coordinator = dockedBrowserCoordinator,
              let api = coordinator.agentAPI(for: uuid) else {
            return .error(id: request.id, code: CLIErrorCode.notFound, message: "Browser not found")
        }

        // Strip browser_id from params before forwarding
        var forwardParams: [String: Any] = [:]
        if let params = request.params {
            for (key, value) in params.asDictionary where key != "browser_id" {
                forwardParams[key] = value.toAny()
            }
        }
        // BrowserAgentAPI uses "surface_id" internally
        forwardParams["surface_id"] = uuid.uuidString

        let result = await api.dispatch(method: method, params: forwardParams)
        switch result {
        case .ok(let dict): return .ok(id: request.id, result: dict.toCLIJSON())
        case .err(let code, let message): return .error(id: request.id, code: code, message: message)
        }
    }
}
```

### Async Handling

`BrowserAgentAPI.dispatch` is `async` (JS evaluation). The socket server already supports async handlers via `Task { @MainActor in }`. The `handleBrowser` method is marked `async` and awaits the result before responding.

Current `CLICommandRouter.dispatch` is synchronous. We add an async variant:

```swift
func dispatchAsync(_ request: CLIRequest) async -> CLIResponse {
    if request.method.hasPrefix("browser.") {
        return await handleBrowser(request)
    }
    return dispatch(request) // existing sync path
}
```

The socket server calls `dispatchAsync` instead of `dispatch`.

## Command Categories

### Management (3 commands — custom handlers)

| Method | Params | Returns |
|--------|--------|---------|
| `browser.list` | `query?` | `tabs: [{id, title, url}]` |
| `browser.open` | `url?` | `browser_id` |
| `browser.close` | `browser_id` | `closed: bool` |

### Per-Tab (48 commands — forwarded to BrowserAgentAPI)

All take `browser_id` (required) plus method-specific params. The CLI strips `browser_id`, adds `surface_id`, and forwards.

**Navigation (4)**: navigate, back, forward, reload
**URL/Title (2)**: url.get, get.title
**DOM Interaction (10)**: click, dblclick, hover, focus, fill, type, press, check, uncheck, scroll_into_view
**Form (2)**: select, scroll
**DOM Queries (7)**: get.text, get.html, get.value, get.attr, get.count, get.box, get.styles
**State Checks (3)**: is.visible, is.enabled, is.checked
**Element Finding (10)**: find.role, find.text, find.label, find.placeholder, find.alt, find.title, find.testid, find.first, find.last, find.nth
**Advanced (4)**: snapshot, eval, wait, screenshot
**Cookies/Storage (4)**: cookies.get, cookies.set, cookies.clear, storage.get
**Dialogs (2)**: dialog.accept, dialog.dismiss

## Rust CLI Design

The Rust CLI groups browser commands under `crispy browser <subcommand>`:

```
crispy browser list [--query <text>]
crispy browser open [--url <url>]
crispy browser close <browser_id>
crispy browser <browser_id> navigate <url>
crispy browser <browser_id> back
crispy browser <browser_id> click --selector <sel>
crispy browser <browser_id> snapshot [--max-depth <n>]
crispy browser <browser_id> eval <script>
crispy browser <browser_id> wait --selector <sel> [--timeout <ms>]
crispy browser <browser_id> screenshot
...
```

The `<browser_id>` is positional. All per-tab commands follow `crispy browser <id> <action> [args]`.

Internally, the Rust CLI maps every subcommand to the corresponding `browser.*` JSON-RPC method and forwards params as a flat JSON object.

## Registry Strategy

Instead of 51 individual `CommandRegistration` entries with full param descriptors, we use a **bulk registration** approach:

```swift
// One registration per method, but descriptors are minimal for forwarded commands
static let browserForwardedMethods: [(method: String, summary: String)] = [
    ("browser.navigate", "Navigate to a URL"),
    ("browser.back", "Go back"),
    ...
]
```

The `help` output for forwarded commands shows the method name and summary. Detailed param docs live in the spec (agents read `crispy help browser` for the overview, then the spec for full schemas).

## Performance

- `browser.list`: < 5ms (in-memory dict scan)
- `browser.navigate`: < 10ms (fires WKWebView load, returns immediately)
- `browser.eval`: 5–50ms (depends on JS complexity)
- `browser.wait`: up to timeout (default 5s), holds connection open
- `browser.screenshot`: 50–200ms (WKWebView snapshot + PNG encode)
- `browser.snapshot`: 20–100ms (DOM walk via JS)

## Error Handling

BrowserAgentAPI already returns structured errors (`code` + `message`). These map directly to CLIResponse errors. Common codes:
- `not_found` — element not found by selector
- `invalid_params` — missing required param
- `js_error` — JavaScript execution failed
- `timeout` — wait condition not met
- `unavailable` — no WebView (browser closed during operation)

## Testing Strategy

1. **Unit**: Mock `BrowserAgentAPI` dispatch, verify CLI handler forwards correctly
2. **Integration**: `crispy browser list` from CrispyLocal terminal with a browser tab open
3. **E2E**: `crispy browser <id> navigate https://example.com && crispy browser <id> snapshot`

## Files Modified

| File | Change |
|------|--------|
| `CLICommandRouterBrowserHandlers.swift` | **New** — handleBrowser, handleBrowserList, handleBrowserOpen, handleBrowserClose |
| `CLICommandRouter.swift` | Add browser registrations, `dispatchAsync`, `dockedBrowserCoordinator` property |
| `AppContainer.swift` | Wire coordinator to router |
| `CLISocketServer.swift` | Call `dispatchAsync` instead of `dispatch` |
| `crispyvibes-cli/src/main.rs` | Add `BrowserCommand` enum and dispatch |
| `specs/features/platform/agent-cli/commands-browser.md` | Update with full 51-command spec |
