# Automation CLI Authoring

Date: 2026-07-22
Status: proposed
Owners: Agent CLI, Vibe Lanes, Schedules

## Goal

Make Crispy's automation model fully authorable through the bundled `crispy`
CLI so an agent can:

- import and manage real Skill packages;
- create and version Vibes;
- compose Vibe Lanes from pinned Vibes;
- create, inspect, pause, enable, and run Schedules;
- design and preview Schedule recurrence;
- validate and apply a complete automation graph without writing Crispy's
  persistence files directly.

The CLI must use the same managers and validation paths as the SwiftUI
surfaces. A CLI-created resource must appear immediately in Automation, and a
UI edit must be visible to the next CLI read.

## Scope Boundaries

This plan does not add:

- offline edits while Crispy is not running;
- direct writes to Crispy's Application Support files;
- a daemon or exact execution while Crispy is quit;
- cron expressions, event triggers, or remote Schedule targets;
- reusable recurrence templates independent of a Schedule;
- Skill version history.

Skills continue to use content digests for conflict detection. This is not
presented as Skill versioning or immutable Skill pinning.

## Research Summary

### Existing control plane

- `CLISocketServer` accepts newline-delimited JSON requests over a
  bundle-scoped Unix socket.
- The socket is owner-only (`0600`), but any process running as the same macOS
  user may connect. The CLI is not limited to descendants of Crispy.
- `CLICommandRouter` runs on `@MainActor`, registers dotted methods, and exposes
  live command descriptors through `help`.
- The app must be running. `CRISPY_SOCKET` selects the app instance.
- Mutations are expected to route through app services rather than write
  Application Support files directly.

### Current automation model

| Resource | Current owner | Identity and revision | Persistence |
|---|---|---|---|
| Skill | `VibeLaneSkillStore` | managed slug or linked `SKILL.md` path; no version | package files on disk; linked references/digests in encrypted libSQL |
| Vibe | `VibeLaneTaskManager` | UUID plus integer version | encrypted libSQL current and immutable revision rows |
| Vibe Lane | `VibeLaneTaskManager` | UUID plus integer version | encrypted libSQL Lane rows plus ordered foreign-keyed Vibe pins |
| Schedule | `VibeLoopManager` (legacy internal name) | UUID; `updatedAt` but no revision counter | encrypted libSQL definition, runtime, and run rows |
| Recurrence | part of `VibeLoopDefinition` | no independent identity | serialized in the owning Schedule row |

The dependency and pinning chain is:

```text
Skill references
      |
      v
Vibe version
      |
      v
Vibe Lane version (steps pin Vibe versions)
      |
      v
Schedule (freezes a complete Vibe Lane snapshot)
```

Updating an upstream resource intentionally does not update downstream pins.
The CLI must preserve this rule.

### Existing command gaps

1. The Swift router exposes `lane.*` and `lane.task.*`, but the Rust `crispy`
   client has no `lane` subcommand. The normal CLI cannot invoke those methods.
2. Current `lane.create` and `lane.update` accept embedded checkpoint
   definitions. The current product model instead requires lane steps to
   reference central, versioned Vibes.
3. There are no router attachments or RPC commands for
   `VibeLaneSkillStore`, central Vibes, `VibeLoopManager`, or schedule preview.
4. Skill removal is protected by usage count in the UI, but the store itself
   does not enforce that relationship.
5. Vibe and lane authoring persistence methods often return `Void` and log
   write failures. That is insufficient for a reliable CLI or multi-resource
   apply.
6. Vibes and Vibe Lanes have versions, but handlers do not require an expected
   version. Concurrent UI and CLI edits can overwrite one another.
7. Schedules have no revision counter for optimistic concurrency.
8. The Rust client is a single large `main.rs`; adding four command families
   there will make command/schema parity harder to maintain.
9. Some Agent CLI documentation still describes the removed process-ancestry
   gate even though the implementation and threat model use same-user access.

### Primary implementation sources

