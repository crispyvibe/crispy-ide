# Jupyter Notebook Support — Threat Model

## Overview

The feature spawns a local Jupyter Server (a child process executing arbitrary
Python via kernels) and renders its web UI in a `WKWebView`. The attack surface is
broader than a passive previewer because it (a) launches a long-lived local server,
(b) executes user code, and (c) loads remote-origin (loopback) web content. This
model documents the boundaries and mitigations.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App → spawned `jupyter` process | Crispy launches `jupyter notebook` with a constructed argument vector and resolved PATH environment |
| WebView ↔ local server | The `WKWebView` talks HTTP/WebSocket to `127.0.0.1:PORT` authenticated by a per-server token |
| Kernel → host | Executed notebook code runs with the user's privileges and full local access |
| File system → app | `.ipynb` files are read/written by the server's Contents API |
| Remote host ↔ app (SSH) | For remote projects the server runs on the host (bound to remote `127.0.0.1`); reached via an `ssh -L` loopback-to-loopback forward over the existing ControlMaster. Launch/poll/kill scripts run in a remote login shell |

## Attack Surfaces

1. Server bind address and authentication (network exposure).
2. The auth token (leakage via logs/URLs).
3. WebView navigation (origin confinement; untrusted notebook outputs).
4. Process argument/PATH construction (command/argument injection).
5. Notebook content itself (executed code, malicious outputs).
6. Remote launch script construction (the notebook root dir is single-quote
   escaped, the token is hex, and the remote pid is validated numeric before it is
   interpolated into the `kill` command — guarding shell injection on the host).

## Threats

### F050-T01: Server exposed beyond loopback
- **Vector:** server bound to `0.0.0.0` or an interface reachable on the network.
- **Impact:** remote parties could reach the server and execute code.
- **Likelihood:** Low (explicitly configured).
- **Mitigation:** always pass `--ip=127.0.0.1`; never `0.0.0.0`. (F050-R09)

### F050-T02: Auth token leakage
- **Vector:** the token is written to logs, diagnostics, or a logged URL.
- **Impact:** a local process reading logs could drive the server/kernel.
- **Likelihood:** Low–Medium.
- **Mitigation:** generate a per-server random token; never log the URL or token
  (the service logs only host:port); token lives only in the in-memory URL passed
  to the web view. (F050-R09)

### F050-T03: WebView navigates to a malicious origin
- **Vector:** notebook content or an output links/redirects the top-level frame
  off the local-server origin.
- **Impact:** the trusted notebook surface renders attacker-controlled content.
- **Likelihood:** Low.
- **Mitigation:** `NotebookNavigationDelegate` allows top-level navigation only to
  the loopback host:port (plus `about`/`blob`/`data`); `linkActivated` to other
  origins is handed to the system browser and cancelled in-frame. (F050-R09)

### F050-T04: Command / argument injection via paths
- **Vector:** a crafted notebook path or root directory injects extra arguments or
  shell semantics into the spawn.
- **Impact:** unintended process behavior.
- **Likelihood:** Low.
- **Mitigation:** spawn via `Process` with an explicit argument array (no shell);
  paths are passed as single `--ServerApp.root_dir=` / URL-encoded path components,
  not interpolated into a command string.

### F050-T05: Orphaned server/kernel processes
- **Vector:** the app quits or the workspace closes without terminating children.
- **Impact:** leaked processes holding a port and executing kernels.
- **Likelihood:** Medium without explicit teardown.
- **Mitigation:** `JupyterServerService.shutdownAll()` is invoked from
  `applicationWillTerminate`, terminating every server process and releasing web
  views. (F050-R08)

### F050-T06: Untrusted notebook outputs / arbitrary code execution
- **Vector:** opening a notebook and running it executes embedded code; rich
  outputs may contain active content.
- **Impact:** code runs with the user's privileges (inherent to notebooks).
- **Likelihood:** N/A (intended capability) — but a foreseeable user risk.
- **Mitigation:** execution is user-initiated; outputs are treated as untrusted and
  confined to the loopback-origin web view; no raw kernel/protocol traffic is
  persisted. Notebook trust/signing remains Jupyter's responsibility.

## Residual Risks

- Executed notebook code is, by design, unsandboxed and runs as the user — the
  same risk as running the notebook in a terminal.
- Vulnerabilities in the user's Jupyter/Notebook 7 install are outside Crispy's
  control; mitigation depends on the user keeping Jupyter updated.
- The free-port reservation has a small TOCTOU window between release and the
  server binding the port.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-1 (Input validation) | Compliant | Argument-array spawn; URL-encoded path components |
| SEC-3a (Network exposure) | Compliant | Loopback-only bind + token auth |
| SEC (Secret handling) | Compliant | Token never logged; URL/token not persisted |
| REL (Cleanup) | Compliant | `shutdownAll()` on app termination |
