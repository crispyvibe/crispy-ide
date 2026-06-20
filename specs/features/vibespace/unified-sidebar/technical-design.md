# Unified Project Side Panel — Technical Design

## Overview

The unified layout is rendered by `VibeSpaceSidebarPanelView` when `AppShellStore.vibespaceSidebarUnified` is true (the default). The "Workspace" rail item (`AppSideMenuItem.workspace`, `square.grid.2x2`) is its own side-menu destination: selecting it enters the unified layout; selecting any classic tab (Files/Git/Sessions/Conversations) exits it. The panel composes per-project/worktree nodes instead of the classic tab `switch`, with the Shelf folded in at the top. Worktree discovery/grouping comes from `WorktreeServicing` (F055) via `UnifiedSidebarViewModel`; the node views reuse existing file-tree, source-control, and conversation pieces.

## Architecture

```
ContentView
  └─ HomeAppSideMenuRailView (ContentViewToolbar.swift)
       ├─ Workspace rail item → showWorkspaceSidebar() → setVibeSpaceSidebarUnified(true)
       └─ Files/Git/Sessions/Conversations → showProjectSidebar(_:) → setVibeSpaceSidebarUnified(false)
  └─ vibespaceSidebarPanel (ContentViewUnifiedSidebarActions.swift)
       └─ VibeSpaceSidebarPanelView (ContentViewVibeSpaceSidebar.swift)
            ├─ classic: switch on sidebarTab → Files/Git/Sessions/Conversations panes
            └─ unified: ScrollView { LazyVStack
                 ├─ ShelfSidebarSectionView           (Shelf at top, when non-empty)
                 └─ ForEach(unifiedProjectGroups)
                      ├─ VibeSpaceRepositoryNodeView   (clubbed worktree roots + Other worktrees)
                      └─ VibeSpaceWorktreeNodeView      (single project or a worktree child)
                            └─ Files (ProjectFileTreeView) | Changes | Chats + header view-toggles + create menu
            }
```

The header unified/classic toggle (`onToggleUnified`) was removed — the rail owns the choice. `HomeShellContext.activeAppSideMenuItem` returns `.workspace` whenever `vibespaceSidebarUnified` is true, so the rail highlights Workspace.

Files:
- `ContentViewVibeSpaceSidebar.swift` — `VibeSpaceSidebarPanelView` (classic + unified bodies, Shelf section, grouping `unifiedProjectGroups`, `branchByProject`, `nodeTypeIcon`, `reloadUnified`). Observes `AgentConversationStore` so `threadChangeCounter` bumps reload newly created threads.
- `ContentViewUnifiedSidebarActions.swift` — `extension ContentView`: panel construction + handlers (`newChat`, `newWorktree`, `deleteWorktree`, file/folder actions).
- `ContentViewToolbarActions.swift` — `showWorkspaceSidebar()` (enter unified) and `showProjectSidebar(_:)` (classic tab selection now also exits unified).
- `UnifiedSidebarViewModel.swift` — `@MainActor ObservableObject` mediating state: `@Published placementByProject`, `worktreesByCommonDir`, `threadsByProject`; `reload`, `reloadThreads`, `addWorktree`.
- `VibeSpaceWorktreeNodeView.swift` — collapsible node; segmented Files/Changes/Chats toggle cluster + contextual `+` menu + Close/Delete context menu; `vibespaceHoverHighlight()` on every interactive control.
- `VibeSpaceRepositoryNodeView.swift` — collapsible repo "section fence"; clubbed worktree children + "Other worktrees" + New Worktree.
- `UnifiedSidebarModels.swift` — `ProjectGitPlacement`, `WorktreeEntry` (+ `canonicalPath`, `notOpened(_:openedCanonicalPaths:)`), `WorktreeProbeResult`, `UnifiedProjectGroup`.