- `Features/AgentCLI/CLICommandRouter.swift`
- `Features/AgentCLI/CLICommandRouterLaneHandlers.swift`
- `rust/crispyvibes-cli/src/main.rs`
- `Features/VibeLanes/Services/VibeLaneTaskManager+VibeAuthoring.swift`
- `Features/VibeLanes/Services/VibeLaneTaskManager+LaneAuthoring.swift`
- `Features/VibeLanes/Services/VibeLaneSkillStore.swift`
- `Features/VibeLanes/Services/VibeLaneStore.swift`
- `Features/VibeLanes/Services/VibeLaneReferenceResolver.swift`
- `Features/Loops/Models/VibeLoopDefinition.swift`
- `Features/Loops/Services/VibeLoopManager.swift`
- `Features/Loops/Services/VibeLoopManager+Scheduling.swift`
- `Features/Loops/Services/VibeLoopStore.swift`
- `Features/Loops/Services/VibeLoopScheduleCalculator.swift`

## Product Decisions

### Two authoring workflows

Provide both:

1. **Typed resource commands** for inspecting or changing one resource.
2. **Declarative automation bundles** for validating, planning, and applying a
   complete dependency graph.

Resource commands are useful for interactive agents. Bundles are the reliable,
reviewable path for creating a reusable automation setup.

### Recurrence remains part of a Schedule

Interval, daily, or weekly recurrence is configuration owned by one Schedule,
not a separately reusable entity. Do not add independent recurrence CRUD or
persistence.

Expose recurrence design through:

- a `recurrence` field on `schedule.create` and `schedule.update`; and
- a pure `schedule.preview` operation that validates a recurrence and
  returns upcoming occurrences without saving a Schedule.

### JSON is the bundle interchange format

Use versioned JSON for the first release:

```text
apiVersion: crispy.dev/automation/v1alpha1
kind: AutomationBundle
```

JSON is already supported end to end by Rust, Swift, Codable, and the wire
protocol. It is deterministic for agents and avoids introducing a second
parser before the schema stabilizes. It is not the persistence model: the app
validates the document and commits metadata to encrypted libSQL. YAML can be
added later as a client-side translation into the same interchange model.

### Stable IDs, display names

- Vibes, Vibe Lanes, and Schedules are referenced by UUID in writable
  configuration.
- Names remain display values and optional search conveniences.
- Name lookup must never choose between duplicates.
- A bundle that intends repeated application must include stable UUIDs.
- Skills use their canonical `reference`, which is the managed slug or linked
  `SKILL.md` path.

### Explicit revision adoption

Bundle references support three policies:

- `managed`: pin the revision produced by a resource declared in the same
  bundle;
- an integer: pin that exact existing revision;
- `latest`: explicitly adopt the current revision at apply time.

`latest` is never an implicit default. This keeps Vibe Lane and Schedule updates
reviewable.

### Safe defaults

- A newly created Schedule is paused unless both its document requests `enabled`
  and the caller passes an explicit Full Trust acknowledgement.
- An Automation apply never starts a run. `crispy schedule run-now` is a
  separate command.
- Missing resources are not pruned merely because they are absent from a
  bundle.
- Deletion requires an explicit resource entry with `state: "absent"` and an
  `--allow-delete` acknowledgement.
- Skill import copies into Crispy by default. Linking mutable external content
  requires `--link` or `mode: "link"` and produces a warning.

## Proposed CLI

### Skills

```text
crispy skill list [--source bundled|personal|linked] [--role work|review]
crispy skill show <reference> [--include-body]
crispy skill validate <path-or-reference>
crispy skill import <path> [--copy|--link]
crispy skill update <reference> --from <package-path> --expected-digest <sha256>
crispy skill duplicate <reference>
crispy skill remove <reference> --expected-digest <sha256>
```

`skill import` accepts a `SKILL.md`, one package directory, or a collection
containing nested packages. Copy mode must copy the complete package, including
references, scripts, assets, and agent metadata. It must not reduce a package
to name, description, and an inline instruction field.

Removal must fail when any current Vibe references the Skill. Bundled and
linked Skills remain read-only; a linked Skill can be unlinked, while editing
requires duplication or copy import.

### Vibes

```text
crispy vibe list [--category <category>] [--status ready|needs-setup]
crispy vibe show <uuid>
crispy vibe validate --file <vibe.json>
crispy vibe create --file <vibe.json>
crispy vibe update <uuid> --file <vibe.json> --expected-version <n>
crispy vibe delete <uuid> --expected-version <n>
```

Create and update accept the full expectation contract: category, Work goal and
instructions, Work Skills, Verification definition and Review Skills,
verification owner, Bounds, and engine configuration.

Validation must include Skill existence/readiness and role compatibility, not
only `VibeDefinition.isReady`.

### Vibe Lanes and tasks

