---
title: "Agent Conversation Protocol (ACP)"
feature: "F011"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "ACP"
  order: 1
---

# Agent Conversation Protocol (ACP)

## Overview

ACP lets you connect AI coding agents directly inside Crispy. You can chat with an agent, have it read and edit your project files, run terminal commands, and work through multi-step tasks — all within your vibespace.

CrispyVibes supports three types of agents:

- **ACP-compatible agents** — any agent that implements the Agent Conversation Protocol
- **Claude Code** — Anthropic's coding agent, with direct integration for trust modes and model selection
- **Codex** — OpenAI's coding agent, with direct integration for trust modes and model selection

## Getting Started

### Prerequisites

Install the agent CLI tool you want to use. CrispyVibes discovers agents from your system PATH:

- **Claude Code:** Install via `npm install -g @anthropic-ai/claude-code` or follow Anthropic's instructions
- **Codex:** Install via `npm install -g @openai/codex` or follow OpenAI's instructions
- **Custom agents:** Any executable that speaks the ACP protocol

### Connecting to an Agent

1. Open an ACP pane from the toolbar or command palette.
2. Select an agent from the **Agent** picker. Only agents found on your system appear as available.
3. Select a **Project** to scope the agent's file access.
4. Click **Connect**.

The agent starts as a background process. Once connected, you'll see the compose bar ready for input.

If an agent appears grayed out, its executable wasn't found on your PATH. Verify the installation and restart CrispyVibes.

### Auto-Connect

Standalone panes remember their configuration. When you reopen a vibespace, panes with auto-connect enabled will reconnect automatically using the previously selected agent, project, and settings.

## Trust Modes

Trust modes control how much autonomy the agent has. Choose based on how much you trust the agent and the sensitivity of your project.

| Mode | Behavior | When to Use |
|------|----------|-------------|
| **Standard** | Every file edit and terminal command requires your explicit approval | Default. Use for unfamiliar agents or sensitive projects. |
| **Full Trust** | All actions are auto-approved without prompts | Use with trusted agents in controlled environments where speed matters. |

### Allow-Always (Session Escalation)

When a permission card appears in standard mode, you may see an **Allow Always** option. Selecting it switches the session to auto-approve all subsequent requests — equivalent to full trust for the remainder of that session. This does not persist across reconnects.

## Conversation

### Sending Prompts

Type your message in the compose bar at the bottom of the chat pane and press **Enter** (or click Send). Your message appears in the timeline, and the agent begins responding.

While the agent is working, you'll see a "Thinking…" indicator. Click **Cancel** to stop the agent mid-response.

### Reading Responses

Agent responses appear as they stream in. You may see several types of content:

- **Text** — the agent's main response, rendered as markdown
- **Thoughts** — the agent's reasoning process, shown in a secondary style
- **Tool calls** — actions the agent is taking (reading files, writing code, running commands), shown as grouped cards with status indicators
- **Plans** — multi-step plans the agent proposes, with status for each step
- **Diffs** — file changes summarized with additions and deletions

### Resending Messages

Hover over any message you sent and click **Resend**. This removes all messages from that point forward and places the text back in the compose bar for editing.

### Slash Commands

Type `/` in the compose bar to see available slash commands. These are advertised by the connected agent and vary by agent type. Select a command from the suggestion list to insert it.

## Permissions

When an agent wants to perform an action in standard trust mode, a **permission card** appears in the timeline.

Each card shows:
- The action the agent wants to take (e.g., "Write to src/main.swift")
- **Allow** — approve this single action
- **Deny** — reject this action
- **Allow Always** — approve this and all future actions for the session

The agent pauses until you respond. Denied actions are reported back to the agent, which may adjust its approach.

In full trust mode, no permission cards appear — all actions proceed automatically.

## Models

### Switching Models

For ACP agents, available models are negotiated during the connection handshake. Use the **Model** picker in the pane header to switch models mid-session.

For Claude Code and Codex (direct integrations), models come from a built-in catalog:

- **Claude Code:** Sonnet 4.5, Opus 4.6, Sonnet 4, Haiku 4
- **Codex:** GPT-5.4, GPT-5.3 Codex, GPT-5.3 Codex Spark, GPT-5.2 Codex, GPT-5.2

### Reasoning Levels

Direct integration agents (Claude Code, Codex) support reasoning level selection:

| Level | Description |
|-------|-------------|
| Low | Fastest responses, minimal reasoning |
| Medium | Balanced (default) |
| High | More thorough reasoning |
| Max | Most thorough, slowest |

Reasoning level is set before connecting and persists across pane restores.

## Standalone Pane vs Board Tile

ACP sessions can live in two places:

### Standalone Pane

Opened in the content viewer area. Best for focused, extended conversations. Includes the full setup strip with agent, project, model, trust, and reasoning pickers. Use this when you want a dedicated chat alongside your editor.

### Board Tile

Added to the terminal board grid. Best for monitoring or quick interactions alongside terminal sessions. The tile shows the chat view in a compact card. Use this when you want the agent visible alongside your terminals.

Both use the same underlying session and chat system. You can have multiple panes and tiles connected to different agents or projects simultaneously.

## Settings

### Global Defaults

Open **Settings → ACP** to configure:

- **Default Agent** — which agent to pre-select in new panes
- **Default Trust Mode** — Standard or Full Trust
- **Default Model** — pre-selected model for new sessions
- **Default Reasoning Level** — pre-selected reasoning level for direct integrations

### Custom Agents

Add custom ACP-compatible agents in **Settings → ACP**:

1. Click **Add Agent**
2. Enter a **Title** (display name)
3. Enter the **Executable** name or path
4. Add any required **Arguments**
5. Save

Custom agents appear alongside built-in agents in all pickers.

### Per-Project Overrides

In **VibeSpace Settings**, you can override the default agent for specific projects. This is useful when different projects work best with different agents. Clearing the override reverts to the global default.

## Keyboard Shortcuts

Keyboard shortcuts for ACP are planned but not yet implemented. Current interactions use the mouse and compose bar.

## Troubleshooting

### Agent Not Found

The agent picker shows the agent as unavailable (grayed out).

- Verify the CLI tool is installed: run the agent command in your terminal (e.g., `claude --version`)
- Check that the executable is on your PATH
- For custom agents, verify the executable path in Settings → ACP
- Restart CrispyVibes after installing new CLI tools

### Connection Failed

The pane shows a connection error after clicking Connect.

- Check that the agent CLI is up to date
- Look at the error message — it may indicate a missing dependency or auth issue
- Try disconnecting and reconnecting
- Check Crispy's developer tools (ACP console) for diagnostic output

### Permission Denied

The agent reports that a file operation was denied.

- The file may be outside the project boundary. ACP agents can only access files within the selected project directory.
- Check that the project picker points to the correct project root.

### Agent Stops Responding

The agent appears connected but doesn't respond to prompts.

- Click **Cancel** to abort the current prompt
- Disconnect and reconnect the session
- Check if the agent process is still running (visible in Activity Monitor)
- The agent may have crashed — check stderr output in developer tools

## Known Limitations

- **No conversation persistence.** Chat history is lost when you disconnect. Reconnecting starts a fresh conversation.
- **No multi-agent sessions.** Each pane or tile connects to one agent at a time.
- **No real-time collaboration.** Sessions are single-user.
- **Direct integration agents require specific CLI versions.** If Claude Code or Codex change their output format, you may need to update CrispyVibes.
- **Terminal output visibility.** Commands run by the agent appear in terminal tabs, but output capture depends on the terminal engine's callbacks.
