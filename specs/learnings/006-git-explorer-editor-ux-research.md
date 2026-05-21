# Git, Explorer, and Editor UX Research

Status: Active
Last Updated: 2026-03-04
Owner: Engineering
Scope: `specs/features/sidebar/*`, `specs/features/editor/code/feature.md`, `projects/crispyvibes/crispyvibes/Features/VibeSpace/*`, `projects/crispyvibes/crispyvibes/Features/Editor/Views/*`

## Purpose

Document the UX patterns used for recent Git workflow, folder explorer visibility, and editor line-number planning, with references to mature editor behavior.

Feedback triage log: (archived — all items completed)

## Validation Snapshot (2026-03-04)

- `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/FolderExplorerViewContent.swift`: staged/unstaged sections, branch menu, history actions, row-level stage/unstage actions.
- `projects/crispyvibes/crispyvibes/Features/VibeSpace/ViewModels/FolderExplorerViewModelActions.swift`: stage/unstage/commit/push/checkout mutations with focused operation flows.
- `projects/crispyvibes/crispyvibes/Features/VibeSpace/Services/PaneWorkerExecutorGit.swift`: narrow Git commands per mutation and `git check-ignore --stdin`.
- `projects/crispyvibes/crispyvibes/Features/VibeSpace/Views/FolderExplorerFileTreeRow.swift`: de-emphasis styling for git-ignored entries.
- `projects/crispyvibes/crispyvibes/Features/Editor/Views/CodeEditorView.swift` and `projects/crispyvibes/crispyvibes/Features/Editor/Views/PlainTextEditor.swift`: no line-number gutter implementation yet.

## Primary References

- Reference IDE Source Control overview (SCM panel layout, staging workflow, inline diff)
- Reference IDE Git branches/worktrees documentation (branch management, worktree support)
- Reference IDE repositories/remotes view documentation (multi-repo, remote tracking)
- Reference IDE update notes on Git decorations in Explorer (file-level change badges)
- Reference IDE update notes on `explorer.excludeGitIgnore` setting (ignore-based filtering)
- Reference IDE update notes on optimistic Source Control updates (instant UI feedback)
- Reference IDE update notes on Source Control view information architecture (panel reorganization)

## Adopted UX Patterns

### 1. Single-pane SCM workflow with clear action hierarchy

Pattern:
- Keep frequent actions near status list: stage/unstage, stage all, commit, push, refresh.
- Keep stateful controls (branch, history) in a compact top strip.

Applied in CrispyVibes:
- Git pane now has branch menu, history action, refresh action, commit composer, and per-row stage/unstage/file-history actions.
- Operation feedback is inline via lightweight status row.

### 2. Explicit separation of staged vs unstaged state

Pattern:
- Split changes into staged and unstaged sections for quick mental parsing.
- Preserve status badges for file-level change semantics.

Applied in CrispyVibes:
- Git list renders `Staged` and `Changes` sections.
- Rows compute capabilities from index/worktree status and show context actions accordingly.

### 3. Branch visibility and quick checkout

Pattern:
- Show current branch persistently.
- Support quick local/remote checkout from one menu.

Applied in CrispyVibes:
- Branch menu surfaces current branch and checkout targets (local + remote).
- Checkout triggers status/branch refresh after mutation.

### 4. Lightweight history surfaces

Pattern:
- Repository history and file-specific history should be discoverable but non-blocking.
- History details should prioritize scannability: subject, hash, author, date.

Applied in CrispyVibes:
- Repository and file history are loaded on demand into a sheet.
- History list uses compact metadata-first rows.

### 5. Explorer visibility policy for hidden and ignored paths

Pattern:
- Hidden files are often useful in developer workflows and should be visible by default in IDE contexts.
- Ignored paths should be de-emphasized rather than always removed, preserving discoverability.

Applied in CrispyVibes:
- Dot/hidden entries now remain in explorer tree.
- Git-ignored entries are flagged and visually softened.

## Planned UX Patterns (Not Yet Shipped)

### 6. Line-number gutter as a persistent code affordance

Pattern:
- Code editing should always include a stable line-number gutter.
- Gutter width should scale with line count to avoid jitter and clipping.

Current status in CrispyVibes:
- Not implemented yet in current code editor and plain-text editor views.

## Performance Rules Applied

- Use narrow Git commands for each mutation (`stage`, `unstage`, `commit`, `push`, `checkout`) instead of broad refresh-only actions.
- Batch ignore checks via one `git check-ignore --stdin` call for immediate children.
- Cache line starts and only recompute line metrics when text length changes.
- Load history lazily (sheet open) instead of prefetching on every refresh.

## Deferred UX Work (Not in this change)

- Commit graph UI inside CrispyVibes (current implementation is list history, not graph visualization).
- Bulk multi-select Git actions in sidebar.
- Explorer setting toggle for show/hide ignored entries (currently always shown with de-emphasis).
- Line-number gutter for code and plain-text editors.
