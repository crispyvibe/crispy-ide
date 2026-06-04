# Unified Project Side Panel — Threat Model

## Overview
The unified panel is presentation over existing data; its own risk surface is small. The notable surfaces are the git/worktree operations it triggers (covered by F052) and the file/chat creation it initiates.

## Trust Boundaries
- User input: branch name (New Worktree → F052), new file/folder names (folder explorer), worktree selection.
- Services: `WorktreeServicing` (git), source-control VM (git status/diff), `AgentConversationStore` (RPC), folder explorer (filesystem).

## Attack Surfaces
- Creation actions (New File/Folder, New Agent Chat, New Worktree) routed to existing services.
- Per-project Changes list opening diffs (reuses F026 paths).

## Threats

### F053-T01: Worktree create/delete risks
- Vector/Impact/Mitigation: delegated to F052 (branch-name injection, force-delete data loss, primary-worktree protection). See F052 threat model.

### F053-T02: Acting on the wrong project/worktree
- Vector: the contextual `+` menu's meaning depends on the active view; node actions target a specific worktree.
- Impact: a file/chat created in an unintended worktree.
- Likelihood: Low.
- Mitigation: the active view toggle is visually highlighted; actions are bound to the node's own `project`, and creation operates on the selected worktree's explorer.

### F053-T03: Stale discovery showing removed worktrees
- Vector: cached worktree list after external `git worktree` changes.
- Mitigation: re-probe on vibespace/project-set change and on `.vibespaceWorktreesDidChange`; parser skips prunable/missing entries (F052-T04).

### F053-T04: Performance / main-actor stalls
- Vector: building heavy views or running git on the main actor.
- Mitigation: only the active node body builds; git + thread IO run off the main actor.

## Residual Risks
- Conversation threads are listed by project path; a thread with an empty/foreign path won't appear under a worktree (acceptable).

## NFR Compliance
- SEC-1: no new untrusted input handling beyond F052.
- PERF: lazy bodies + gated re-probe protect the sidebar render budget.
- A11Y: nodes/toggles expose accessibility identifiers.
