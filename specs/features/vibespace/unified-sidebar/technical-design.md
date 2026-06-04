# Unified Project Side Panel — Technical Design

## Overview

The unified layout is rendered by the existing `VibeSpaceSidebarPanelView` when `AppShellStore.vibespaceSidebarUnified` is true. It composes per-project/worktree nodes instead of the classic tab `switch`. Worktree discovery/grouping comes from `WorktreeServicing` (F055); the node views reuse existing file-tree, source-control, and conversation pieces.

## Architecture

```
ContentView
  └─ vibespaceSidebarPanel (ContentViewUnifiedSidebarActions.swift)
       └─ VibeSpaceSidebarPanelView (ContentViewVibeSpaceSidebar.swift)
            ├─ classic: switch on sidebarTab → Files/Git/Sessions/Conversations panes
            └─ unified: ForEach(unifiedProjectGroups)
                 ├─ VibeSpaceRepositoryNodeView   (clubbed worktrees + Other worktrees)
                 └─ VibeSpaceWorktreeNodeView      (single project or a worktree child)
                       └─ Files (ProjectFileTreeView) | Changes | Chats + header view-toggles + create menu
```

Files:
- `ContentViewVibeSpaceSidebar.swift` — `VibeSpaceSidebarPanelView` (classic + unified bodies, grouping `unifiedProjectGroups`, `reloadUnified`).
- `ContentViewUnifiedSidebarActions.swift` — `extension ContentView`: panel construction + handlers (`newChat`, `newWorktree`, `deleteWorktree`, file/folder actions).
- `VibeSpaceWorktreeNodeView.swift` — collapsible node; header toggles + contextual `+` menu + Close/Delete context menu.
- `VibeSpaceRepositoryNodeView.swift` — collapsible repo "section fence"; clubbed worktree children + "Other worktrees" + New Worktree.
- `UnifiedSidebarModels.swift` — `UnifiedProjectGroup` + worktree value types.

## Data Flow
- `unifiedProjectGroups` groups `activeVibeSpaceProjects` by `worktreeInfoByProject[…].commonDir`; computes title, `otherWorktrees` (repo worktrees minus added), and `primaryPath`.
- `reloadUnified()` (on `.task` keyed by vibespace+project-set, and `.onReceive(.vibespaceWorktreesDidChange)`) syncs source control, loads threads (`thread.list` grouped by project path), and probes worktrees.
- Node bodies: Files = `ProjectFileTreeView(project.folderExplorer)`; Changes = matching `VibeSpaceSourceControlRepositoryViewModel.statusItems` filtered/sorted/badged; Chats = `unifiedThreadsByProject[path]`.

## API / Command Contracts
- `AppShellStore.setVibeSpaceSidebarUnified(_:)`; `showVibeSpaceSidebar(_:)` clears unified.
- Notifications: `.removeProjectRequested` (Close), `.vibespaceWorktreesDidChange` (re-probe after worktree mutation).
- Creation reuses `folderExplorer.createNewFile/Folder/refreshTree`, `contentViewerStore.openACPPane`, and `addProjectsViaCLI` (open worktree / open created worktree).

## State Management
Panel `@State`: `unifiedThreadsByProject`, `worktreeInfoByProject`, `worktreesByCommonDir`. Node-local `@State`: `isExpanded`, `activeTab` (Files/Changes/Chats). `vibespaceSidebarUnified` is `@Published private(set)` on `AppShellStore`, mutated via setter.

## Dependencies
`WorktreeServicing` (F055), source-control VM (F026), `AgentConversationStore` (F040), folder explorer (F024), `ProjectFileTreeView`.

## Platform Considerations
macOS; AppKit `NSAlert`/`NSTextField` for the new-worktree prompt + delete confirmation, presented from the ContentView extension.

## Performance Constraints
Only the active view body builds; collapsed nodes are header-only. Re-probe gated to vibespace/project-set change or worktree mutation; git + thread IO off the main actor.

## Migration / Rollout Notes
Opt-in (default off); the classic layout is unchanged. No persistence changes.
