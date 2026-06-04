# Jupyter Notebook Support — Spec

Status: draft

## Overview

First-class support for Jupyter notebooks (`.ipynb`) with **full editing and
execution against the user's real local Python environment** — not a read-only
viewer and not an in-browser (WASM/Pyodide) kernel. Notebooks open as a dedicated
editor surface where users edit cells, run code against a live kernel bound to
their actual interpreter (venv, conda, system, pyenv), see streaming outputs, and
save back to valid `.ipynb`.

### Decided approach

The notebook front-end is the **Jupyter Notebook 7 UI hosted inside a `WKWebView`**,
connected to a **locally spawned Jupyter Server**:

- **Swift owns the process and chrome.** `JupyterServerService` (modeled on the
  `ACPTransport` long-lived-process pattern) spawns `jupyter notebook`, binds it to
  loopback with a token, monitors health, and shuts it down. Environment/kernel
  detection reuses the `CommandPathResolver.environmentWithResolvedPath()` PATH so
  it sees the user's interpreters.
- **The embedded Notebook 7 app owns the protocol.** The kernel messaging protocol,
  rich-output rendering, and persistence (Contents API) are handled by Jupyter
  itself. Swift never implements ZMQ, HMAC signing, or the wire format.

Mount point: a new `.notebook` case in `MarkdownViewModel.DocumentType`, routed
through `EditorPluginRegistry` to a dedicated `NotebookEditorView`. The tab icon
reuses the bundled `notebook.svg` Seti icon.

## Dependencies

- F006 (Content Viewer) — tab kind, routing, and editor surface mounting.
- F007 (Editing) / F039 (Document Buffer) — dirty-state and save lifecycle (the
  notebook surface deliberately bypasses the text buffer; see F050-R06).
- F013 (Worker) — PATH resolution for interpreter/Jupyter detection.
- F011 (ACP) — reference pattern for a managed long-lived process.
- F015 (Theming) — tab/chrome theming.
- F049 (File Comments) — comment store, side panel, and surface-bridge pattern
  reused for notebook comments (F050-R11).
- External (BSD-3): the user's own `jupyter notebook` (Notebook 7) / `jupyter_server`
  install. No Jupyter runtime is bundled (see Open Questions).

## Requirements

### F050-R01: Open notebooks
`.ipynb` files open in a dedicated notebook editor tab (not the raw JSON code view),
routed via a `.notebook` document type.

### F050-R02: Faithful rendering
All cell types (markdown, code, raw) and output types (stream/text, `text/html`,
`image/*`, errors/tracebacks, rich MIME bundles) render with execution counts and
cell ordering preserved.

### F050-R03: Cell editing
Users can edit code, markdown, and raw cells; add, delete, move, split, and merge
cells; and convert cell type.

### F050-R04: Execution against a real local kernel
Users can run a cell, run all, interrupt, and restart the kernel. Execution targets
a live Jupyter kernel bound to the user's selected local interpreter. Output streams
incrementally; execution counts and error tracebacks update in place.

### F050-R05: Interpreter / kernel selection
Users can pick the kernel/interpreter for a notebook from registered kernelspecs
(`jupyter kernelspec list`) and from discoverable environments (venv/conda/system).

### F050-R06: Faithful persistence
Saving round-trips the notebook to valid `.ipynb`, preserving nbformat fields
(cell ids, metadata, `execution_count`, unknown keys). Saving is handled by the
Jupyter Contents API; the notebook surface does not load `.ipynb` into the text
buffer, so autosave never overwrites the server-managed file. External on-disk
changes reload the notebook (F050-R12).

### F050-R07: Jupyter availability detection
On opening a notebook the app detects whether a usable `jupyter` is resolvable in
the user's PATH and surfaces clear, actionable messaging when it is not. Absence of
Jupyter never crashes or blocks the rest of the app.

### F050-R08: Server lifecycle and cleanup
A Jupyter Server is started lazily on first notebook open, scoped per root
directory, health-monitored, and explicitly shut down via the app termination path.
No kernel or server process is leaked on app quit.

### F050-R09: Security boundary
The server binds to `127.0.0.1` only (never `0.0.0.0`), requires token
authentication, and the token is never written to logs or a logged URL. The
WebView's allowed top-level navigation is restricted to the local-server origin;
external links open in the system browser. Notebook outputs are treated as
untrusted content.

