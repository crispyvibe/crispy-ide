# F021 — VibeSpace Projects

Status: draft

Domain: **VibeSpace (D2)**.
Covers project creation, focus management, add/remove projects, project sessions,
stacked card previews, hydration order, layout persistence, and project container actions.

> Cross-reference: F014 (Navigation) retains rail placement and canvas layout scenarios.
> Scenarios here focus on project-level lifecycle within a vibespace.

---

## Dependencies

- F020 (VibeSpace Lifecycle) — vibespace must exist before projects are managed
- F001 (Terminal Sessions & Tabs) — terminal hydration and session management
- F023 (Project Color Coding) — color tags on stacked cards

---

## Scenarios

### F021-S01 · Add Project supports selecting multiple folders (APP-019)

```gherkin
Given the user clicks `Add Project`
When the folder picker returns multiple directories
Then one project is created per selected folder
And duplicates in the same picker result are ignored by normalized path
```

### F021-S02 · Existing project folder is not duplicated (APP-020)

```gherkin
Given a selected folder is already open as a project
When the same folder is selected again in Add Project
Then no duplicate project is created
And the existing project becomes focused
```

### F021-S03 · New project becomes focused (APP-021)

```gherkin
Given one or more folders are selected
When project creation succeeds
Then the last processed project becomes focused
And an active terminal is ensured for that project root
```

### F021-S04 · Selecting a stacked project card focuses it (APP-025)

```gherkin
Given multiple projects are open
When the user clicks a stacked project card
Then that project becomes focused
And terminal availability is ensured for the focused project
And keyboard focus moves to the focused project's active terminal
```

### F021-S05 · VibeSpace open hydrates focused terminal first and rail terminals next (APP-026)

```gherkin
Given a VibeSpace has multiple projects
When the user opens that VibeSpace
Then the focused project terminal is ensured first
And non-focused project terminals are hydrated progressively for rail previews
And non-focused project terminal sessions are started in background hydration order
```

### F021-S06 · Closing focused project falls back safely (APP-027)

```gherkin
Given multiple projects are open and one is focused
When the focused project is closed
Then it is removed from project list
And focus falls back to the last remaining project
```

### F021-S07 · Closing last project returns to empty state (APP-028)

```gherkin
Given only one project is open
When the project is closed
Then no focused project remains
And the app returns to empty state UI
```

### F021-S08 · Restart Project restarts all pane workers/sessions (APP-029)

```gherkin
Given a focused project is open
When the user clicks `Restart Project`
Then explorer worker restarts
And editor worker restarts and reloads the current file if one is open
And terminal pane restarts and recreates an active tab
```

### F021-S09 · Close Project removes the focused project (APP-030)

```gherkin
Given a focused project is open
When the user clicks the close icon in project header
Then the project is removed from state
And focus fallback behavior is applied
```

### F021-S10 · Stacked card shows grouped project terminal stack preview (APP-031)

```gherkin
Given a stacked project has at least one terminal session
When the stacked card renders
Then one representative terminal is displayed for that project
And that representative terminal is chosen from the project's visible rail terminals using activity-first, then recency-based ordering
And additional visible terminals in that project are represented as a collapsed stack affordance instead of separate top-level project cards
And terminal density is compact for higher information density
```

### F021-S11 · Stacked card surfaces project activity state (APP-032)

```gherkin
Given a stacked project has terminal output activity in any tab
When the stacked card header renders
Then the stack icon keeps the Project color treatment
And the header shows the same inline activity indicator style used in terminal tabs until activity goes idle
```

### F021-S12 · Stacked card handles missing terminal (APP-033)

```gherkin
Given a stacked project has no terminal session
When the stacked card renders
Then a `Loading Terminal` placeholder is shown until session hydration completes
```

### F021-S13 · Stacked project rail encourages adding projects when only one project exists (APP-024)

```gherkin
Given exactly one project is open
When ContentView renders
Then the project rail shows an `Add Project(s)` call to action
And the rail does not show a passive `No Stacked Projects` placeholder
```

### F021-S14 · User drags editor and terminal splitters (APP-039)

```gherkin
Given focused Project view is visible
When user drags explorer/editor or editor/terminal dividers
Then layout fractions are updated in memory for that Project
And fractions are persisted in app layout state store using normalized Project path key
```

### F021-S15 · Reopen restores persisted Project layout (APP-040)

