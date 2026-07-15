# Unified Project Side Panel — Spec

Status: draft

## Overview

The Unified Project Side Panel ("Workspace") is its own side-menu rail destination — a peer of the classic Files / Git / Sessions / Conversations tabs — and is the default side-panel layout. Instead of swapping the whole panel between separate tabs, it shows a single per-project view: each project (or git worktree) is a collapsible node whose body shows its Files, Source Control changes, or Conversations via compact in-header view toggles, so a file is reachable with minimal clicks. The Shelf is folded in at the top of the panel. Worktrees of the same repository (identified by `ProjectGitPlacement` worktree-root identity) club together (F055); a subdirectory opened as its own project stands alone.

## Dependencies

- F021 (VibeSpace Projects) — projects, focus, file explorer, add/remove
- F026 (Git Operations) — per-project changed-files (reuses the source-control view model)
- F040 (Agent Conversation Persistence) — per-project conversation threads
- F055 (Git Worktrees) — worktree clubbing, discovery, lifecycle
- F033 (Shelf) — folded into the unified panel, rendered at the top above the project nodes

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
Worktrees of one repository MUST be clubbed under a collapsible "section fence" repository row (lighter than a tree row) with a worktree count. Grouping uses `ProjectGitPlacement` worktree-root identity (`commonDir` + symlink-resolved `worktreeRoot`): only projects opened at a true worktree root club together. A subdirectory opened as its own project — or a non-git folder — MUST render as a standalone node and MUST NOT be clubbed with or mislabeled as the worktree it lives in. Single-checkout/non-repo projects render as a single node (F055-R02).

### F056-R08: Shelf folded in
The Shelf (F033) MUST render inside the unified panel, above the project nodes, when it has entries — reusing the same shelf section/callbacks as the classic Files pane (open, reveal, rename, delete, remove, clear).

### F056-R05: Friendly, Filtered Changes
The Changes view MUST show colored status badges (A/M/D/R/U) — not raw porcelain codes — sorted modified→deleted→renamed→added, and MUST hide OS/tool noise (`.DS_Store`, `Thumbs.db`, `.ipynb_checkpoints/`).

### F056-R06: Creation Affordances
Each worktree node MUST offer creation actions contextual to the active view: Files → New File / New Folder / Refresh; Chats → New Agent Chat. The repository row MUST offer New Worktree… (F055-R04).

### F056-R07: Performance
Only the active view's body builds; collapsed nodes don't load file trees or fetch threads. Worktree/thread discovery re-runs only on vibespace/project-set change or worktree mutation.

### F056-R09: Project & worktree node context menus
Project-root nodes MUST expose the shared `ProjectNodeContextMenu` (F021-R20/R21) — previously they had no context menu. Worktree child nodes MUST show the same navigation actions (Make Current Project, Open in Terminal, Reveal in Finder, New File, New Folder, Copy Path) but substitute **Close Worktree** / **Delete Worktree** (F055) for Park Project / Remove Project.

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

### Scenario F056-S05: Subdirectory project stays standalone
**Given** a repository's worktree is open and a subdirectory of it is also opened as its own project
**When** the unified panel groups projects
**Then** the subdirectory project renders as a standalone node, not clubbed under the repository row, and is not counted among that repo's worktrees.

### Scenario F056-S06: Shelf at the top
**Given** the Workspace panel is showing and the Shelf has entries
**When** the panel renders
**Then** the Shelf section appears above the project nodes with its open/reveal/rename/delete/remove/clear actions.

### Scenario F056-S07: Project root exposes the shared context menu
**Given** the Workspace panel is showing a project-root node
**When** the user right-clicks the node
**Then** the shared `ProjectNodeContextMenu` renders (Make Current Project, Open in Terminal, Reveal in Finder, New File, New Folder, Copy Path, Park Project, Remove Project) — matching the classic Files pane.
**And** for a worktree child node, the same navigation actions appear with Close Worktree / Delete Worktree in place of Park / Remove.

## Acceptance Criteria
- Workspace is its own rail destination and the default side-panel layout; selecting a classic tab exits it
- Per-project nodes with Files/Changes/Chats header toggles; focused auto-expands
- Repositories club worktree roots by `ProjectGitPlacement` identity; subdirectory/non-git projects stay standalone; changes show friendly badges and hide noise
- Shelf rendered at the top of the panel
- New File/Folder/Chat/Worktree available without leaving the panel

## Open Questions
- Fold Sessions into the unified panel (currently classic-only)?
- Per-node "Other worktrees" collapsed dashboard of branch chips (deferred).

## Change History
| Date | Change | Author |
|------|--------|--------|
| 2026-06-04 | Initial draft — opt-in unified per-project sidebar, view toggles, repo clubbing, friendly changes, creation affordances | — |
| 2026-06-19 | Promoted to dedicated "Workspace" rail destination, default-on (R01/S04); Shelf folded in at top (R08/S06); grouping uses `ProjectGitPlacement` worktree-root identity, subdirectory projects standalone (R04/S05); dedicated `UnifiedSidebarViewModel` mediates state | — |
| 2026-07-07 | Project-root nodes now expose the shared `ProjectNodeContextMenu` (previously had none); worktree children use the same navigation actions with Close/Delete Worktree in place of Park/Remove (R09/S07) | — |
