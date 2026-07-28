# Schedules — Spec

Status: implemented

Feature: F061

## Overview

Schedules run recurring Vibe Lane tasks against local project directories.
It is the default tab in the application-level **Automation** destination,
alongside **Vibe Lanes** and **Vibes**. Automation remains available with no
open VibeSpace, and due work executes through the app-owned Vibe Lane task
manager.

Scheduling operates while Crispy is open. Launch, wake, activation, clock changes, and
time-zone changes reconcile missed occurrences. F061 does not install a
LaunchAgent or promise exact execution while Crispy is quit.

Schedules are the time-based layer of the Automation model:

```text
Vibe (Loop) -> Vibe Lane (Spiral) -> Schedule
```

A Schedule does not contain the retry loop. Each Vibe owns its bounded retry
behavior, while the frozen Vibe Lane carries verified context forward through
its ordered Vibes. The Schedule only decides when a new task starts.

## Dependencies

- F014 (Navigation) — global application surface and side-menu destination.
- F011 (ACP) — headless agent sessions.
- F047 (External Agent Sessions) — app-owned session execution.
- F059 (Vibe Lanes) — lane definitions, task execution, task detail, and
  checkpoint state.

## Requirements

### F061-R01: Global Automation surface

Automation MUST be an always-enabled application side-menu destination. It MUST
open as a full-width `AppShellStore` surface before Home/VibeSpace resolution
and MUST NOT depend on an active VibeSpace, project sidebar, board, or
spotlight. It MUST expose persistent **Schedules**, **Vibe Lanes**, and
**Vibes** tabs, with Schedules selected by default.

### F061-R02: Schedule definition

The user MUST be able to create, edit, delete, enable, and pause a Schedule. A Schedule
MUST contain a name, local project directory, task instruction, Vibe Lane
snapshot, recurrence, missed-run policy, and enabled state. The editor MUST
offer explicit **Save Paused** and **Review & Enable** outcomes. Deleting a Schedule
with active work MUST let the user either stop the run or keep it running while
only the schedule is deleted. Lane and Vibe authoring MUST be reachable from the
Schedule editor without discarding the in-progress Schedule draft.

### F061-R03: Supported recurrence

F061 MUST support anchored intervals, daily local times, and one-or-more-day
weekly local times. Intervals MUST be at least 15 minutes. Calendar schedules
MUST store an IANA time-zone identifier, advance through nonexistent local
times, and fire only once during repeated local times.

### F061-R04: One execution path

A due or manually triggered Schedule MUST create a normal `VibeLaneTask` through
`VibeLaneTaskManager`. Schedules MUST NOT duplicate the lane engine. The task MUST
use the Schedule's project path, task instruction, and immutable lane snapshot. Its
lane revision and task record MUST be durable before the task is published or
execution starts.

### F061-R05: Missed occurrences

The default policy MUST run only the latest missed occurrence after Crispy
returns. The optional skip policy MUST claim the latest missed occurrence
without creating a task. A normal scheduler wake MUST still run when the skip
policy is selected. F061 MUST NOT replay every missed interval.

### F061-R06: Overlap and idempotency

Only one non-terminal task MAY exist per Schedule. A due occurrence MUST be skipped
when the previous task is Running or Needs you. Scheduled occurrence IDs MUST
be deterministic, and task origins MUST let crash recovery link an existing
task rather than create a duplicate.

### F061-R07: Frozen lane revisions

Saving a Schedule MUST retain an immutable Vibe Lane snapshot. Later Vibe Lane edits
MUST NOT change future runs until the user explicitly chooses **Update Vibe
Lane**. The surface MUST indicate when a newer source Vibe Lane version exists.

### F061-R08: Status and history

The surface MUST show Scheduled, Queued, Running, Needs you, Paused, and Blocked
states, plus next run, last run, and bounded run history. Queued MUST distinguish
a task waiting for Vibe Lane capacity from one that is executing. A linked run
MUST open the existing Vibe Lane task detail. Linked lane task transitions MUST
update the Schedule immediately and persist the task state and stop reason in run
history. Bootstrap MUST backfill those fields for legacy linked run records.
Schedule state and execution state MUST remain independent: pausing prevents
future occurrences but does not misreport or implicitly stop an active task.
Filters MUST evaluate both axes so an active paused Schedule remains discoverable
under both Active and Paused.

### F061-R09: Unattended trust

Enabling any Schedule MUST require explicit Full Trust confirmation because every
Vibe Lane checkpoint executes with Full Trust. Quick enable controls MUST
enforce the same rule as the editor. Updating the frozen lane revision of an
enabled Schedule MUST require confirmation that identifies the old version, new
version, and new stage route.

### F061-R10: Durable state

Definitions, runtime claims, and run records MUST persist together through one
encrypted libSQL transaction. A mutation MUST update published state only after
that transaction commits. A failed or corrupt database response MUST fail
closed and surface an actionable error rather than silently loading an empty
schedule. Legacy Loop JSON documents MUST be imported once as part of the
atomic Automation migration and archived only after commit. Run history MUST
retain at most 200 records per Schedule.

### F061-R11: Lifecycle reconciliation

The scheduler MUST start after Vibe Lanes bootstrap, keep one cancellable wake
task, and reconcile on launch, wake, application activation, system clock
change, and time-zone change. Shutdown MUST cancel the wake task before the
Vibe Lane manager shuts down. Lane shutdown MUST invalidate in-flight run
generations so cancellation completions cannot mark resumable tasks stopped or
start queued work during teardown.

