---
title: "Remote Agent CLI"
feature: "F051"
domain: "remote"
audience: "user"
version: "1.1"
sidebar:
  label: "Remote CLI"
  order: 3
---

# Remote Agent CLI

## Overview

The `crispy` command works inside terminals connected to a remote SSH project — including for AI agents running on the remote host — without installing any package or binary on the remote machine. Commands run against your local Crispy app and behave the same as they do locally. (A tiny `~/.local/bin/crispy` wrapper is created so any shell finds the command.)

## Getting Started

1. In **Settings → Connections**, edit your SSH profile and make sure **"Allow Agent CLI (crispy) on this connection"** is on (default).
2. Connect to the remote project and open a terminal.
3. Run `crispy ping`. You should see the app version — confirming the relay is active. Agents can run it too (e.g. `bash -lc "crispy whoami --json"`).

The remote host needs `nc` (with `-N`) or `socat` available, and SSH forwarding permitted. No other setup is required.

## Workflows

- **Agents on the remote**: an agent running on the remote host can call `crispy` (e.g. `crispy whoami`, `crispy file open src/app.ts`) and read the result from standard output, just like any other CLI.
- **Context is automatic**: commands resolve the current remote project and terminal from environment the app injects — usually you don't pass IDs.
- **File paths are remote paths**: `crispy file open <path>` opens a file from the **remote** project; paths outside the project are rejected.

## Keyboard Shortcuts

None specific to this feature.

## Settings / Configuration

- **Per-connection opt-in**: each SSH profile has an **"Allow Agent CLI (crispy) on this connection"** toggle (Settings → Connections → edit a profile). On by default; turn it off for shared or untrusted hosts, where `crispy` then simply isn't available on that connection.

## Troubleshooting

- **`crispy: command not found`** (in an agent/login shell): ensure `~/.local/bin` is on your remote login `PATH` (default on Ubuntu via `~/.profile`), and re-open the terminal so the wrapper is written.
- **`crispy: IDE relay unavailable`**: the host disallows SSH forwarding (`AllowStreamLocalForwarding`/`AllowTcpForwarding`), the connection dropped, or `nc`/`socat` is missing. The rest of your shell keeps working; re-open the terminal or enable forwarding.
- **Command hangs**: shouldn't happen (`nc -N` half-closes); if it does, reconnect the remote project.

## Known Limitations

- Requires SSH forwarding to be permitted, and `nc`/`socat` present on the remote host.
- The relay runs the bundled `crispy` on your Mac; latency is one SSH round-trip per command.
- Exposure is bounded to **processes running as your remote user** (the forwarded socket is `0600`). Treat shared/multi-user hosts with caution and use the per-connection toggle.
- A remote file open in the editor auto-reloads on external change via ~4s polling (no FSEvents/inotify remotely). `whoami` may report a stale vibespace until context passthrough lands.
