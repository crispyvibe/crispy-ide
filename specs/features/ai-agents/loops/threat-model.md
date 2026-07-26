# Schedules — Threat Model

## Overview

F061 converts a saved schedule into unattended Vibe Lane execution. Its primary
risks are unintended authority, duplicate/costly execution, stale project or
lane targets, persistence tampering, and resource exhaustion. Agent execution
itself inherits F059 and ACP threat boundaries.

## Trust Boundaries

- **User configuration to scheduler:** names and instructions are untrusted
  authored data; project paths and schedules control execution context.
- **Scheduler to Vibe Lane engine:** a due occurrence crosses from passive
  persisted state into active agent work.
- **Lane snapshot to tools:** all checkpoints execute with Full Trust, so the
  lane can edit files and run commands without permission prompts.
- **Database to runtime:** Schedule (`automation_loops`) rows or serialized
  payloads can be stale, corrupt, or modified by another process running as the
  same user.
- **Wall clock to occurrence claim:** sleep, DST, manual clock changes, and
  process crashes can repeat or omit apparent times.

## Attack Surfaces

- Schedule editor and persisted task instructions.
- Local project-directory selection and later path/symlink changes.
- Full-trust enable and quick actions.
- Wake/activation/clock notification reconciliation.
- Encrypted libSQL state and one-time migration from legacy JSON documents.
- Deterministic task-origin recovery.
- Linked lane lifecycle reconciliation used for overlap and attention status.

## Threats

### F061-T01: Unintended full-trust execution

- **Vector:** A user enables a schedule whose frozen lane can run commands or
  edit files without per-command approval.
- **Impact:** High.
- **Likelihood:** Medium.
- **Mitigation:** Every enabled Schedule requires an explicit unattended Full Trust
  confirmation in both editor and quick-enable paths. The dashboard shows the
  lane and target project; users can pause at any time. F059 bounds, review,
  concurrency, and stop controls remain active.

### F061-T02: Duplicate occurrence after crash or clock rollback

- **Vector:** Crispy crashes between claim and task linkage, or the system clock
  moves backward across a prior occurrence.
- **Impact:** Medium: repeated edits, commands, or agent/API cost.
- **Likelihood:** Medium without controls.
- **Mitigation:** Persist the claim and pending run before creation; derive a
  deterministic occurrence UUID; commit the claim and pending record together;
  store the occurrence in `VibeLaneTaskOrigin`; require the lane revision and
  task record to be durable before execution; make task creation idempotent;
  recover pending links on bootstrap; require due dates to be strictly later
  than the persisted claim. Paused definitions do not recover pending work
  until the user explicitly enables them.

### F061-T03: Target path substitution

- **Vector:** A selected directory is removed and replaced, or a symlink changes
  to point outside the originally intended project.
- **Impact:** High if unattended work runs in a different directory.
- **Likelihood:** Low.
- **Mitigation:** Standardize and resolve symlinks on save; require an existing
  directory before each trigger; block invalid targets. Residual risk remains
  for same-path replacement after validation, inherited from local filesystem
  ownership.

### F061-T04: Persisted schedule or instruction tampering

- **Vector:** Another same-user process tampers with the Automation database to
  increase frequency, change instructions, or select a more powerful Lane
  snapshot.
- **Impact:** Medium–High.
- **Likelihood:** Low.
- **Mitigation:** Decode typed Codable schemas, enforce SQL constraints and
  foreign keys, reject corrupt state, validate recurrence/project/Lane before
  triggering, enforce the 15-minute minimum in the model, and commit complete
  Schedule state transactionally. Residual: a same-user process already shares the
  user's filesystem authority.

### F061-T05: Resource and cost exhaustion

- **Vector:** Many frequent Schedules become due together or a user repeatedly uses
  Run Now.
- **Impact:** Medium.
- **Likelihood:** Medium.
- **Mitigation:** 15-minute scheduled minimum, one active task per Schedule,
  Vibe Lane global concurrency cap, per-project serialization, bounded run
  history, and one catch-up occurrence rather than replaying the backlog. Schedule
  state is reconciled from the canonical linked lane task on every publication
  and bootstrap rather than trusting a stale history label. Residual: Run Now is
  intentionally not rate-limited.

