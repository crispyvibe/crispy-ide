# Vibe Lanes — Technical Design

Status: draft · Feature: F059

This document is the implementation-facing contract. `schema-design.md` is an
expanded schema appendix; if there is a conflict, this `technical-design.md` and
`spec.md` win.

## Overview

Vibe Lanes is split into a UI component and an execution component. In product
language, each Vibe is a bounded **Loop** and each Vibe Lane is a forward-moving
**Spiral**. These terms describe behavior; persisted `VibeLoop*` identifiers
belong to F061 Schedules and remain unchanged for compatibility.

- The UI creates lanes/tasks, authors checkpoint engines, renders task state,
  answers Supply/Steer/Review requests, and can rerun a terminal task's attempted
  checkpoint with an engine override.
- The execution component owns task state, schedules runnable tasks, drives worker
  and reviewer sessions, applies checkpoint engine settings, enforces checkpoint
  bounds, and persists every transition.

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
       -> AutomationDatabaseStore
       -> VibeLaneNotifying
       -> ACPAgentEngineOptionCatalog

ContentView title-bar action
  -> ContentSurfacePolicy
       -> TerminalSpotlightCoordinator
       -> ContentViewerStore
       -> VibeSpaceTerminalBoardStore
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
- **Automation database store** persists Vibes, Lane revisions and ordered Vibe
  pins, tasks, linked Skill references, and handoff metadata in encrypted
  libSQL transactions.
- **Skill store** installs bundled packages, owns personal packages, tracks
  linked package entrypoints, scans resources, and computes authoring readiness.
- **Worker runner** performs checkpoint Work with only the Vibe's Work skills.
- **Reviewer runner** checks outcomes against Verification with only the Vibe's
  Review skills.
- **Engine option catalog** supplies direct-integration options statically and
  caches model/mode capabilities discovered from protocol-agent sessions.
- **Notifier** surfaces Needs-you moments as user notifications (no-op in tests).
- **Content surface policy** routes title-bar opens to a board spotlight or
  detailed tab; detached windows insert into their own board surface directly.

## Data Flow

### Create Task

1. UI calls `createTask(laneID, title, projectPath)`. The New Task screen defaults
   the project to the focused one but lets the user pick any directory. It shows
   the pinned lane's per-checkpoint engine summaries read-only.
2. Manager resolves the current lane and first checkpoint.
3. Task is created as `running`, pins `laneVersion`, captures optional repo
   baseline, persists, and schedules. `agentID` remains only as a legacy
   task-wide override for old data/API callers.
4. Engine begins at `currentCheckpointKey`; each turn carries the pinned
   checkpoint's engine configuration.

### Discover and Resolve a Checkpoint Engine

1. The lane editor resolves the effective agent from the checkpoint override or
   app-wide ACP default.
2. `ACPAgentEngineOptionCatalog` returns static models/modes for direct Codex or
   Claude Code integrations. For a protocol agent, it opens one non-auto-approved
   headless probe session on demand and caches the session's models and modes.
   Regular ACP sessions also publish discovered options into the same catalog.
3. At attempt start, `VibeLaneEngineConfiguration.resolvingDefaults()` resolves
   agent and reasoning from app preferences. It resolves the app model only when
   the agent is also inherited; an explicitly authored agent with no model keeps
   model nil so that agent chooses its own default. Mode nil always means agent
   default.
4. `VibeLaneACPAgentRunner` connects the installed agent through its direct or
   ACP transport with `VibeLaneEngineConfiguration.enforcedTrustMode`
   (`fullTrust`), validates any explicit model/mode against session capabilities,
   applies it, and verifies the session reports the requested value. The app-wide
   ACP trust preference is intentionally ignored for lane execution.
5. The runner returns a `VibeLaneEngineSnapshot` from the live session. Failure
   to find or apply an explicit option is an execution error, not a fallback.

### Resolve Skills

`VibeLaneSkillStore` treats each skill as a package rooted at `SKILL.md`.
Bundled and personal packages live under the managed skill root. Linked packages
remain at their selected locations, with entrypoint paths retained in the
Automation database. Collection import recursively discovers up to 200
entrypoints while skipping build, dependency, and VCS directories.

