---
title: "Terminal Presets"
feature: "F005"
domain: "terminal"
audience: "user"
version: "1.0"
sidebar:
  label: "Presets"
  order: 5
---

# Terminal Presets

## Overview

Terminal Presets provides a launcher menu for AI coding tools directly from the terminal tab bar. It detects which CLI tools are installed on your system, displays them with brand icons, and launches them in dedicated named terminal tabs with a single click. Presets support two launch modes — Standard and Full Trust — for tools that offer elevated permission levels.

## Getting Started

1. Open a vibespace with at least one project.
2. Look at the terminal tab bar — the Tools dropdown appears alongside the tab chips.
3. Click the Tools dropdown to see which AI tools are detected on your system.
4. Click any tool to launch it in a new named terminal tab.

## Workflows

### Launching a Preset Tool

1. Click the **Tools** dropdown in the terminal tab bar.
2. Only installed tools appear, each with its brand SVG icon:
   - **Kiro** — launches `kiro-cli`
   - **Claude** — launches `claude`
   - **Codex** — launches `codex`
   - **Gemini** — launches `gemini`
   - **OpenCode** — launches `opencode`
   - **Copilot** — launches `copilot`
3. Click the tool name.
4. A new terminal tab is created with the tool's short name as the tab title.
5. The preset command is sent to the terminal session.
6. Keyboard focus moves to the new tab.

### Switching Launch Mode

1. In the terminal tab bar, find the mode selector (Standard / Full Trust toggle).
2. Switch between modes:
   - **Standard**: Launches the tool with default arguments (no elevated permissions).
   - **Full Trust**: Launches with full-trust arguments (e.g., `--dangerously-skip-permissions` for Claude, `--dangerously-bypass-approvals-and-sandbox` for Codex, `--approval-mode yolo` for Gemini, `--trust-all-tools` for Kiro, `--allow-all` for Copilot).
3. The selected mode persists across app restarts.
4. Tools that don't define a full-trust command are disabled (grayed out) when Full Trust mode is selected.

### Tool Availability Detection

Crispy detects installed tools by checking:
- The system PATH (as resolved by the app)
- Standard fallback install directories

Detection results are cached and persisted. Tools not found on your system are hidden from the menu entirely.

## Keyboard Shortcuts

No dedicated keyboard shortcuts for preset launching. Use the Tools dropdown in the terminal tab bar.

## Settings

| Setting | Location | Effect |
|---------|----------|--------|
| Preset Launch Mode | Terminal tab bar mode selector | Persisted in `crispyvibes.terminal.presetLaunchMode` — controls Standard vs Full Trust |

The launch mode is stored in app storage and persists across restarts.

## Tips

- **Shell resolves the command**: The preset command is dispatched into your interactive shell, which resolves the executable against its own PATH (including `.zshrc` / `.bash_profile` additions). This means tools installed via version managers (Volta, nvm, asdf, mise, Cargo, etc.) work correctly even if the GUI app's PATH doesn't include them.
- **Named tabs**: Each preset creates a tab named after the tool (e.g., "Kiro", "Claude") so you can easily identify which AI session is which.
- **Working directory**: The preset launches in the current active tab's working directory, or the first tab's directory, or falls back to the project root.
- **Full Trust availability**: OpenCode has no full-trust variant — it's disabled in Full Trust mode. Kiro, Claude, Codex, Gemini, and Copilot all support Full Trust.
- **Re-detection**: Available presets are refreshed when the terminal view appears. If you install a new tool, switch away from and back to the terminal to trigger re-detection.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Tool not appearing in the menu | Ensure the CLI tool is installed and accessible on your PATH. Try running the command in a regular terminal first. |
| "does not define a full-trust launch mode" error | The selected tool doesn't support Full Trust mode. Switch to Standard mode. |
| "Select a project or terminal directory" error | No working directory is available. Ensure a project is open in the vibespace. |
| Tool launches but command fails | The tool may require authentication or configuration. Check the tool's own setup instructions. |
| Preset menu is empty | No supported tools were detected. Install at least one of: kiro-cli, claude, codex, gemini, opencode, copilot. |