```gherkin
Given a Project has persisted pane layout in app layout state store
When the Project is reopened
Then explorer/editor split ratio is restored
And terminal pane height ratio is restored
```

---

### F021-S16 · Park Project terminates sessions and persists snapshot (R09–R10)

```gherkin
Given project P is open with active terminals and at least one browser
When the user selects "Park Project" on P from the Files-tab right-click menu
Then `VibeSpaceCanvasActionsCoordinator.parkProject(id:)` runs
And browsers owned by P are snapshotted into ProjectConfigFile.browserSessionEntries
And the same browsers are dispatched for close via `.closeBrowserRequested`
And ProjectConfigFile.isParked is set to true
And `VibeSpaceState.parkProject(id:)` shuts down the live ProjectSession (terminating terminals)
And the path is appended to `parkedProjectPaths` and removed from `projects`
```

### F021-S17 · Activate (unpark) restores a parked project (R11)

```gherkin
Given a parked project P with persisted terminalEntries and browserSessionEntries
When the user selects "Activate Project" on P
Then `VibeSpaceState.unparkProject(path:)` creates a fresh ProjectSession from the factory
And the path is removed from `parkedProjectPaths` and appended to `projects`
And ProjectConfigFile.isParked is set to false
And persisted browser sessions are restored via DockedBrowserCoordinator (tile or detailed-view)
And the unparked project becomes the focused project
```

### F021-S18 · Parked projects do not appear in the rail or get hydrated (R14)

```gherkin
Given a vibespace has live and parked projects
When the vibespace opens
Then the rail shows only live projects
And the hydration coordinator hydrates only live projects' terminals
And parked projects are NOT included in VibeCast broadcast target enumerations
```

### F021-S19 · Parked projects appear in the Files-tab "Parked Projects" section (R12)

```gherkin
Given a vibespace has at least one parked project
When the Files tab renders
Then a "Parked Projects" section appears below the live projects list
And each parked project entry shows its folder name and an "Activate Project" right-click menu item
```

### F021-S20 · Adding a project that is already parked auto-unparks it (R09 spirit)

```gherkin
Given project P is parked
When the user invokes Add Project for the same folder
Then `VibeSpaceState.addProjects(from:)` detects P is parked
And calls `unparkProject(path:)` to recreate the live session
And no duplicate entry is created
```

### F021-S21 · Click-to-select: tab activation switches focused project (R15–R17)

```gherkin
Given content viewer has tabs from multiple projects
And focused project is P1
When the user clicks a tab whose owning project is P2
Then `EditorGroupStore.activateTab` posts `.contentViewerTabActivated`
And the listener resolves the tab's owning project (file URL prefix, BrowserTabReference.projectPath, or terminal projectID)
And calls `vibespaceCanvasActionsCoordinator.focusProject(P2)`
And subsequent project-scoped UI (rail focus, scope toggle) reflects P2
```

### F021-S22 · Click-to-select is idempotent for the already-focused project (R15)

```gherkin
Given focused project is P1
When the user activates a tab whose owning project is P1
Then the listener detects `focusedProject?.id == owner.id`
And the focusProject call is suppressed (no recursion, no redundant focus signpost)
```

### F021-S23 · Click-to-select on board tile switches focused project (R17)

```gherkin
Given canvas mode is Board
And a tile owned by project P2 exists on the active surface
And focused project is P1
When the user clicks the tile
Then `VibeSpaceTerminalBoardStore.activateTile` posts `.boardTileActivated` with userInfo["projectPath"] = P2's path
And the listener resolves P2 from the live projects array
And calls `vibespaceCanvasActionsCoordinator.focusProject(P2)`
And the same idempotency guard applies (no-op if P2 is already focused)
```

### F021-S24 · Click-to-select on terminal tray and parked-project exclusions (R17, R14)