Portable `SKILL.md` front matter supplies `name` and `description`, including
literal and folded multiline descriptions. Optional `crispy.skill.json` stores
Crispy-specific category, Work/Review roles, unattended/interactive mode, and
required commands. The store scans up to 500 package resources, classifies
references, scripts, assets, and agent metadata, and reports empty instructions,
missing local Markdown references, missing required commands, and scan limits.
Unavailable packages cannot be newly assigned in the Vibe editor; interactive
packages cannot be Review skills. Duplicating a package copies its full
directory, not only `SKILL.md`.

At execution, the engine resolves bare skill names under the managed root;
explicit relative, home-relative, and absolute paths are preserved. Before the
first attempt it verifies that all Work skills and agent-run Review skills still
resolve to a `SKILL.md`; a missing package stops the checkpoint. It injects only
path references, never skill contents. Work references go only to the worker.
Review references go only to the independent reviewer with instructions to use
them for verification.

### Run Checkpoint

1. Engine chooses the pinned checkpoint engine, or the attempt-local rerun
   override when one exists.
2. Engine resolves required inputs. Fatal misses take precedence over Supply.
3. Missing non-user input stops the task: `missingInput` when an earlier
   checkpoint declared the key in `produces`, `misAuthoredLane` otherwise.
4. Missing ask-user input creates `InputRequest(kind: supply)` and transitions to
   `needsInput`.
5. Worker receives task input, checkpoint Work, the previous step's handoff
   inline, the file paths of ALL earlier passed checkpoints' handoffs (read on
   demand), and resolved carry-forward inputs.
6. Reviewer checks outcome against Verification using the same checkpoint
   engine. Human-review checkpoints persist the worker's active engine while
   waiting for a verdict.
7. FAIL records attempt, immutable engine snapshot, and feedback, then retries
   while bounds remain. Bounds are checked before each new attempt and before
   verification. The task manager also monitors active checkpoint deadlines
   independently of ACP because a `session/prompt` request may never return. It
   invalidates the run generation, disconnects worker/reviewer sessions, and
   applies the authored Stop or Escalate behavior when a deadline expires. A
   completed PASS stands if it is persisted before the monitor observes expiry.
8. PASS records the handoff, persists it to
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
5. Review stores an approve/reject verdict for the completed work turn. Approval
   continues the shared PASS path; rejection requires feedback and records a
   failed attempt without rerunning the original work turn.
6. Request is cleared, task becomes `running`, persists, and schedules.

### Rerun a Step

1. Task detail offers rerun only for a Done or Stopped task and a checkpoint with
   attempt history.
2. UI starts from the checkpoint's pinned Vibe engine and calls
   `rerunStep(taskID, checkpointKey, engine)`.
3. Manager cancels stale work, releases worker/reviewer sessions, stores a
   `VibeLaneRerunRequest`, increments the run's budget/rerun epochs, and starts
   fresh sessions.
4. The engine executes only the selected checkpoint with the request's engine.
   Prior attempts remain intact and the new attempt records its live snapshot.
5. On PASS, handoff/carry-forward are refreshed and the task returns to its
   previous Done or Stopped state. A Done task recomputes its outcome summary.
   Downstream checkpoints are not replayed.

### Surface Presentation

- The main title-bar `flowchart` button posts `.toggleVibeLanes`.
- In board mode, `ContentSurfacePolicy` resolves Vibe Lanes to `.spotlight`.
  `TerminalSpotlightCoordinator` presents `.vibeLanes`; its pin metadata permits
  board pinning, and `addVibeLanesTile(surfaceID:)` inserts the persistent tile
  before dismissing the spotlight.
- In detailed mode, policy resolves to `.detailTab`; the coordinator activates
  an existing `.vibeLanes` tab or opens one.
- Detached board windows use an AppKit `NSToolbarItem` and call
  `addVibeLanesTile(surfaceID:)` directly because the window owns a distinct
  surface. Validation disables the item for a full surface or duplicate tile.
- `TileContentKind.vibeLanes` is Codable and participates in board rendering,
  transfer, restoration, and spotlight carousel enumeration.

## API / Command Contracts

