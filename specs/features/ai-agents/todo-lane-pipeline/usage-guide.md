---
title: "Todo Lane Pipeline"
feature: "F060"
domain: "ai-agents"
audience: "user"
version: "1.0"
sidebar:
  label: "Todo Pipeline"
  order: 8
---

# Todo Lane Pipeline

## Overview

The Todo Lane Pipeline connects your todos to Vibe Lanes, so a quick note can
become verified, autonomous work — with as much or as little help as you want
along the way:

- **Attach files** to a todo as live links that open in Crispy like any file.
- **Triage** runs quietly in the background after you capture a todo: it finds
  related files, drafts the questions worth answering, and suggests a lane.
- **Refine** opens a chat with an agent that interviews you and sharpens the
  todo into something dispatchable — writing the results back into the todo.
- **Dispatch** sends the todo to a lane. Progress reports arrive in the todo's
  own thread, and the todo can complete itself when the work is done.

Every stage is optional. A todo you never triage, refine, or dispatch behaves
exactly as before.

## Getting Started

1. Capture a todo as usual (⌃⌘T or the Todos panel).
2. If auto-triage is on, chips appear on the todo shortly after you stop
   typing: a suggested lane and a question count.
3. Open the todo and either answer the questions via **Refine**, or jump
   straight to **Send to Lane…** if the todo is already clear.

Triage is controlled per vibespace: **off**, **project todos only**
(default), or **all todos**.

## Workflows

### Attach files to a todo

- **Drag and drop** any file onto the todo's detail pane, or
- type the **file-search trigger** in the notes editor or thread composer —
  the same inline search you know from terminals — and pick a file. Add
  `:120` after a path to anchor a line.

Linked files show as chips. Click a chip to open the file in Crispy (at the
anchored line, if set). Links are references, not copies — if a file moves or
is deleted, the chip shows a *missing* state and you can remove or re-pick it.
Files outside your projects are badged as external.

### Let triage work for you

After you capture or edit a todo, triage waits for you to finish typing, then
runs once in the background. You'll see:

- a **lane chip** — the suggested lane, one click away from dispatch;
- a **questions chip** — what an agent would need to know first;
- a short **summary message** in the todo's thread.

Triage never edits your title or notes. If it has nothing useful to say (a
two-word errand, say), it stays silent.

### Refine a todo with an agent

Click **Refine** on a todo to open a chat that already knows the todo, its
files, and the triage findings — it starts by asking the open questions, not
"what do you want?". As you agree on the goal, done-criteria, and constraints,
the agent updates the todo's notes directly; you'll see the changes live.

Close the chat any time — the refined todo keeps everything. Reopening Refine
resumes the same conversation when it's still available.

### Dispatch to a lane

Click **Send to Lane…** (or the suggested-lane chip), pick a lane, and review
the pre-filled inputs. Anything the lane still needs is flagged before you
confirm — fill it in, or proceed and answer later through the lane's normal
*Needs you* flow.

After dispatch, the todo's thread receives progress messages: *dispatched*,
*needs your input*, *stopped*, *done*. When the task finishes, the todo offers
one-tap completion (or completes itself, if you've enabled that).

- A todo tracks one active task at a time; you can dispatch again once the
  previous task finishes or stops.
- Deleting the todo never cancels the lane task — manage running work from the
  Vibe Lanes dashboard.

### From the terminal (agents and scripts)

Everything the UI can do, the CLI can do — todos behave the same no matter
where they were created or dispatched from:

```
crispy todo file add <id> --path src/Parser.swift:120
crispy todo file list <id>
crispy todo triage show <id>
crispy todo dispatch <id> --lane "Fix a bug" --input repro="run UITests/login"
```

Agents use the same commands during refine to attach files they find — and,
once you've agreed in the conversation, to dispatch the todo for you. Dispatch
refuses to proceed when the lane still needs answers (unless you pass
`--allow-unresolved`) and when the todo already has a task running. Todos
created from the CLI get the same triage, chips, and thread updates as
captured ones.

## Keyboard Shortcuts

- **⌃⌘T** — quick-capture a todo (existing, configurable).
- The file-search trigger inside todo editors follows your F038 inline-trigger
  token settings.

## Settings / Configuration

- **Vibespace settings → Todos → Auto-triage:** off / project todos only /
  all todos.
- **Vibespace settings → Todos → On task done:** offer one-tap complete
  (default) or auto-complete the todo.

## Troubleshooting

- **No triage chips appear** — check the auto-triage setting, and note that
  very short or vibespace-level errand todos are skipped by design. Triage
  also needs a configured ACP agent.
- **A file chip shows as missing** — the file was moved or deleted. Click the
  chip to remove or re-pick it. Agents are told the link is unavailable, so a
  stale link won't corrupt their work.
- **Dispatch says inputs are unresolved** — the lane's first step needs
  information the todo doesn't have yet. Use Refine to fill the gaps, or
  proceed and supply the answers when the task asks.
- **Refine won't resume the old chat** — sessions can expire; a fresh one
  starts seeded from the todo's current state, so nothing is lost.

## Known Limitations

- One active lane task per todo.
- File links don't track renames or moves; a moved file shows as missing.
- Triage runs on new and edited todos, not retroactively over your backlog.