```text
crispy lane list
crispy lane show <uuid-or-unambiguous-name>
crispy lane validate --file <lane.json>
crispy lane create --file <lane.json>
crispy lane update <uuid> --file <lane.json> --expected-version <n>
crispy lane delete <uuid> --expected-version <n>
crispy lane restore-starters

crispy lane task create ...
crispy lane task list ...
crispy lane task show ...
crispy lane task answer ...
crispy lane task stop ...
crispy lane task delete ...
```

The writable lane schema uses `steps`, not embedded checkpoints:

```json
{
  "id": "d6336ab2-2232-4b60-9a22-ff703122cf2b",
  "name": "Release Vibe Lane",
  "description": "Prepare and verify a release.",
  "steerLimit": 1,
  "steps": [
    {
      "key": "verify-release",
      "vibe": {
        "id": "5ac45743-4e3d-4aa5-8ee5-caa15215247d",
        "version": 3
      },
      "requires": [],
      "produces": [
        {
          "key": "release_evidence",
          "type": "text",
          "description": "Tests and package checks used for the decision."
        }
      ]
    }
  ]
}
```

The server resolves each Vibe reference and stores only the pinned ID/version
and lane-owned handoff data. Existing embedded `checkpoints` RPC input should
remain temporarily available as a deprecated compatibility path, but the Rust
CLI and new documentation must use `steps`.

### Schedules

```text
crispy schedule list [--status scheduled|active|needs-you|paused|blocked]
crispy schedule show <uuid>
crispy schedule create --file <schedule.json> [--confirm-full-trust]
crispy schedule update <uuid> --file <schedule.json> --expected-revision <n> \
  [--confirm-full-trust]
crispy schedule pause <uuid> --expected-revision <n>
crispy schedule enable <uuid> --expected-revision <n> --confirm-full-trust
crispy schedule adopt-lane <uuid> --lane <uuid> --expected-revision <n> \
  [--confirm-full-trust]
crispy schedule run-now <uuid>
crispy schedule runs <uuid> [--limit <n>]
crispy schedule delete <uuid> --expected-revision <n> \
  [--stop-active|--keep-active]
crispy schedule preview <schedule flags> [--count <n>]
```

Human-friendly schedule flags:

```text
--every 30m [--anchor <ISO-8601>]
--daily 09:00 --timezone America/Chicago
--weekly mon,wed,fri --at 09:00 --timezone America/Chicago
```

The canonical RPC and bundle shape remains typed:

```json
{"kind":"interval","seconds":1800,"anchor":"2026-07-22T14:00:00Z"}
{"kind":"daily","hour":9,"minute":0,"timeZone":"America/Chicago"}
{"kind":"weekly","weekdays":["mon","wed","fri"],"hour":9,"minute":0,"timeZone":"America/Chicago"}
```

Weekday names avoid exposing Foundation's `1...7` convention to users. The
server converts names and remains the authority for minimum interval, time
zone, DST, and next-occurrence validation.

`schedule.run-now` must preserve the existing behavior: it does not move the next
scheduled occurrence and still obeys the one-active-run overlap guard.
`--confirm-full-trust` is required on create, update, or lane adoption only
when the resulting Schedule is enabled.

### Declarative bundles

```text
crispy automation schema
crispy automation validate --file crispy.automation.json
crispy automation plan --file crispy.automation.json
crispy automation apply --file crispy.automation.json
crispy automation apply --file crispy.automation.json \
  --confirm-full-trust --allow-delete
crispy automation export --output <directory>
```

All commands support `--json`; `--file -` reads stdin.

Example:

```json
{
  "apiVersion": "crispy.dev/automation/v1alpha1",
  "kind": "AutomationBundle",
  "metadata": {
    "name": "nightly-release-check"
  },
  "skills": [
    {
      "reference": "release-review",
      "source": {
        "mode": "copy",
        "path": "./skills/release-review"
      }
    }
  ],
  "vibes": [
    {
      "id": "5ac45743-4e3d-4aa5-8ee5-caa15215247d",
      "name": "Verify release",
      "category": "release",
      "work": {
        "goal": "Produce release evidence.",
        "instructions": "Run the release checks and preserve their output.",
        "skills": []
      },
      "verify": {
        "definition": "All required release checks pass and evidence is present.",
        "reviewSkills": ["release-review"],
        "humanReview": false
      },
      "bounds": {
        "maxAttempts": 3,
        "timeoutSeconds": 1800,
        "onExhausted": "escalate"
      },
      "engine": {}
    }
  ],
  "lanes": [
    {
      "id": "d6336ab2-2232-4b60-9a22-ff703122cf2b",
      "name": "Release Vibe Lane",
      "steerLimit": 1,
      "steps": [
        {
          "key": "verify-release",
          "vibe": {
            "id": "5ac45743-4e3d-4aa5-8ee5-caa15215247d",
            "version": "managed"
          },
          "produces": [{"key": "release_evidence", "type": "text"}]
        }
      ]
    }
  ],
  "schedules": [
    {
      "id": "3c5f2778-cdbc-4990-bc83-d16ceead3098",
      "name": "Nightly release check",
      "enabled": false,
      "projectPath": "../product",
      "taskInstruction": "Check whether the current branch is release-ready.",
      "lane": {
        "id": "d6336ab2-2232-4b60-9a22-ff703122cf2b",
        "version": "managed"
      },
      "recurrence": {
        "kind": "daily",
        "hour": 9,
        "minute": 0,
        "timeZone": "America/Chicago"
      },
      "missedRunPolicy": "runLatestOnce"
    }
  ]
}
```

Relative source and project paths resolve against the manifest directory and
are reported as canonical paths in the plan. A task's resolved `projectPath` is
its immutable execution directory; lane variables and checkpoint outputs cannot
change it.

## Validation and Planning

`automation.validate` performs no writes. It must:

1. Decode and schema-check the complete document.
2. Reject duplicate resource IDs and Skill references.
3. Resolve Skill packages and check front matter, resources, required
   commands, interaction mode, and Work/Review role compatibility.
4. Validate Vibe readiness and referenced Skills.
5. Resolve every Vibe Lane step to an exact Vibe revision, normalize step keys,
   and run `VibeLaneDefinition.validationIssues`.
6. Resolve every Schedule to an immutable Vibe Lane snapshot.
7. Validate project directories, recurrence, missed-run policy, and enabled
   Full Trust requirements.
8. Build the dependency graph and reject cycles or unresolved references.
9. Return structured diagnostics with resource kind, resource ID, JSON path,
   severity, stable code, and message.

`automation.plan` additionally reads current app state and returns ordered
actions:

```text
CREATE skill release-review
UPDATE vibe Verify release v2 -> v3
UPDATE lane Release Vibe Lane v4 -> v5 (adopts Vibe v3)
UPDATE schedule Nightly release check r7 -> r8 (adopts Lane v5, remains paused)
```

Each action includes before/after digests, dependency reason, warnings, and
whether Full Trust or deletion acknowledgement is required. Unchanged
resources are `NOOP` and do not receive a new version.

Updating a Vibe must also report Vibe Lanes that remain pinned to the older
version. Updating a Vibe Lane must report Schedules that retain an older frozen
snapshot. This is information, not an implicit cascade.

## Concurrency and Idempotency

### Optimistic concurrency

- Vibe update/delete requires `expectedVersion`.
- Vibe Lane update/delete requires `expectedVersion`.
- Add `revision: Int` to `VibeLoopDefinition`, defaulting legacy records to
  `1`; Schedule mutations require `expectedRevision`.
- Skill update/remove uses an `expectedDigest` calculated from the package
  entrypoint, metadata, and managed resources.
- Add a stable `conflict` CLI error with current revision/digest in structured
  result data.
- Extend `CLIResponse.error` with an optional `details` object so conflict,
  validation, acknowledgement, and partial-apply failures do not require
  clients to parse human messages.

For a declarative bundle:

- create requires that the ID/reference does not already exist;
- identical desired content is a no-op regardless of revision;
- changing an existing resource requires the expected revision/digest in the
  resource declaration;
- an explicit `--force-conflicts` may be added for users, but agents should not
  use it by default.

### Apply ordering

Resolve and validate in dependency order:

```text
stage Skill packages
  -> validate Skills
  -> resolve Vibes
  -> resolve Vibe Lanes
  -> resolve Schedules and requested enable state
  -> commit all metadata in one database transaction
```

No Schedule or other metadata change becomes visible if validation, package staging,
or the database transaction fails.

### Failure model

Add an `AutomationAuthoringCoordinator` that:

1. obtains one app-side authoring lock;
2. validates and plans against one database snapshot;
3. stages and fully validates copied Skill packages before metadata mutation;
4. submits one typed apply request containing Skills references, Vibes, Vibe
   Lanes, Schedules, and requested enable states;