### F050-R10: Native integration
The notebook surface integrates with the app's tabs, theming, and split-pane
behavior consistent with other editor content. A single persistent web view is
re-parented across surfaces (inline pane, split, spotlight) so the live kernel
session and executed outputs survive moving between them.

### F050-R11: Comment support
Notebooks participate in the F049 comment system. Comments anchor to the **nbformat
cell id** (with the cell source fingerprint as a reorder/edit fallback), render
in-cell markers, and are keyed by the notebook file path so they persist across
sessions and appear in the side panel, the cross-file view, and the CLI. Location
labels read "Cell N".

### F050-R12: External change reload
When the `.ipynb` changes on disk (e.g. an agent edits it), the open notebook
reloads so the change surfaces, debounced to coalesce burst events.

### F050-R13: Remote (SSH) notebooks
A notebook opened from a remote (SSH) project launches its Jupyter Server **on the
remote host** — rooted at the notebook's remote directory and bound to remote
loopback — and is reached through an SSH local port forward over the existing
ControlMaster connection. The server is one-per-host+root, started lazily, and its
remote process is killed (and the forward cancelled) on app quit. When the host
lacks `jupyter` or `python3`, the surface shows the same "unavailable" state as the
local case (F050-R07). The loopback-only/token boundary in F050-R09 holds on both
ends (remote bind is `127.0.0.1`; the forward is loopback-to-loopback).

## Scenarios

### Scenario F050-S01: Open and read a notebook
- **Given** a project containing `analysis.ipynb`
- **When** the user opens it from the explorer
- **Then** it opens in a notebook editor tab with all cells and previously-saved
  outputs rendered

### Scenario F050-S02: Edit and save
- **Given** an open notebook
- **When** the user edits a cell and saves
- **Then** the `.ipynb` on disk reflects the change and preserves other cells'
  metadata, ids, and outputs

### Scenario F050-S03: Execute against the local environment
- **Given** an open notebook with a selected local Python interpreter
- **When** the user runs a code cell that imports an installed package
- **Then** the kernel executes it, output streams into the cell, and the execution
  count increments

### Scenario F050-S04: Select interpreter
- **Given** a machine with multiple Python environments
- **When** the user opens the kernel picker
- **Then** registered kernelspecs and discoverable environments are listed, and
  selecting one (re)binds the notebook's kernel

### Scenario F050-S05: Jupyter not installed
- **Given** the resolved environment has no `jupyter`
- **When** the user opens a notebook
- **Then** the app shows a clear message that Jupyter is required and how to install
  it, without blocking other app functionality

### Scenario F050-S06: Clean shutdown
- **Given** running notebooks and kernels
- **When** the user quits the app
- **Then** all kernels and the Jupyter Server process terminate with no orphans

### Scenario F050-S07: Comment on a cell
- **Given** an open notebook
- **When** the user selects text in a cell and adds a comment
- **Then** an in-cell marker appears, a thread is created keyed to the notebook
  file path and anchored to the cell id, and it shows in the side panel labeled
  "Cell N"

### Scenario F050-S08: Spotlight preserves kernel state
- **Given** a notebook with executed cells in the inline pane
- **When** the user opens it in spotlight
- **Then** the same web view (kernel session + outputs) moves to spotlight, and
  returns to the inline pane when spotlight closes

### Scenario F050-S09: External edit reloads
- **Given** an open notebook
- **When** the `.ipynb` is changed on disk by another tool/agent
- **Then** the open notebook reloads and shows the change

## Acceptance Criteria

- Notebooks open, render, edit, execute (against the real local interpreter), and
  save round-trip without corrupting `.ipynb`.
- Kernel interrupt/restart and interpreter selection work.
- Server binds localhost-only with token auth; no token leakage; no orphaned
  processes after quit.
- Missing-Jupyter is handled gracefully.
- Comments anchor to cells and persist across sessions and surfaces.

## Open Questions

- Bundle a managed Jupyter runtime vs. require the user's own Jupyter install
  (current: require the user's install).
- Per-workspace vs. per-root-directory server granularity for multi-root workspaces
  (current: per root directory).
- Remote (F034 SSH) notebooks — out of scope for v1.
- Cell-id resolution currently reads the DOM with an index + source-fingerprint
  fallback; the robust source is the JupyterLab model API.

## Change History

| Date | Change |
|------|--------|
| 2026-05-30 | Initial spec captured from the F049→F050 draft requirement and the POC implementation. Renumbered to F050 (F049 is File Comments). |
