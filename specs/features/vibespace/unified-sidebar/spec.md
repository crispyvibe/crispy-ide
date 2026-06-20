# Unified Project Side Panel — Spec

Status: draft

## Overview

The Unified Project Side Panel is an opt-in sidebar layout that replaces the classic tab-swapped panel (Files / Git / Sessions / Conversations) with a single per-project view. Each project (or git worktree) is a collapsible node whose body shows its Files, Source Control changes, or Conversations via compact in-header view toggles — so a file is reachable with minimal clicks. Repositories with multiple worktrees club their worktrees together (F055).

## Dependencies

- F021 (VibeSpace Projects) — projects, focus, file explorer, add/remove
- F026 (Git Operations) — per-project changed-files (reuses the source-control view model)
- F040 (Agent Conversation Persistence) — per-project conversation threads
- F055 (Git Worktrees) — worktree clubbing, discovery, lifecycle
- F033 (Shelf) — (classic panel only; not yet folded into unified)

## Requirements

### F056-R01: Dedicated Workspace rail destination
The unified layout MUST be its own side-menu rail destination ("Workspace",
`AppSideMenuItem.workspace`), a peer of Files / Git / Sessions / Conversations —
not a mode squeezed into the Files explorer. The Workspace panel is the default
side-panel layout (`AppShellStore.vibespaceSidebarUnified` default on); selecting
any classic rail tab exits it, and selecting Workspace re-enters it.

### F056-R02: Per-project Nodes
Each project MUST render as a collapsible node showing Files / Changes / Chats for that project, not as global cross-project sections.

### F056-R03: View Toggles (no tab-strip row)
A worktree node MUST expose Files / Changes / Chats as compact toggles in its header (with counts), defaulting to Files. Switching is one click; the active view fills the node body. The focused project's node auto-expands so its files are visible with zero clicks.

### F056-R04: Repository Grouping
Worktrees of one repository MUST be clubbed under a collapsible "section fence" repository row (lighter than a tree row) with a worktree count; single-checkout/non-repo projects render as a single node (F055-R02).

### F056-R05: Friendly, Filtered Changes
The Changes view MUST show colored status badges (A/M/D/R/U) — not raw porcelain codes — sorted modified→deleted→renamed→added, and MUST hide OS/tool noise (`.DS_Store`, `Thumbs.db`, `.ipynb_checkpoints/`).

### F056-R06: Creation Affordances
Each worktree node MUST offer creation actions contextual to the active view: Files → New File / New Folder / Refresh; Chats → New Agent Chat. The repository row MUST offer New Worktree… (F055-R04).

### F056-R07: Performance
Only the active view's body builds; collapsed nodes don't load file trees or fetch threads. Worktree/thread discovery re-runs only on vibespace/project-set change or worktree mutation.

## Scenarios

### Scenario F056-S01: Zero-click focused files
**Given** unified mode with a focused project
**When** the panel appears
**Then** the focused worktree is expanded showing its file tree, no clicks required.

### Scenario F056-S02: Switch a node's view
**Given** an expanded worktree on Files
**When** the user taps the Changes toggle
**Then** the body swaps to that worktree's changed-files list (badges, noise filtered).

### Scenario F056-S03: Create from the node
**Given** a worktree on the Files view
**When** the user uses the node's + → New File
**Then** a new file is created in that worktree's tree.

### Scenario F056-S04: Workspace is a separate rail destination
**Given** the classic Files explorer is showing
**When** the user selects the Workspace rail item
**Then** the panel shows the unified per-project layout; selecting Files (or any
classic tab) returns to the classic layout. The two never share one panel.

## Acceptance Criteria
- Unified is opt-in; classic untouched when off
- Per-project nodes with Files/Changes/Chats header toggles; focused auto-expands
- Repositories club worktrees; changes show friendly badges and hide noise
- New File/Folder/Chat/Worktree available without leaving the panel

## Open Questions
- Fold Sessions and Shelf into the unified panel (currently classic-only)?
- Per-node "Other worktrees" collapsed dashboard of branch chips (deferred).
- A dedicated `UnifiedSidebarViewModel` to fully mediate state (currently the panel holds view state and calls the injected `WorktreeServicing` directly).

## Change History
| Date | Change | Author |
|------|--------|--------|
| 2026-06-04 | Initial draft — opt-in unified per-project sidebar, view toggles, repo clubbing, friendly changes, creation affordances | — |