### F061-T09: Cancellation completion corrupts newer state

- **Vector:** A stopped run or application shutdown cancels an engine task, but
  its asynchronous completion arrives after a replacement run starts or while
  teardown is releasing sessions.
- **Impact:** Medium: a live run can lose its scheduling slot, queued work can
  start during shutdown, or a resumable task can be persisted as stopped.
- **Likelihood:** Medium without generation ownership.
- **Mitigation:** Every task run owns a generation token. Stop, delete, rerun,
  and shutdown invalidate older generations; stale completions cannot mutate
  task state or clear a replacement slot. Shutdown disables queue scheduling
  before cancellation.

### F061-T06: Frozen vulnerable lane persists

- **Vector:** A source Vibe or lane is corrected, but an existing Lane or Schedule
  continues using its older pinned revision.
- **Impact:** Medium.
- **Likelihood:** Medium.
- **Mitigation:** Frozen snapshots prevent silent privilege expansion. The Lane
  designer flags newer Vibe versions, and Automation flags newer Lane versions
  for Schedules. The user must first adopt the Vibe in the Lane and then choose
  Update Lane for the Schedule; the latter confirms the old/new versions and the
  new full-trust stage route. Residual: the user may leave an unsafe old
  revision scheduled.

### F061-T07: Persistence failure launches unclaimed work

- **Vector:** Disk failure prevents a complete Schedule mutation, runtime claim,
  lane revision, or task record from being durably written.
- **Impact:** Medium through possible replay.
- **Likelihood:** Low.
- **Mitigation:** Async store APIs report commit failure. The Schedule manager
  updates published state only after the database transaction commits, and task
  creation proceeds only after the pending claim, exact Lane revision, and task
  record are durable. Failures stop dispatch and are surfaced in the UI.
  Deterministic origins provide recovery if a later linkage write fails.

### F061-T08: Misleading schedule around DST

- **Vector:** A nonexistent or repeated local time surprises the user.
- **Impact:** Low.
- **Likelihood:** Medium.
- **Mitigation:** Store and display the IANA time zone, use Foundation calendar
  matching, advance nonexistent times, and choose only the first repeated time.
  DST behavior has regression tests.

## Residual Risks

- Exact execution is unavailable while Crispy is quit.
- Same-user persistence tampering and same-path directory replacement are not
  prevented by OS isolation.
- Run Now has no separate rate limit beyond Vibe Lane capacity controls.
- A scheduled wake delayed by more than 60 seconds is treated as missed work;
  Skip missed runs may therefore skip under prolonged process suspension.

## NFR Compliance

- **SEC-2:** State is kept in the OS application-support directory. Integrity
  verification is not yet implemented and remains an explicit residual gap.
- **SEC-3a:** Typed decoding and schedule/path/lane validation.
- **SEC-5:** Full Trust confirmation and inherited ACP/Vibe Lane execution
  boundaries.
- **SEC-7:** Explicit local project directory and validation before trigger.
- **REL-1 / REL-2:** Acknowledged atomic state commits, fail-closed decoding,
  durable task creation, legacy migration, and pending recovery.
- **REL-4:** Minimum interval, overlap guard, concurrency caps, bounded history.
- **REL-5:** Deterministic occurrences and idempotent task origin.
- **REL-6:** Scheduler and generation-invalidating task-manager shutdown from
  `AppDelegate`.
- **OBS-1 / OBS-5:** Persistence failures use the legacy `loops` OSLog category
  and are surfaced on the Schedules surface and failed action.
- **A11Y-1 / A11Y-2 / A11Y-6:** Labeled controls, keyboard-native form controls,
  and stable accessibility identifiers for primary workflows.
- **TEST-2 / TEST-3 / TEST-4:** Pure schedule calculator, injected clock/store,
  in-memory stores, and isolated temporary project folders.
