# Agent CLI — Automation Commands

This document specifies the `vibe.*`, `skill.*`, and `schedule.*` command
families. They are app-side adapters over the existing `VibeLaneTaskManager`,
`VibeLaneSkillStore`, and `VibeLoopManager`; there is no separate Automation
bundle or CLI persistence layer.

## Complete direct authoring flow

Discover the live surface first (`crispy help`, then focused topics such as
`crispy help lane.validate`). Use `--json` and carry returned identities into
each downstream document; never infer or silently update a pin.

```bash
# 1. Validate and copy-import a real Skill package (copy is the default).
crispy skill validate ./skills/release-review --json
SKILL_REF=$(crispy skill import ./skills/release-review --json | jq -r '.skills[0].reference')
# `--link` is opt-in and must be accompanied by a warning that the external
# package remains mutable and later source edits are reflected by Crispy.

# 2. Put $SKILL_REF in vibe.json work.skills or verify.reviewSkills.
crispy vibe validate --file vibe.json --json
VIBE_RESULT=$(crispy vibe create --file vibe.json --json)
VIBE_ID=$(printf '%s' "$VIBE_RESULT" | jq -r '.vibe.id')
VIBE_VERSION=$(printf '%s' "$VIBE_RESULT" | jq -r '.vibe.version')

# 3. Put those exact values in lane.json steps[].vibe.
crispy lane validate --file lane.json --json
LANE_RESULT=$(crispy lane create --file lane.json --json)
LANE_ID=$(printf '%s' "$LANE_RESULT" | jq -r '.lane.id')
LANE_VERSION=$(printf '%s' "$LANE_RESULT" | jq -r '.lane.version')

# 4. Preview recurrence, then create schedule.json with enabled:false and the
# exact returned lane id/version.
crispy schedule preview --file recurrence.json --count 5 --json
crispy schedule create --file schedule.json --json
```

Canonical `lane.json` uses `steps`, for example
`{"steps":[{"key":"review","vibe":{"id":"<returned-id>","version":1}}]}`.
The Lane owns only `requires`/`produces`; expectation content comes from the
pinned Vibe. Embedded `checkpoints` are deprecated compatibility and cannot be
combined with `steps`. Canonical paused `schedule.json` uses
`{"enabled":false,"lane":{"id":"<returned-lane-id>","version":1},...}`.

Validation and recurrence preview are pure. Skill changes do not alter Vibes,
Vibe changes do not repin Lanes, and Lane changes do not alter frozen Schedule
snapshots. Only pass `--confirm-full-trust` when the user explicitly enables a
reviewed Schedule for unattended execution.

## Vibes

- `vibe.list [--category <id-or-name>] [--status ready|needs-setup]`
- `vibe.show <id-or-name>`
- `vibe.validate --file <json>`
- `vibe.create --file <json>`
- `vibe.update <id-or-name> --file <json> --expected-version <n>`
- `vibe.delete <id-or-name> --expected-version <n>`

Create, update, and validate send the parsed JSON object in `params.document`.
Validation is pure: it checks required fields, bounds, installed Skill
availability, and Work/Review role compatibility without writing. The `ready`
field and list status filters use this same validation, including missing Skill
packages, missing package references or commands, interactive Review Skills,
and role mismatches.

Vibes are manager-versioned. Update and delete require the version returned by
list/show. A stale `expectedVersion` returns `conflict` and performs no write.
Deletion is refused while a current Lane references the Vibe.

## Skills

- `skill.list [--source bundled|personal|linked] [--role work|review]`
- `skill.show <reference> [--include-body]`
- `skill.validate <reference-or-path>`
- `skill.import <path> [--copy|--link]`
- `skill.duplicate <reference>`
- `skill.remove <reference>`

Copy is the import default. It discovers and validates packages using the
store's existing scan/parse limits, then copies each complete package directory
(including scripts, references, assets, and metadata) into the managed personal
root. Link mode reuses the store's persisted `linkCollection` behavior and does
not copy files. Linked packages remain externally mutable; personal copies are
editable in Crispy; bundled packages are read-only.

`skill.validate` is pure. `skill.remove` deletes a personal package or unlinks a
linked package through the Skill store and is refused while any current Vibe
references that Skill. Skills have no digest field in the current model, so this
contract deliberately has no `expectedDigest` parameter.

## Schedules

- `schedule.list [--status scheduled|active|needs-you|paused|blocked]`
- `schedule.show <id-or-name>`
- `schedule.create --file <json> [--confirm-full-trust]`
- `schedule.update <id-or-name> --file <json> [--confirm-full-trust]`
- `schedule.pause <id-or-name>`
- `schedule.enable <id-or-name> --confirm-full-trust`
- `schedule.adopt-lane <id-or-name> --lane <id-or-name> [--confirm-full-trust]`
- `schedule.run-now <id-or-name>`
- `schedule.runs <id-or-name> [--limit <1...200>]`
- `schedule.delete <id-or-name> [--stop-active|--keep-active]`
- `schedule.preview --file <recurrence-json> [--count <1...50>]`

Create and update send the parsed JSON object in `params.document`. A Schedule
document contains `name`, `projectPath`, `taskInstruction`, a Lane reference or
`{id, version}` object, `recurrence`, optional `missedRunPolicy`, and optional
`enabled`. The app freezes the manager-owned current Lane snapshot; a supplied
Lane version must be current.

Any create, update, enable, or lane adoption whose resulting Schedule is enabled
requires `confirmFullTrust: true` before the manager is called. Pause affects
future occurrences and does not stop an active run. `run-now` preserves the
manager's overlap and recurrence behavior. Delete's active-run choice is passed
to the existing manager.

`preview` validates recurrence and computes upcoming timestamps with
`VibeLoopScheduleCalculator`; it does not save a Schedule. Schedules have no
revision field in the existing model, so this contract deliberately has no
`expectedRevision` parameters.

The Swift router registers camel-case `schedule.adoptLane`/`schedule.runNow`
and kebab-case aliases used by the bundled Rust CLI.

## Output

Default CLI output is a concise human summary. `--json` returns the exact result
object for automation. Skill summaries identify linked external mutability, and
enabled Schedule summaries identify active Full Trust execution.
