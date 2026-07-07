# Vibe Lanes — Spec

Status: draft

Feature: F059 · Canonical source of truth

This spec set is the source of truth for Vibe Lanes implementation going forward.
The `vision/` subfolder (the original blog draft and diagram) is background
material; when it conflicts with this feature spec, this feature spec wins.

## Overview

Vibe Lanes lets a developer run work through reusable, visible processes instead
of babysitting agent chats. A **lane** is an ordered list of **checkpoints**. A
**task** is one run of a user's input through a lane on a specific project.

Each checkpoint is an **Expectation Construct** with three authored parts:

> **Work** — what the worker should produce.
> **Verification** — how the outcome is judged, as a plain-text "done when..."
> definition checked by an independent reviewer.
> **Bounds** — how many attempts and how much time the worker gets before the
> checkpoint either stops or asks a person to steer.

Within a checkpoint, the worker attempts the Work, the reviewer judges the actual
outcome against Verification, and failure feedback is fed into the next attempt.
On pass, the checkpoint records carry-forward and the task advances. On exhausted
bounds, the checkpoint follows the author's bound behavior: **stop** or
**escalate** to a person for steering, subject to the lane's steer limit.

The feature has two components with the schema as their contract:

- **UI component** — authors lanes, starts tasks, renders state, and answers open
  input requests.
- **Execution component** — runs checkpoints, drives worker/reviewer sessions,
  enforces bounds, persists transitions, and emits task state.

Core terms:

- **Lane** — a reusable, versioned process template. Lanes do not run by
  themselves.
- **Checkpoint** — one bounded Work -> Verify loop with carry-forward contract.
- **Verification** — authored data; an independent reviewer checks the outcome
  and returns PASS/FAIL with feedback. Ambiguous means FAIL.
- **Task input** — the user's per-run instruction, such as "Fix the flaky payment
  test." It is combined with each checkpoint's reusable Work.
- **Carry-forward** — named values produced by passed checkpoints and required by
  later checkpoints.
- **Needs input** — a paused state where the user must supply a missing input or
  steer an exhausted checkpoint.

## Dependencies

- F011 (ACP) — worker and reviewer agent sessions.
- F040 (Agent Conversation Persistence) — persistent task/checkpoint state.
- F047 (External Agent Sessions) — headless ACP sessions driven by the engine.
- F020 (VibeSpace Lifecycle) — project-scoped task launch.
- F006 (Content Viewer) — dashboard, task detail, and lane editor surfaces.
- F055 (Git Worktrees) — optional future per-task workspace isolation.

## Requirements

### F059-R01: Lane as a reusable process

A lane MUST be an ordered list of one or more checkpoints and MUST be reusable
across many tasks. Lanes MUST be versioned. The user MUST be able to create,
edit, and delete lanes. Checkpoint keys MUST be stable, normalized, unique, and
non-empty on save.

Shipped starter lanes MUST reconcile with the stored set on startup: pristine
(never user-edited) starters refresh to improved shipped content, newly shipped
starters are added, and user deletions persist (tombstones). A user-edited copy
of a starter MUST never be auto-overwritten. The user MUST be able to restore
deleted starters explicitly.

### F059-R02: Checkpoint definition

Each checkpoint MUST declare Work, Verification, Bounds, and a carry-forward
contract:

- Work: goal, instructions, and skills. Skills are file paths to skill folders or
  `SKILL.md` files that the worker reads on demand; contents are not inlined.
- Verification: a plain-text "done when..." definition checked by the reviewer.
- Bounds: max attempts, time limit, and bound behavior (`stop` or `escalate`).
- Contract: `requires` named inputs and `produces` named outputs. Required inputs
  MAY be marked `ask-user`.

### F059-R03: Task = one run through a lane

A task MUST run one user input through a chosen lane against one project path.
The task MUST pin the exact lane version it started from. Tasks are independent
in state: one task stopping, needing input, failing, or completing MUST NOT alter
another task.

### F059-R04: Checkpoint loop and reviewer verdict

Within a checkpoint, the worker MUST attempt the Work and the verification MUST
judge the outcome against the Verification definition. By default an independent
reviewer agent judges; a checkpoint authored with `humanReview` MUST instead
pause as `needsInput` with a Review request after the work turn, and the user's
verdict (approve / request changes with feedback) becomes the verification
result — without re-running the worker. On FAIL, feedback MUST be fed back to
the worker and the checkpoint MUST stay put. On PASS, the task MUST advance to
the next checkpoint or become Done if it was the last checkpoint. The engine MUST
NOT decide completion from worker free-form text, and the worker MUST NOT be able
to edit verification or the verdict.

### F059-R05: Carry-forward contract

When a checkpoint passes, the worker MUST write a handoff. The engine MUST
persist the handoff to a per-task handoff file on disk and MUST inject the file
paths of all earlier passed checkpoints' handoffs into later checkpoint prompts
(read on demand — contents are not inlined). Handoff files are the durable
carry-forward substrate: they survive app restarts and fresh agent sessions.

