# Vibe Lanes — Threat Model

Status: canonical draft · Feature: F059

## Overview

Vibe Lanes runs agent work autonomously through reusable checkpoints. The central
risks are runaway loops, trusting worker self-assessment, reviewer prompt
injection, unsafe human steering, cross-task interference, and corrupted state
replay. The canonical model mitigates these with reviewer verdicts, explicit
bounds, `needsInput` pauses, steer limits, project-level scheduling, live
engine-option validation, immutable attempt snapshots, and state validation.

## Trust Boundaries

- **User/author -> Lane definition.** Lane definitions can encode dangerous work,
  weak verification, excessive bounds, ask-user prompts, escalation behavior,
  and per-checkpoint agent/model choices. Trust is not authored: all execution
  uses Full Trust.
- **Engine -> Agent capability discovery.** Protocol agents report dynamic
  models/modes; direct integrations use a static catalog. Advertised capability
  data is not proof that the option was applied.
- **Engine -> Worker.** Worker output is untrusted. It must not decide
  completion or mutate lane verification.
- **Engine -> Reviewer.** Reviewer output is structured but still untrusted until
  parsed. Evidence under review may contain prompt injection.
- **Engine -> Human input.** Supply and Steer answers are trusted as user intent
  but may be malformed, overly broad, or malicious if the UI is driven by another
  local actor.
- **Skill package -> Worker/reviewer.** A skill package is executable guidance
  read by a Full Trust agent. Linked packages can be modified outside Crispy
  after authoring and package scripts can perform arbitrary local actions.
- **Engine -> Persistence.** Persisted lane/task state must be validated before
  replay.
- **Task -> Task.** Tasks share project files until workspace isolation exists.
- **Agent -> Local system.** Vibe Lane ACP sessions use Full Trust and
  auto-approve permission requests, giving the agent broad command/file access.

## Attack Surfaces

- Vibe Work, Verification, Bounds, engine settings, and referenced Work/Review
  skills plus lane handoffs, steer limits, and ask-user prompts.
- Skill entrypoints, linked package locations, referenced resources, scripts,
  assets, required-command declarations, and external package mutations.
- Agent/model/mode discovery and session option application.
- Attempt-local rerun engine overrides.
- Worker responses and generated files.
- Reviewer prompts, evidence, and parsed verdicts.
- Supply values and Steer guidance.
- Open input request state.
- Encrypted libSQL metadata, retained revisions, and one-time legacy JSON input.
- Shared project workspace.
- ACP session permissions.

## Threats

### F059-T01: Runaway checkpoint / cost explosion

- **Vector:** Verification never passes and the worker loops indefinitely.
- **Impact:** High — cost and resource exhaustion.
- **Mitigation:** Engine-enforced `maxAttempts` and `timeoutSeconds`. Exhausted
  bounds either stop or create a bounded Steer request. Steer is capped by the
  lane's `steerLimit`; at the limit, the next exhaustion stops.

### F059-T02: Infinite human steering loop

- **Vector:** A checkpoint repeatedly escalates to the user and consumes more
  attempts after every guidance answer.
- **Impact:** Medium-High — cost, fatigue, false sense of progress.
- **Mitigation:** Lane-level `steerLimit`; `steerCount` persisted on the task;
  exhausted bounds at or above the limit stop instead of asking again.

### F059-T03: Worker self-certification

- **Vector:** Worker claims it is done and the engine advances.
- **Impact:** High — silent bad outcomes.
- **Mitigation:** Completion comes only from reviewer PASS against the authored
  Verification. Worker free-form text is never parsed for completion, and worker
  cannot edit Verification or verdict.

### F059-T04: Reviewer prompt injection

- **Vector:** Files, diffs, test output, handoffs, or a referenced Review skill
  contain instructions that manipulate the reviewer into PASS or change files.
- **Impact:** High — verification bypass.
- **Mitigation:** Reviewer prompt treats evidence as quoted data, constrains
  Review skills to inspection and verification, requires a structured PASS/FAIL,
  and treats ambiguous output as FAIL. High-stakes done-when definitions should
  require deterministic checks the reviewer runs. Reviewer read-only behavior
  remains policy-enforced until ACP provides a technical capability boundary.

### F059-T05: Unsafe Supply input

- **Vector:** User-supplied value such as URL, path, token name, or environment
  identifier causes the worker to act on the wrong target or expose data.
- **Impact:** Medium-High.
- **Mitigation:** Supply prompts should be specific about expected format and
  scope. Engine stores values as carry-forward and injects them as data, not
  executable instructions. Lane authors should avoid asking for secrets; if a
  secret is unavoidable, pass a reference/key name rather than the secret value.

### F059-T06: Unsafe Steer guidance

- **Vector:** User guidance tells the worker to bypass verification, delete data,
  or expand scope after repeated failure.
- **Impact:** High.
- **Mitigation:** Steer guidance is injected as feedback, not as a change to Work,
  Verification, or Bounds. Reviewer still gates PASS against the original
  Verification. Steer count is limited.