## Data Flow
- `unifiedProjectGroups` groups `activeVibeSpaceProjects` by `placementByProject[…].commonDir`, but **only for projects at a true worktree root** (`ProjectGitPlacement.isWorktreeRoot`). Subdirectory projects and non-git folders are always standalone. Each group computes title, `otherWorktrees` (repo worktrees minus opened roots, via `WorktreeEntry.notOpened` matching canonical symlink-resolved paths case-insensitively for APFS), and `primaryPath`.
- `branchByProject` is derived once from `worktreesByCommonDir` (indexed by common dir + lowercased canonical worktree root) — branch is read from the authoritative porcelain worktree list, never a per-project query, so a subdirectory project and its worktree never disagree.
- `nodeTypeIcon` renders `shippingbox.fill` for a worktree root vs `folder.fill` for a standalone project so the two never look alike.
- `UnifiedSidebarViewModel.reload()` (on `.task` keyed by vibespace+project-set, and `.onReceive(.vibespaceWorktreesDidChange)`) syncs source control, loads threads (`thread.list` grouped by project path), and probes worktrees. `reloadThreads()` runs on `agentConversationStore.threadChangeCounter` changes to surface new ACP threads immediately without re-probing git.
- Node bodies: Files = `ProjectFileTreeView(project.folderExplorer)`; Changes = matching `VibeSpaceSourceControlRepositoryViewModel.statusItems` filtered/sorted/badged; Chats = `threadsByProject[path]`.
- New Agent Chat is presented through `VibeSpaceCanvasActionsCoordinator.present(.agentChat(…))`, which consults `ContentSurfacePolicy` (ADR-003) for the surface rather than forcing a layout.

## API / Command Contracts
- `AppShellStore.setVibeSpaceSidebarUnified(_:)`; `vibespaceSidebarUnified` defaults to `true`. `showVibeSpaceSidebar(_:)` shows the sidebar for a classic tab.
- `ContentView.showWorkspaceSidebar()` enters/toggles the unified panel (rail item); `showProjectSidebar(_:)` selects a classic tab and exits unified.
- `AppSideMenuItem.workspace` (`square.grid.2x2`); rail wired via `onWorkspace: showWorkspaceSidebar`. `HomeShellContext.activeAppSideMenuItem` returns `.workspace` when unified is active.
- Notifications: `.removeProjectRequested` (Close), `.vibespaceWorktreesDidChange` (re-probe after worktree mutation).
- Creation reuses `folderExplorer.createNewFile/Folder/refreshTree`, `contentViewerStore.openACPPane`, and `addProjectsViaCLI` (open worktree / open created worktree). New Agent Chat goes through `VibeSpaceCanvasActionsCoordinator.present(_:)`.

## State Management
`UnifiedSidebarViewModel` (`@MainActor ObservableObject`) owns `@Published private(set)` `placementByProject` (`[String: ProjectGitPlacement]`), `worktreesByCommonDir`, and `threadsByProject`; the panel reads them via forwarders so the View never touches services directly. Node-local `@State`: `isExpanded`, `activeTab` (Files/Changes/Chats). `vibespaceSidebarUnified` is `@Published private(set)` on `AppShellStore`, mutated via setter. The panel `@ObservedObject`s `AgentConversationStore` to react to `threadChangeCounter`.

## Dependencies
`WorktreeServicing` (F055), source-control VM (F026), `AgentConversationStore` (F040), folder explorer (F024), `ProjectFileTreeView`.

## Platform Considerations
macOS; AppKit `NSAlert`/`NSTextField` for the new-worktree prompt + delete confirmation, presented from the ContentView extension.

## Performance Constraints
Only the active view body builds; collapsed nodes are header-only. Re-probe gated to vibespace/project-set change or worktree mutation; git + thread IO off the main actor.

## Migration / Rollout Notes
The unified "Workspace" panel is now the default side-panel layout (`vibespaceSidebarUnified` default `true`); the classic tabs remain reachable via their rail items and are unchanged in behavior. No persistence changes.