Declared `produces` values MAY be emitted in the verified work turn or in the
handoff; the engine MUST accept either source and MUST store emitted values in
carry-forward. A checkpoint that passes without emitting a declared output MUST
be logged, not failed — and MUST NOT erase a value already present in
carry-forward.

Before a checkpoint runs, the engine MUST resolve every required key:

- present in carry-forward -> inject it and run the checkpoint;
- absent, not `ask-user`, and no earlier checkpoint declares it in `produces`
  -> stop the task as a mis-authored lane (`misAuthoredLane`);
- absent, not `ask-user`, but an earlier checkpoint declared it in `produces`
  -> stop the task with `missingInput` (a runtime emission failure, not an
  authoring error);
- absent and marked `ask-user` -> set the task to `needsInput` with a Supply
  request.

Fatal resolutions MUST take precedence over Supply: when a checkpoint is missing
both a fatal key and an ask-user key, the task stops without asking the user.

### F059-R06: Bounds, stop, and steer

The engine MUST enforce each checkpoint's max-attempt and time bounds. Bounds are
checked before each new attempt and before verification begins. A verification
that completes with PASS stands even if the time bound elapsed while verifying —
the bound did not run out first. When a bound is exhausted before PASS:

- if the checkpoint bound behavior is `stop`, the task MUST become Stopped with a
  distinct reason (`verificationFailed` or `timeout`);
- if the behavior is `escalate` and the task is under the lane's steer limit, the
  task MUST become `needsInput` with a Steer request that includes the last
  reviewer feedback and exhausted-bound reason;
- if the behavior is `escalate` but the steer limit is reached, the task MUST
  become Stopped.

When the user answers a Steer request, the guidance MUST be fed to the worker as
feedback, the checkpoint MUST get a fresh bounded attempt window, and the task
MUST resume Running.

### F059-R07: Human input requests

A task in `needsInput` MUST have exactly one open input request. Requests are:

- **Supply** — missing ask-user inputs. The user's answers are stored in
  carry-forward and the checkpoint runs.
- **Steer** — exhausted bounds with escalation. The user's guidance is appended
  as feedback and the checkpoint retries with a fresh bounded budget.
- **Review** — a human-verification checkpoint finished its work. The user
  approves (PASS) or requests changes with feedback (FAIL, which loops back to
  the worker). Rejection without feedback MUST be refused.

The user MUST be able to answer the request or stop the task. The scheduler MUST
NOT run tasks while they are in `needsInput`.

### F059-R08: Crash-safe persistence and resume

Task state, open input request, carry-forward, current checkpoint, attempt
history, steer count, and per-checkpoint outcomes MUST be persisted after every
transition. After restart, Running tasks resume from the last persisted
checkpoint, `needsInput` tasks remain paused with their request intact, and
terminal tasks remain terminal. Persisted state MUST be validated before replay;
invalid or inconsistent state MUST be refused rather than run.

### F059-R09: Dashboard and observability

The dashboard MUST show every task's lane, current checkpoint, state, and attempt
count, with counts by state. `Needs input` tasks MUST be shown as **Needs you**
and sorted above Running, Stopped, and Done. The transition into `needsInput`
MUST fire a user notification (exactly once per open request). A task detail view
MUST show the lane path, activity log, last verification result, carry-forward
values, any open input request, and openable worker/reviewer ACP timelines.

### F059-R10: Task controls

The UI MUST support: create task, stop task, answer input request, delete task,
create lane, update lane, delete lane. A generic Resume command MUST NOT blindly
retry exhausted bounds; resumption from `needsInput` happens through a Supply or
Steer answer.

## Scenarios

### F059-S01: A task runs a lane end to end

- **Given** a lane `Reproduce -> Patch -> Verify -> Summarize`
- **When** each checkpoint's verification passes in turn
- **Then** the task advances checkpoint by checkpoint and ends Done after the
  final checkpoint, with checkpoint runs, handoffs, and carry-forward persisted.

### F059-S02: A checkpoint self-corrects

- **Given** a checkpoint whose reviewer fails attempt 1 and passes attempt 2
- **When** the reviewer feedback is returned
- **Then** the worker receives that feedback, retries, and the checkpoint
  completes on PASS.

### F059-S03: Required output carries forward

- **Given** checkpoint A produces `repro` and checkpoint B requires `repro`
- **When** A passes and emits `repro`
- **Then** B receives `repro` in its first prompt.

### F059-S04: Missing ask-user input pauses for Supply

- **Given** checkpoint Deploy requires `api_base` marked `ask-user`
- **When** `api_base` is absent from carry-forward
- **Then** the task becomes Needs you with a Supply request; after the user
  answers, `api_base` is stored and Deploy runs.

### F059-S05: Missing non-user input stops as mis-authored

- **Given** a checkpoint requires `api_diff` not marked `ask-user`
- **When** no prior checkpoint declares `api_diff` in `produces`
- **Then** the task stops and records the `misAuthoredLane` reason.