```gherkin
Given canvas mode is Detailed
And the terminal tray displays only the focused project's terminals (FocusedProjectView wraps a single project's terminalViewModel)
When the user taps a terminal tab in the tray
Then no project switch occurs (the tab's owning project is by construction the focused project)

Given a vibespace has live projects and parked projects
When VibeCast broadcast targets are enumerated for the active vibespace
Then only live projects' terminals appear as targets (terminalSources derives from `state.projects`)
And the scope toggle (`if projects.count > 1`) counts only live projects
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F021-R01 | Add Project supports multi-select and deduplicates by normalized path |
| F021-R02 | New project becomes focused with an active terminal ensured |
| F021-R03 | Focused terminal hydrates first; rail terminals hydrate progressively |
| F021-R04 | Closing focused project falls back to last remaining; closing last returns to empty state |
| F021-R05 | Restart Project restarts explorer, editor, and terminal workers |
| F021-R06 | Stacked cards show grouped project terminal stacks with compact previews, representative-terminal ordering, and activity indicators |
| F021-R07 | Project layout splitter positions persist per normalized project path |
| F021-R08 | Single-project rail shows `Add Project(s)` CTA |
| F021-R09 | Project Park State — projects support a "parked" state retaining a full state snapshot but NOT hydrating sessions on vibespace open |
| F021-R10 | Park Lifecycle — parking terminates terminals, closes browsers, stops watchers, persists snapshot |
| F021-R11 | Unpark Restoration — activating a parked project recreates terminals and browsers from saved snapshot, focuses the project |
| F021-R12 | Parked Project UI Placement — parked projects appear in the Files tab as a distinct "Parked Projects" section, NOT in the project rail |
| F021-R13 | Park/Unpark Interaction — Park via right-click on project entry → "Park Project"; Activate via right-click on parked entry → "Activate Project". Bulk parking is NOT required |
| F021-R14 | Parked Project Exclusion — parked projects MUST NOT appear in the rail, hydrate terminals on vibespace open, be VibeCast targets, or contribute to scope-toggle project count |
| F021-R15 | Pane Focus Selects Project — single-click focus on a pane (terminal, file, browser) MUST set the pane's owning project as the focused project |
| F021-R16 | Immediate Focus Change — focus change happens on single click, no double-click required |
| F021-R17 | Cross-Surface Consistency — click-to-select MUST work across content viewer tabs, terminal tray, board tiles, and detached board windows |

---

## Acceptance Criteria

- Multi-folder selection creates one project per folder with no duplicates
- Focus fallback chain works correctly when projects are removed
- Terminal hydration order prioritizes focused project
- Layout splitter positions survive app restart
- Parked projects do not hydrate sessions on vibespace open and do not appear in the project rail (F021-R09, R14)
- Park/unpark round-trip preserves terminals (via terminalEntries) and browsers (via browserSessionEntries) (F021-R10, R11)
- Files tab renders a "Parked Projects" section with activate context menu (F021-R12, R13)
- Single-click on a content-viewer tab whose owning project differs from the focused project switches focus (F021-R15, R16)
- Click-to-select is idempotent — already-focused projects do not re-trigger focus (F021-R15)

## Test Coverage

| Scope | Test File |
|---|---|
| Park/unpark state transitions; addProjects auto-unpark; ProjectConfigFile + VibeSpaceConfigFile backward-compatible decode; ProjectSession deallocation after park; repeated park/unpark cycles do not accumulate sessions | `tests/unit/Models/VibeSpaceStateParkingTests.swift` |
| `.boardTileActivated` notification posted with `projectPath` when project-owned tile activates; userInfo lacks key for standalone tile | `tests/unit/Features/Terminal/ViewModels/VibeSpaceTerminalBoardStoreClickToSelectTests.swift` |
| Existing project lifecycle and add/remove behavior | `tests/unit/Models/VibeSpaceStateTests.swift`, `tests/unit/Models/VibeSpaceStateTestsOverridesAndPaths.swift` |
| Pre-existing memory lifecycle for ProjectSession + TerminalViewModel + EditorGroupStore | `tests/unit/Features/Terminal/ViewModels/TerminalMemoryLifecycleTests.swift`, `tests/unit/Features/ContentViewer/ViewModels/ContentViewerMemoryLifecycleTests.swift` |

---

## Open Questions

- Should project removal prompt for confirmation?
- Should bulk park (multi-select) be added in a future iteration? Currently single-project only (F021-R13).

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Initial draft — extracted from F014 Navigation | — |
| 2026-05-22 | Added project parking (F021-R09–R14) and click-to-select project (F021-R15–R17), with scenarios S16–S22 | — |
| 2026-05-22 | Closed F021-R17 cross-surface coverage: board-tile click-to-select wired via `.boardTileActivated`; terminal-tray and exclusion behaviors documented as inherent in scenarios S23–S24 | — |
