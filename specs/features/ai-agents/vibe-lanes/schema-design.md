# Vibe Lanes — Schema Design

Status: canonical draft · Feature: F059

The schema is the contract between:

- **UI component** — authors lanes, lists/opens tasks, sends commands, renders
  state, and answers input requests.
- **Execution component** — runs tasks through checkpoints, drives ACP sessions,
  enforces bounds, persists transitions, and emits state.

Everything below maps to Swift `Codable` types persisted through
`AutomationDatabaseStore` in Crispy's encrypted libSQL database. JSON is a
serialization boundary for helper RPCs, CLI interchange, and one-time legacy
migration; it is not authoritative application storage.

## 1. Authoring Schema

```text
Vibe {
  id:             UUID
  version:        Int
  name:           String
  description:    String?
  category:       engineering | incidentResponse | release |
                  productLaunch | researchAndDecisions | general
  engine:         EngineConfiguration
  work:           WorkDefinition
  verify:         VerificationDefinition
  bounds:         Bounds
}

Lane {
  id:             UUID
  schemaVersion:  Int
  version:        Int
  name:           String
  description:    String?
  steerLimit:     Int                 // max user Steer answers per task/lane run
  steps:          [LaneStep]          // ordered; one or more
  seededFingerprint: String?          // set when seeded from the shipped starter
                                      // catalog (hash of that content); cleared
                                      // on first user edit
}

LaneStep {
  key:          String                // stable identity within lane
  order:        Int
  vibeID:       UUID
  vibeVersion:  Int                   // explicit immutable pin
  requires:     [InputRequirement]
  produces:     [OutputDeclaration]
}

WorkDefinition {
  goal:         String
  instructions: String
  skills:       [String]              // references to skill packages
}

EngineConfiguration {
  agentID:       String?              // nil = app-wide ACP default agent
  modelID:       String?              // nil = app default only with inherited
                                      // agent; otherwise selected-agent default
  modeID:        String?              // nil = selected-agent default
  reasoningLevel: (low | medium | high | max)? // nil = app-wide ACP default
}

VerificationDefinition {
  definition:   String                // plain-text "done when..." statement
  reviewSkills: [String]              // packages read only by the reviewer agent
  humanReview:  Bool                  // true = the user verifies instead of the
                                      // reviewer agent (pauses for a Review verdict)
}

SkillPackage {                         // filesystem entity, not lane JSON
  root:             URL
  entrypoint:       root/SKILL.md
  source:           bundled | personal | linked
  name:             String             // SKILL.md front matter
  description:      String             // SKILL.md front matter
  resources:        [SkillResource]
  crispyMetadata:   SkillMetadata?     // root/crispy.skill.json
}

SkillMetadata {
  category:         String
  roles:            [work | review]
  interaction:      unattended | interactive
  requiredCommands: [String]
}

SkillResource {
  relativePath: String
  kind:         reference | script | asset | agentMetadata | other
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

- `automation_vibes` is the canonical Vibe library.
  `automation_lane_steps` stores each Lane revision's ordered, foreign-keyed
  Vibe revision pins; it does not duplicate Work, Verification, Bounds, engine,
  or skills.
- `category` segments the central library and lane designer without changing
  execution semantics. Legacy Vibes without a category migrate to `general`;
  shipped starter Vibes migrate to their catalog category.
- Stable step `key`s are identities; `order` is presentation/execution order
  only. The referenced Vibe supplies the human-facing name.
- Editing a Vibe creates a new version. Existing lane pins do not move
  automatically; the lane designer exposes an explicit update action.
- Legacy lanes with embedded checkpoints migrate one-to-one into central Vibes.
  Runtime task/Schedule snapshots may remain resolved and self-contained.
- Missing `engine` decodes as an all-nil configuration. The engine resolves
  defaults when an attempt starts, not when the lane is saved.
- Missing `reviewSkills` decodes as an empty list. Review skills use the same
  bare-name and explicit-path resolution as Work skills, but are sent only to
  the independent reviewer.
- `SKILL.md` remains the portable source of agent instructions. The optional
  `crispy.skill.json` sidecar stores only Crispy authoring metadata.
- Managed packages are addressed by their directory name. Linked packages are
  addressed by an absolute `SKILL.md` path retained in
  `automation_skill_references`.
- A Vibe stores skill references, not skill contents. Personal and linked skill
  packages are not version-pinned with Vibes in the current schema.
- An explicitly selected agent plus nil model means that agent's own default
  model. This avoids applying a model ID that belongs to the app-default agent.
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
  deletions of starters persist in `automation_lane_tombstones`;
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
  agentID:              String?       // legacy task-wide agent fallback only
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
  pendingSteerGuidance: String?
  pendingHumanVerdict:  VerificationResult?
  pendingHumanEngine:   EngineSnapshot?
  rerunRequest:         RerunRequest?
  lastRerunCheckpointKey: String?

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
  rerunEpochCount:     Int            // budget epochs created by isolated rerun
  activeEngine:        EngineSnapshot?
}

Attempt {
  id:         UUID
  index:      Int
  promptKind: goal | feedback | steer
  result:     VerificationResult?
  at:         Date
  budgetEpoch: Int
  engine:     EngineSnapshot?         // live settings reported by the session
}

EngineSnapshot {
  agentID:       String
  agentName:     String
  modelID:       String?
  modelName:     String?
  modeID:        String?
  modeName:      String?
  trustMode:     standard | fullTrust
  reasoningLevel: (low | medium | high | max)? // nil if unsupported by agent
}

All new attempts run with `fullTrust`. `EngineConfiguration` does not persist a
trust choice, and a legacy `trustMode` key is ignored during decode.
`EngineSnapshot.trustMode` remains because history records the actual mode used,
including old attempts that may have run in Standard.

RerunRequest {
  checkpointKey:          String
  engine:                 EngineConfiguration
  previousState:          stopped | done
  previousStopReason:     StopReason?
  previousCheckpointKey:  String
  requestedAt:            Date
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
- `rerunEpochCount` distinguishes budget epochs created by isolated reruns from
  epochs consumed by Steer, preserving steer-count validation.
- `activeEngine` appears as soon as a session connects; `Attempt.engine` freezes
  the session-reported values when the attempt settles.
- `rerunRequest` is transient persisted execution state. It overrides only the
  selected attempt and never mutates the pinned lane revision.
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
running -> needsInput    human-review checkpoint awaits a verdict
running -> stopped       exhausted stop bound
running -> stopped       exhausted escalate bound at steer limit
running -> stopped       missing non-user input, error, or user stop

needsInput -> running    Supply or Steer answered
needsInput -> stopped    user stop

done -> running          isolated checkpoint rerun starts
running -> done          isolated rerun passes; prior terminal state restored
stopped -> running       isolated checkpoint rerun starts
running -> stopped       isolated rerun passes; prior terminal state restored
```

