# Vibe Lanes — Spec

Status: draft

Feature: F059 · Canonical source of truth

This spec set is the source of truth for Vibe Lanes implementation going forward.
The `vision/` subfolder (the original blog draft and diagram) is background
material; when it conflicts with this feature spec, this feature spec wins.

## Overview

Vibe Lanes lets a developer run work through reusable, visible processes instead
of babysitting agent chats. The product model is:

- **Vibe (Loop)** — one reusable expectation that retries within authored
  bounds until verification passes or the Vibe stops for human direction.
- **Vibe Lane (Spiral)** — an ordered recipe of pinned Vibes that carries
  verified evidence, decisions, and outputs forward. It never makes an implicit
  backward jump; an authored bounded loop group may explicitly revisit its
  contiguous member checkpoints.
  to earlier checkpoints.
- **Schedule** — a recurring trigger that starts a new task with a frozen Vibe
  Lane revision.

A **task** is one run of a user's input through a Vibe Lane on a specific
project.

Each Vibe is formally an **Expectation Construct** with three authored parts:

> **Work** — what the worker should produce.
> **Verification** — how the outcome is judged, as a plain-text "done when..."
> definition checked by an independent reviewer.
> **Bounds** — how many attempts and how much time the worker gets before the
> checkpoint either stops or asks a person to steer.

Within a checkpoint, the worker attempts the Work, the reviewer judges the actual
outcome against Verification, and failure feedback is fed into the next attempt.
On pass, the checkpoint records carry-forward and the task advances. On exhausted
bounds, the checkpoint follows the author's bound behavior: **stop** or
**escalate** to a person for steering, subject to the Vibe Lane's steer limit.

The feature has two components with the schema as their contract:

- **UI component** — authors Vibe Lanes, starts tasks, renders state, and answers
  open input requests.
- **Execution component** — runs checkpoints, drives worker/reviewer sessions,
  enforces bounds, persists transitions, and emits task state.

Core terms:

- **Vibe (Loop)** — a reusable, versioned outcome contract with its own
  Work -> Verification -> Feedback retry cycle.
- **Vibe Lane (Spiral)** — a reusable, versioned recipe of Vibes that
  accumulates verified context as it advances. Vibe Lanes do not run by
  themselves.
- **Checkpoint** — one pinned Vibe placed in a Vibe Lane with a carry-forward
  handoff.
- **Verification** — authored data; an independent reviewer checks the outcome
  and returns PASS/FAIL with feedback. Ambiguous means FAIL.
- **Task input** — the user's per-run instruction, such as "Fix the flaky payment
  test." It is combined with each checkpoint's reusable Work.
- **Carry-forward** — named values produced by passed checkpoints and required by
  later checkpoints.
- **Engine** — the checkpoint's authored agent, model, mode, and reasoning
  choices. Unset choices inherit ACP defaults. Vibe Lane execution always uses
  Full Trust.
- **Needs input** — a paused state where the user must supply a missing input or
  steer an exhausted checkpoint.
- **Schedule** — an independently managed recurring trigger that freezes a Vibe
  Lane revision and creates ordinary tasks when due.

## Dependencies

- F011 (ACP) — worker and reviewer agent sessions.
- F040 (Agent Conversation Persistence) — persistent task/checkpoint state.
- F047 (External Agent Sessions) — headless ACP sessions driven by the engine.
- F020 (VibeSpace Lifecycle) — project-scoped task launch.
- F006 (Content Viewer) — dashboard, task detail, and lane editor surfaces.
- F002 (Terminal Board) — spotlight and persistent board-tile presentation.
- F048 (Terminal Board Multi-Monitor) — detached-board title-bar insertion and
  surface-scoped persistence.
- F055 (Git Worktrees) — optional future per-task workspace isolation.

## Requirements

### F059-R01: Vibes and Vibe Lanes as reusable authoring entities

A Vibe MUST centrally own Work, Verification, Bounds, engine, and skills. Vibes
MUST be independently listable, editable, versioned, and reusable across Vibe
Lanes. A Vibe Lane MUST be an ordered list of one or more pinned Vibe references
and MUST be reusable across many tasks. Vibe Lanes MUST be versioned. Step keys
MUST be stable, normalized, unique, and non-empty on save.

