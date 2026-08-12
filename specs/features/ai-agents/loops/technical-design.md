# Schedules — Technical Design

## Overview

F061 adds an application-owned scheduler around F059. `VibeLoopManager` owns
definitions, claims, and history; `VibeLoopScheduler` decides when to
reconcile; `VibeLaneTaskManager` remains the only executor.

The product calls the timed entity a **Schedule** and labels the recipe surface
**Vibe Lanes**. Explanatory surfaces describe each bounded Vibe as a **Loop**
and the accumulating lane as a **Spiral**. Existing `VibeLoop*` Swift types,
JSON migration paths, and `automation_loops` tables retain their names as
compatibility identifiers.

## Architecture

```text
 AppShellStore.ActiveSurface.automation
                  |
        AutomationSurfaceView
          /       |       \
      Schedules      Vibe Lanes      Vibes
        |          \       /
VibeLoopManager  VibeLaneTaskManager ----> lane engine / ACP runners
        \                 /
         AutomationDatabaseStore
          encrypted libSQL
        |
VibeLoopScheduler
```

`AppContainer` creates and bootstraps the lane manager first, then the Schedule
store, manager, and scheduler. Both manager and scheduler are retained for the
application lifetime. No feature singleton or VibeSpace-scoped service is
introduced.

## Data Flow

1. The editor validates a local folder, instruction, lane snapshot, recurrence,
   and selected **Save Paused** or **Review & Enable** outcome. Enabling confirms
   Full Trust before calling `VibeLoopManager.save`.
2. A save commits definitions, runtime state, and history in one database
   transaction, then publishes the new values and asks the scheduler to
   recompute its earliest wake.
3. Reconciliation asks `VibeLoopScheduleCalculator` for the latest due
   occurrence after the persisted claim baseline. Scheduler wakes and catch-up
   events are distinct from configuration changes so Skip missed runs does not
   suppress a normal live run or classify an edit as catch-up.
4. The manager atomically persists a pending run and schedule claim before task
   creation. A failed claim stops the flow.
5. It rejects active overlap or invalid configuration; otherwise it calls
   `VibeLaneTaskManager.createTask(laneSnapshot:origin:)`.
6. The lane manager saves the task against an existing exact Lane revision
   before publishing or running it. The database foreign key rejects a missing
   revision. The task origin stores Schedule ID, deterministic occurrence ID, and
   scheduled date. The run record is linked to the created task.
7. On bootstrap, pending run records search task origins and recover links
   without relaunching work.
8. `VibeLoopManager` observes the lane manager's published task values. Every
   linked task transition updates the Schedule's live projection and persists
   `taskState` plus `taskStopReason` on the matching occurrence record.

## API / Command Contracts

### `VibeLoopManager`

- `bootstrap()` loads state and recovers pending occurrences.
- `save(_:)`, `delete(id:stopActiveRun:)`, and
  `setEnabled(_:id:confirmsFullTrust:)` mutate authored state and return whether
  the durable commit succeeded.
- `reconcileDueLoops(at:reason:)` claims and dispatches latest due occurrences.
- `runNow(id:)` creates a UUID-backed manual occurrence without changing the
  schedule claim.
- `status(for:)`, `nextRunDate(for:)`, and `runs(for:)` are UI projections.

### `VibeLaneTaskManager`

The exact-snapshot overload requires the pinned Lane revision to exist and the
task transaction to succeed before publishing or executing the task. Creation
is idempotent when the origin contains an occurrence ID. Legacy decoded tasks
default their missing origin to `.manual`.

No Schedule CLI is part of F061.

## State Management

`VibeLoopDefinition` stores authored state and an immutable
`VibeLaneDefinition`. `VibeLoopRuntimeState` stores the last claimed scheduled
date, latest task link, and failure. `VibeLoopRunRecord` stores one scheduled or
manual occurrence, its linked task ID, and the latest reconciled lane task state
and stop reason.

The UI projection is the product of two independent axes:

| Schedule | Execution | Display status |
|---|---|---|
| enabled | idle | Scheduled |
| paused | idle | Paused |
| blocked | idle | Blocked |
| any | queued | Queued |
| any | running | Running |
| any | needs input | Needs you |

`stopRun(pauseLoop: true)` persists the paused definition and reschedules the
wake task before stopping the linked lane task. Main-actor isolation makes that
transition atomic relative to scheduler callbacks. Stopping only the task keeps
the schedule enabled, so the next occurrence may start normally.

The task publisher's emitted value is indexed inside `VibeLoopManager` before
the UI is notified. This avoids forwarding `objectWillChange` too early and
rendering the previous lane state. Run-record reconciliation also occurs during
bootstrap, so records written before lifecycle fields existed are backfilled
from their linked task. The Vibe Lane task remains the canonical detailed
execution record.

