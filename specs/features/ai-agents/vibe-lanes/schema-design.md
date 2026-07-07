# Vibe Lanes — Schema Design

Status: canonical draft · Feature: F059

The schema is the contract between:

- **UI component** — authors lanes, lists/opens tasks, sends commands, renders
  state, and answers input requests.
- **Execution component** — runs tasks through checkpoints, drives ACP sessions,
  enforces bounds, persists transitions, and emits state.

Everything below maps to Swift `Codable` types and a persisted JSON store.

## 1. Definition Schema

```text
Lane {
  id:             UUID
  schemaVersion:  Int
  version:        Int
  name:           String
  description:    String?
  steerLimit:     Int                 // max user Steer answers per task/lane run
  checkpoints:    [Checkpoint]        // ordered; one or more
  seededFingerprint: String?          // set when seeded from the shipped starter
                                      // catalog (hash of that content); cleared
                                      // on first user edit
}

Checkpoint {
  key:       String                   // stable identity within lane
  order:     Int
  work:      WorkDefinition
  verify:    VerificationDefinition
  bounds:    Bounds
  requires:  [InputRequirement]
  produces:  [OutputDeclaration]
}

WorkDefinition {
  goal:         String
  instructions: String
  skills:       [String]              // paths to skill folders / SKILL.md files
}

VerificationDefinition {
  definition:  String                 // plain-text "done when..." statement
  humanReview: Bool                   // true = the user verifies instead of the
                                      // reviewer agent (pauses for a Review verdict)
}

Bounds {
  maxAttempts:    Int
  timeoutSeconds: Int
  onExhausted:    stop | escalate
}

InputRequirement {
  key:      String
  askUser:  Bool
  prompt:   String?                   // optional user-facing Supply prompt
}

OutputDeclaration {
  key:         String
  description: String?
}
```

Notes:

- Stable checkpoint `key`s are identities; `order` is presentation/execution
  order only.
- `askUser` means the engine may pause for Supply if the key is absent. A
  non-ask-user missing key means the lane is mis-authored and the task stops.
- `onExhausted = escalate` means exhausted bounds create a Steer request while
  the task is under `steerLimit`.
- Additive readers should tolerate legacy `requires: [String]` and
  `produces: [String]` by interpreting those keys as `askUser = false` inputs
  and output declarations with no description.
- Starter reconciliation: on bootstrap the store merges the shipped starter
  catalog with stored lanes. Pristine starters (seed fingerprint matches
  content, or legacy `version == 1` seeds) are refreshed in place with a
  version bump; newly shipped starters are added unless tombstoned; user
  deletions of starters persist as tombstones (`lane-tombstones.json`);
  user-edited lanes (fingerprint cleared on save) are never touched. An
  explicit restore command clears tombstones and re-runs reconciliation.

## 2. Execution Schema

```text
Task {
  id:                   UUID
  projectPath:          String
  title:                String        // user's per-run input
  laneID:               UUID
  laneVersion:          Int
  agentID:              String?       // ACP agent for this task's sessions;
                                      // nil = app-wide default at send time
  state:                running | needsInput | stopped | done
  stopReason:           StopReason?
  currentCheckpointKey: String

  workerSessionRef:     String?
  workerThreadRef:      String?
  reviewerSessionRef:   String?
  reviewerThreadRef:    String?

  currentActivity:      String?
  lastVerification:     VerificationResult?
  activityLog:          [ActivityLogEntry]?

  workspaceRef:         String?       // reserved for future per-task isolation
  carryForward:         [String:String]
  outcomeSummary:       String?
  repoBaselineRef:      String?
  openInputRequest:     InputRequest?
  steerCount:           Int

  createdAt:            Date
  updatedAt:            Date
  checkpointRuns:       [CheckpointRun]
}

CheckpointRun {
  checkpointKey:       String
  status:              pending | running | needsInput | passed | stopped
  stopReason:          StopReason?
  summary:             String?
  attempts:            [Attempt]
  startedAt:           Date?
  endedAt:             Date?
  activeWindowStartedAt: Date?        // reset on Steer answer
  budgetEpoch:         Int            // increments on Steer answer
}

Attempt {
  id:         UUID
  index:      Int
  promptKind: goal | feedback | steer
  result:     VerificationResult?
  at:         Date
  budgetEpoch:Int
}

VerificationResult {
  passed:    Bool
  detail:    String?
  feedback:  String?
}

InputRequest {
  id:            UUID
  kind:          supply | steer | review
  checkpointKey: String
  createdAt:     Date
  prompt:        String
  missingKeys:   [String]             // supply only
  lastFeedback:  String?              // steer only
  reason:        StopReason?          // steer only: verificationFailed|timeout
}

ActivityLogEntry {
  id:      UUID
  at:      Date
  kind:    system | worker | verify | input | error
  message: String
  detail:  String?
}

enum StopReason {
  done
  verificationFailed
  timeout
  stoppedByUser
  error
  missingInput
  misAuthoredLane
  steerLimitReached
}
```

