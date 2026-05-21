# Terminal Inline Triggers — Threat Model

## Overview

Inline triggers accept live user input, inspect terminal-adjacent context, and can insert generated or file-backed text back into a command draft. The main risks are incorrect context resolution, unsafe auto-execution, leaked background resources, and remote/local boundary confusion.

## Trust Boundaries

- User-typed input vs. picker-generated insertions
- Local vibespace filesystem vs. remote SSH filesystem context
- UI process vs. bundled helper process used for local path search
- Saved shortcut definitions vs. active terminal input

## Attack Surfaces

- Live parsing of terminal and compose input
- Helper-process launch and query transport
- Shortcut insertion and prompt-generation insertion
- Remote/local context mapping

## Threats

### F038-T01: Wrong-context path insertion

- Vector: Picker uses stale or incorrect vibespace/session context and inserts a path from the wrong project or host.
- Impact: Commands target the wrong files or wrong machine.
- Likelihood: Medium.
- Mitigation: Bind picker state to the originating surface identity and require token replacement to use that surface's current context.

### F038-T02: Accidental execution through picker confirmation

- Vector: Confirming a picker row sends or executes a command immediately instead of only replacing text.
- Impact: Unexpected command execution.
- Likelihood: Medium.
- Mitigation: Keep all picker actions review-first and require explicit later submission by the user.

### F038-T03: Orphan helper or search work after dismissal

- Vector: Picker-scoped helper processes, observers, or async tasks survive after dismiss or surface teardown.
- Impact: Resource leaks, battery drain, stale updates into dead views.
- Likelihood: Medium.
- Mitigation: Tie helper lifecycle to picker state, stop work on dismiss, and clear subscriptions when the owning surface disappears.

### F038-T04: Untrusted generated text inserted into a terminal draft

- Vector: Built-in generate action returns unsafe or surprising command text.
- Impact: User may later run an unintended command.
- Likelihood: Medium.
- Mitigation: Generated text is inserted for review only, never auto-executed, and remains editable before submission.

## Residual Risks

- Remote SSH path-result parity is still a planned extension, so interim implementations must avoid silently falling back to local path assumptions.
- Large-result path search still requires strict lifecycle discipline to avoid reintroducing memory or responsiveness regressions.

## NFR Compliance

- SEC-1, SEC-3a — see `specs/nfr/security.md`
- REL-1 — see `specs/nfr/reliability.md`
- PERF-3 — see `specs/nfr/performance.md`
