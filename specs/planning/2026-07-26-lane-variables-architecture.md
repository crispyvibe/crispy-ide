# Lane Variables and Iteration — Architecture

Feature: F059 Vibe Lanes
Status: accepted direction; implementation staged
Diagram: `specs/features/ai-agents/vibe-lanes/vision/VibeLanes-lane-variables.excalidraw`
Supersedes the dynamic working-directory and runtime engine-variable proposals.

## 1. Decisions

Vibe Lanes has three deliberately separate forms of state:

| Concern | Owner | Mutable during a task |
|---|---|---|
| Execution directory | `VibeLaneTask.projectPath` | No |
| Agent, model, mode, reasoning | pinned Vibe/checkpoint engine | Only through an explicit attempt-local rerun override |
| Inter-step data | typed lane variables and append-only values | Yes, through declared outputs or user Supply |

These concerns are not unified. Their authority, lifetime, and replay semantics are
different, and combining them would let ordinary agent output silently alter where
or how later Full Trust work executes.

A task executes in the project directory selected when the task is created. Every
worker, reviewer, handoff, final-outcome, retry, and rerun invocation uses that same
`projectPath`. A checkpoint cannot change it. If future workspace isolation creates
a worktree, task creation must finish that allocation before the first ACP session
starts and persist the resulting immutable task directory.

Engine settings remain authored on the pinned Vibe/checkpoint. Lane data cannot
select an agent, model, mode, reasoning level, or trust mode. A separate reviewer
engine, if required, is an authored field of Verification rather than a variable.

## 2. Typed lane data

Lane variables model data passed between checkpoints. They do not configure the
engine.

```text
LaneVariable
  name          String                  unique within the lane
  type          LaneVariableType
  scope         .task | .iteration
  laneDefault   String?

LaneVariableType
  .path | .branchName | .verdict | .number | .boolean | .text

LaneValue
  variable      String
  type          LaneVariableType
  raw           String
  writer        .laneAuthor | .user | .step(key: String, visit: Int, attempt: Int)
  scopeInstance .task | .iteration(group: String, visit: Int)
  writtenAt     Date
```

There is no persisted `reserved` flag. Engine configuration is not addressable by
variable name, so a value named `workdir`, `agent`, or `model` is ordinary context
and has no engine-side effect.

### 2.1 Append-only history

Writes append a `LaneValue`; they never mutate or delete an earlier value. The
current binding is the newest value for the variable whose scope instance is live:

- task scope is live for the whole task;
- iteration scope is live only for one visit of one loop group.

Execution reads the current binding. Replay, task detail, and diagnostics can inspect
the complete value history. Reruns append values and never rewrite the value against
which an earlier attempt was verified.

### 2.2 Typed contracts and write authority

Checkpoint contracts become typed:

```text
VibeLaneInputRequirement
  key       String
  type      LaneVariableType
  askUser   Bool
  prompt    String?

VibeLaneOutputDeclaration
  key       String
  type      LaneVariableType
  detail    String?
```

A checkpoint may write only keys declared by its `produces` contract. Lane
validation checks that every non-user input can be satisfied by an earlier producer
or a lane default, and that producer/consumer types agree.

### 2.3 Resolution

For checkpoint *S* and data variable *v*, resolution uses the first available value:

1. newest live `LaneValue`;
2. the lane-authored default;
3. a Supply request when *S* marks the missing input `askUser`.

An unresolved non-user input stops as `missingInput` when an earlier producer
exists, or `misAuthoredLane` when no valid producer/default exists. Engine and
working-directory defaults are intentionally absent from this chain.

## 3. Typed ingress

Free-form `OUTPUT <key>: <value>` scanning is replaced by a declared output payload.
Use a structured tool result when supported and one fenced JSON object otherwise.
The payload is captured from the work turn before verification, persisted with the
attempt, and included in reviewer evidence.

Any unknown key, undeclared key, duplicate key, type mismatch, oversized value, or
unparseable payload fails the attempt and returns actionable feedback to the worker.
No partial write is committed. A human-review pause persists the work text and typed
payload so approval resumes the exact attempt rather than settling with empty work.

The post-verdict handoff summarizes a passed checkpoint but cannot introduce or
override machine-readable values. This keeps every carried value inside the evidence
the reviewer approved.

## 4. Immutable execution context

`VibeLaneTask.projectPath` is both the scheduling key and execution directory for the
entire task. Task creation canonicalizes it; UI, CLI, and Schedule entry surfaces
verify that their selected target is an eligible local directory. Once persisted,
it is immutable.

All agent invocation sites use `task.projectPath`:

- worker Work;
- independent reviewer;
- handoff generation;
- final outcome;
- retries and isolated reruns.