Notes:

- `needsInput` is non-terminal. It pauses scheduling until the request is answered
  or the task is stopped.
- Exactly one `openInputRequest` is allowed when `state == needsInput`; no open
  request is allowed for `running`, `stopped`, or `done`.
- `activeWindowStartedAt` and `budgetEpoch` let Steer reset a checkpoint's bounded
  retry window without deleting historical attempts.
- `steerCount` counts accepted Steer answers for the task. Exhausted bounds with
  `steerCount >= lane.steerLimit` stop instead of asking again.
- `missingInput` covers a required key an earlier checkpoint declared in
  `produces` but failed to emit (a runtime emission failure); `misAuthoredLane`
  is used when an absent required input was not ask-user and no prior checkpoint
  declared it. Fatal misses take precedence over Supply requests.
- Handoffs are additionally persisted as files under
  `<handoffRoot>/<taskID>/<checkpointKey>.md`; later checkpoints receive the
  paths of all earlier passed checkpoints' handoff files. Declared outputs are
  parsed from the handoff or, as fallback, the verified work turn, and never
  overwrite-to-delete an existing carry-forward value.

## 3. State Transitions

```text
created -> running

running -> running       failed attempt, bounds remain
running -> running       checkpoint passes, more checkpoints remain
running -> done          final checkpoint passes
running -> needsInput    ask-user input missing
running -> needsInput    exhausted escalate bound under steer limit
running -> stopped       exhausted stop bound
running -> stopped       exhausted escalate bound at steer limit
running -> stopped       missing non-user input, error, or user stop

needsInput -> running    Supply or Steer answered
needsInput -> stopped    user stop
```

## 4. Commands

```text
createTask(laneID, title, projectPath, agentID?) -> Task
stopTask(taskID)
answerInput(taskID, requestID, answer) -> Task
deleteTask(taskID)

createLane(name) -> Lane
updateLane(lane) -> Lane
deleteLane(laneID)
```

`answerInput` accepts:

```text
SupplyAnswer { values: [String:String] }
SteerAnswer  { guidance: String }
ReviewAnswer { approved: Bool, feedback: String? }  // feedback required on reject
```

Rules:

- Supply answers write values into `carryForward`, clear `openInputRequest`, and
  resume Running.
- Steer answers append guidance as feedback, increment `steerCount`, clear
  `openInputRequest`, reset the current checkpoint budget window, and resume
  Running.
- `stopTask` cancels running ACP work or stops a Needs you task. It releases ACP
  sessions and persists `stoppedByUser`.
- A blind `resumeTask` command is intentionally not part of the canonical
  contract. Needs you resumes through `answerInput`; exhausted Stopped tasks need
  a new task or a lane/task edit flow.

## 5. Observation and Scheduling

The manager publishes `[Task]` plus lane definitions/revisions. The UI renders the
published model and does not reach into engine internals.

The scheduler may start only tasks with `state == running` and no in-flight engine
job. It MUST ignore `needsInput`, `stopped`, and `done`.

A per-task run generation token prevents a superseded engine after stop/delete
from clobbering or resurrecting a task.

## 6. Persistence and Versioning

- Persist after every transition, including each activity change, open input
  request, answer, and terminal state.
- A task pins `laneVersion`; the store retains the exact lane revision while any
  task references it.
- Version lookup is strict. A pinned version MUST NOT silently resolve to a newer
  lane.
- Persisted tasks are validated before replay:
  - lane revision exists;
  - current checkpoint exists;
  - checkpoint runs reference existing checkpoints;
  - `needsInput` has exactly one valid request;
  - non-Needs states have no open request;
  - steer count is non-negative and not inconsistent with history.

## 7. Evolvability

- `schemaVersion` is the contract version. Additive optional fields do not require
  a bump if readers are defensive.
- Breaking changes require a bump and migration.
- Legacy `running | stopped | done` tasks can migrate without an open request.
  Legacy stopped missing-input tasks cannot be auto-converted to Supply unless the
  lane revision marks the missing key ask-user.

## 8. Superseded Decisions

The 2026-06-28 three-state model is superseded. The canonical schema includes
`needsInput`, Supply, Steer, stop-vs-escalate bounds, ask-user inputs, and
lane-level steer limit.