Editing a Vibe MUST create a new version and MUST NOT silently update Vibe Lanes.
The Vibe Lane designer MUST expose an explicit update when a newer Vibe version
is available. A Vibe used by a Vibe Lane MUST NOT be deleted.

Shipped starter Vibe Lanes MUST reconcile with the stored set on startup: pristine
(never user-edited) starters refresh to improved shipped content, newly shipped
starters are added, and user deletions persist (tombstones). A user-edited copy
of a starter MUST never be auto-overwritten. The user MUST be able to restore
deleted starters explicitly.

### F059-R02: Vibe definition and Vibe Lane handoff

Each Vibe MUST declare Work, Verification, and Bounds:

- Work: goal, instructions, and Work skills. A skill is a reusable package
  rooted at `SKILL.md`, with optional `references/`, `scripts/`, `assets/`, and
  agent metadata. The worker receives the package path and reads its entrypoint
  and supporting files on demand; contents are not inlined.
- Verification: a plain-text "done when..." definition, optional Review skills,
  and verification owner. Review skills use the same path resolution as Work
  skills, are read on demand only by the reviewer agent, and are not sent to the
  worker.
- Bounds: max attempts, time limit, and bound behavior (`stop` or `escalate`).

Skills MUST be manageable independently from Vibes. The central Skills library
MUST support bundled, personal, and linked packages; recursively import a
selected collection; preserve a package when duplicating it; and show package
resources, role eligibility, interaction mode, required commands, and readiness.
Crispy-specific metadata MUST live beside `SKILL.md` in `crispy.skill.json`
without changing the portable skill entrypoint. A package with a missing local
reference or required command MUST be unavailable for new Vibe assignments.
Interactive skills MUST NOT be assignable as Review skills.

Each Vibe Lane step MUST pin a Vibe ID and version. The Vibe Lane step owns the
handoff: `requires` named inputs and `produces` named outputs. Required inputs
MAY be marked `ask-user`.

### F059-R03: Task = one run through a Vibe Lane

A task MUST run one user input through a chosen Vibe Lane against one project
path. The selected `projectPath` MUST be the execution directory for the entire
task and MUST NOT be changed by checkpoint output, carry-forward, retry, or rerun.
If future workspace isolation allocates a worktree, allocation MUST complete before
the task starts and the resulting path MUST remain immutable. The task MUST pin the
exact Vibe Lane version it started from. Tasks are independent in state: one task
stopping, needing input, failing, or completing MUST NOT alter another task.

### F059-R04: Checkpoint loop and reviewer verdict

Within a checkpoint, the worker MUST attempt the Work and the verification MUST
judge the outcome against the Verification definition. By default an independent
reviewer agent judges, using any authored Review skills only to inspect and
verify the outcome; a checkpoint authored with `humanReview` MUST instead
pause as `needsInput` with a Review request after the work turn, and the user's
verdict (approve / request changes with feedback) becomes the verification
result — without re-running the worker. On FAIL, feedback MUST be fed back to
the worker and the checkpoint MUST stay put. On PASS, the task MUST advance to
the next checkpoint or become Done if it was the last checkpoint. The engine MUST
NOT decide completion from worker free-form text, and the worker MUST NOT be able
to edit verification or the verdict.

Before the first attempt, the engine MUST verify that every required Work skill
and agent-run Review skill still resolves to a readable `SKILL.md`. A missing
package MUST stop the checkpoint before the worker runs.

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

### F059-R11: Per-checkpoint engine

Every checkpoint MUST be able to author an ACP engine consisting of agent,
model, mode, and reasoning level. The lane editor MUST use the same
installed-agent discovery and agent-scoped model/mode capabilities as ACP chat,
including custom agents.

Unset values MUST resolve as follows:

- agent -> app-wide ACP default;
- model -> app-wide ACP default only when the agent is also inherited; when a
  checkpoint explicitly selects an agent and leaves model unset, use that
  agent's own default;
- mode -> agent default;
- reasoning -> app-wide ACP default.

Worker, reviewer, handoff, final-outcome, and rerun sessions MUST use Full Trust.
The lane editor MUST NOT offer Standard or app-default trust choices. A legacy
persisted checkpoint trust value MUST NOT change this runtime policy.

