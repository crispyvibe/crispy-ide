# Project Enhancements — Planning

Date: 2026-06-02 (updated 2026-06-03)
Status: draft (planning)
Author: research + plan

## Intent Analysis

Originally three enhancements were requested:

1. ~~**CLI add/remove projects**~~ — **shipped**.
2. ~~**Context-menu "Remove Project"** (active + parked)~~ — **shipped**.
3. **Worktrees + unified side panel** — (a) git worktree support for projects, and (b) consolidate Files, Git, and Agent Chats into a **single** side panel instead of three tab-switched sidebars.

This document now tracks only the remaining work: Git Worktrees and the Unified Project Side Panel.

> **Shipped (2026-06-03):** CLI project lifecycle was completed — `crispy vibespace activate-project` / `list-projects` added alongside the existing `add/remove/park` (F044-R83/R84). Context-menu **Remove Project** was added for both active (F021-R18) and parked (F021-R19) projects, with no confirmation prompt. Canonical specs live in `specs/features/vibespace/projects/` (F021) and `specs/features/platform/agent-cli/` (F044); both are covered by unit tests. These items were removed from this planning doc.

## Remaining Work

| Item | Current state | Work needed |
|---|---|---|
| Unified side panel | The sidebar is **already one panel** (`VibeSpaceSidebarPanelView`) that *swaps* content by `AppShellStore.vibespaceSidebarTab` (`.files`/`.git`/`.sessions`/`.conversations`), toggled by the activity-bar rail. User wants all of it visible together (no tab switching). | Recompose the panel into stacked collapsible sections reusing existing panes; repurpose rail buttons as scroll-to anchors. New feature **F053**. |
| Worktrees | **No** app feature. Only the dev script `scripts/create-worktree.sh`. Git runs via `git -C <path> …` in `PaneWorkerExecutorGitCommands`. | Add `worktree add/list/remove` executor + UI in the Git section; opening a worktree reuses the existing `addProjects` flow. New feature **F052**. |

Feature numbering (per `specs/features/INDEX.md`, next prefix is **F052**):
- **F052 — Git Worktrees** (D6 Source Control)
- **F053 — Unified Project Side Panel** (D1 App Shell / D5 Explorer)

---

## Git Worktrees (new feature F052)

### Current behaviour
- **No** in-app worktree feature. Only the developer script `scripts/create-worktree.sh` (sets up a build-ready worktree of the IDE repo itself).
- Git actions run through `Features/VibeSpace/Services/PaneWorker/PaneWorkerExecutorGitCommands.swift` as `git -C <rootURL.path> <verb> …` (stage/commit/push/pull/fetch/checkoutGitBranch/discard).
- Repositories are discovered per project by `VibeSpaceSourceControlViewModel` (multi-repo aware); branch UI lives in `VibeSpaceSourceControlView` / repository view models.

### Proposed requirements

- **F052-R01 — List worktrees.** For a repository, the app MUST list existing worktrees via `git -C <repo> worktree list --porcelain` (path, branch, HEAD, locked/bare flags).
- **F052-R02 — Add worktree.** The app MUST create a worktree via `git -C <repo> worktree add [-b <new-branch>] <path> [<commit-ish>]`, supporting (a) new branch and (b) existing branch checkout. Inputs validated (non-empty path, path not existing/occupied).
- **F052-R03 — Open worktree as project.** After creating (or from the list), the user MUST be able to open a worktree directory as a project in the active vibespace. **Reuse `VibeSpaceState.addProjects(from:)`** — a worktree is just a directory; no new project model needed.
- **F052-R04 — Remove worktree.** The app MUST remove a worktree via `git -C <repo> worktree remove <path>` (with `--force` only after explicit confirmation when dirty). If that worktree is open as a project, offer to remove the project too (reuses the shipped F021-R18 removal path).
- **F052-R05 — Prune.** Provide `git worktree prune` for stale administrative entries (optional / behind a menu).
- **F052-R06 — Surface in Git UI.** Worktree actions MUST live in the Source Control section near the branch menu (e.g., a "Worktrees" submenu: list / new / remove), consistent with existing branch UX (F026-R08).
- **F052-R07 — Errors.** Worktree command failures MUST surface as structured, user-facing messages (reuse `PaneWorkerError.workerFailure` + `gitCommandErrorDetail`).

