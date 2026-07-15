---
title: "Terminal Presets"
feature: "F005"
domain: "terminal"
audience: "user"
version: "1.1"
sidebar:
  label: "Presets"
  order: 5
---

# Terminal Presets

## Overview

Terminal Presets lets you launch AI coding-agent CLIs straight from the terminal. Agents live in the **Agent CLI** menu inside the terminal commands menu (the terminal-icon button, alongside Signals, tmux, and Shortcuts) — available both in the detailed view and on terminal board tiles. Crispy detects which agent CLIs are installed, shows them with their names, and launches them for you. Agents that support an elevated permission level offer both **Standard** and **Full Trust** when you launch them.

## Getting Started

1. Open a vibespace with at least one project.
2. In a terminal (detailed view or a board tile), click the **terminal-icon** menu in the header.
3. Open the **Agent CLI** submenu to see which agents are detected on your system.
4. Click an agent to launch it.

## Workflows

### Launching an Agent

1. Click the **terminal-icon** menu, then open **Agent CLI**.
2. Only installed agents appear:
   - **Kiro** — launches `kiro-cli`
   - **Claude** — launches `claude`
   - **Codex** — launches `codex`
   - **Gemini** — launches `gemini`
   - **OpenCode** — launches `opencode`
   - **Copilot** — launches `copilot`
3. Click the agent (or pick Standard / Full Trust for agents that offer it).
4. Where it launches depends on the surface:
   - **Detailed view**: a new terminal tab is created, named after the agent, and the command runs there.
   - **Terminal board tile**: the command runs in that tile's own session.
5. Keyboard focus moves to the launched session.

If no agents are detected, the menu shows **"No agents on PATH."**

### Choosing Standard or Full Trust

Trust mode is chosen per agent, each time you launch:

1. In the **Agent CLI** submenu, agents that support elevated permissions expand into a submenu with **Standard** and **Full Trust**.
2. Pick one:
   - **Standard**: launches with default arguments (no elevated permissions).
   - **Full Trust**: launches with full-trust arguments (e.g., `--dangerously-skip-permissions` for Claude, `--dangerously-bypass-approvals-and-sandbox` for Codex, `--approval-mode yolo` for Gemini, `--trust-all-tools` for Kiro, `--allow-all` for Copilot).
3. Agents without a full-trust variant (e.g., OpenCode) appear as a single item and launch in Standard.

There is no global launch-mode toggle — you choose per launch.

### Tool Availability Detection

Crispy detects installed tools by checking:
- The system PATH (as resolved by the app)
- Standard fallback install directories

Detection results are cached and persisted. Tools not found on your system are hidden from the menu entirely.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for launching agents. Use the **Agent CLI** menu inside the terminal commands menu.

## Settings

There is no separate terminal launch-mode setting — trust mode (Standard / Full Trust) is chosen per agent, each time you launch, from the Agent CLI menu.

(Startup profiles in VibeSpace Settings have their own separate trust selection for auto-launched terminals; that is unrelated to this menu.)

## Tips

- **Shell resolves the command**: The command is dispatched into your interactive shell, which resolves the executable against its own PATH (including `.zshrc` / `.bash_profile` additions). This means tools installed via version managers (Volta, nvm, asdf, mise, Cargo, etc.) work correctly even if the GUI app's PATH doesn't include them.
- **Where it lands**: In the detailed view, launching creates a new tab named after the agent (e.g., "Kiro", "Claude"). On a terminal board tile, the agent runs in that tile's own session.
- **Working directory**: In the detailed view the agent launches in the active tab's working directory (falling back to the first tab's directory or the project root). On a board tile it uses that tile's session.
- **Full Trust availability**: OpenCode has no full-trust variant — it shows a single Standard item. Kiro, Claude, Codex, Gemini, and Copilot offer both Standard and Full Trust.
- **Re-detection**: Available agents are refreshed when the terminal view appears. If you install a new tool, switch away from and back to the terminal to trigger re-detection.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Agent not appearing in the menu | Ensure the CLI tool is installed and accessible on your PATH. Try running the command in a regular terminal first. |
| Menu shows "No agents on PATH" | No supported agents were detected. Install at least one of: kiro-cli, claude, codex, gemini, opencode, copilot. |
| "Select a project or terminal directory" error | No working directory is available. Ensure a project is open in the vibespace. |
| Agent launches but command fails | The tool may require authentication or configuration. Check the tool's own setup instructions. |