### F059-S10: Declared-but-unemitted output stops as missing input

- **Given** checkpoint A declares `repro` in `produces` and checkpoint B requires
  `repro` not marked `ask-user`
- **When** A passes without emitting `repro`
- **Then** the miss is logged at A, no carried value is erased, and B stops the
  task with `missingInput` (not `misAuthoredLane`).

### F059-S11: Handoffs survive a fresh session

- **Given** checkpoints A and B passed and wrote handoff files
- **When** checkpoint C runs (including after an app restart with a fresh agent
  session)
- **Then** C's prompt references both A's and B's handoff file paths.

### F059-S06: Exhausted bounds escalate for Steer

- **Given** checkpoint Patch is configured to escalate and the lane steer limit
  has not been reached
- **When** Patch exhausts attempts or time without PASS
- **Then** the task becomes Needs you with a Steer request including the last
  reviewer feedback; after the user gives guidance, Patch retries with a fresh
  bounded budget.

### F059-S07: Steer limit stops the task

- **Given** a lane steer limit of 1
- **When** a checkpoint exhausts bounds a second time
- **Then** the task stops instead of asking for more guidance.

### F059-S08: Resume after crash

- **Given** a task is Running or Needs you
- **When** the app is relaunched
- **Then** Running resumes safely from persisted state, and Needs you remains
  paused with the same open request.

### F059-S09: Invalid state refused

- **Given** persisted task state fails validation
- **When** the task attempts to load
- **Then** the engine refuses to replay it and degrades gracefully.

## Acceptance Criteria

- The specs, schema, usage guide, UX brief, and threat model consistently define
  the four states: `running`, `needsInput`, `stopped`, `done`.
- A lane can declare ask-user required inputs, bound behavior, and a steer limit.
- Supply and Steer flows are covered by unit tests with deterministic fakes.
- Exhausted `stop` bounds stop; exhausted `escalate` bounds produce a Steer
  request under the steer limit and stop at/over the limit.
- Missing ask-user input produces a Supply request; a missing non-user input
  stops the task — `misAuthoredLane` when nothing could supply it,
  `missingInput` when an earlier checkpoint declared it. Fatal misses take
  precedence over Supply, and missing outputs never erase carried values.
- Passed checkpoints persist handoff files; later checkpoints receive all prior
  handoff paths.
- The transition into Needs you fires a notification exactly once per request.
- The dashboard sorts **Needs you** tasks first and task detail renders the open
  request with an answer flow.
- Focused engine/manager tests cover persistence and restart behavior for
  `needsInput` tasks.
- No code path reads worker free-form text to decide verification, and none lets
  the worker edit verification or reviewer verdict.

## Out of Scope

- Human approval gates on every advance. Human verification exists only as a
  per-checkpoint authored choice (`humanReview`); agent-verified checkpoints
  advance without approval.
- Strategy ladders or multiple fallback strategies inside a checkpoint. Bounds
  produce either stop or one bounded steer path.
- Scheduled/event triggers. Tasks start manually.
- No-progress detection beyond max attempts and time.
- Per-task workspace isolation. Reserved via `workspaceRef`, but not required for
  this feature.

## Open Questions

- Default starter lane wording for project-type-agnostic verification.
- Whether reviewer read-only behavior should become a technical ACP trust mode
  instead of prompt guidance.

## Change History

- 2026-07-06 — Human verification: a checkpoint may be authored with
  `humanReview`, pausing after the work turn for the user's approve /
  request-changes verdict (Review request kind). Per-task project path and ACP
  agent selection added to task creation.
- 2026-07-03 — Starter-lane reconciliation: pristine starters auto-refresh on
  startup, deletions persist via tombstones, edits opt lanes out permanently,
  and an explicit Restore command re-adds starters. Starter catalog deepened:
  full carry-forward contracts, checklist verifications, ask-user Supply demo,
  escalate bounds on expensive steps, stack-agnostic instructions.
- 2026-07-03 — Context-passing revision: handoffs persist to files and inject by
  path (durable across restarts); declared outputs accepted from the verified
  work turn or handoff and never erase carried values; `missingInput`
  distinguished from `misAuthoredLane`; fatal misses precede Supply; a completed
  PASS stands over a concurrent timeout; Needs you notification promoted from
  open question to requirement.
- 2026-07-02 — Made this spec set the canonical source of truth. Restored the
  four-state model, Supply, Steer, ask-user inputs, stop-vs-escalate bounds, and
  steer limit.
- 2026-06-28 — Simplified draft reduced states to Running / Stopped / Done and
  removed escalation/human input. Superseded by the 2026-07-02 canonical draft.
- 2026-06-23 — Task -> Lane -> Checkpoint model with broader strategy/human
  checkpoint machinery. Superseded.
- 2026-06-22 — Goal Contract reframing. Superseded.
- 2026-06-20 — Initial draft. Superseded.