The worker, reviewer, handoff, and final-outcome turns for a checkpoint MUST use
that checkpoint's resolved engine. An explicit model or mode MUST be offered and
successfully applied by the connected session; unavailable or ignored choices
MUST stop loudly as an execution error rather than silently falling back.

Starter lanes SHOULD remain portable across installed agents while making
opinionated per-step choices. The shipped catalog uses inherited agents/models
with checkpoint-specific reasoning levels.

### F059-R12: Engine observability and isolated rerun

Each active checkpoint run MUST expose the engine reported by its connected
session. Every settled attempt MUST persist an immutable engine snapshot with
agent/model/mode names and identifiers, trust mode, and supported reasoning
level.

For a Done or Stopped task, the user MUST be able to rerun a previously attempted
checkpoint with an attempt-local engine override. The rerun MUST:

- preserve earlier attempts and their engine snapshots;
- start a fresh budget epoch and fresh worker/reviewer processes while retaining
  their logical transcript history;
- leave the lane revision and authored checkpoint engine unchanged;
- return the task to its prior terminal state after the rerun passes;
- persist enough rerun state for crash-safe validation and resume.

An isolated rerun does not automatically replay downstream checkpoints.

### F059-R13: View-aware opening and board persistence

The app title bar MUST expose Vibe Lanes with the `flowchart` symbol and route the
action according to the active view:

- primary board view -> open a Vibe Lanes spotlight; the spotlight MUST expose a
  pin action that inserts one persistent Vibe Lanes tile into the primary board
  and dismisses the spotlight;
- detailed view -> activate an existing Vibe Lanes content tab or open one;
- detached board window -> insert a persistent Vibe Lanes tile directly into
  that detached surface.

A surface MUST contain at most one Vibe Lanes tile. Detached title-bar insertion
MUST disable when the surface is full or already contains the tile. Persistent
tiles MUST survive layout restoration, participate in carousel navigation, and
support existing board transfer/detach behavior.

### F059-R14: Managed transcript lifetime

Worker and reviewer transcripts MUST remain openable after their engine-owned ACP
process disconnects or the task reaches a terminal state. Replacing a process for an
authored engine change MUST preserve the existing visible timeline and persistence
context. A terminal transcript restored after app or view recreation MUST render as
ended and MUST NOT show a waiting-for-session spinner. Process lifetime MUST NOT be
treated as transcript lifetime.

### F059-R15: Typed lane data boundary

Lane variables MUST carry typed inter-step data only. They MUST NOT alter the task
`projectPath`, agent, model, mode, reasoning level, or trust mode. Those execution
choices remain immutable task context or versioned Vibe/checkpoint authoring data.

### F059-R16: Authored multi-checkpoint loop groups

A lane MAY define bounded loop groups over two or more contiguous checkpoints.
Groups MUST be uniquely named, ordered, non-overlapping, and composed of ordinary
checkpoints that retain their authored Vibes, engines, skills, bounds, and records.
After the final member passes, the engine MUST evaluate the authored exit condition
against declared carry-forward outputs. A true condition advances beyond the group;
a false condition begins the next visit until `maxIterations` is reached.

Exhaustion MUST follow the authored `stop`, `escalate`, or `advance` behavior.
Escalation pauses as Needs you and allows an explicit advance-or-stop decision.
Every checkpoint run, input request, rerun, handoff, and active cursor MUST carry its
visit identity. Restart/resume MUST route a passed visit without invoking its worker
or reviewer again. Loop routing MUST NOT change the task directory or any member's
authored engine configuration.

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

### F059-S12: Checkpoint inherits ACP defaults

- **Given** a checkpoint leaves its engine unset
- **When** its first attempt starts
- **Then** the engine uses the app-wide ACP agent/model/reasoning defaults, uses
  Full Trust and the selected agent's default mode, and records the actual
  session values.

### F059-S13: Explicit agent exposes its own models

- **Given** a checkpoint selects an installed protocol agent such as Kiro
- **When** the lane editor loads that agent's engine options
- **Then** the model and mode pickers contain the capabilities discovered from a
  temporary ACP session, matching regular ACP behavior.

### F059-S14: One step reruns with a different engine

