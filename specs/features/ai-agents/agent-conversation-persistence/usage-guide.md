---
title: "Agent Conversation Persistence"
feature: "F040"
domain: "ai-agents"
audience: "user"
version: "3.0"
sidebar:
  label: "Conversation History"
  order: 2
---

# Agent Conversation Persistence

## Overview

Your conversations with AI agents are automatically saved and searchable. Close CrispyVibes, reopen it, and every conversation is right where you left it — messages, tool activity, file changes, all of it. This works with every agent type — ACP, Claude Code, Codex, and any future agents.

There's no save button and no "export before closing" warning. Conversations persist across app restarts, vibespace switches, and system reboots. You can search across all your past conversations by keyword or by describing what you're looking for in plain language.

No conversation ever "expires." You open a thread, you see your history, you type. The system handles everything else — connecting to the agent, resuming context, managing sessions — all behind the scenes.

## Getting Started

There is nothing to set up. Conversations are saved automatically the moment you start chatting with an agent — regardless of which agent type you're using. When you reopen CrispyVibes, your conversation history is already there.

If you're updating from a version of CrispyVibes that didn't have conversation persistence, your history starts fresh — previous sessions are not retroactively saved.

## Workflows

### Viewing Conversation History

Your conversation history lives in the side panel. The default view is scoped to your current vibespace, organized by project and sorted by date.

```
┌─────────────────────────────────┐
│ 🔍 Search conversations...      │
├─────────────────────────────────┤
│ ▼ my-vibespace  Current VibeSpace│
│                                 │
│   ▼ backend (project)           │
│   Recent                        │
│    🤖 Fix auth token refresh    │  ← agent icon + title
│      3 min ago                  │
│    🤖 Add pagination to API     │
│      1 hour ago                 │
│   Older                         │
│    🤖 Debug SSH timeout         │
│      Apr 23                     │
│                                 │
│   ▼ frontend (project)          │
│    🤖 Refactor nav component    │
│      Apr 23                     │
│                                 │
│ ▸ Other VibeSpaces (3)          │
└─────────────────────────────────┘
```

- Active conversations show a green dot indicator.
- Click any conversation to load it — the compose bar is always ready.

### Resuming a Past Conversation

Click a conversation in the sidebar to open it. Your full message history loads immediately and the compose bar is ready for input. Just type.

- **If the agent is still connected:** Your message is sent immediately. No delay.
- **If the agent is disconnected:** The system silently reconnects in the background. You may see a brief connecting indicator, but the compose bar stays visible. Your message is sent as soon as the connection is established.

The system automatically picks the best resume strategy based on the agent's capabilities:
- If the agent supports lightweight resume (ACP `session/resume`), it reconnects without replaying history — fast and seamless.
- If the agent supports session loading (ACP `session/load`), it replays the full conversation to restore internal state.
- For CLI-based agents (Claude Code, Codex), the stored session/thread ID is passed to the CLI for continuation.
- You don't need to choose between these — it happens automatically.

**If resume fails** (e.g., the agent no longer recognizes the session), you'll see a dialog explaining what went wrong and offering to start a fresh session. The system never silently discards your session context.

**If the agent process crashes**, the error is shown in an orange banner at the top of the conversation with the actual reason (including what the agent printed to stderr). You can click Retry to reconnect.

There's no "read-only" mode and no "Start new turn" button. Every conversation is always ready for your next message.

### Searching Conversations

Use the search field at the top of the conversation sidebar.

- **Keyword search** — type a word or phrase (e.g., "pagination") to find all conversations containing that exact term. Results appear instantly.
- **Natural language search** — describe what you're looking for in your own words (e.g., "that thing where we fixed the login flow"). CrispyVibes finds relevant conversations even if those exact words weren't used.

Search results show the conversation title, a matched message snippet, and a timestamp. Click a result to jump directly to that conversation at the matching message. Search covers your full conversation history — not just the most recent 2,000 messages.

### Renaming a Conversation

Conversations are automatically titled based on your first message. To rename one:

1. Double-click the conversation title in the sidebar.
2. Type the new name.
3. Press **Enter** to confirm.

### Deleting a Conversation

1. Click the delete (✕) button on a conversation row in the sidebar.
2. An inline confirmation appears: "Delete this conversation? Cancel / Delete"
3. Click **Delete** to confirm.

The conversation is removed from the sidebar, any open tabs, board tiles, and the dock preview. This action is permanent and cannot be undone.

### Exporting a Conversation

1. Right-click a conversation in the sidebar.
2. Choose **Export as Markdown** or **Export as JSON**.

- **Markdown** produces a human-readable document with all messages, tool calls, and file changes — the complete conversation history.
- **JSON** produces a machine-readable format for use with external tools — also the complete history.

