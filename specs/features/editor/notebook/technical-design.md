# Jupyter Notebook Support — Technical Design

## Overview

`.ipynb` files are rendered by the **Jupyter Notebook 7 web app** inside a
`WKWebView`, backed by a **locally spawned Jupyter Server**. Swift owns the process
lifecycle, the web-view hosting/arbitration, and the comment bridge; Jupyter owns
the kernel protocol, output rendering, and persistence. The integration plugs into
the existing editor pipeline rather than introducing a new tab type.

## Architecture

```
ContentViewer (.file tab, .ipynb)
  └─ MarkdownEditorView (documentType == .notebook)
       └─ EditorPluginRegistry → NotebookEditorPlugin
            └─ NotebookEditorView (SwiftUI)
                 ├─ @Environment jupyterServerService: JupyterServerService
                 └─ NotebookWebViewHost (NSViewRepresentable)
                      └─ NotebookHostContainerView ──┐ (one per surface)
                                                     ▼
                              NotebookWebViewArbiter (1 per notebook path)
                                ├─ WKWebView (persistent, re-parented)
                                ├─ NotebookNavigationDelegate (origin confinement + didFinish)
                                └─ NotebookCommentBridge (cell-id comment adapter)
                                          │ HTTP/WebSocket (127.0.0.1 + token)
                                          ▼
                              jupyter notebook (spawned Process)
```

Key types (all in `Features/Editor/Views/NotebookEditorView.swift`):

- **`JupyterServerService`** (`@MainActor`, app-wide, injected via `AppContainer`
  and SwiftUI environment): spawns/owns Jupyter servers and the per-notebook
  web-view arbiters; resolves availability; `shutdownAll()`.
- **`NotebookEditorView`**: SwiftUI surface with `starting / ready / unavailable /
  failed` states; resolves the notebook URL and the shared arbiter; wires comments.
- **`NotebookWebViewArbiter`** (one per notebook path): owns the persistent
  `WKWebView`, re-parents it to the highest-priority visible host, reloads on
  external change, and owns the comment bridge.
- **`NotebookHostContainerView`** (`NSView`): one per mounted surface; drives
  recency-based ownership arbitration via window/visibility transitions.
- **`NotebookNavigationDelegate`**: confines top-level navigation to the loopback
  origin; fires `onDidFinish` for bundle (re)injection.
- **`NotebookCommentBridge`** (`WKScriptMessageHandler`): cell-id comment adapter.

## Data Flow

**Open:** `detectDocumentType(.ipynb) → .notebook` → plugin → `NotebookEditorView`
→ `service.isJupyterAvailable()` → `service.notebookURL(for:)` (lazily starts the
server rooted at the notebook's directory, health-polls `/api/status`) →
`service.webViewArbiter(forNotebook:url:)` → host renders the shared web view.

**Server start:** reserve a free loopback port (bind `:0`) → generate a 24-byte
hex token → spawn `/usr/bin/env jupyter notebook --no-browser --ip=127.0.0.1
--port=N --ServerApp.token=… --ServerApp.open_browser=False --ServerApp.root_dir=…`
with `CommandPathResolver.environmentWithResolvedPath()` → poll
`http://127.0.0.1:N/api/status?token=…` until `200`.

**Remote (SSH) server start (F050-R13):** the plugin passes
`viewModel.fileContentProvider?.remoteNotebookHost` (the `SFTPFileContentProvider`
vends its `SSHConnection`, which conforms to `RemoteNotebookHosting`) to
`NotebookEditorView`, and `service.notebookURL(for:remoteHost:)` branches to
`ensureRemoteServer`. There: generate the token + reserve a *local* loopback port →
`host.runLoginScript(...)` runs a `bash -l -s` script (fed via stdin over the
ControlMaster) that picks a free *remote* loopback port in `python3`, launches a
detached `jupyter notebook` bound to it, and echoes `OK <pid> <port>` (or `ERR
no-jupyter`/`no-python` → `.unavailable`) → `host.forwardPort(local→remote)` issues
`ssh -O forward -L` on the existing socket → poll `http://127.0.0.1:localPort/api/
status?token=…` until `200`. Servers are keyed `host|rootDir`; a `RemoteHandle`
(host, pid, ports) drives teardown (`cancelForward` + remote `kill`) in
`shutdownAll`.

**Execution & save:** handled entirely by Notebook 7 against the spawned server
over its WebSocket kernel protocol and Contents API.

**External change:** `JupyterServerService` arbiter observes
`.fileSystemContentsDidChange`; if the notebook path changed, debounce (400 ms) and
`webView.reload()`.

**Comments:** see API Contracts below.

## API / Command Contracts

Comment bridge ↔ in-page adapter (`WKScriptMessage`):

| Direction | Name | Payload |
|-----------|------|---------|
| JS → Swift | `nbCommentsRequestAdd` | `{domSelector: cellId, domFingerprint, anchorText, startLine=cellNum, …, body}` |
| JS → Swift | `nbCommentsGutterClick` | `{threadID}` |
| Swift → JS | `setComments(threads, selectedId)` | `[{id, cellId, fingerprint, status}]` |
| Swift → JS | `scrollTo(cellId)` | cell id string |

Anchor mapping onto `CommentAnchor` (no schema change): `domSelector` = cell id,
`domFingerprint` = hash of cell source, `startLine`/`endLine` = 1-based cell number
(drives the "Cell N" label), `anchorText` = selected text (fuzzy fallback).
Comments are stored via `VibeSpaceCommentStore.add(filePath:…, surfaceKind: .file)`
keyed by the notebook file path.

## State Management

- `JupyterServerService` keys `servers` and `arbiters` by directory / notebook path.
- The arbiter holds the single `WKWebView`; `NotebookHostContainerView` instances
  contend for it by a monotonically increasing claim sequence (most-recently-shown
  surface wins; ownership falls back when a surface hides).
- `NotebookEditorView` is stateless beyond its `phase`; comment wiring is idempotent
  and re-applied on appear, on `store.changes`, and on `onPageLoaded`.

## Dependencies (frameworks, libraries)

- WebKit (`WKWebView`), AppKit (`NSView` re-parenting), Foundation `Process`,
  Darwin sockets (free-port reservation).
- The user's `jupyter notebook` (Notebook 7) install — not bundled.

## Platform Considerations

- macOS only. Server is a child `Process`; loopback-only binding.
- Notebook 7 is a virtualized SPA: off-screen cells may not be in the DOM, so the
  comment adapter uses a `MutationObserver` (disconnected during its own writes) to
  re-apply decorations as cells render.

## Performance Constraints

- Server start is lazy and one-per-root; health-poll budget ~30 s before failure.
- The persistent, re-parented web view avoids reload cost (and kernel-session loss)
  when moving between surfaces.

## Migration / Rollout Notes

- Additive: a new `DocumentType` case + plugin; no change to existing tab types.
- `AppContainer` gains a `jupyterServerService` dependency (constructor argument).
- POC scope: embeds Notebook 7 wholesale; no bundled runtime; no automated tests yet
  for detection/lifecycle; user-facing strings use inline `String(localized:)`.
