# Vibe Lanes — Threat Model

Status: canonical draft · Feature: F059

## Overview

Vibe Lanes runs agent work autonomously through reusable checkpoints. The central
risks are runaway loops, trusting worker self-assessment, reviewer prompt
injection, unsafe human steering, cross-task interference, and corrupted state
replay. The canonical model mitigates these with reviewer verdicts, explicit
bounds, `needsInput` pauses, steer limits, project-level scheduling, and state
validation.

## Trust Boundaries

- **User/author -> Lane definition.** Lane definitions can encode dangerous work,
  weak verification, excessive bounds, ask-user prompts, and escalation behavior.
- **Engine -> Worker.** Worker output is untrusted. It must not decide
  completion or mutate lane verification.
- **Engine -> Reviewer.** Reviewer output is structured but still untrusted until
  parsed. Evidence under review may contain prompt injection.
- **Engine -> Human input.** Supply and Steer answers are trusted as user intent
  but may be malformed, overly broad, or malicious if the UI is driven by another
  local actor.
- **Engine -> Persistence.** Persisted lane/task state must be validated before
  replay.
- **Task -> Task.** Tasks share project files until workspace isolation exists.
- **Agent -> Local system.** ACP trust mode controls command/file blast radius.

## Attack Surfaces

- Lane Work, Verification, Bounds, Contract, steer limit, and ask-user prompts.
- Worker responses and generated files.
- Reviewer prompts, evidence, and parsed verdicts.
- Supply values and Steer guidance.
- Open input request state.
- Persisted JSON state and retained lane revisions.
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

- **Vector:** Files, diffs, test output, or handoffs contain instructions that
  manipulate the reviewer into PASS.
- **Impact:** High — verification bypass.
- **Mitigation:** Reviewer prompt treats evidence as quoted data, requires a
  structured PASS/FAIL, and ambiguous output is FAIL. High-stakes done-when
  definitions should require deterministic checks the reviewer runs.

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
- **Mitigation:** ACP trust mode bounds the process. Reviewer is instructed to be
  read-only, but this is not a hard capability boundary unless ACP provides a
  read-only trust mode or command/path guard. This remains accepted residual risk
  until hardened.

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

## Residual Risks

- Reviewer remains probabilistic and can be wrong.
- Reviewer read-only behavior is currently prompt/policy enforced unless ACP
  grows a technical read-only mode.
- Auto-approved unattended work inherits ACP trust-mode risk.
- Same-project serialization reduces, but does not replace, true per-task
  workspace isolation.
- A local attacker with persistence keys can still forge state.

## NFR Compliance

- **SEC-1** Process Isolation — ACP trust mode bounds agent process behavior.
- **SEC-2** Data at Rest — task/lane state persists through app persistence.
- **SEC-3a** Input Sanitization — reviewer verdicts and input requests are
  structured; evidence and carry-forward are treated as data.
- **REL-1/REL-2/REL-3/REL-4/REL-5** — persisted transitions, resume, validation,
  bounds, and resource caps.
- **OBS-1/OBS-2/OBS-5** — activity logs capture attempts, input requests,
  verification outcomes, and terminal reasons.
