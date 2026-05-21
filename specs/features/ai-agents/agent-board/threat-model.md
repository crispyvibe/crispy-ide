# Agent Board — Threat Model

## Overview

The Agent Board is a vision-stage coordination surface for multi-phase agent work. It orchestrates workflows across agent conversations, terminal runs, and source-control state. Because it delegates to existing subsystems (ACP sessions, terminal infrastructure, git operations), its own threat surface is limited to workflow state integrity and UI-level trust decisions. It performs no direct network I/O.

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Board UI ↔ ACP Sessions | Board cards reference agent conversations by ID. The board trusts that ACP session data has not been tampered with. |
| Board UI ↔ Terminal Infrastructure | Verification phases spawn terminal runs. Commands are passed through the existing terminal session layer, not constructed by the board itself. |
| Board UI ↔ Git State | Review phases read source-control status via the shared `GitExploring` protocol. The board does not execute git mutations directly. |
| Board persistence ↔ Disk | Board layout and card state are serialized to the vibespace config directory. |

## Attack Surfaces

1. **Workflow template catalog** — built-in and project-default templates define phase sequences. A malicious template could prescribe dangerous automation policies.
2. **Card artifact links** — cards link to conversations, terminal runs, and source-control artifacts by reference. Spoofed references could mislead the user about what was actually verified.
3. **Automation policy execution** — phase advancement policies determine when a card auto-advances. Overly permissive policies could skip human review gates.
4. **Board persistence file** — serialized board state on disk could be modified by another process to inject misleading workflow status.

## Threats

### F011-T01: Malicious workflow template injects unreviewed automation

- **Vector:** A project-level workflow template override (stored in the project directory) defines `autoAdvance: true` for verification and review phases, causing the board to skip human checkpoints.
- **Impact:** Code changes proceed without user review; potential for undetected regressions or malicious modifications.
- **Likelihood:** Low — requires write access to the project directory.
- **Mitigation:** Automation policies MUST default to manual advancement for review and verification phases. Any template that sets `autoAdvance` on security-sensitive phases MUST surface a confirmation prompt before first use. Linked NFR: SEC-Input-Sanitization.

### F011-T02: Artifact link spoofing via tampered persistence

- **Vector:** An attacker with local file access modifies the board's serialized state to point card artifact links at different conversations or terminal outputs, making it appear that verification passed when it did not.
- **Impact:** User trusts a false verification status; ships unverified code.
- **Likelihood:** Very low — requires local file system access as the same user.
- **Mitigation:** Board state files SHOULD use the same HMAC-signed JSON persistence as other vibespace config. Artifact links MUST be validated against live session registry before displaying "verified" status. Linked NFR: SEC-Data-Protection.

### F011-T03: Resource exhaustion via unbounded card creation

- **Vector:** A runaway automation or user script creates thousands of work cards, exhausting memory and making the board unusable.
- **Impact:** App performance degradation, potential hang.
- **Likelihood:** Low.
- **Mitigation:** Enforce a maximum active card count per board (e.g., 200). Archive cards beyond the limit automatically. Linked NFR: PERF-Responsiveness.

### F011-T04: UI spoofing of phase completion status

- **Vector:** Board renders phase status from persisted state without re-validating. A stale or corrupted state file could show "review complete" for a card whose underlying git state has diverged.
- **Impact:** False confidence in code review status.
- **Likelihood:** Low — state is written by the app itself.
- **Mitigation:** Phase completion indicators MUST be re-validated against live subsystem state (git status, conversation existence) when the board is restored from persistence. Stale indicators MUST show a "needs refresh" badge. Linked NFR: SEC-Data-Protection.

## Residual Risks

- The board delegates security-critical operations (command execution, git mutations) to other subsystems. Threats in those subsystems are covered by their own threat models.
- A user with local file access can always manipulate board state; this is inherent to local-only apps.

## NFR Compliance

| NFR | Status | Notes |
|-----|--------|-------|
| SEC-Input-Sanitization | Compliant | Templates validated; automation policies gated. |
| SEC-Data-Protection | Compliant | HMAC-signed persistence; live validation on restore. |
| PERF-Responsiveness | Compliant | Card count capped; archival enforced. |
| A11Y | N/A | Vision stage — accessibility reviewed at implementation. |
| OBS | Compliant | Board state transitions logged via existing diagnostics. |