## Scenarios

### Scenario F061-S01: Open Automation without a VibeSpace

**Given** no VibeSpace exists, **when** the user selects Automation, **then**
the global surface opens on Schedules and project-scoped rail destinations remain
disabled.

### Scenario F061-S02: Run a scheduled occurrence

**Given** an enabled Schedule is due, **when** reconciliation runs, **then** one
Vibe Lane task starts from the frozen snapshot and the occurrence is recorded.

### Scenario F061-S03: Catch up after sleep

**Given** several occurrences elapsed while Crispy was unavailable and the
policy is Run once, **when** Crispy returns, **then** only the latest occurrence
starts.

### Scenario F061-S04: Skip missed work

**Given** an occurrence elapsed while Crispy was unavailable and the Schedule uses
Skip missed runs, **when** catch-up reconciliation runs, **then** the occurrence
is claimed and recorded without creating a task. An on-time scheduler wake
still starts its task.

### Scenario F061-S05: Prevent overlap

**Given** a Schedule task is Running or Needs you, **when** another occurrence is
due, **then** the occurrence is recorded as skipped and no second task starts.

### Scenario F061-S06: Confirm full trust

**Given** a Schedule is paused or newly created, **when** the user enables it,
**then** Crispy explains that Vibe Lanes execute with unattended Full Trust and
requires explicit confirmation.

### Scenario F061-S07: Preserve a lane revision

**Given** a saved Schedule and a later Vibe Lane edit, **when** the Schedule runs,
**then** it uses the saved revision until Update Vibe Lane is selected.

### Scenario F061-S08: Survive rollback and recovery

**Given** an occurrence was claimed or its task was created before a crash,
**when** the clock moves backward or Crispy restarts, **then** the same
occurrence is not created twice.

### Scenario F061-S09: Run now

**Given** a valid Schedule, **when** the user selects Run Now, **then** a task
starts without moving the next scheduled occurrence.

### Scenario F061-S10: Block an unavailable target

**Given** the saved project directory no longer exists, **when** a run is due,
**then** the Schedule becomes Blocked and no task starts.

### Scenario F061-S11: Reflect linked lane lifecycle

**Given** a Schedule started a Vibe Lane task, **when** that task becomes Running,
Needs you, Done, or Stopped, **then** the Schedule status and linked history update
without reopening the surface, and the reconciled lifecycle survives restart.
Stopping only the task leaves an enabled schedule eligible for its next
occurrence; Stop and pause updates the schedule before stopping the task.

### Scenario F061-S12: Delete while work is active

**Given** a Schedule has an active full-trust task, **when** the user deletes the
Schedule, **then** Crispy requires an explicit choice to stop the run and delete or
keep the run and delete only the schedule.

### Scenario F061-S13: Fail a durable mutation

**Given** Schedule state or a new lane task cannot be written, **when** a save,
claim, or task creation is attempted, **then** no corresponding in-memory
mutation or execution starts and Crispy surfaces the failure.

### Scenario F061-S14: Author dependencies from a Schedule

**Given** a partially completed Schedule draft, **when** the user opens its Lane or
the Vibe library from the editor, **then** Automation changes to the matching
tab and returning to Schedules preserves the draft. Vibe Lane and Vibe updates
remain explicitly versioned; the Schedule keeps its frozen Vibe Lane until Update
Vibe Lane is used.

## Acceptance Criteria

- The Automation rail control is usable before any VibeSpace is created.
- Automation exposes Schedules, Vibe Lanes, and Vibes without
  duplicating their entities.
- Daily/weekly recurrence honors stored time zones and both DST transitions.
- Occurrence claims survive restarts and clock rollback without duplicate work.
- Full-trust enablement cannot be performed through an unconfirmed quick action.
- `VibeLoopTests` covers the scheduler and persistence behavior through
  F061-S13, including validation
  underlying F061-S10, legacy lifecycle backfill, file migration, and corrupt
  state rejection.
- The full `CrispyVibesUnitTests` target passes.

## Open Questions

- Exact execution while Crispy is quit requires a separately reviewed helper or
  LaunchAgent design and is outside F061.
- Remote project targets remain deferred until Vibe Lane execution has an
  application-level remote working-directory contract.

## Change History

- 2026-07-16: Implemented global navigation, scheduler, persistence, dashboard,
  editor, run history, frozen lane snapshots, and tests.
- 2026-07-16: Reconciled linked Vibe Lane lifecycle into live Schedule status and
  persistent run history.
- 2026-07-16: Separated schedule and execution state, made stop-and-pause
  atomic, and hardened wake, pending-recovery, and shutdown transitions.
- 2026-07-17: Consolidated Schedule persistence into an acknowledged atomic state
  document, added queued execution, explicit active-run deletion and lane
  update confirmations, action feedback, and the Save Paused / Review & Enable
  editor flow.
- 2026-07-20: Made Automation the global entry point for Schedules, Lanes, and
  Vibes, with draft-preserving transitions from Schedule setup into authoring.
- 2026-07-23: Renamed the user-facing scheduled entity to Schedule; legacy
  implementation and persistence identifiers remain compatible.
- 2026-07-24: Clarified the conceptual model as Vibe (Loop) and Vibe Lane
  (Spiral), while keeping primary navigation labels concise.
- 2026-07-24: Clarified that Schedule owns recurrence only; retry behavior
  belongs to Vibes and forward progress belongs to Vibe Lanes.