Exporting is the only way conversation data leaves your machine.

### Viewing Conversations from Other VibeSpaces

Conversations from other vibespaces appear in a collapsible "Other VibeSpaces" section at the bottom of the sidebar. This section is collapsed by default and shows the total count.

### Viewing File Changes (Diff Panel)

When an agent modifies files during a conversation, a "Changed files" summary appears after the response. Each file shows addition/deletion counts.

- Click **View diff** to open a full-screen diff panel with a file sidebar and syntax-highlighted diffs.
- Click individual files in the sidebar to navigate between them.
- Press **Escape** to close the diff panel.

### Attaching Images

You can attach images to your messages:

- **Paste**: Copy an image and press **Cmd+V** in the compose bar.
- **Drag and drop**: Drag image files onto the compose bar.

Images appear as thumbnails above the text input. Click the ✕ on a thumbnail to remove it. Images are sent to the agent alongside your text message.

## Keyboard Shortcuts

Keyboard shortcuts for conversation history are planned but not yet implemented. Current interactions use the mouse and sidebar.

## Settings / Configuration

### Auto-Delete Old Conversations

Open **Settings → Privacy** and find **Auto-delete conversations older than**. Choose from:

| Option | Behavior |
|--------|----------|
| **Never** | Conversations are kept indefinitely (default) |
| **7 days** | Conversations older than 7 days are automatically removed |
| **30 days** | Conversations older than 30 days are automatically removed |
| **90 days** | Conversations older than 90 days are automatically removed |

Cleanup runs automatically when CrispyVibes starts. Set it once and forget about it.

### Clear All Conversations

To delete all conversation history at once, open **Settings → Privacy** and click **Clear all conversations**. This action is permanent and cannot be undone.

## Troubleshooting

### My conversations disappeared

Conversation history is scoped to your current vibespace by default. If you switched vibespaces, your conversations from the other vibespace won't appear in the sidebar.

- Switch back to the vibespace where the conversations took place.
- Or click **Show all conversations** at the bottom of the sidebar to see conversations across all vibespaces and projects.

### Search isn't finding what I expect

- Try different keywords. Search matches exact terms, so "auth" won't match "authentication" in keyword mode.
- Try rephrasing naturally. Instead of a single keyword, describe what you remember: "the conversation about fixing login errors" may surface results that a keyword search misses.
- Remember that search covers your full history — even messages older than what the timeline displays.

### Conversation history is empty after updating CrispyVibes

This is expected. Conversation persistence is new — only conversations started after the update are saved. Previous sessions were not recorded and cannot be recovered.

### Agent conversations work but nothing is saved

If the persistence system encounters an issue on startup, CrispyVibes falls back to the previous behavior where conversations are not saved. This is rare, but if it happens:

1. Quit and reopen CrispyVibes.
2. If the problem persists, check for disk space issues.
3. Contact support if conversations continue not saving after a restart.

### I see a brief "connecting" indicator when I type in an old conversation

This is normal. When you type in a conversation whose agent session has ended, CrispyVibes silently reconnects to the agent in the background. The connecting indicator disappears once the connection is established and your message is sent automatically.

## Future Capabilities

### Tags and Filtering

The conversation system is built with extensibility in mind. Future updates may include:

- **Tags** — label conversations with custom tags (e.g., "bug-fix", "feature", "research") for quick filtering.
- **Filtering by tag** — narrow the sidebar to show only conversations matching specific tags.
- **System-generated tags** — automatic categorization based on conversation content.

These capabilities are not yet available in the UI but the underlying infrastructure supports them.

### Thread Hierarchies

Future features may introduce thread relationships — for example, a multi-step workflow where each step is its own conversation linked to a parent, or sub-conversations branched from a main thread. The conversation system is designed to support these patterns when they're ready.

## Known Limitations

- **Maximum 2,000 messages displayed per conversation.** Very long conversations show only the most recent 2,000 messages in the timeline. Older messages are still searchable and included in exports.
- **Conversations are stored locally only.** History is not synced between devices. Each Mac has its own conversation history.
- **Conversation history starts fresh.** Previous sessions before this feature was added are not retroactively saved.
- **No conversation branching.** You cannot fork a conversation into multiple paths.
- **No sharing.** Conversations cannot be shared with teammates directly. Use the export feature to share manually.
- **Resume quality varies by agent.** Agents that support `session/resume` (like Kiro CLI) provide the fastest reconnection. Agents that support `session/load` replay the full conversation on reconnect, which takes longer for long threads. Agents without either get transcript replay, which gives the agent your history but not its internal state. In all cases, the experience is seamless — you just type and the system handles the rest.
