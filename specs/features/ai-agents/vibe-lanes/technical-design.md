# Vibe Lanes — Technical Design

Status: draft · Feature: F059

This document is the implementation-facing contract. `schema-design.md` is an
expanded schema appendix; if there is a conflict, this `technical-design.md` and
`spec.md` win.

## Overview

Vibe Lanes is split into a UI component and an execution component.

- The UI creates lanes/tasks, renders task state, and answers Supply/Steer input
  requests.
- The execution component owns task state, schedules runnable tasks, drives worker
  and reviewer ACP sessions, enforces checkpoint bounds, and persists every
  transition.

The canonical task states are:

```text
running | needsInput | stopped | done
```

## Architecture

```text
VibeLaneSurfaceView
  -> VibeLaneTaskManager
       -> VibeLaneEngine
            -> VibeLaneWorkRunning
            -> VibeLaneReviewing
       -> VibeLaneStoring
       -> VibeLaneNotifying
```

Responsibilities:

- **Views** render only published manager state and call manager commands.
- **Task manager** is the public command/observation boundary. It owns published
  `[Task]`, lane definitions, scheduling, persistence, and run generation guards.
  Its single task-write chokepoint detects the transition into `needsInput` and
  fires the notifier exactly once per open request.
- **Engine** runs one task through one lane revision. It emits full task snapshots
  on every transition, and persists each passed checkpoint's handoff to
  `<handoffRoot>/<taskID>/<checkpointKey>.md` (deleted with the task).
- **Store** persists lanes, retained lane revisions, and tasks.
- **Worker runner** performs checkpoint Work.
- **Reviewer runner** checks outcomes against Verification.
- **Notifier** surfaces Needs-you moments as user notifications (no-op in tests).

## Data Flow

### Create Task

1. UI calls `createTask(laneID, title, projectPath, agentID?)`. The New Task
   screen defaults the project to the focused one but lets the user pick any
   directory, and defaults the agent to the app-wide ACP default but lets the
   user pick any installed ACP agent for this task.
2. Manager resolves the current lane and first checkpoint.
3. Task is created as `running`, pins `laneVersion`, stores the optional agent
   override, captures optional repo baseline, persists, and schedules.
4. Engine begins at `currentCheckpointKey`; every worker turn and reviewer
   request carries the task's `agentID` (nil = default at send time).

### Run Checkpoint

1. Engine resolves required inputs. Fatal misses take precedence over Supply.
2. Missing non-user input stops the task: `missingInput` when an earlier
   checkpoint declared the key in `produces`, `misAuthoredLane` otherwise.
3. Missing ask-user input creates `InputRequest(kind: supply)` and transitions to
   `needsInput`.
4. Worker receives task input, checkpoint Work, the previous step's handoff
   inline, the file paths of ALL earlier passed checkpoints' handoffs (read on
   demand), and resolved carry-forward inputs.
5. Reviewer checks outcome against Verification.
6. FAIL records attempt and feedback, then retries while bounds remain. Bounds
   are checked before each new attempt and before verification; a completed PASS
   stands even if the time bound elapsed while verifying.
7. PASS records the handoff, persists it to
   `<handoffRoot>/<taskID>/<checkpointKey>.md`, parses declared outputs into
   carry-forward (from the handoff, falling back to the verified work turn;
   never deleting existing values), and advances.

### Exhausted Bounds

1. Engine detects attempt or time exhaustion.
2. If `bounds.onExhausted == stop`, task becomes `stopped`.
3. If `bounds.onExhausted == escalate` and `steerCount < lane.steerLimit`, task
   becomes `needsInput` with `InputRequest(kind: steer)`.
4. If steer limit is reached, task becomes `stopped` with `steerLimitReached` or
   the exhausted-bound reason plus steer-limit detail.

### Answer Input

1. UI calls `answerInput(taskID, requestID, answer)`.
2. Manager validates the task is `needsInput` and request IDs match.
3. Supply writes values to `carryForward`.
4. Steer appends guidance as feedback context, increments `steerCount`, resets the
   current checkpoint budget epoch/window.
5. Request is cleared, task becomes `running`, persists, and schedules.

## API / Command Contracts

```text
createTask(laneID, title, projectPath) -> Task?
stopTask(taskID)
answerInput(taskID, requestID, answer) -> Task?
deleteTask(taskID)

createLane(name) -> Lane
updateLane(lane) -> Lane
deleteLane(laneID)
```

Answers:

```text
SupplyAnswer { values: [String:String] }
SteerAnswer  { guidance: String }
```

There is no canonical blind `resumeTask`. `needsInput` resumes through
`answerInput`. A stopped exhausted task should not simply flip back to running
without changing budget/history semantics.

## State Management

`Task` includes:

- identity/project/title/lane pin;
- `state`;
- `currentCheckpointKey`;
- ACP worker/reviewer session refs;
- activity and last verification;
- `carryForward`;
- `openInputRequest`;
- `steerCount`;
- checkpoint run history.

`CheckpointRun` includes attempt history and budget epoch/window fields so Steer
can reset future budget without erasing history.

Scheduler rules:

- start only `running` tasks;
- never schedule `needsInput`, `stopped`, or `done`;
- enforce global concurrency cap;
- serialize tasks per project path until workspace isolation exists;
- use run generation tokens so late engine writes cannot resurrect deleted or
  stopped tasks.

## Persistence

Persist after every transition:

- state changes;
- activity updates;
- attempts and verification results;
- carry-forward updates;
- open input request creation/answer;
- steer count changes;
- terminal states.

Lane edits bump `version`. A task resolves the exact `laneVersion` it pinned. The
store retains pinned revisions while referenced by any task.

Replay validation rejects tasks with:

- missing lane revision;
- invalid current checkpoint;
- checkpoint runs for unknown keys;
- `needsInput` without exactly one request;
- non-Needs states with an open request;
- impossible steer count/history.

## Dependencies

- SwiftUI/AppKit for UI.
- ACP sessions for worker and reviewer.
- App persistence store for lanes/tasks/revisions.
- Optional Git baseline/diff evidence for reviewer context.

## Platform Considerations

- UI and manager types are `@MainActor`.
- Runners must not block the main actor while waiting for ACP work.
- User-facing strings go through `AppStrings`.
- Reviewer read-only behavior is currently prompt/policy enforced unless ACP adds
  a technical read-only trust mode.

## Performance Constraints

- Cap concurrent running tasks globally.
- Serialize per project path while workspaces are shared.
- Cap activity log and reviewer evidence stored on task.
- Persist compact state snapshots; do not store unbounded chat transcripts in the
  task model.

## Migration / Rollout Notes

- Legacy `running/stopped/done` tasks can load with `openInputRequest = nil` and
  `steerCount = 0`.
- Legacy `requires: [String]` maps to `InputRequirement(askUser: false)`.
- Legacy `produces: [String]` maps to `OutputDeclaration`.
- Legacy stopped missing-input tasks should remain stopped unless their pinned
  lane revision can unambiguously mark the missing key ask-user.
- Starter lanes reconcile on bootstrap (`reconcileStarterLanes`): first run
  seeds the catalog with content fingerprints; later runs refresh pristine
  starters in place (version-bumped, so revisions pinned by tasks stay
  distinct), add new starters, and honor deletion tombstones. Legacy seeds
  without fingerprints count as pristine while still at version 1, since every
  user save bumps the version and clears the fingerprint. Pinned tasks are
  unaffected: task creation archives the exact lane revision it runs against.