Pending records recover only while their definition is enabled. A paused
pending record remains durable and is retried after explicit enablement.
Successfully saving a valid definition clears a prior configuration failure.

`commitState` constructs a complete `VibeLoopPersistedState`, commits it through
`AutomationDatabaseStore`, and only then replaces the manager's published
definitions, runtime states, and run records. Database and decode errors
propagate to the manager, which fails closed and exposes a persistence error to
the surface. History compaction retains the newest 200 records per Schedule.

Deleting a Schedule removes its definition, runtime state, and history in one
commit. If an active task exists, the UI requires either **Stop Run and Delete**
or **Keep Run and Delete Schedule**; already-created task records remain in
Vibe Lanes.

## Scheduling

Intervals advance from a fixed anchor. Daily and weekly schedules use a
Gregorian `Calendar` configured with the stored IANA time zone,
`matchingPolicy: .nextTime`, and `repeatedTimePolicy: .first`.

The claim baseline is the later of `createdAt` and
`lastClaimedScheduledAt`. A due occurrence must be strictly later than that
baseline, preventing replay after clock rollback. The scheduler owns one sleep
task and caps an individual sleep at seven days so long schedules are
periodically recalculated.

Scheduled wakes carry their expected occurrence into reconciliation. A matching
wake within 60 seconds is treated as live scheduled work; schedule edits use
configuration-change semantics; launch, activation, wake, clock-change, and
later callbacks use catch-up semantics. Therefore Skip missed runs advances
missed work but does not disable the Schedule's normal cadence or skip a due run
while its configuration is being updated.

The lane manager associates completion with a per-task generation. A stale
completion cannot clear a replacement run's in-flight slot. Shutdown increments
all active generations before cancellation, disables further scheduling, and
leaves persisted Running tasks resumable on the next launch.

Checkpoint deadlines are enforced by the lane manager independently of ACP
prompt completion. If an agent request stops responding, deadline expiry
invalidates the task generation, disconnects its sessions, persists the
checkpoint's authored Stop or Escalate outcome, and publishes that transition
back to the Schedule. Bootstrap resolves already-expired Running tasks before
attempting ACP resume, so a stale persisted task cannot keep future occurrences
in `skippedActiveRun`.

## Navigation and UI

`AppShellStore.ActiveSurface.automation` participates in the existing
single-active-surface routing. The application rail groups Automation with Home
and never disables it based on project state. Existing
`showsVibeSpaceSidebar` logic hides the project split pane whenever Automation
is active.

`AutomationSurfaceView` keeps Schedules, Vibe Lanes, and Vibes mounted
behind a shared tab bar. This preserves Schedule editor state while the user
opens Lane or Vibe authoring. The Lane and Vibe tabs reuse
`VibeLaneSurfaceView` and its central navigation model; no definitions or
editors are duplicated.

The Schedules tab routes internally between dashboard, editor, Schedule detail, and the
existing `VibeLaneTaskDetailView`. The empty dashboard presents one creation
action without inactive table chrome. The editor keeps time zone and missed-run
policy under Advanced, keeps validation feedback in its fixed footer, and
separates saving paused from reviewing Full Trust and enabling. Run, enable,
update, delete, and stop failures remain on screen. Updating a frozen lane shows
the old and new versions plus the new stage route before confirmation.

Known VibeSpace projects are suggestions only; `NSOpenPanel` supports arbitrary
local folders.

## Dependencies

- Foundation `Calendar`, `TimeZone`, `CryptoKit`, Codable, and file APIs.
- SwiftUI and AppKit (`NSOpenPanel`, wake notifications).
- F059 Vibe Lane model, task manager, and task detail view.

No third-party scheduling dependency is added.

## Platform Considerations

F061 targets macOS 26+. `NSWorkspace.didWakeNotification`,
`NSSystemTimeZoneDidChange`, and `NSSystemClockDidChange` trigger
reconciliation. Application activation is handled by `AppDelegate`.

## Performance Constraints

- One scheduler sleep task for all Schedules.
- O(number of Schedules) reconciliation and next-wake calculation.
- O(number of linked task records) lifecycle reconciliation on lane task
  publication.
- At most 200 run records retained per Schedule.
- Existing Vibe Lane global and per-project concurrency limits remain in force.

## Migration / Rollout Notes

Installations with legacy `state.json`, `definitions.json`, `runtime.json`, or
`runs.json` import them into the encrypted Automation database in the same
transaction as legacy Vibe, Lane, task, Skill-reference, and handoff metadata.
After commit, source JSON moves to a timestamped backup. The migration marker
makes retries idempotent; malformed input fails closed and remains in place.

Existing Vibe Lane tasks remain compatible because absent origin data decodes
as `.manual`. Legacy Loop run records decode missing `taskState` and
`taskStopReason` as nil and are backfilled from linked tasks on bootstrap.
Removing F061 data does not alter lane definitions or tasks.