### Design / code changes
- New executor methods in `PaneWorkerExecutorGitCommands.swift`: `listGitWorktrees`, `addGitWorktree`, `removeGitWorktree`, `pruneGitWorktrees` (+ a porcelain parser, mirroring `GitOutputParser`).
- New `PaneWorkerCommand` cases in `Features/VibeSpace/Services/PaneWorker/PaneWorkerInfrastructure.swift` (sits alongside `gitStatus`, `gitBranches`, etc.).
- View-model surface on the source-control repository VM (`VibeSpaceSourceControlRepositoryViewModel`) + a small worktree sheet/menu in `VibeSpaceSourceControlView`.
- "Open as project" routes to `homeCatalogCoordinator.addProjects…` / the `VibeSpaceCanvasActionsCoordinator.addProjectsViaCLI`-equivalent UI path.
- Optional: a `vibespace.worktree.*` CLI surface for agents (defer; align with F044 if wanted).

### Risks / notes
- Worktrees and the main repo share `.git`; removing a worktree with uncommitted changes needs the force-confirm guard (R04).
- A worktree opened as a project is discovered independently by source-control discovery (its own repo root), so no special-casing in discovery is expected — validate during implementation.

---

## Unified Project Side Panel (new feature F053)

### Current behaviour (important nuance)

The app does **not** render three separate sidebars. There is a **single** panel, `VibeSpaceSidebarPanelView` (`Features/VibeSpace/Canvas/Views/ContentViewVibeSpaceSidebar.swift`), whose body `switch`es on `vibespaceShell.sidebarTab` (`AppShellStore.vibespaceSidebarTab`, enum `FolderExplorerViewModel.SidebarTab`: `.files` / `.git` / `.sessions` / `.conversations`) and shows exactly one pane:

- `.files` → `VibeSpaceSidebarFilesPane` (projects + per-project file trees + shelf + **parked projects**)
- `.git` → `VibeSpaceSidebarGitPane` → `VibeSpaceSourceControlView`
- `.sessions` → `VibeSpaceSidebarSessionsPane`
- `.conversations` → `VibeSpaceSidebarConversationsPane` (agent chats)

The tab is chosen by the left **activity-bar rail** (`HomeAppSideMenuRailView` in `Features/Home/Views/ContentViewToolbar.swift`) via `showProjectSidebar(.files/.git/.sessions/.conversations)`.

So the user's "three different sidebars" = these tab-swapped panes. The ask: show **Files + Git + Agent Chats together in one panel** anchored on the existing projects/files view.

### Design options

- **Option A — Stacked collapsible sections (recommended).** One `ScrollView`/`LazyVStack` containing collapsible sections: **Projects & Files**, **Source Control**, **Conversations** (and optionally Sessions). Reuse the existing pane views as section bodies. Activity-bar buttons become **scroll-to-section + expand** anchors instead of full-panel swaps. Lowest-risk: panes already exist and are self-contained; mostly composition + a disclosure-state store.
- **Option B — Per-project nested subsections.** Each project node expands into Files / Source Control / Chats scoped to that project. Most "IDE-like" but a larger rewrite (git/chat views are currently vibespace-scoped, not strictly per-project) and higher risk. Defer unless explicitly wanted.
- **Option C — Keep tabs, add a split.** Allow the panel to split (e.g., Files on top, Git/Chats below). Middle ground; more layout/persistence work than A for less consolidation.

**Recommendation: Option A.** It directly satisfies "one panel, no tab switching" while reusing `VibeSpaceSidebarFilesPane`, `VibeSpaceSidebarGitPane`, and `VibeSpaceSidebarConversationsPane` as sections.

### Proposed requirements

