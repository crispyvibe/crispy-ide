# Feature Brief — Vibe Lanes

Status: canonical draft · Feature: F059

## What It Is

Vibe Lanes is a task-first surface for autonomous work. The user starts a task,
chooses a reusable Vibe Lane, and watches that task move through visible
checkpoints. The user manages flow and outcomes, not chat transcripts.

The explanatory model is **Vibe (Loop) -> Vibe Lane (Spiral) -> Schedule**.
Primary navigation stays concise: **Vibes**, **Vibe Lanes**, and **Schedules**.
Parenthetical terms belong in onboarding and explanatory surfaces, not every
operational label.

## Product Shape

- **Automation** — global entry point with Schedules, Vibe Lanes, and
  Vibes tabs.
- **Dashboard** — all tasks, sorted by actionability.
- **Task detail** — checkpoint path, current work, verification history,
  engine history, carry-forward, open input request, rerun, and chats.
- **Vibe Lane editor** — reusable process authoring.
- **Spotlight / board tile** — board-native preview and persistent placement.

## Primary Objects

- **Task** — the thing the user wants done.
- **Vibe (Loop)** — reusable expectation contract with bounded retries.
- **Vibe Lane (Spiral)** — reusable process template that accumulates verified
  context while moving forward.
- **Checkpoint** — one Vibe placed in a Vibe Lane.
- **Schedule** — recurring trigger for a frozen Vibe Lane revision.
- **Engine** — the agent/model/mode/reasoning used by one checkpoint. Trust is
  always Full Trust.
- **Input request** — Supply, Steer, or Review prompt that pauses a task as
  Needs you.

## Surface Expectations

The application rail MUST open Automation with Schedules selected by default.
Schedules, Vibe Lanes, and Vibes remain independent entities and views
behind persistent tabs. Opening Vibe Lane or Vibe authoring from a Schedule
draft MUST preserve that draft. The update chain remains explicit: a Vibe Lane
adopts a newer Vibe, then a Schedule adopts the newer Vibe Lane revision.

The `flowchart` title-bar control behaves by surface:

- primary board: open spotlight; show pin in the spotlight header; successful pin
  inserts one persistent tile and dismisses the spotlight;
- detailed: activate/open the Vibe Lanes tab;
- detached board: add one tile directly to the originating surface and disable
  the control for a duplicate or full board.

## Dashboard Expectations

Tasks are grouped or sorted by state:

1. **Needs you** — requires user action now.
2. **Running** — active or queued.
3. **Stopped** — terminal but not successful.
4. **Done** — completed.

Each task row shows:

- title;
- Vibe Lane name;
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

Task detail must make the Vibe Lane path legible:

- checkpoint rail with passed/current/stopped/waiting states;
- selected checkpoint detail;
- Work, Verification, Bounds, and Contract;
- authored engine and session-reported active/attempt engines;
- attempts and reviewer feedback;
- carry-forward values;
- worker/reviewer chat buttons.

Done and Stopped tasks expose an icon-only rerun action for checkpoints with
attempt history. The rerun sheet starts from the authored engine and makes clear
that this is a single-step attempt, not a Vibe Lane edit or downstream replay.

When `openInputRequest` exists, it is the main task action:

- Supply renders fields for missing keys and saves values into carry-forward.
- Steer renders last reviewer feedback, exhausted-bound reason, remaining steer
  count, and a guidance field.
- Both flows include Stop.

## Vibe Library and Editor Expectations

The Vibes view is the canonical library for reusable expectation contracts. It
MUST support search, Ready/Needs setup status, usage counts, create, edit, and
delete when unused. The Vibe editor owns:

- Engine: installed agent, agent-scoped model/mode, and reasoning, with explicit
  App default / Agent default options; no trust selector;
- Work: goal, instructions, Work skills;
- Verification: done-when definition, Review skills, and verification owner;
- Bounds: max attempts, time limit, stop or escalate.

The primary Vibe flow MUST emphasize **Outcome -> Done when -> Limits**. Review
skills MUST appear with Done when. Engine and Work skills remain available as
secondary Execution settings. The library inspector and task definition MUST
label the two skill roles distinctly.

## Vibe Lane Designer Expectations

The Vibe Lane designer MUST use a kiosk-style composition:

- searchable Vibe library;
- ordered Vibe Lane recipe;
- selected-step inspector.

Adding a Vibe creates a pinned reference, not a copy. The selected-step
inspector shows the resolved Vibe summary and edits only Vibe Lane-owned identity
and handoff data. A newer Vibe version appears as **Update available** and is
adopted only through an explicit action. Creating or editing a Vibe from the
designer opens the same central Vibe entity used by the separate Vibes view.

Protocol-agent model/mode discovery is asynchronous. Keep picker dimensions
stable while loading, show a compact progress indicator, and show a warning
tooltip when discovery fails.

## New Task Expectations

Task creation chooses task input, project, and Vibe Lane. It does not override
the agent. The route preview lists each checkpoint with its inherited/authored
engine summary so users can inspect execution choices before starting.

## States

The UI vocabulary is:

- `running` -> **Running**
- `needsInput` -> **Needs you**
- `stopped` -> **Stopped**
- `done` -> **Done**

Do not show "Needs input" to users unless it is technical detail; the product
label is **Needs you**.

## Starter Vibe Lanes

Starter Vibe Lanes should demonstrate the model, not hide it.

The default bug-fix Vibe Lane should be:

```text
Reproduce -> Patch -> Verify -> Summarize
```

It should use carry-forward keys such as `repro` and `fix`, and at least one
checkpoint should demonstrate `onExhausted = escalate` so users see how Steer is
meant to work.

## Out of Scope

- Marketing/landing-page treatment.
- Blanket human approval gates on every checkpoint.
- Arbitrary strategy ladders.
- Trigger authoring inside the Vibe Lane surface; recurring time triggers
  belong to Schedules.
- Per-task workspace isolation UI.
- Automatic downstream replay after an isolated step rerun.
