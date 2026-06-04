---
title: "Jupyter Notebooks"
feature: "F050"
domain: "editor"
audience: "user"
version: "1.0"
sidebar:
  label: "Notebooks"
  order: 10
---

# Jupyter Notebooks

## Overview

Crispy opens Jupyter notebooks (`.ipynb`) in a dedicated editor tab where you can
read, edit, and **run cells against your own local Python environment** — the same
interpreter and packages you use in the terminal. Outputs, execution counts, and
errors appear inline, and you save back to a standard `.ipynb`.

## Getting Started

Crispy uses **your existing Jupyter install** — it does not bundle one. Install it
into the Python environment you want to use, for example:

```bash
python3 -m venv ~/my-venv
~/my-venv/bin/pip install notebook ipykernel
```

Make sure `jupyter` is on your `PATH` (Crispy also looks in common locations such
as `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`). If Jupyter isn't
found, the notebook tab explains what to install — the rest of the app keeps
working.

## Workflows

### Opening a Notebook

1. In the **File Explorer**, click an `.ipynb` file.
2. The notebook opens in a tab. The first open starts a local Jupyter server (you'll
   briefly see "Starting Jupyter…").
3. All cells and previously-saved outputs render.

### Running Cells

- Run the focused cell, run all, interrupt, and restart the kernel using the
  notebook toolbar — execution runs against your selected local interpreter and
  output streams into the cell.

### Choosing an Interpreter / Kernel

- Use the kernel picker to select from your registered kernels
  (`jupyter kernelspec list`) and discoverable environments.

### Commenting on Cells

1. Select text inside a cell.
2. Click **💬 Comment**, type your note, and submit.
3. A marker appears on the cell and a thread opens in the comments side panel,
   labeled **"Cell N"**. Comments live with the file and also appear in the
   **All Comments** view — the same system used for other files and the browser.

### Spotlight & Split

- Double-click the tab for **spotlight**, or drag it into a **split** — the live
  notebook (running kernel and outputs) moves with you and returns intact.

### External Edits

- If another tool or an agent changes the `.ipynb` on disk, the open notebook
  reloads automatically to show the change.

## Keyboard Shortcuts

No notebook-specific shortcuts. Standard tab navigation applies:

| Action | Shortcut |
|--------|----------|
| Close tab | `⌘W` |
| Next tab | `⌃⇥` |
| Previous tab | `⌃⇧⇥` |

In-notebook editing/execution shortcuts are provided by the Jupyter Notebook 7 UI.

## Settings / Configuration

No in-app configuration. The interpreter/kernel is chosen per notebook via the
kernel picker; Jupyter itself is configured through your environment.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Jupyter is required" message | Install Jupyter into an environment on your PATH (see Getting Started). |
| Reloading kept output disappears | A reload re-reads the file from disk; unsaved outputs since the last save are not restored. Save before triggering a reload. |
| A comment marker lands on the wrong cell | Cell anchoring tracks the cell, but the displayed cell number can go stale after reordering. |

## Known Limitations

- **Requires your own Jupyter install** — none is bundled.
- **Reload is destructive to unsaved state** — showing external disk changes
  re-reads from disk; in-progress kernel output not yet saved can be lost.
- **Remote (SSH) notebooks** run Jupyter on the remote host, reached through a
  forwarded loopback port. The remote host must have `jupyter` (Notebook 7) and
  `python3` on its login-shell `PATH`; if either is missing the notebook shows
  the "unavailable" state. The remote server is started on first open and is
  killed on app quit, but a dropped SSH connection can leave it running until
  the next quit reconnects and cleans up.
- **POC**: kernel/interpreter picker and persistence rely on the embedded Notebook 7
  UI; deeper native integration is planned.