### F059-T07: Cross-task interference

- **Vector:** Two tasks edit the same project workspace and pollute each other's
  changes or verification.
- **Impact:** High.
- **Mitigation:** Until per-task worktrees exist, scheduler should serialize by
  project path and enforce a conservative global concurrency cap. Task state
  remains independent even when workspace isolation is deferred.

### F059-T08: Unintended destructive command

- **Vector:** Worker or reviewer runs a destructive command with auto-approved
  permissions.
- **Impact:** High.
- **Mitigation:** Full Trust is a deliberate product policy and is visible in
  engine summaries. Checkpoint bounds, independent review, stop controls, and
  per-project serialization limit duration and concurrency, not filesystem
  authority. Reviewer read-only behavior is not a hard capability boundary
  unless ACP provides a read-only mode or command/path guard.

### F059-T09: Tampered or corrupted state replay

- **Vector:** Local actor edits persisted state to skip checkpoints, forge PASS,
  remove an open input request, or lower steer count.
- **Impact:** Medium-High.
- **Mitigation:** Integrity-protected persistence plus replay validation:
  referenced lane revision exists, current checkpoint exists, run records are
  coherent, Needs you has exactly one valid request, other states have no open
  request, and steer count/history are sane.

### F059-T10: Lost open input request on crash

- **Vector:** Crash occurs after task enters Needs you but before request persists.
- **Impact:** Medium — stuck or incorrectly resumed task.
- **Mitigation:** Persist task state and `openInputRequest` in the same transition.
  On restart, `needsInput` tasks remain paused and are not scheduled.

### F059-T11: Sensitive data in records/logs

- **Vector:** Carry-forward, handoffs, reviewer evidence, or activity logs capture
  secrets.
- **Impact:** Medium.
- **Mitigation:** Prefer references over raw secret values. Cap reviewer evidence
  stored in task state. Avoid logging known secret-bearing file contents. Treat
  carry-forward as user/project data subject to data-at-rest controls.

### F059-T12: Stale or misreported engine option

- **Vector:** A lane stores a model/mode that an upgraded or custom agent no
  longer offers, or an agent advertises an option but silently ignores it.
- **Impact:** Medium-High — work runs with a weaker or unintended engine while
  appearing configured.
- **Mitigation:** Discover options per agent; validate an explicit model/mode
  against the connected session; apply it and require the session to report the
  requested value. Stop as an execution error on any mismatch. Persist the live
  session snapshot, not only the authored IDs.

### F059-T13: Capability change through step rerun

- **Vector:** A user reruns one completed step with a more capable agent or
  model, bypassing the lane author's conservative engine choice.
- **Impact:** High — the rerun can modify more files or run broader commands than
  the original attempt.
- **Mitigation:** Rerun is an explicit terminal-task action with a visible engine
  sheet. The override is attempt-local, bounded, recorded in immutable history,
  and does not mutate the lane. Trust cannot be escalated in the sheet because
  all Vibe Lane execution already uses Full Trust.

### F059-T14: Malicious or mutated skill package

- **Vector:** A user imports an untrusted collection, or a linked package changes
  after it was assigned. Its instructions or scripts induce the worker/reviewer
  to expose data, modify unrelated files, or approve invalid work.
- **Impact:** High — skill instructions execute inside Full Trust agent sessions.
- **Mitigation:** The Skills library exposes source and location, separates
  Work/Review eligibility, blocks missing package resources and commands, and
  never executes package scripts during import or readiness scanning. Missing
  entrypoints stop a Run before the worker starts. Users should duplicate a
  reviewed linked package when they need a stable local copy. Package signing,
  content pinning, and script sandboxing remain future controls.

## Residual Risks

- Reviewer remains probabilistic and can be wrong.
- Reviewer read-only behavior is currently prompt/policy enforced unless ACP
  grows a technical read-only mode.
- All lane work is auto-approved Full Trust; checkpoint bounds and review do not
  prevent destructive commands or confine filesystem access.
- Protocol agents that do not expose reasoning controls retain agent-defined
  behavior.
- Same-project serialization reduces, but does not replace, true per-task
  workspace isolation.
- Linked skill contents can change without a Vibe or Vibe Lane version change.
- Skill readiness is structural compatibility checking, not provenance
  verification or execution isolation.
- A local attacker with persistence keys can still forge state.

## NFR Compliance

- **SEC-1** Process Isolation — Full Trust does not provide process isolation;
  this remains an explicit accepted gap pending stronger ACP sandbox controls.
- **SEC-2** Data at Rest — task/lane state persists through app persistence.
- **SEC-3a** Input Sanitization — reviewer verdicts and input requests are
  structured; evidence and carry-forward are treated as data; explicit engine
  options are validated against live session capabilities.
- **REL-1/REL-2/REL-3/REL-4/REL-5** — persisted transitions, resume, validation,
  bounds, and resource caps.
- **OBS-1/OBS-2/OBS-5** — activity logs capture attempts, input requests,
  verification outcomes, and terminal reasons.
