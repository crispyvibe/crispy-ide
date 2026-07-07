# Feature Brief — Vibe Lanes

Status: canonical draft · Feature: F059

## What It Is

Vibe Lanes is a task-first surface for autonomous work. The user starts a task,
chooses a reusable lane, and watches that task move through visible checkpoints.
The user manages flow and outcomes, not chat transcripts.

## Product Shape

- **Dashboard** — all tasks, sorted by actionability.
- **Task detail** — checkpoint path, current work, verification history,
  carry-forward, open input request, and chats.
- **Lane editor** — reusable process authoring.

## Primary Objects

- **Task** — the thing the user wants done.
- **Lane** — reusable process template.
- **Checkpoint** — one bounded Work -> Verify loop.
- **Input request** — Supply, Steer, or Review prompt that pauses a task as
  Needs you.

## Dashboard Expectations

Tasks are grouped or sorted by state:

1. **Needs you** — requires user action now.
2. **Running** — active or queued.
3. **Stopped** — terminal but not successful.
4. **Done** — completed.

Each task row shows:

- title;
- lane name;
- project;
- current checkpoint;
- compact checkpoint rail;
- state label;
- attempt count/current activity;
- primary action.

Primary actions:

- Running: Stop.
- Needs you: Answer / Open.
- Stopped: Open / Delete.
- Done: Open.

## Task Detail Expectations

Task detail must make the lane path legible:

- checkpoint rail with passed/current/stopped/waiting states;
- selected checkpoint detail;
- Work, Verification, Bounds, and Contract;
- attempts and reviewer feedback;
- carry-forward values;
- worker/reviewer chat buttons.

When `openInputRequest` exists, it is the main task action:

- Supply renders fields for missing keys and saves values into carry-forward.
- Steer renders last reviewer feedback, exhausted-bound reason, remaining steer
  count, and a guidance field.
- Both flows include Stop.

## Lane Editor Expectations

The editor must author the canonical model:

- lane name and description;
- lane steer limit;
- checkpoint order and stable keys;
- Work: goal, instructions, skills;
- Verification: done-when definition;
- Bounds: max attempts, time limit, stop or escalate;
- Contract: required inputs, ask-user toggle/prompt, produced outputs.

The editor should make mis-authored contracts visible. If a checkpoint requires a
non-ask-user key that no earlier checkpoint produces, warn before save.

## States

The UI vocabulary is:

- `running` -> **Running**
- `needsInput` -> **Needs you**
- `stopped` -> **Stopped**
- `done` -> **Done**

Do not show "Needs input" to users unless it is technical detail; the product
label is **Needs you**.

## Starter Lanes

Starter lanes should demonstrate the model, not hide it.

The default bug-fix lane should be:

```text
Reproduce -> Patch -> Verify -> Summarize
```

It should use carry-forward keys such as `repro` and `fix`, and at least one
checkpoint should demonstrate `onExhausted = escalate` so users see how Steer is
meant to work.

## Out of Scope

- Marketing/landing-page treatment.
- Human approval checkpoint type.
- Arbitrary strategy ladders.
- Scheduled triggers.
- Per-task workspace isolation UI.
