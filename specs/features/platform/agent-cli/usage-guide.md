---
title: "Agent CLI"
feature: "F044"
domain: "platform"
audience: "agent-author"
version: "1.0"
sidebar:
  label: "Agent CLI"
  order: 4
---

# Agent CLI

The `crispy` CLI lets AI coding agents running inside Crispy terminals control the IDE — read terminal output, open files, manage the shelf, drive a browser panel, and inspect the workspace topology. This guide is for agent authors and power users who want to script Crispy.

## How agents discover Crispy

Every terminal Crispy spawns automatically gets these:

**Environment variables:**

| Variable | Value |
|---|---|
| `CRISPY_SOCKET` | Absolute path to the active control socket |
| `CRISPY_CONTEXT` | Tagged caller ID: `terminal.<uuid>` for terminal agents, `acpchat.<uuid>` for ACP-spawned agents |
| `CRISPY_VIBESPACE` | Tagged ID of the focused vibespace (e.g. `vibespace.<uuid>`) |
| `CRISPY_PROJECT_PATH` | Absolute path to the focused project |

**PATH:** `<app>/Contents/Resources/bin` is prepended, so `crispy` is on `$PATH` without configuration.

To check if you're running inside Crispy:

```bash
if [ -n "$CRISPY_SOCKET" ]; then
  echo "Inside Crispy"
fi
```

## First request

```bash
$ crispy ping
{"version": "1.0.0", "build": "47", "app": "Crispy", "protocol_version": 1}

$ crispy identify
{"terminal_id": "abc-123", "terminal_kind": "terminal",
 "vibespace_id": "vs-456", "vibespace_name": "my-project",
 "project_path": "/Users/manu/projects/foo", "project_name": "foo"}
```

Every command accepts `--json` for machine-readable output. Default output is human-readable.

## Core agent loop

Most agents follow this loop in their tool implementations:

```
1. crispy identify           ← know where I am
2. crispy terminal create    ← spawn a worker terminal
3. crispy terminal send …    ← run a command
4. crispy terminal wait …    ← block until it finishes
5. crispy terminal read      ← capture the output
6. crispy file open …        ← show results to the user
```

## Common workflows

### Run a build and report the result

```bash
TERMINAL=$(crispy terminal create --json | jq -r .terminal_id)
crispy terminal send --terminal-id "" --submit "cargo build"
crispy terminal wait --terminal-id "" --regex "^error|Finished"
RESULT=$(crispy terminal read --terminal-id "")
echo "$RESULT" | grep -q "Finished" && echo "OK" || echo "FAIL"
```

### Open a file at a specific line

```bash
crispy file open src/main.rs --line 42 --column 8
```

### Add work-in-progress files to the shelf

```bash
crispy shelf add src/main.rs --select
crispy shelf add tests/main_tests.rs
crispy shelf list
```

### Research a topic and act on it

```bash
crispy browser open "https://docs.rs/clap"
crispy browser wait --load_state networkidle
TREE=$(crispy browser snapshot --interactive --json | jq -r .tree)
# Agent reasons over $TREE, picks an element, then:
crispy browser click --ref 7
```

### List browsers owned by your project

```bash
# Default — only browsers owned by the caller's project (CRISPY_PROJECT_PATH)
crispy browser list

# Opt-in — all browsers in the vibespace, regardless of project
crispy browser list --scope vibespace
```

## Discovery

Don't hardcode command lists in your agent. Ask the running app what's available:

```bash
crispy help
```

Returns the full method catalog with parameters and error codes. This reflects feature flags — disabled subsystems don't appear.

## Implicit context vs. explicit IDs

Most commands accept `--terminal-id`, `--vibespace-id`, or `--path`. If you don't pass them, the CLI uses the channel client's environment variables:

- `terminal.read` defaults to `$CRISPY_CONTEXT`
- `terminal.create` defaults to creating in the vibespace at `$CRISPY_VIBESPACE`
- `file.open` resolves relative paths against `$CRISPY_PROJECT_PATH`

Pass explicit IDs when you want to operate on a different terminal or vibespace than the one the agent is running in.

## Error handling

Every error response has a stable `code` field. Match on the code, not the message:

| Code | Meaning |
|---|---|
| `unknown_method` | Method not registered in this build |
| `invalid_params` | A required parameter is missing or malformed |
| `terminal_not_found` | The referenced terminal UUID does not exist |
| `vibespace_not_found` | The referenced vibespace UUID does not exist |
| `file_not_found` | Path does not exist (or parent dir missing for write) |
| `permission_denied` | Path escapes project root |
| `unsupported_engine` | `terminal.read` requires Ghostty; this terminal uses SwiftTerm |
| `timeout` | A wait command exceeded its timeout |
| `not_connected` | Subsystem (browser, terminal) not available |
| `eval_error` | `browser.eval` JavaScript threw |
| `stale_ref` | A `browser.snapshot` ref is no longer valid (page navigated) |
| `element_not_found` | A `browser.click` or `browser.type` selector matched nothing |

Example error:

```json
{"ok": false, "error": {"code": "permission_denied",
  "message": "Path escapes project root: /etc/passwd"}}
```

## Security notes (read these)

The CLI is powerful — agents can do anything a user could do in the IDE. Read these before designing your agent.

### What the CLI cannot do

- **Connect from outside Crispy.** Only processes descended from the running Crispy app can connect. The socket is `0600` and we verify peer process ancestry on every connection.
- **Read or write files outside the project.** All `file.*` commands enforce the project root boundary, including symlink resolution. Attempts to escape return `permission_denied` and are logged.
- **Reach across app instances.** `Crispy.app` and `CrispyLocal.app` use different sockets. An agent in one cannot affect the other.

### What the CLI can do — and what to do about it

- **Read terminal scrollback.** `terminal.read --scrollback` returns whatever is on screen, including secrets the user typed earlier. If your agent should not see secrets, do not call this command, or filter the result before sending it to your model.

- **Affect other agents in the same vibespace.** If two agents are running in the same vibespace, agent A can call `terminal.list` to discover agent B's terminal UUID, then `terminal.send` keystrokes into it. v1 of the CLI does NOT prevent this. If you need isolated agents, use separate vibespaces.

- **Read browser cookies and storage via `eval`.** A browser panel an agent has touched should be considered compromised — do not sign into sensitive accounts in panels you intend to share with agents.

- **Spawn arbitrary commands in shells.** `terminal.send` with `submit: true` runs whatever string you pass. The agent is responsible for not pasting untrusted input from its model into a shell.

### What you should log

If you're building an agent that uses the CLI, log every mutation (terminal create/close, file write, shelf add/remove, browser open/eval/click) with timestamps. This makes audits and debugging much easier.

## Persistence

Everything you create through the CLI persists across app restarts:

- Terminals you spawn reappear in the same vibespace after relaunch.
- Files added to the shelf stay there.
- Browser panels you open are restored to their last URL.

This is by design — CLI actions are first-class, not ephemeral. If you don't want persistence, don't create persistent things.

## Reference

- Cross-cutting requirements: [spec.md](spec.md)
- System commands: [commands-system.md](commands-system.md)
- Terminal commands: [commands-terminal.md](commands-terminal.md)
- File commands: [commands-files.md](commands-files.md)
- Shelf commands: [commands-shelf.md](commands-shelf.md)
- Browser commands: [commands-browser.md](commands-browser.md)
- VibeSpace and pane commands: [commands-vibespace.md](commands-vibespace.md)
- Threat model: [threat-model.md](threat-model.md)
- Implementation: [technical-design.md](technical-design.md)