- **F053-R01 — Single composed panel.** The vibespace sidebar MUST present Projects/Files, Source Control, and Conversations as concurrently-visible, independently collapsible sections within one scroll container.
- **F053-R02 — Section disclosure persistence.** Per-section expanded/collapsed state MUST persist per vibespace (extend `LayoutPersistenceService` / `AppShellStore`).
- **F053-R03 — Rail buttons as anchors.** Activity-bar Files/Git/Conversations buttons MUST expand + scroll to the corresponding section rather than swap the panel. Active-state highlight follows the section nearest the top / last targeted.
- **F053-R04 — Section headers + actions.** Each section MUST keep its header actions (Files: add-to-shelf; Git: clone/refresh) currently in `vibespaceSidebarHeader`.
- **F053-R05 — Performance.** Collapsed sections MUST NOT eagerly build/refresh heavy content (lazy bodies; git refresh and ACP thread loading gated on expansion) to protect sidebar render budget.
- **F053-R06 — Sessions placement.** Decide whether Sessions becomes a 4th section or stays a separate view (open question below).

### Files to touch
- `Features/VibeSpace/Canvas/Views/ContentViewVibeSpaceSidebar.swift` — replace the `switch` with composed collapsible sections; rework `vibespaceSidebarHeader` into per-section headers.
- `App/AppShellStore.swift` — replace/augment single `vibespaceSidebarTab` with per-section disclosure state; keep `setVibeSpaceSidebarTab` as "expand+scroll" for the rail.
- `Features/Home/Views/ContentViewToolbar.swift` + `Features/Home/Actions/ContentViewToolbarActions.swift` — `showProjectSidebar` becomes expand-and-scroll.
- Reuse (likely unchanged): `VibeSpaceSidebarFilesPane`, `VibeSpaceSidebarGitPane`, `VibeSpaceSidebarConversationsPane`, `VibeSpaceSidebarSessionsPane`.
- `Features/VibeSpace/ViewModels/Explorer/FolderExplorerTypes.swift` — `SidebarTab` may shift from "selected tab" to "section identity".

### Risks
- Highest-uncertainty item. `SidebarTab`/`activeSidebarTab` is referenced widely (FolderExplorer view models, lifecycle git refresh gating at `FolderExplorerViewModelTreeLifecycle` lines ~272/312). Changing its meaning needs care — prefer **adding** disclosure state and keeping `SidebarTab` as section identity to limit blast radius.
- Sidebar render/perf budget: keep section bodies lazy and gate refresh on expansion.
- This file (`ContentView.swift` neighbourhood) is prone to SwiftUI type-checker timeouts — keep composed section builders factored into small `@ViewBuilder`/helper funcs.

---

## Cross-Cutting: Docs, Tests, Sequencing

### Required docs (per `specs/features/CONVENTION.md` — 4 docs each)
- **F052 Git Worktrees** (`specs/features/source-control/worktrees/`): spec, technical-design, threat-model, usage-guide.
- **F053 Unified Project Side Panel** (`specs/features/app-shell/unified-sidebar/` or `explorer/unified-sidebar/`): 4 docs.
- Update `specs/features/INDEX.md`: register F052/F053, bump "next available prefix" to F054.

### Test plan
- **Worktrees:** executor tests against a temp git repo (add/list/remove/prune); "open worktree as project" behavioral test.
- **Unified panel:** view/snapshot or behavioral tests that all sections render together and disclosure persists; perf check that collapsed sections don't refresh.
- Run: `xcodebuild test … -only-testing:CrispyVibesUnitTests` (per AGENTS.md). Use the `crispyvibes-local` scheme for manual runs; never kill the main `Crispy.app`.

### Suggested sequencing (independent, parallelizable)
1. **Git Worktrees** (additive; isolated to the Git layer).
2. **Unified panel** (largest/most-uncertain; do last and behind a careful refactor of `SidebarTab` semantics).

## Open Questions

1. **Unified panel:** Should **Sessions** and the **Shelf** also fold into the unified panel, or only Files + Git + Conversations? Keep the activity-bar rail (as anchors) or remove it entirely?
2. **Unified panel:** Per-project nested sections (Option B) ever desired, or is the stacked-sections model (Option A) the target?
3. **Worktrees:** Should worktree actions also be exposed over the agent CLI, or UI-only for now?
