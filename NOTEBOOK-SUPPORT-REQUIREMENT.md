# Jupyter Notebook Support — Spec

Feature: F049 · Domain: D4 (Editor) · Target folder: `specs/features/editor/notebook/`
Status: draft

## Overview

Add first-class support for Jupyter notebooks (`.ipynb`) with **full editing and
execution against the user's real local Python environment** — not a read-only
viewer and not an in-browser (WASM/Pyodide) kernel. Notebooks open as a dedicated
editor surface where users can edit cells, run code against a live kernel bound to
their actual interpreter (venv, conda, system, pyenv), see streaming outputs, and
save back to valid `.ipynb`.

### Decided approach (Option B)

The notebook front-end is hosted inside the existing `WKWebView` surface and
connects to a **locally spawned Jupyter Server** over its WebSocket messaging
protocol. The split of responsibilities:

- **Swift owns the process and the chrome.** A `JupyterServerService` (modeled on
  the `ACPTransport` long-lived-process pattern) spawns `jupyter server`, captures
  its URL + auth token, monitors health, and shuts it down. Environment/kernel
  detection reuses the one-shot `CommandExecuting` / `ManagedProcessRunner` path and
  `CommandPathResolver.environmentWithResolvedPath()` so it sees the user's PATH.
- **JavaScript owns the protocol.** The in-WebView front-end (JupyterLab notebook
  components) speaks the kernel messaging protocol via `@jupyterlab/services`
  (BSD-3). Swift never implements ZMQ, HMAC signing, or the wire format.
- **Persistence** round-trips `.ipynb` through the server Contents API (or Swift
  write through the existing `AutosaveScheduler` + worker `writeFile`), preserving
  the full nbformat schema (cell ids, metadata, outputs, `execution_count`).

Mount point: a new `.notebook` case in `MarkdownViewModel.DocumentType` /
`ContentViewerTabKind`, routed to a dedicated notebook editor plugin. The tab icon
reuses the bundled `notebook.svg` Seti icon.

## Dependencies

- F006 (Content Viewer) — tab kind, routing, and editor surface mounting.
- F007 (Editing) / F039 (Document Buffer) — dirty-state, autosave, save lifecycle.
- F013 (Worker) — process execution and PATH resolution for detection.
- F011 (ACP) — reference pattern for managed long-lived process + streaming transport.
- F015 (Theming) — notebook chrome and output theming.
- External (BSD-3): `jupyter_server` / `jupyter_kernel_gateway`, `@jupyterlab/services`
  and JupyterLab notebook components. Added to `Resources/` runtime assets and
  `Resources/THIRD_PARTY_NOTICES.md`.

## Requirements

### F049-R01: Open notebooks
`.ipynb` files open in a dedicated notebook editor tab (not the raw JSON code view),
routed via a `.notebook` document type.

### F049-R02: Faithful rendering
All cell types (markdown, code, raw) and output types (stream/text, `text/html`,
`image/*`, errors/tracebacks, rich MIME bundles) render with execution counts and
cell ordering preserved.

### F049-R03: Cell editing
Users can edit code, markdown, and raw cells; add, delete, move, split, and merge
cells; and convert cell type. Edits mark the document dirty.

### F049-R04: Execution against a real local kernel
Users can run a cell, run all, interrupt, and restart the kernel. Execution targets
a live Jupyter kernel bound to the user's selected local interpreter. Output streams
incrementally; execution counts and error tracebacks update in place.

### F049-R05: Interpreter / kernel selection
Users can pick the kernel/interpreter for a notebook from registered kernelspecs
(`jupyter kernelspec list`) and from discoverable environments (venv/conda/system).
The selection persists with the notebook session.

### F049-R06: Faithful persistence
Saving round-trips the notebook to valid `.ipynb`, preserving nbformat fields not
modeled by the editor (cell ids, metadata, `execution_count`, unknown keys).
Integrates with existing dirty-state tracking and autosave; external on-disk changes
to a clean buffer reload.

### F049-R07: Jupyter availability detection
On opening a notebook the app detects whether a usable Jupyter Server is available in
the selected environment and surfaces clear, actionable messaging (with remediation)
when it is not. Absence of Jupyter never crashes or blocks the rest of the app.

### F049-R08: Server lifecycle and cleanup
A Jupyter Server is scoped per workspace (one server hosts many notebooks/kernels),
started lazily on first notebook open, health-monitored, and explicitly shut down via
the workspace `shutdown()` path. No kernel or server process is leaked on tab close,
workspace close, or app quit.

### F049-R09: Security boundary
The server binds to `127.0.0.1` only (never `0.0.0.0`), requires token
authentication, and the token is never written to logs or a logged URL. The WebView's
allowed navigation is restricted to the local-server origin plus bundled assets.
Notebook outputs are treated as untrusted content. Raw kernel/protocol traffic is not
persisted to disk.

### F049-R10: Native integration
The notebook surface integrates with the app's tabs, theming, and split-pane behavior
consistent with other editor content. (Comments-panel parity, F049-comments, is
desirable but may be deferred.)

## Scenarios

### Scenario F049-S01: Open and read a notebook
Given a project containing `analysis.ipynb`,
When the user opens it from the explorer,
Then it opens in a notebook editor tab with all cells and previously-saved outputs
rendered.

### Scenario F049-S02: Edit and save
Given an open notebook,
When the user edits a markdown cell and saves,
Then the `.ipynb` on disk reflects the change and preserves all other cells'
metadata, ids, and outputs.

### Scenario F049-S03: Execute against the local environment
Given an open notebook with a selected local Python interpreter,
When the user runs a code cell that imports a package installed in that environment,
Then the kernel executes it, the output streams into the cell, and the execution
count increments.

### Scenario F049-S04: Select interpreter
Given a machine with multiple Python environments,
When the user opens the kernel picker,
Then registered kernelspecs and discoverable environments are listed, and selecting
one (re)binds the notebook's kernel.

### Scenario F049-S05: Jupyter not installed
Given the selected environment has no Jupyter Server,
When the user opens a notebook,
Then the app shows a clear message explaining Jupyter is required and how to install
it, without blocking other app functionality.

### Scenario F049-S06: Clean shutdown
Given a workspace with running notebooks and kernels,
When the user closes the workspace or quits the app,
Then all kernels and the Jupyter Server process are terminated with no orphaned
processes.

## Acceptance Criteria

- Notebooks open, render, edit, execute (against the real local interpreter), and
  save round-trip without corrupting `.ipynb`.
- Kernel interrupt/restart and interpreter selection work.
- Server binds localhost-only with token auth; no token leakage; no orphaned
  processes after close/quit.
- Missing-Jupyter is handled gracefully.
- Unit coverage for detection and server lifecycle; integration coverage for the
  edit→save round-trip.

## Open Questions

- Custom JupyterLab-components widget (native chrome, deferred comments integration)
  vs. embedding the Notebook 7 app wholesale — start with which?
- Bundle a managed Jupyter runtime vs. require the user's own Jupyter install?
- Per-workspace vs. per-project server granularity for multi-root workspaces.
- Remote (F034 SSH) notebooks — in scope later, out of scope for v1.

## Change History

- draft — initial requirement captured from design discussion (Option B: full
  editing + execution against the real local Python environment).