5. commits that request in one immediate libSQL transaction;
6. publishes manager state only after commit.

A failed transaction rolls back without compensating writes or a recovery
journal. Staged but unreferenced package directories are safe to remove as
orphaned files. Because plans use stable IDs and expected revisions, retry is
idempotent.

## App-Side Design

### Router wiring

Attach these app-owned services in `AppContainer`:

- `VibeLaneTaskManager` (already attached);
- `VibeLaneSkillStore`;
- `VibeLoopManager`;
- `AutomationAuthoringCoordinator`.

Add focused handler files:

```text
CLICommandRouterSkillHandlers.swift
CLICommandRouterVibeHandlers.swift
CLICommandRouterLaneAuthoringHandlers.swift
CLICommandRouterScheduleHandlers.swift
CLICommandRouterAutomationHandlers.swift
```

Handlers remain thin adapters. Resolution, validation, version checks, usage
checks, and persistence belong in shared authoring services so SwiftUI and CLI
cannot diverge.

### Store hardening

Before exposing mutation commands:

- replace authoring `Void` writes with throwing or `Result` APIs;
- publish manager state only after durable writes succeed;
- construct complete resources before their first save;
- add one transactional batch-apply API used by the coordinator;
- move Skill usage protection below the UI;
- add Schedule revision migration;
- reuse one validation service from the UI, direct commands, and bundles.

Direct writes to the Automation database, legacy metadata JSON, or managed
Skill folders are never a supported CLI path.

### Discovery

Extend `crispy help` with `skill`, `vibe`, `lane`, `schedule`, and `automation`
domains. Its glossary defines Vibe (Loop), Vibe Lane (Spiral), Schedule, and
Skill without exposing legacy implementation names as product nouns.

`automation.schema` returns the exact JSON Schema supported by the running app.
Agents should discover this schema instead of assuming the installed app
matches a hardcoded client example.

## Rust Client Design

Split `projects/crispyvibes/rust/crispyvibes-cli/src/main.rs` before adding the
new surface:

```text
src/main.rs
src/client.rs
src/output.rs
src/commands/skill.rs
src/commands/vibe.rs
src/commands/lane.rs
src/commands/schedule.rs
src/commands/automation.rs
```

The Rust client owns:

- clap argument parsing;
- reading JSON from a file or stdin;
- schedule shorthand parsing;
- resolving the manifest base directory;
- human-readable formatting.

Swift owns all authoritative validation and mutation semantics.

Define useful process exit statuses:

| Exit | Meaning |
|---|---|
| 0 | success, including a no-op plan/apply |
| 1 | transport or unexpected server failure |
| 2 | validation failure |
| 3 | optimistic-concurrency conflict |
| 4 | acknowledgement required |
| 5 | partial apply requiring recovery |

## Security and Trust

1. Any same-user process can author global Automation resources through the
   socket. This is broader than one project or VibeSpace and must be added to
   the Agent CLI threat model.
2. Enabling a Schedule crosses from passive configuration into unattended Full
   Trust execution. Require both `enabled: true` and
   `--confirm-full-trust`; record the acknowledgement in the audit event.
3. The CLI must not provide a flag that silently enables all imported Schedules.
4. Copy import is the stable default for Skills. Linked Skills can change
   outside Crispy without a Vibe, Lane, or Schedule revision change; plans must
   surface that residual risk.
5. Normalize and resolve project and Skill source paths, including symlinks,
   before planning. Revalidate Schedule targets immediately before execution as
   today.
6. Do not implement environment-variable or secret interpolation in the
   manifest. Task instructions and Skill files must not become a secret store.
7. Bound manifest size, collection discovery, resource scans, history reads,
   and schedule preview counts.
8. Destructive actions must fail when references still exist unless the same
   reviewed plan also updates/removes those references in a valid order.
9. Add an append-only Automation audit log containing timestamp, request ID,
   caller context, operation, affected IDs, old/new revision or digest, and
   result. Do not log full Skill bodies or task instructions.

## Implementation Phases

### Phase 0: Correct and harden the baseline

- Add the missing Rust `lane` subcommands for already-supported task commands.
- Change new lane authoring input from embedded checkpoints to central Vibe
  references while retaining deprecated RPC compatibility.
- Make Skill, Vibe, Lane, and Schedule authoring persistence failures observable.
- Add shared validators, optimistic concurrency, Skill usage enforcement, and
  Schedule revisions.