## 4. Commands

```text
createTask(laneID, title, projectPath, agentID?) -> Task
stopTask(taskID)
answerInput(taskID, requestID, answer) -> Task
rerunStep(taskID, checkpointKey, engine) -> Task
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
- `rerunStep` accepts only a terminal task and a checkpoint with attempt history.
  It preserves history, creates a fresh budget epoch/session pair, runs only that
  checkpoint, and restores the previous terminal state after PASS.
- A blind `resumeTask` command is intentionally not part of the canonical
  contract. Needs you resumes through `answerInput`; exhausted Stopped tasks need
  a new task or a lane/task edit flow.

## 5. Observation and Scheduling

The manager publishes `[Task]` plus lane definitions/revisions. The UI renders the
published model and does not reach into engine internals.

The scheduler may start only tasks with `state == running` and no in-flight engine
job. It MUST ignore `needsInput`, `stopped`, and `done`.

A per-task run generation token prevents a superseded engine after stop/delete
from clobbering or resurrecting a task, and prevents an old completion from
clearing a replacement rerun's in-flight slot. Shutdown invalidates every
active generation before cancellation and disables queue scheduling, preserving
Running state for relaunch recovery.

## 6. Persistence and Versioning

- Persist after every transition, including each activity change, open input
  request, answer, active/attempt engine snapshot, rerun transition, and terminal
  state.
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
  - steer count is non-negative and not inconsistent with budget epochs after
    excluding `rerunEpochCount`;
  - a rerun request targets the current known checkpoint and preserves a valid
    prior terminal state.

## 7. Evolvability

- `schemaVersion` is the contract version. Additive optional fields do not require
  a bump if readers are defensive.
- Missing checkpoint engines decode as `.default`; missing engine snapshots and
  rerun fields decode as nil/zero.
- Breaking changes require a bump and migration.
- Legacy `running | stopped | done` tasks can migrate without an open request.
  Legacy stopped missing-input tasks cannot be auto-converted to Supply unless the
  lane revision marks the missing key ask-user.

## 8. Superseded Decisions

The 2026-06-28 three-state model is superseded. The canonical schema includes
`needsInput`, Supply, Steer, stop-vs-escalate bounds, ask-user inputs, and
lane-level steer limit.