- **Given** a Done or Stopped task has an attempted checkpoint
- **When** the user reruns that checkpoint with a different engine
- **Then** a fresh attempt and budget epoch use the override, earlier history is
  preserved, the lane is unchanged, and the task returns to its prior terminal
  state after PASS.

### F059-S15: Title-bar action respects the active surface

- **Given** Vibe Lanes is opened from the title bar
- **When** the active view is board, detailed, or a detached board
- **Then** it respectively opens a pinnable spotlight, activates/opens a detail
  tab, or directly inserts one tile into the originating detached surface.

### F059-S16: Carry-forward cannot change execution context

- **Given** a checkpoint emits data named `workdir`, `agent`, or `model`
- **When** a later checkpoint runs
- **Then** those values are injected only as ordinary typed context, while every
  agent invocation uses the task's original `projectPath` and authored engine.

### F059-S17: Terminal transcript reopens as history

- **Given** a worker or reviewer transcript belongs to a terminal task and its
  in-memory ACP store has been released
- **When** the user reopens that transcript
- **Then** its persisted timeline is restored as ended, with no reconnect action
  or waiting-for-session spinner.

### F059-S18: Two checkpoints repeat as one bounded group

- **Given** an authored loop group `Implement -> Verify` with `maxIterations: 3`
  and an exit condition `tests_passed == true`
- **When** the first Verify visit emits `tests_passed: false`
- **Then** the task returns to Implement at visit 2, preserves visit 1 history and
  handoffs, and uses each checkpoint's authored engine in the immutable task directory.

### F059-S19: An exhausted loop escalates

- **Given** a loop group reaches its final allowed visit with a false exit condition
  and `onExhausted: escalate`
- **When** the final member passes
- **Then** the task becomes Needs you without changing that passed run, and the user
  may explicitly advance beyond the group or stop the task.

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
- Authored loop groups repeat only their contiguous members, retain every visit's
  run and handoff lineage, enforce `maxIterations`, and apply stop/escalate/advance
  without rebinding directory or engine settings.
- The transition into Needs you fires a notification exactly once per request.
- The dashboard sorts **Needs you** tasks first and task detail renders the open
  request with an answer flow.
- Focused engine/manager tests cover persistence and restart behavior for
  `needsInput` tasks.
- Checkpoint engine tests cover default resolution, explicit-agent model
  semantics, unavailable model/mode failure, active/attempt snapshots, and
  isolated rerun history.
- Agent-scoped option discovery populates protocol-agent models and modes without
  requiring an existing visible chat session.
- Board/detailed routing matches F059-R13; pinning inserts a Codable Vibe Lanes
  tile, and duplicate/capacity checks are surface-scoped.
- No code path reads worker free-form text to decide verification, and none lets
  the worker edit verification or reviewer verdict.

## Out of Scope

- Human approval gates on every advance. Human verification exists only as a
  per-checkpoint authored choice (`humanReview`); agent-verified checkpoints
  advance without approval.
- Strategy ladders or multiple fallback strategies inside a checkpoint. Bounds
  produce either stop or one bounded steer path.
- Trigger authoring. F059 tasks start manually; F061 Schedules create the same
  ordinary task type on a recurring cadence.
- No-progress detection beyond max attempts and time.
- Per-task workspace isolation. Reserved via `workspaceRef`, but not required for
  this feature.

## Open Questions

- Default starter lane wording for project-type-agnostic verification.
- Whether reviewer read-only behavior should become a technical ACP trust mode
  instead of prompt guidance.

## Change History

- 2026-07-24 — Defined the explanatory model as Vibe (Loop), Vibe Lane
  (Spiral), and Schedule while preserving concise operational labels.
- 2026-07-16 — Fixed all Vibe Lane execution to Full Trust and removed the
  checkpoint Standard/app-default trust control.
- 2026-07-15 — Added per-checkpoint ACP engines (agent, model, mode,
  reasoning), session-reported attempt history, terminal-task step reruns, and
  agent-scoped option discovery. Added the `flowchart` title-bar action with
  board spotlight/pin, detailed-tab activation, and detached-surface insertion.
- 2026-07-12 — Agent CLI surface: `lane.*` / `lane.task.*` commands give R10's
  create/stop/answer/delete task and create/update/delete lane controls a
  second caller through the same task manager (see
  `specs/features/platform/agent-cli/commands-lanes.md`).

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