Lane outputs may contain path values, but paths are context for the agent; the engine
does not `chdir` based on them. Tasks targeting the same canonical project path are
serialized. Symlink/repository identity hardening may make serialization more
conservative later, but no task changes scheduling identity after admission.

## 5. Authored engines

`VibeLaneEngineConfiguration` remains part of the pinned Vibe/checkpoint revision.
Resolution is:

- authored agent, otherwise app ACP default;
- authored model, otherwise app model only when the agent is inherited;
- authored mode, otherwise agent default;
- authored reasoning, otherwise app ACP default;
- Full Trust always.

An isolated rerun may supply an attempt-local engine override. It does not mutate the
lane, task directory, or any data variable.

If product requirements add a distinct reviewer engine, Verification gains an
explicit authored `reviewEngine` field. It is versioned and pinned with the Vibe; it
is never produced by a worker.

## 6. ACP transcript lifecycle

A task exposes one logical worker timeline and one logical reviewer timeline. The
underlying ACP process may reconnect when an authored engine configuration changes
or after an unexpected disconnect, but process lifetime is not transcript lifetime.

Invariants:

1. `ACPSessionRegistry` retains the managed store when the engine detaches a process.
2. Reattaching a process preserves the store's timeline and persistence context.
3. Final task release marks the managed transcript ended instead of removing it.
4. A terminal task target carries ended state, so recreating a store after app or
   view teardown restores history as ended and never shows an indefinite Waiting
   spinner.
5. The transcript remains read-only/openable after the task ends; rerun reconnects
   it explicitly.

## 7. Iteration

The recommended iteration model is an authored loop group:

```text
VibeLaneLoopGroup
  key            String
  members        [String]
  maxIterations  Int
  exitWhen       VariableCondition
  onExhausted    .stop | .escalate | .advance

VariableCondition
  .equals(variable: String, value: String)
  .notEquals(variable: String, value: String)
  .isSet(variable: String)
  .all([VariableCondition])
  .any([VariableCondition])
  .not(VariableCondition)
```

Members are ordinary checkpoints with independently authored Vibes, engines, skills,
bounds, and records. This supports reusable `code -> test -> review` groups without
turning reviewer configuration into runtime data.

Loop execution needs durable group key, visit, member position, exit-evaluation
point, exhaustion behavior, and handoff lineage. Rerun epochs remain separate from
visits.

### 7.1 Per-visit records

Checkpoint-run identity becomes `(checkpointKey, visit)`. Every consumer must choose
current, latest, named, or all visits explicitly. This affects model validation,
engine transitions, manager commands, timeout handling, task detail, CLI output, and
handoff persistence.

### 7.2 Persistence migration

The iteration change requires database schema v8:

- add visit to handoff identity and filenames;
- migrate legacy runs to visit `0`;
- migrate untyped carry-forward values to task-scoped `.text` values with a legacy
  writer marker;
- default legacy `requires`/`produces` contracts to `.text`;
- round-trip variables, defaults, typed contracts, and loop groups through
  `StoredVibeLaneDefinition`;
- preserve resumability of valid Running and Needs-you tasks.

The Vibe Lane Codable contract version also bumps for its breaking typed-contract
change; it is distinct from the database schema version.

## 8. Invariants

1. A task directory is selected once and never changed by lane execution.
2. Agent output cannot select engine settings or trust mode.
3. A step writes only declared, type-compatible data variables.
4. Values are append-only and record their writer and scope instance.
5. Typed outputs are persisted before verification and are exactly what the reviewer
   evaluates.
6. Human-review resume retains the original work and output payload.
7. ACP transcript lifetime outlives any individual managed process.
8. The engine runs no subprocess and performs no git or repository mutation itself.

## 9. Sequencing

| # | Change | Depends on |
|---|---|---|
| 1 | Remove dynamic directory behavior; make transcript ending/reconnect durable | — |
| 2 | Typed variable model and typed `requires`/`produces` | — |
| 3 | Structured ingress persisted before verification | 2 |
| 4 | CLI/editor/task-detail support for typed data and history | 2, 3 |
| 5 | Per-visit run identity and schema-v8 migration | — |
| 6 | Loop groups and durable loop execution state | 2, 5 |
| 7 | Conditional routing or concurrent members | 5, 6 |

The July 22 Automation CLI authoring schema must adopt typed contracts when steps 2–4
land. Schedules continue freezing one lane revision and one immutable project path.
The Todo bridge must translate seeded string values into declared typed task values.

## 10. Remaining decisions

1. Canonical validators and size limits for each data type.
2. Retention policy for append-only value history.
3. Exact loop entry, exit-evaluation, resume, and handoff-lineage rules.
4. Whether a separately authored reviewer engine is needed before loop groups.

None of these decisions reopens runtime directory or engine selection by lane data.