- Reconcile Agent CLI documentation with same-user socket authorization.

### Phase 1: Resource RPCs

- Attach Skill and Schedule services to `CLICommandRouter`.
- Implement `skill.*`, `vibe.*`, revised `lane.*`, `schedule.*`, and
  `schedule.preview`.
- Add structured serializers that return IDs, revisions/digests, readiness,
  pinning, next run, and validation diagnostics.
- Add audit events for every mutation.

### Phase 2: Typed Rust commands

- Modularize the Rust crate.
- Add typed clap commands, JSON file/stdin input, schedule shorthand, stable
  exit statuses, and human output.
- Ensure every public RPC has either a typed CLI command or is explicitly
  server-only.

### Phase 3: Declarative bundles

- Add the versioned JSON Schema and `automation.schema`.
- Implement graph resolution, `validate`, and `plan`.
- Implement transactional `apply`, acknowledgements, and per-action results.
- Add `automation.export` that emits stable IDs and exact pinned revisions.
  Portable export should copy personal Skill packages into the output
  directory; linked Skills should remain explicit links with warnings unless
  copy export is requested.

### Phase 4: UI and operational integration

- Refresh open Automation views after CLI mutations.
- Surface audit history and incomplete-apply recovery errors in Automation.
- Show CLI-created paused Schedules and the same Full Trust enable flow as
  UI-created Schedules.
- Add command examples and bundle workflows to the Agent CLI, Vibe Lanes, and
  Schedules documentation.

## Test Plan

### Swift unit tests

- Handler happy paths, malformed params, missing attachments, duplicate names,
  ambiguous names, and structured errors.
- Vibe and Vibe Lane expected-version conflicts.
- Schedule expected-revision conflicts, enable acknowledgement, active-run delete
  choices, lane adoption, run-now, and schedule preview.
- Skill copy/link/import/update/remove, digest conflicts, role compatibility,
  unavailable resources, usage protection, and collection limits.
- Bundle graph resolution, exact/managed/latest pinning, no-op detection,
  stale downstream reporting, and delete ordering.
- Persistence failure before and during apply, transaction rollback, orphaned
  package cleanup, and the guarantee that no requested Schedule enables after a
  failed dependency action.

### Rust tests

- clap parsing for every new command.
- file/stdin JSON loading and malformed documents.
- interval/daily/weekly shorthand, weekday parsing, and ISO anchors.
- RPC method and parameter mapping.
- human and JSON output plus exit-status mapping.

### Integration tests

- Start `CrispyLocal.app`, invoke the bundled `crispy` binary, and verify a
  Skill -> Vibe -> Vibe Lane -> paused Schedule bundle appears in the managers.
- Apply the same bundle twice and verify the second apply is all `NOOP`.
- Edit a Vibe through the UI between plan and apply and verify `conflict`.
- Enable a Schedule only with Full Trust acknowledgement and verify the frozen lane
  version.
- Update a Vibe without declaring its Lane and verify the Lane and Schedule pins do
  not move.
- Interrupt an apply before commit and verify no partial metadata is visible;
  verify migration/bootstrap completes before the scheduler starts.
- Add a parity test that compares the app's advertised automation methods with
  the Rust client's declared method mappings.

## Acceptance Criteria

- An agent can create a complete Skill -> Vibe -> Vibe Lane -> Schedule setup using
  only `crispy`, with no direct persistence writes.
- Direct commands and declarative apply produce the same entities the UI reads.
- The same bundle is idempotent and does not bump versions on a no-op.
- Concurrent UI/CLI edits return conflicts rather than overwriting changes.
- Schedules can be validated and previewed without saving.
- New and imported Schedules remain paused by default.
- No Schedule enables after a partial or failed bundle apply.
- Updating a Vibe or Vibe Lane never silently advances downstream pins.
- Full Trust enablement, linked Skill risk, deletion, and partial failure are
  explicit in both human and JSON output.
- Swift unit tests, Rust tests, the CLI/app integration suite, and
  `CrispyVibesUnitTests` pass.

## Recommended Delivery Order

Implement Phase 0 and Phase 1 first. They establish reliable service contracts
and make each entity independently manageable. Then add the Rust commands and
bundle planner. Do not begin with manifest apply on top of the current
best-effort persistence APIs; that would make a polished CLI capable of
producing partially saved automation graphs.
