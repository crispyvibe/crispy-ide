# Vibe Lanes — Functional Model

Status: canonical draft · Feature: F059

This document explains the behavior. `spec.md` defines requirements, and
`schema-design.md` defines the data contract.

## Essence

Stop managing agents. Manage work.

A **Vibe (Loop)** is a reusable expectation contract. A **Vibe Lane (Spiral)**
is a recipe that puts Vibes in order and carries verified progress forward. A
**task** is one user input moving through that recipe. Each Vibe is a bounded
loop with a bar:

> produce this, prove it this way, carry the result forward.

That unit is formally an **Expectation Construct** and is called a **Vibe** in
the product:

- **Work** — what should exist after the attempt.
- **Verification** — how the actual outcome is judged.
- **Bounds** — how many tries and how much time are allowed before stopping or
  asking for steering.

## The New Dimension

A normal agent loop retries one prompt until a check improves. Vibe Lanes adds
direction across loops: an ordered Spiral of independently verified
checkpoints.

```
checkpoint -> checkpoint -> checkpoint -> Outcome
     ^              ^              ^
     | feedback     | feedback     | feedback
```

The unit of progress is not "the worker says it is done." It is "this checkpoint
passed its authored verification; carry its result to the next checkpoint."
The Spiral moves forward by default rather than implicitly revisiting prior
checkpoints: each Vibe owns its retry Loop, and the lane accumulates verified
outputs and context. An author may additionally group contiguous checkpoints into
a bounded loop with an explicit output condition; only that group can revisit its
members.

## The Core Nouns

- **Vibe (Loop)** — reusable, versioned Work + Verification + Bounds
  definition.
- **Vibe Lane (Spiral)** — reusable, versioned ordered path of pinned Vibe
  references. Inert until a task uses it.
- **Task** — one run of a user's input through a lane in one project.
- **Checkpoint** — one Vibe placed in a lane, with lane-specific handoff data.
- **Worker** — agent session that performs the Work.
- **Reviewer** — separate agent session that checks the actual outcome against
  the Verification.
- **Engine** — the checkpoint's agent, model, mode, and reasoning choices.
  Execution trust is fixed to Full Trust.
- **Human** — supplies missing ask-user inputs and steers stuck checkpoints.
- **Author** — designs Vibes and composes lanes from them.

## Vibe and Lane-Step Shape

```text
Vibe
├─ Engine
│    agent          — installed ACP/direct agent or app default
│    model          — agent-scoped model or default
│    mode           — agent mode or default
│    reasoning
│    trust          — Full Trust (fixed execution policy)
│
├─ Work
│    goal           — what to accomplish
│    instructions   — constraints and local process
│    skills[]       — paths to skills the worker reads on demand
│
├─ Verification
│    definition     — plain-text "done when..." statement checked by reviewer
│    reviewSkills[] — paths to skills the reviewer reads on demand
│    humanReview    — user takes the reviewer's seat when true
│
├─ Bounds
│    maxAttempts
│    timeoutSeconds
└─ onExhausted    — stop | escalate

Lane Step
├─ key              — stable identity inside the lane
├─ order
├─ vibeID
├─ vibeVersion      — pinned; updates are adopted explicitly
└─ Handoff
     requires[]     — named inputs needed before this step can run
     produces[]     — named outputs emitted after PASS
```

Work, Verification, and Bounds are the Vibe. The handoff is how Vibes connect
inside a lane and therefore is not owned by the reusable Vibe.

Engine choices are authored on the Vibe and pinned with its version. Unset
choices inherit ACP defaults at attempt start. An explicit agent with no model
uses that agent's own default model. This prevents a model from the app-default
agent from leaking into a different agent.

Editing a Vibe creates a new version. Existing lanes continue using the version
they pinned until the author explicitly adopts the update. Tasks and Schedules
retain resolved snapshots for immutable execution.

The worker and reviewer use the checkpoint's same resolved engine. The live
session reports what it actually applied, and the task stores that immutable
snapshot on each attempt.

Verification is authored data, not engine behavior. The reviewer may inspect
files and run commands the definition implies. Optional Review skills provide
reusable review procedures without hardcoding verifier types; they are resolved
like Work skills and sent only to the reviewer. Completion is always PASS/FAIL
against the authored definition. The worker cannot edit that definition or the
verdict.

## One Checkpoint Loop

```text
        ┌──── feedback ◄── fail ──┐
        ▼                         │
Work ──────► Verify ──────────────┘
                │
              pass ──► handoff + carry-forward
```

On FAIL, reviewer feedback becomes the next worker prompt. On PASS, the worker
writes a handoff and emits the checkpoint's declared outputs. The engine persists
the handoff to a file, stores the outputs in carry-forward, and advances. A
completed PASS stands even if the time bound elapsed during verification — the
bound did not run out first.

The engine checks bounds before each new attempt and before verification begins.
Exhausted bounds do not rely on
the worker to stop. They follow the author's choice:

- **stop** — task becomes Stopped with a reason;
- **escalate** — task becomes Needs you with a Steer request if under the steer
  limit, otherwise Stopped.

## Carry-Forward

Context lives in durable substrates the agent already has — the session thread,
the project files, and persisted **handoff files** — not inside the engine. The
engine points at context rather than carrying it.

When a checkpoint passes, its handoff is persisted to a per-task file
(`<handoffRoot>/<taskID>/<checkpointKey>.md`). Every later checkpoint receives
the paths of **all** earlier passed checkpoints' handoff files in its prompt, to
read on demand — the same pattern as skills. This survives app restarts and
fresh ACP sessions, when chat memory is gone.

