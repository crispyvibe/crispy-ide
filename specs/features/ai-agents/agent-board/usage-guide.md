---
title: "Agent Board"
feature: "F011"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "Agent Board"
  order: 1
---

# Agent Board

## Overview

The Agent Board provides an AI agent conversation panel within Crispy. It allows you to interact with AI coding agents (Claude Code, Codex, Kiro, and others) directly inside the IDE through the Agent Conversation Protocol (ACP). Each agent session runs in a standalone pane with a chat timeline, compose input, and tool call visibility.

## Getting Started

1. Open the sidebar and navigate to the **Sessions** tab to see available agent panes.
2. Click the **+** button or use the agent pane creation action to open a new ACP session.
3. Select an agent from the agent registry dropdown (e.g., Claude Code, Codex, Kiro).
4. Optionally select a model and project context for the session.
5. The agent connects automatically. Type a message in the compose area and press Enter to begin.

## Workflows

### Starting a New Agent Session

1. Open a new ACP standalone pane from the Sessions sidebar or toolbar.
2. Choose your preferred agent from the agent picker dropdown.
3. Select a model if the agent supports multiple models.
4. Assign a project context so the agent has workspace awareness.
5. Set trust mode (Standard or Full Trust) based on your preference.
6. Type your prompt and press Enter — the agent connects and responds.

### Reviewing Tool Calls and Diffs

1. As the agent works, tool calls appear in the timeline with expandable details.
2. File diffs are rendered inline with syntax highlighting.
3. Click a diff entry to open the Diff Spotlight panel for a larger view.
4. Permission requests appear as cards — approve or deny each tool action.

### Resuming a Previous Conversation

1. Open the Sessions sidebar to see saved conversation threads.
2. Click a previous thread to restore it in a new pane.
3. The session attempts to reconnect and resume from where it left off.
4. If resume fails, you are prompted to start a fresh session.

### Managing Trust Mode

1. In the session header, toggle between **Standard** and **Full Trust** modes.
2. Standard mode requires explicit approval for each tool call.
3. Full Trust mode passes `--trust-all-tools` to the CLI agent, allowing autonomous operation.

### Attaching Images

1. Paste or drag images into the compose area.
2. Attached images appear as thumbnails below the compose input.
3. Images are sent alongside your text message to the agent.

### Using Slash Commands

1. Type `/` in the compose area to see available commands.
2. Commands are filtered as you type.
3. Select a command to insert it into your prompt.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Send message | Enter |
| New line in compose | Shift+Enter |
| Open Developer Tools | ⌘⌥D |

## Settings

- **Trust Mode**: Standard (requires approval) or Full Trust (autonomous). Set per session.
- **Reasoning Level**: Controls the depth of agent reasoning (Low, Medium, High).
- **Auto-Connect**: When enabled, sessions connect automatically on creation.
- **Agent Selection**: Choose from discovered agents in the registry.
- **Model Selection**: Pick a specific model when the agent supports multiple.

## Tips

- Each ACP pane is independent — you can run multiple agent sessions simultaneously across different projects.
- Conversation history is persisted per thread and can be restored across app restarts.
- The agent title updates to reflect the first user message if no explicit title is set.
- Use the Diff Spotlight panel (click a diff in the timeline) for a focused code review experience.
- Context window usage is displayed when the agent reports it, helping you gauge remaining capacity.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Agent won't connect | Verify the CLI tool is installed and accessible in your PATH. Check App Settings → AI for configuration. |
| Session shows "Connection Error" | The underlying CLI process may have crashed. Try disconnecting and reconnecting, or start a fresh session. |
| Resume fails after restart | The remote session may have expired. Accept the prompt to start a new session. |
| Tool calls not appearing | Ensure the agent supports tool use and that trust mode is configured appropriately. |
| Empty agent registry | Agents are discovered from installed CLI tools. Install at least one supported agent CLI (kiro, claude, codex). |