```text
createTask(laneID, title, projectPath) -> Task?
stopTask(taskID)
answerInput(taskID, requestID, answer) -> Task?
rerunStep(taskID, checkpointKey, engine) -> Task?
deleteTask(taskID)

createLane(name) -> Lane
updateLane(lane) -> Lane
deleteLane(laneID)
```

Answers:

```text
SupplyAnswer { values: [String:String] }
SteerAnswer  { guidance: String }
ReviewAnswer { approved: Bool, feedback: String? }
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
- checkpoint run history;
- pending human-review engine;
- optional rerun request and last-rerun checkpoint marker.

`CheckpointRun` includes attempt history, active engine, and budget/rerun
epoch fields so Steer and isolated rerun can reset future budget without erasing
history. Every `Attempt` may include the immutable engine snapshot reported by
its session.

Scheduler rules:

- start only `running` tasks;
- never schedule `needsInput`, `stopped`, or `done`;
- enforce global concurrency cap;
- serialize tasks per project path until workspace isolation exists;
- enforce active checkpoint deadlines outside the engine's ACP await so a
  non-responsive agent cannot hold a task and its project slot indefinitely;
- resolve expired persisted Running tasks before reconnecting sessions during
  bootstrap;
- use run generation tokens so late engine writes cannot resurrect deleted or
  stopped tasks or clear the in-flight slot of a replacement rerun;
- invalidate active generations and disable queue scheduling before shutdown
  cancellation so persisted Running tasks remain resumable.

## Persistence

Persist after every transition:

- state changes;
- activity updates;
- attempts and verification results;
- carry-forward updates;
- open input request creation/answer;
- steer count changes;
- active/attempt engine snapshots and rerun state;
- terminal states.

Lane edits bump `version`. A task resolves the exact `laneVersion` it pinned. The
database retains immutable revisions and enforces exact Lane and Vibe revision
relationships with foreign keys. Manager state is published only after the
corresponding transaction commits.

Skill package files and handoff Markdown remain on disk. The database stores
linked Skill references plus handoff path/digest metadata. It never dual-writes
legacy JSON metadata files.

Replay validation rejects tasks with:

- missing lane revision;
- invalid current checkpoint;
- checkpoint runs for unknown keys;
- `needsInput` without exactly one request;
- non-Needs states with an open request;
- impossible steer count/history after excluding rerun budget epochs;
- invalid rerun target or prior terminal state.

## Dependencies

- SwiftUI/AppKit for UI.
- ACP sessions for worker and reviewer.
- Encrypted libSQL Automation store for metadata and revision relationships.
- Optional Git baseline/diff evidence for reviewer context.

## Platform Considerations

- UI and manager types are `@MainActor`.
- Runners must not block the main actor while waiting for ACP work.
- User-facing strings go through `AppStrings`.
- Reviewer read-only behavior is currently prompt/policy enforced unless ACP adds
  a technical read-only trust mode.
- Direct-integration process settings are immutable, so a changed checkpoint
  engine replaces the headless session instead of reusing it.

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
- Legacy checkpoints without `engine` decode as all-default configuration.
- Legacy authored `trustMode` keys are ignored. Attempt snapshots retain their
  recorded trust mode.
- Legacy attempts/runs without engine or rerun fields decode with nil snapshots
  and zero rerun epochs.
- Legacy task-wide `agentID` remains a fallback only when the checkpoint has no
  authored agent.
- Existing JSON metadata is imported once in one database transaction. Source
  files move to a timestamped `Automation Legacy Backup` only after that
  transaction succeeds; startup is idempotent if migration is retried.
- Legacy stopped missing-input tasks should remain stopped unless their pinned
  lane revision can unambiguously mark the missing key ask-user.
- Starter lanes reconcile on bootstrap (`reconcileStarterLanes`): first run
  seeds the catalog with content fingerprints; later runs refresh pristine
  starters in place (version-bumped, so revisions pinned by tasks stay
  distinct), add new starters, and honor deletion tombstones. Legacy seeds
  without fingerprints count as pristine while still at version 1, since every
  user save bumps the version and clears the fingerprint. Pinned tasks are
  unaffected: task creation must reference an exact Lane revision already
  constrained by the database.
