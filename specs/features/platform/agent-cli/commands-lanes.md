# Agent CLI — Vibe Lane Commands

This document specifies the `lane.*` and `lane.task.*` commands. See
[spec.md](spec.md) for cross-cutting requirements and
[F059 Vibe Lanes](../../ai-agents/vibe-lanes/spec.md) for the underlying
feature. Every command is a thin passthrough to the same
`VibeLaneTaskManager` the UI observes, so F059's invariants (single open input
request, pinned lane versions, the Needs-you notification chokepoint) hold for
both callers. The CLI never reaches into the engine or the store directly.

For dispatching a **todo** to a lane, use `todo.dispatch`
(F060, [todo-lane-pipeline](../../ai-agents/todo-lane-pipeline/spec.md));
`lane.task.create` starts a task from an arbitrary input with no todo involved.

## Commands

Lane authoring (F059-R01):

- `lane.list` — list all authored lanes
- `lane.show` — one lane's full definition
- `lane.create` — create a lane (optionally with full checkpoints)
- `lane.update` — edit a lane; bumps its version
- `lane.delete` — delete a lane
- `lane.restoreStarters` — restore deleted / refresh pristine starter lanes

Task control (F059-R03/R07/R10):

- `lane.task.create` — run an input through a lane on a project
- `lane.task.list` — task summaries + counts by state
- `lane.task.show` — full task detail incl. any open input request
- `lane.task.answer` — answer a Supply / Steer / Review request
- `lane.task.stop` — stop a running or needs-input task
- `lane.task.delete` — delete a task and its handoff files

All commands return `not_connected` when Vibe Lanes is unavailable, and
`invalid_params` for unknown lanes/tasks, ambiguous lane names, or answers that
do not match the open request's kind.

---

## Lane references

Wherever a command takes a `lane` parameter it accepts either a lane UUID or a
case-insensitive lane name. A name matching several lanes is refused with
`invalid_params` listing the candidates (same resolution as `todo.dispatch`).

## `lane.list` / `lane.show`

`lane.list` takes no parameters and returns `lanes`: an array of
`{id, name, version, description?, steerLimit, checkpointCount, route, starter}`.
`starter` is true for pristine shipped starter lanes (never user-edited).

`lane.show` takes `lane` and returns the summary plus `checkpoints`: ordered
`{key, order, goal, instructions?, skills?, verify: {definition, humanReview},
bounds: {maxAttempts, timeoutSeconds, onExhausted}, requires?, produces?}`.

## `lane.create` / `lane.update`

| Name | Type | Required | Description |
|---|---|---|---|
| `lane` | string | update only | Lane name or UUID. |
| `name` | string | create only | Lane name (optional on update). |
| `description` | string | no | What the lane is for. Empty string clears it on update. |
| `steerLimit` | integer | no | Steer escalations the lane allows (default 1 on create). |
| `checkpoints` | array | no | Checkpoint definitions in the lane schema (see `lane.show` shape with `work: {goal, instructions?, skills?}`). Full replacement on update. |

Both return the resulting `lane` detail. Checkpoint keys are normalized exactly
like the UI editor save path (F059-R01: stable, unique, non-empty keys), and
`lane.update` bumps the lane version — running tasks keep the version they
pinned (F059-S07 semantics). Malformed `checkpoints` fail with `invalid_params`
before any lane is persisted. `lane.update` with no editable field provided is
refused.

## `lane.delete` / `lane.restoreStarters`

`lane.delete` takes `lane`. In-flight and finished tasks keep resolving the
revision they pinned. Deleted starter lanes persist as tombstones;
`lane.restoreStarters` re-adds them and refreshes pristine starters to the
latest shipped content, returning the resulting lane summaries.

## `lane.task.create`

| Name | Type | Required | Description |
|---|---|---|---|
| `lane` | string | yes | Lane name or UUID. |
| `input` | string | yes | The per-run instruction (task input/title, F059-R03). |
| `project` | string | no | Absolute project path. Defaults to the caller's `CRISPY_PROJECT_PATH`. Must be an existing directory. |
| `agent` | string | no | ACP agent id for worker/reviewer sessions. |
| `inputs` | object | no | Initial carry-forward values (same trust class as Supply answers; empty values dropped). |

Returns `task`: the created task summary. Creation uses the exact
`createTask` path the UI uses, so lane-version pinning, repo baseline capture,
and scheduling caps apply identically.

## `lane.task.list` / `lane.task.show`

`lane.task.list` takes optional `state` (`running | needsInput | stopped |
done`) and `project` filters. Returns `tasks` (needs-input first, then most
recently updated — the F059-R09 dashboard order) and `counts`.

`lane.task.show` takes `id` (task UUID) and returns full detail: lane and
route, current checkpoint, per-checkpoint runs with attempt counts and stop
reasons, carry-forward values, last verification, outcome summary, steer count,
and any open input request (`{id, kind, checkpoint, prompt, missingKeys?,
lastFeedback?, reason?}`).

## `lane.task.answer`

Answers the task's single open input request (F059-R07). The parameter shape
must match the open request's kind; a mismatch is refused with a message
naming the expected shape.

| Name | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Task UUID. |
| `values` | object | Supply | Answers keyed by missing input key; every key needs a non-empty value. |
| `guidance` | string | Steer | Fed to the worker as feedback; the checkpoint gets a fresh bounded budget. |
| `approve` | boolean | Review | The human verdict. |
| `feedback` | string | Review reject | Required when `approve` is false (rejection without feedback is refused, F059-R07). |

Returns the resumed `task` summary. Answers route through the same
`answerInput` methods the UI sheets call, so request-id/kind validation and
resume semantics are shared.

## `lane.task.stop` / `lane.task.delete`

Both take `id`. `lane.task.stop` refuses terminal tasks with `invalid_params`;
`lane.task.delete` also removes the task's persisted handoff files and prunes
unpinned lane revisions (manager semantics, not CLI-specific).

## Change History

- 2026-07-12 — Initial version: lane authoring and task control commands
  (F059-R10 parity with the UI).
