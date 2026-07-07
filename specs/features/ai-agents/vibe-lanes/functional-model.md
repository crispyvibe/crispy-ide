# Vibe Lanes — Functional Model

Status: canonical draft · Feature: F059

This document explains the behavior. `spec.md` defines requirements, and
`schema-design.md` defines the data contract.

## Essence

Stop managing agents. Manage work.

A **lane** is a reusable process. A **task** is one user input moving through that
process. Each step is a bounded loop with a bar:

> produce this, prove it this way, carry the result forward.

That unit is an **Expectation Construct**:

- **Work** — what should exist after the attempt.
- **Verification** — how the actual outcome is judged.
- **Bounds** — how many tries and how much time are allowed before stopping or
  asking for steering.

## The New Dimension

A normal agent loop retries one prompt until a check improves. Vibe Lanes adds
direction across loops: an ordered path of independently verified checkpoints.

```
checkpoint -> checkpoint -> checkpoint -> Outcome
     ^              ^              ^
     | feedback     | feedback     | feedback
```

The unit of progress is not "the worker says it is done." It is "this checkpoint
passed its authored verification; carry its result to the next checkpoint."

## The Core Nouns

- **Lane** — reusable, versioned list of checkpoints. Inert until a task uses it.
- **Task** — one run of a user's input through a lane in one project.
- **Checkpoint** — one Work -> Verify loop, bounded and ordered.
- **Worker** — agent session that performs the Work.
- **Reviewer** — separate agent session that checks the actual outcome against
  the Verification.
- **Human** — supplies missing ask-user inputs and steers stuck checkpoints.
- **Author** — designs lanes: Work, Verification, Bounds, required/produced
  keys, which inputs are ask-user, bound behavior, and steer limit.

## Checkpoint Shape

```text
Checkpoint
├─ Work
│    goal           — what to accomplish
│    instructions   — constraints and local process
│    skills[]       — paths to skills the worker reads on demand
│
├─ Verification
│    definition     — plain-text "done when..." statement checked by reviewer
│
├─ Bounds
│    maxAttempts
│    timeoutSeconds
│    onExhausted    — stop | escalate
│
└─ Contract
     requires[]     — named inputs needed before this checkpoint can run
     produces[]     — named outputs emitted after PASS
```

Work, Verification, and Bounds are the expectation construct. The contract is how
constructs connect into a lane.

Verification is authored data, not engine behavior. The reviewer may inspect
files and run commands it believes the definition implies, but completion is
always PASS/FAIL against the authored definition. The worker cannot edit that
definition or the verdict.

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
running -> needsInput    missing ask-user input, or exhausted escalate bound

needsInput -> running    user answers Supply or Steer
needsInput -> stopped    user stops
```

The scheduler runs only `running` tasks. `needsInput`, `stopped`, and `done`
tasks are not scheduled.

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
later lane edits do not mutate in-flight or finished tasks.

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
- Tasks persist every transition and validate before replay.

## Out of Scope

- Strategy ladders or multiple fallback strategies inside a checkpoint.
- Human approval gates on every advance (Review is per-checkpoint, authored).
- Scheduled/event triggers.
- No-progress detection beyond attempts/time.
- Per-task workspace isolation.