Alongside the handoff, small declared outputs are parsed from the handoff (or,
as a fallback, from the verified work turn's text) and stored in a per-task
key/value map.

Before a checkpoint runs, each required input is resolved:

- present in carry-forward -> injected into the first worker prompt;
- absent and marked ask-user -> task pauses for Supply;
- absent, not ask-user, and no earlier checkpoint declares it in `produces` ->
  task stops as mis-authored (`misAuthoredLane`);
- absent, not ask-user, but an earlier checkpoint declared it -> task stops
  with `missingInput` (the lane was right; the worker failed to emit).

Fatal resolutions take precedence over Supply so the user is never asked to
answer a task that must stop anyway. Missing declared outputs are logged, not
failed immediately — and never erase a value already carried forward.

## Needs You

Three moments put a task in `needsInput`, shown to the user as **Needs you**,
sorted to the top of the dashboard, and announced with a notification (fired
exactly once per open request):

- **Supply** — a required ask-user input is missing. The user supplies values,
  those values go into carry-forward, and the checkpoint starts.
- **Steer** — bounds are exhausted and the checkpoint is configured to escalate.
  The user sees the last reviewer feedback and gives guidance. That guidance is
  appended as feedback, the checkpoint receives a fresh bounded attempt window,
  and the task resumes.
- **Review** — a checkpoint authored with `humanReview` finished its work. The
  user takes the reviewer's seat: approve records a PASS and the lane advances;
  request-changes (feedback required) records a FAIL that loops back to the
  worker like any reviewer rejection. The work is never re-run by a verdict.

Steers are limited by the lane's `steerLimit`. When the limit is reached, the
next exhausted bound stops instead of asking again.

## Task States

```text
created -> running

running -> done          final checkpoint passes
running -> stopped       bound exhausted with stop, non-user input missing,
                         steer limit reached, error, or user stop
running -> needsInput    missing ask-user input, exhausted escalate bound,
                         or human-review verdict required

needsInput -> running    user answers Supply or Steer
needsInput -> stopped    user stops

done/stopped -> running  isolated rerun of one attempted checkpoint
running -> done/stopped  rerun passes and restores the prior terminal state
```

The scheduler runs only `running` tasks. `needsInput`, `stopped`, and `done`
tasks are not scheduled.

## Isolated Step Rerun

After a task is Done or Stopped, any checkpoint with attempt history can run
again with an attempt-local engine override. This starts a fresh budget epoch and
fresh sessions without deleting history or changing the lane. A passing rerun
refreshes that checkpoint's handoff/carry-forward and restores the task's prior
terminal state; it does not replay downstream checkpoints.

## Presentation

Vibe Lanes uses one title-bar identity (`flowchart`) but respects the current
surface:

- board mode opens a temporary spotlight that can be pinned into one persistent
  Vibe Lanes tile;
- detailed mode opens or activates the Vibe Lanes content tab;
- a detached board inserts the tile directly into its own surface.

## Worked Example

Lane: **Fix a bug**

```text
Reproduce -> Patch -> Verify -> Summarize
```

Task input: "Fix the flaky payment test."

1. **Reproduce** writes a deterministic failing test. Reviewer confirms the test
   fails for the bug. Produces `repro`.
2. **Patch** requires `repro`. Worker patches the cause. Reviewer still sees the
   flake, so feedback loops back. Attempts exhaust; Patch is configured to
   escalate, so the task becomes Needs you with a Steer request. The user says,
   "Pin the clock with FakeClock." Patch retries with fresh bounds and passes.
   Produces `fix`.
3. **Verify** requires `repro` and `fix`. Worker runs the relevant and full
   checks. Reviewer confirms the fixed state.
4. **Summarize** writes the final outcome. Task becomes Done.

## Parallelism

Tasks are independent in state. One task stopping, needing input, or completing
does not change another task.

Workspace isolation is not part of this feature. Until a per-task worktree exists,
the manager should serialize tasks per project path and enforce a conservative
global concurrency cap to avoid two unattended workers editing the same project at
once.

## Versioning

Each task pins the lane version it started on. The store retains that revision so
later lane edits do not mutate in-flight or finished tasks, including each
checkpoint's authored engine.

## Decisions Locked

- The canonical task states are `running`, `needsInput`, `stopped`, `done`.
- Human input is limited to Supply, Steer, and per-checkpoint Review
  (`humanReview`). There are no approve-to-advance gates on agent-verified
  checkpoints.
- Bounds are max attempts + time, with `stop` or `escalate` behavior.
- Steer is bounded by a lane-level steer limit.
- Carry-forward uses named required/produced values; handoffs persist to files
  and are injected by path.
- Verification is authored data checked by an independent reviewer, not worker
  self-assessment and not hardcoded engine behavior.
- Agent/model/mode/reasoning are authored per checkpoint; sessions must report
  explicit options as applied or execution stops.
- Worker and reviewer sessions always run with Full Trust. Standard trust is not
  an authored lane option.
- Engine snapshots are immutable attempt history; rerun overrides are
  attempt-local and preserve the authored lane.
- Tasks persist every transition and validate before replay.

## Out of Scope

- Strategy ladders or multiple fallback strategies inside a checkpoint.
- Human approval gates on every advance (Review is per-checkpoint, authored).
- Trigger authoring. Recurring time triggers belong to F061 Schedules.
- No-progress detection beyond attempts/time.
- Per-task workspace isolation.
- Automatic replay of downstream checkpoints after an isolated rerun.
