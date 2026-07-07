---
title: "Vibe Lanes"
feature: "F059"
domain: "ai-agents"
audience: "user"
version: "4.0"
sidebar:
  label: "Vibe Lanes"
  order: 5
---

# Vibe Lanes

## Overview

Vibe Lanes runs work through reusable processes. You give a **task** to a
**lane**; the lane moves the task through ordered **checkpoints** until the work
is done, stopped, or waiting for you.

Each checkpoint has:

- **Work** — what the worker should produce.
- **Verification** — how an independent reviewer decides whether the outcome is
  done.
- **Bounds** — how many attempts and how much time the checkpoint gets before it
  stops or asks you to steer.

Checkpoints pass context forward as named values, so later checkpoints can depend
on earlier results.

## Getting Started

1. Open **Vibe Lanes** with a project open.
2. Press **New task**, describe the work, and choose a lane.
3. Optionally change the **project directory** (defaults to the focused project)
   and the **agent** (defaults to your app-wide ACP agent).
4. Watch the task move through its checkpoint path.
5. Open the task when it is **Needs you**, Stopped, or Done.

## Task States

- **Running** — the engine is running or waiting for capacity to run the task.
- **Needs you** — the task is paused for a Supply, Steer, or Review answer.
- **Stopped** — the task cannot continue without starting different work or
  changing the lane/task setup.
- **Done** — the final checkpoint passed and the outcome is recorded.

Needs you tasks appear first on the dashboard, and a notification fires the
moment a task pauses for you.

## How a Task Moves

At each checkpoint, the worker performs the Work. The verification checks the
actual outcome against the definition and returns PASS or FAIL — by default an
independent reviewer agent judges; checkpoints authored as **Verified by: You**
pause for your verdict instead.

- PASS records a handoff, stores declared outputs, and advances.
- FAIL sends reviewer feedback back to the worker for another attempt.
- Exhausted bounds either stop the task or ask you to steer, depending on the
  lane.

The worker can change files and explain what it did, but it cannot decide that a
checkpoint is complete. Completion comes from the reviewer.

## Supply

Supply happens when a checkpoint requires an input marked ask-user and the value
is not already in carry-forward.

Example: a Deploy checkpoint requires `api_base`. The task pauses as **Needs
you**, asks for `api_base`, stores your answer, and continues.

## Steer

Steer happens when a checkpoint exhausts its bounds and the lane author chose to
escalate. The task shows the last reviewer feedback and asks for guidance.

Your guidance is fed to the worker as feedback. The checkpoint gets a fresh
bounded attempt window and resumes. Steers are limited by the lane's steer limit;
once reached, the next exhausted bound stops the task.

## Review (human verification)

Review happens when a checkpoint is authored with **Verified by: You**. After
the worker finishes, the task pauses as **Needs you** with the checkpoint's
done-when checklist. Inspect the outcome yourself — project files, the diff, or
the worker thread — then:

- **Approve** — records a PASS and the lane advances.
- **Request changes** — requires feedback; records a FAIL and your feedback goes
  to the worker for another attempt, then the step pauses for your review again.

Waiting on your verdict never consumes attempts or time; rejections count like
any failed attempt.

## Creating and Editing Lanes

Open **Lanes** from the dashboard. For each lane, configure:

- name and description;
- steer limit;
- ordered checkpoints.

For each checkpoint, configure:

- Work: goal, instructions, and skill paths;
- Verification: done-when definition, and who verifies it (reviewer agent or you);
- Bounds: max attempts, time limit, stop or escalate;
- Contract: required inputs, which are ask-user, and produced outputs.

Edits apply to new tasks. Existing tasks keep the lane version they started on.
Use **Restore starters** to re-add deleted starter lanes and refresh unedited
ones to the latest shipped versions — lanes you edited are never changed.

## Following Work

Open a task to see:

- checkpoint path and status;
- current activity;
- last verification result and feedback;
- carry-forward inputs/outputs;
- any open Supply, Steer, or Review request;
- worker and reviewer chats.

## Running Many Tasks

Tasks are independent in state. One task needing input or stopping does not affect
another. Until per-task workspace isolation exists, code-editing tasks should be
serialized per project so two workers do not edit the same files at once.

## Restart Behavior

Running tasks resume from the last persisted checkpoint after restart. Needs you
tasks remain paused with the same request. Done and Stopped tasks remain terminal.
Invalid saved state is refused instead of replayed.

## Troubleshooting

- **A task says Needs you.** Open it and answer the Supply, Steer, or Review
  request, or stop it.
- **A task stopped after missing input.** The lane likely required a key that no
  earlier checkpoint produced and did not mark it ask-user.
- **A task stopped after repeated Steer.** The lane reached its steer limit.
- **A checkpoint keeps failing.** Tighten its Work or Verification, or add an
  earlier checkpoint that produces the context it needs.
- **A task will not resume after restart.** Its persisted state failed validation.

## Known Limitations

- No per-task workspace isolation yet.
- No scheduled/event triggers.
- Human verification is per-checkpoint (authored); there are no blanket
  approve-every-advance gates.
- Reviewer read-only behavior is currently policy/prompt-driven unless ACP adds a
  technical read-only trust mode.
