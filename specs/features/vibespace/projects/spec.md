# F021 — VibeSpace Projects

Status: implemented

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
And ProjectConfigFile.isParked is set to true
And `VibeSpaceState.parkProject(id:shutdown:false)` removes the live ProjectSession from `projects` without shutting it down yet
And the path is appended to `parkedProjectPaths`
And only then are the snapshotted browsers dispatched for close via `.closeBrowserRequested`
And all project-keyed file flushes race the true 30-second timeout before the retained session shuts down exactly once
And removing P before browser close prevents close-triggered fallback logic from refocusing the project being parked
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

### F021-S25 · Remove active project via context menu (R18)

```gherkin
Given project P is open (live) and shown in the Files tab
When the user selects "Remove Project" on P's right-click menu
Then `.removeProjectRequested` is posted with P's project id
And `VibeSpaceCanvasActionsCoordinator.removeProject(id:)` runs
And P's terminals/browsers are torn down and P is removed from `projects`
And focus falls back to the last remaining project (F021-S06)
And no confirmation prompt is shown
```

### F021-S26 · Remove parked project via context menu (R19)

```gherkin
Given project P is parked (shown in the Files-tab "Parked Projects" section)
When the user selects "Remove Project" on P's right-click menu
Then `.removeParkedProjectRequested` is posted with P's path
And `VibeSpaceCanvasActionsCoordinator.removeParkedProject(path:)` runs
And `VibeSpaceState.removeParkedProject(path:)` drops P from `parkedProjectPaths` and clears its associated per-project state
And P is NOT activated (no live session is created)
And no confirmation prompt is shown
```

### F021-S27 · Active project node exposes the shared local/remote context menu (R20, R23)

```gherkin
Given project P is open (live) and shown as a project-root node in either explorer surface
When the user right-clicks P's node
Then the shared `ProjectNodeContextMenu` renders Make Current Project, Open in Terminal,
     Open in System, New File, New Folder, Copy Path, Park Project, and Remove Project
And a local project also shows Reveal in Finder
And a remote/SSH project instead shows Download… and does not show Reveal in Finder
And the menu is identical in the classic Files pane and the unified/combined sidebar
```

### F021-S28 · "Make Current Project" focuses the project (R20)

```gherkin
Given project P is open and is not the focused project
When the user selects "Make Current Project" on P's node
Then `.makeCurrentProjectRequested` is posted with P's project id
And ContentView routes it to `VibeSpaceCanvasActionsCoordinator.focusProject(id:)`
And P becomes the focused project, reusing the existing focusProject path
```

### F021-S29 · "Open in Terminal" always opens a new terminal at the project root (R20)

```gherkin
Given project P is open
When the user selects "Open in Terminal" on P's node
Then the action routes through the same FileTreeAction handler used by file/folder nodes
And a NEW terminal tab is opened at the project ROOT
And an existing terminal is never selected in place of adding a new one
```

### F021-S30 · External project actions match project location (R20, R23)

```gherkin
Given project P is open
When the user right-clicks P's node
Then a local project shows Open in System and Reveal in Finder
And Open in System asks macOS to open the local project directory
And a remote/SSH project shows Open in System and Download…
And Reveal in Finder is HIDDEN for the remote/SSH project
And remote actions use the shared app-wide transfer progress, cancellation, and completion surface
```

### F021-S31 · Cross-surface parity via the shared component (R21)

```gherkin
Given the shared `ProjectNodeContextMenu` backs both explorer surfaces
When a project node is right-clicked in the classic Files pane and in the unified/combined sidebar
Then the same location-appropriate menu items, wording, and routing are used in both
And Open in Terminal, Open in System, Download…, Reveal in Finder, New File, New Folder, and Copy Path
    behave identically to each action's applicable file/folder-row counterpart
```

### F021-S32 · Add Project can create and select a new folder (R22)

```gherkin
Given the user opens the local folder picker from `Add Project`
When the desired project directory does not exist yet
Then the picker offers New Folder creation
And the newly created directory can be selected and added as a project
```

### F021-S33 · Local project root opens in the system (R23)

```gherkin
Given an active local project root is visible
When the user selects Open in System
Then macOS opens the original local project directory
And no remote transfer UI is started
```

### F021-S34 · Remote project root exposes coordinator-backed external actions (R23)

```gherkin
Given an active remote project root is visible
When its context menu opens
Then Open in System and Download… are available
And Reveal in Finder is absent
When either remote operation runs
Then the app-wide coordinator slot shared with explorer file/folder actions reports preparing, transferring, cancelling, publishing, completion, or failure
And Cancel is unavailable during cancellation and publication
And cancellation retains the slot until transport and staging cleanup complete
And publication synchronously acknowledges its MainActor state before a final cancellation check immediately ahead of replace/move
And cancellation after that check may not prevent the atomic publication
And failure remains in the overlay until dismissed
And editor-triggered remote HTML Open in System remains independent of this slot and overlay
```

### F021-S35 · Parked remote row remains identifiable but inactive (R24)

```gherkin
Given a persisted parked path is an `ssh://` URI
When the Parked Projects section renders it
Then the shared SSH identifier parser recognizes its percent-encoded or legacy path
And the row uses a server icon and SSH badge
And it shows the literal host with non-default port plus only `…/basename`
And it omits the username and ancestor path components from visible and accessibility text
And its accessibility identifier hashes the persisted identifier
And its context menu contains only Activate Project and Remove Project
And no file browsing, Open in System, Download…, terminal, or mutation action is available until activation
```

---

## Requirements

| ID | Requirement | Status |
|----|-------------|--------|
| F021-R01 | Add Project supports multi-select and deduplicates by normalized path | implemented |
| F021-R02 | New project becomes focused with an active terminal ensured | implemented |
| F021-R03 | Focused terminal hydrates first; rail terminals hydrate progressively | implemented |
| F021-R04 | Closing focused project falls back to last remaining; closing last returns to empty state | implemented |
| F021-R05 | Restart Project restarts explorer, editor, and terminal workers | implemented |
| F021-R06 | Stacked cards show grouped project terminal stacks with compact previews, representative-terminal ordering, and activity indicators | implemented |
| F021-R07 | Project layout splitter positions persist per normalized project path | implemented |
| F021-R08 | Single-project rail shows `Add Project(s)` CTA | implemented |
| F021-R09 | Project Park State — projects support a "parked" state retaining a full state snapshot but NOT hydrating sessions on vibespace open | implemented |
| F021-R10 | Park Lifecycle — parking terminates terminals, closes browsers, stops watchers, persists snapshot | implemented |
| F021-R11 | Unpark Restoration — activating a parked project recreates terminals and browsers from saved snapshot, focuses the project | implemented |
| F021-R12 | Parked Project UI Placement — parked projects appear in the Files tab as a distinct "Parked Projects" section, NOT in the project rail | implemented |
| F021-R13 | Park/Unpark Interaction — Park via right-click on project entry → "Park Project"; Activate via right-click on parked entry → "Activate Project". Bulk parking is NOT required | implemented |
| F021-R14 | Parked Project Exclusion — parked projects MUST NOT appear in the rail, hydrate terminals on vibespace open, be VibeCast targets, or contribute to scope-toggle project count | implemented |
| F021-R15 | Pane Focus Selects Project — single-click focus on a pane (terminal, file, browser) MUST set the pane's owning project as the focused project | implemented |
| F021-R16 | Immediate Focus Change — focus change happens on single click, no double-click required | implemented |
| F021-R17 | Cross-Surface Consistency — click-to-select MUST work across content viewer tabs, terminal tray, board tiles, and detached board windows | implemented |
| F021-R18 | Remove Active Project — live projects expose a "Remove Project" context-menu action (alongside "Park Project") that removes the project and applies focus fallback; no confirmation prompt | implemented |
| F021-R19 | Remove Parked Project — parked projects expose a "Remove Project" context-menu action (alongside "Activate Project") that drops the parked entry and clears its associated state without activating it; no confirmation prompt | implemented |
| F021-R20 | Project Node Context Menu — an active project-root node exposes a full right-click menu via the shared `ProjectNodeContextMenu` component: Make Current Project, Open in Terminal, Open in System, New File, New Folder, Copy Path, Park Project, and Remove Project. Local roots also expose Reveal in Finder. Remote/SSH roots omit Reveal in Finder and additionally expose Download…. Make Current Project is dispatched via `.makeCurrentProjectRequested` → `VibeSpaceCanvasActionsCoordinator.focusProject(id:)` | implemented |
| F021-R21 | Cross-Surface Menu Parity — the project-node menu MUST be identical across the classic Files pane and the unified/combined sidebar (same shared component), and its applicable navigation/external actions MUST route through the same FileTreeAction handlers as file/folder nodes so behavior and wording match | implemented |
| F021-R22 | Local Project Folder Creation — Add Project folder pickers MUST allow creating a new directory and selecting it immediately as a project | implemented |
| F021-R23 | Active Project External Actions — Open in System MUST open an active local root through macOS. For active remote roots, Open in System MUST use a temporary local snapshot and Download… MUST use the shared remote-transfer workflow; remote roots MUST NOT show Reveal in Finder | implemented |
| F021-R24 | Parked Remote Project Presentation — a parked remote row MUST use the shared parser for percent-encoded and legacy `ssh://` identifiers, render a server icon and SSH badge, show literal host/non-default port plus only `…/basename`, omit user and ancestor paths from visible/accessibility text, and hash its accessibility identifier. Badge, host/port, abbreviated path, detail, and accessibility sentence MUST use localized `AppStrings` formatting. It remains inactive and exposes only Activate Project and Remove Project | implemented |

---

## Automatic Board Cleanup Scenarios

### F021-S36 · Parking captures ownership before project shutdown (R25, R28)

```gherkin
Given active project P owns terminal, browser, file, or ACP board tiles on primary or detached surfaces
When the user parks P
Then VibeSpaceCanvasActionsCoordinator captures P's unique projectIdentifier, raw root, terminal tab IDs, and browser ownership keys before shutting down its session or mutating project state
And browser sessions are queried under the host-safe project identifier and, only when unambiguous, the legacy raw-root key
And duplicate browser IDs are removed
And the resulting entries are persisted exactly once under the host-safe project identifier, including when the snapshot is empty
```

### F021-S37 · Park and remove clean every proven project-owned board member (R25–R27)

```gherkin
Given active project P has visible, minimized, or Spotlight board members across primary and detached surfaces
When P is parked or removed
Then the board store performs one normalized and persisted mutation
And every tile proven to be owned by P is removed from visible and minimized collections on every surface
And each corresponding Spotlight member is removed
And empty detached surfaces normalize away and their managed windows close
And unrelated and ambiguously owned tiles remain
```

### F021-S38 · Remote cleanup is host-qualified and fail-closed (R26–R27)

```gherkin
Given two SSH projects use the same raw remote root on different hosts
When one project is parked or removed
Then only tiles carrying or uniquely resolving to that project's host-qualified projectIdentifier are removed
And tiles owned by the other host remain
And a legacy remote tile with only an ambiguous raw-root match is retained fail-closed
```

### F021-S39 · Remove freezes browser ownership before state mutation (R28)

```gherkin
Given active project P owns one or more browser panes
When the user removes P
Then the coordinator freezes P's browser ownership keys before project state is mutated
And board cleanup and browser close use that frozen evidence after the live project session is unavailable
And P's session and associated project state are removed without deleting another project's browser
```

### F021-S40 · Unpark restores uniquely owned browsers and terminals (R29)

```gherkin
Given parked project P has saved browser entries and terminal entries
When P is activated
Then each pinned browser is recreated on the primary surface with its original tile ID and snapshot
And its browser view model carries P's unique projectIdentifier
And terminal reconciliation recreates restored project terminals
And remote terminal context, subscriptions, reconciliation, and Spotlight identities use the host-qualified owner
```

### F021-S41 · Park/remove waits for owned file flushes (R30, R34)

```gherkin
Given a project owns a pinned docked file group, an unpinned preview, a displaced group/preview flush, or another outstanding project-owned close task
When the project is parked or removed
Then each owned group closes all tabs through each tab's own provider
And the unpinned preview is included when its qualified owner matches
And every displaced/outstanding flush remains tracked under that exact projectIdentifier
And project state is removed without immediate session shutdown
And one monitor awaits all returned file-flush tasks while a second waits for a true 30-second timeout
And the first result cancels the losing monitor
And project shutdown occurs exactly once
And a failed close write retains the dirty buffer and is diagnosed
```

### F021-S42 · VibeSpace switch prunes outgoing file groups and persists one browser key (R30–R31)

```gherkin
Given an outgoing VibeSpace has docked file groups and a remote project with qualified and unambiguous legacy browser lookup keys
When another VibeSpace is hydrated
Then outgoing docked file groups are eagerly closed and pruned
And browser snapshots were queried under both eligible lookup keys and deduplicated
And the result was persisted exactly once under the qualified projectIdentifier
And no second browser snapshot is persisted under the legacy raw-root key
```

### F021-S43 · Same-root remote repositories and diffs stay with the exact project (R32)

```gherkin
Given two SSH projects expose the same raw repository root on different hosts
When source control discovers, presents, or opens a changed file from either repository
Then the repository model retains the originating host-qualified projectIdentifier
And it attaches only to that exact project
And tracked diffs use that project's gitExplorer and combine staged plus working output in a preloaded diff tab
And untracked files use that project's exact file provider
```

### F021-S44 · Spotlight routes and shortcut keys preserve unique project identity (R33)

```gherkin
Given projects may share a raw root but have distinct projectIdentifiers
When any main/detached direct, temporary, shortcut, split, permanent, ACP, link, file, browser, editor-pane, restore, or detached-attachment route opens Spotlight
Then the originating projectIdentifier survives unchanged through nested actions
And project-scoped shortcuts are loaded with that exact identifier
And project shortcut keys remain unique across projects
```

### F021-S45 · Park/remove races every project flush against timeout and shuts down once (R34)

```gherkin
Given a project has displaced preview/group flushes, outstanding project-owned flushes, or close tasks returned by cleanup
When the project is parked or removed
Then every matching task remains tracked under the exact projectIdentifier
And one monitor awaits the complete flush set while another awaits the true 30-second timeout
And the first result wins and cancels the other monitor
And project shutdown runs exactly once after either flush completion or timeout
```

### F021-S46 · Legacy SSH persistence canonicalizes without losing dormant project state (R35)

```gherkin
Given a trusted vibespace or per-project config contains a legacy SSH identifier, including the prior raw full identifier formed by sshURI plus an unescaped remote path
When the vibespace and its project configs load
Then live, unresolved, focused, and parked identifiers are canonicalized
And duplicate parked identifiers and parked entries that collide with live or unresolved projects are removed
And the changed trusted parent vibespace config is saved immediately
And project-config lookup checks the canonical key plus supported aliases, rewrites the complete project config under the canonical key, and deletes the migrated alias
And all per-project reads and mutations, browser sessions, and project shortcuts use that migration path
And loadProjectConfigs includes live, unresolved, and parked projects and returns entries keyed by canonical projectPath
And runtime pruning preserves color, startup, ACP-agent, shell, scoped-shortcut, and numeric shortcut state for unresolved and parked projects
```

## Automatic Board Cleanup Requirements

| ID | Requirement | Status |
|----|-------------|--------|
| F021-R25 | Pre-Shutdown Ownership Capture — before an active project park/remove shuts down its session or mutates project state, `VibeSpaceCanvasActionsCoordinator` MUST capture the unique `projectIdentifier`, raw root, terminal tab IDs, and browser ownership keys required for deterministic cleanup | implemented |
| F021-R26 | Proven-Ownership Cleanup — park/remove MUST request one normalized and persisted board-store mutation that removes every proven project-owned visible/minimized tile across primary and detached surfaces and removes each matching Spotlight member; supported evidence includes terminal/browser tile `projectIdentifier`, legacy remote terminal tab membership, component-boundary local file-root containment, stamped file `projectIdentifier`, and ACP `selectedProjectIdentifier` | implemented |
| F021-R27 | Host-Safe Fail-Closed Ownership — remote ownership, runtime terminal subscriptions/context/reconciliation, and Spotlight identities MUST use the host-qualified project identifier; same raw roots on different SSH hosts MUST remain isolated, uniquely provable legacy ownership MAY be migrated, and ambiguous legacy remote raw-root-only tiles MUST be retained | implemented |
| F021-R28 | Park/Remove Ordering — park MUST query browser snapshots under the host-safe identifier and an unambiguous legacy root, deduplicate them, persist once under only the host-safe identifier even when empty, then clean board tiles, remove project state without immediate shutdown, close browsers, and defer exactly-once shutdown until either all project-keyed flushes finish or the true 30-second timeout wins; remove MUST freeze browser keys before state mutation and use the same rule | implemented |
| F021-R29 | Ownership-Preserving Unpark — unpark MUST recreate each pinned browser tile and view model on the primary surface with its original tile ID, snapshot, and unique owner, while terminal reconciliation recreates restored project terminals | implemented |
| F021-R30 | Save-Safe Project and VibeSpace Teardown — park/remove MUST include owned pinned file groups and any unpinned owned preview, retain displaced and outstanding flushes under the exact project identifier, close every tab through its own provider, and defer shutdown until either all matching tasks finish or a true 30-second timeout wins. Eager VibeSpace switching MUST prune outgoing docked file groups | implemented |
| F021-R31 | Canonical Browser Snapshot Persistence — browser snapshots MAY be queried by the qualified identifier plus an unambiguous legacy raw-root key for migration, but the deduplicated result MUST be persisted exactly once under the qualified `projectIdentifier`, never under both keys | implemented |
| F021-R32 | Project-Qualified Source Control — repository discovery and repository models MUST retain the exact originating `projectIdentifier`; an SSH repository attaches only to that exact project even when another host has the same raw root. Remote tracked diffs MUST use that project's `gitExplorer`, combine staged and working output in a preloaded diff tab, and remote untracked files MUST use that project's exact file provider | implemented |
| F021-R33 | Project-Qualified Spotlight and Shortcuts — the exact `projectIdentifier` MUST survive every main/detached direct, temporary, shortcut, split, permanent, ACP, link, file, browser, editor-pane, restore, and detached-attachment Spotlight route. Project shortcut dictionaries and project-scoped shortcut storage MUST use the exact identifier, preserve `ssh://` values verbatim, and keep shortcut slots unique across projects | implemented |
| F021-R34 | Exactly-Once Save-Safe Project Shutdown — displaced preview/group flushes and outstanding flushes MUST remain tracked by their exact project identifier. Park/remove MUST race the complete flush set against a real 30-second timeout, cancel the losing monitor, and call project shutdown exactly once after either result | implemented |
| F021-R35 | Canonical SSH Persistence Migration — live, unresolved, focused, and parked identifiers MUST canonicalize; parked values MUST deduplicate and exclude live/unresolved collisions; a changed trusted parent MUST save immediately. Every per-project read/mutation, browser operation, and shortcut operation MUST migrate supported aliases including the prior raw full identifier to one canonical key. `loadProjectConfigs` MUST include live/unresolved/parked entries keyed canonically, and runtime pruning MUST preserve parked/unresolved settings and shortcut slots | implemented |

## Acceptance Criteria

- Park/remove captures `projectIdentifier`, raw root, terminal tab IDs, and browser ownership keys before session shutdown or project-state mutation (F021-R25).
- One normalized and persisted board mutation removes all proven owned visible/minimized tiles and Spotlight members across primary/detached surfaces, closes newly empty managed detached windows, and retains ambiguous tiles (F021-R26, R27).
- Same-root remote projects on different SSH hosts remain isolated; local file fallback uses path-component boundaries, and ambiguous legacy remote raw-root-only ownership fails closed (F021-R27).
- Park snapshots and overwrites browser entries before cleanup/state removal/close; remove freezes browser keys before state mutation (F021-R28).
- Unpark restores pinned browser tiles/view models on primary with original tile IDs, snapshots, and unique owners; terminal reconciliation recreates restored project terminals (F021-R29).
- Park/remove includes an owned unpinned preview, closes every file tab through its own provider, collects displaced/outstanding flushes by exact project identifier, and races all matching tasks against a true 30-second timeout before exactly-once shutdown; VibeSpace switch eagerly prunes outgoing groups (F021-R30, R34).
- Browser snapshots are queried with qualified plus unambiguous legacy keys but deduplicated and persisted once under only the qualified identifier (F021-R31).
- Canonical SSH migration recognizes the prior raw full identifier and all supported aliases, moves complete per-project state to one canonical key, canonicalizes/deduplicates parent identity sets without re-signing untrusted input, loads parked/unresolved configs, and preserves dormant settings and shortcut slots (F021-R35).

- Multi-folder selection creates one project per folder with no duplicates
- Focus fallback chain works correctly when projects are removed
- Terminal hydration order prioritizes focused project
- Layout splitter positions survive app restart
- Parked projects do not hydrate sessions on vibespace open and do not appear in the project rail (F021-R09, R14)
- Park/unpark round-trip preserves terminals (via terminalEntries) and browsers (via browserSessionEntries) (F021-R10, R11)
- Files tab renders a "Parked Projects" section with activate context menu (F021-R12, R13)
- Single-click on a content-viewer tab whose owning project differs from the focused project switches focus (F021-R15, R16)
- Click-to-select is idempotent — already-focused projects do not re-trigger focus (F021-R15)
- "Remove Project" is available on both active and parked project context menus; removing an active project applies focus fallback, removing a parked project drops it without activation; neither prompts for confirmation (F021-R18, R19)
- Active project-root nodes expose the shared location-appropriate `ProjectNodeContextMenu`; local roots include Open in System and Reveal in Finder, while remote/SSH roots include Open in System and Download… but never Reveal in Finder. The menu remains identical across the classic Files pane and unified/combined sidebar (F021-R20, R21, R23)
- "Open in Terminal" always adds a new terminal at the project root; applicable actions route through the same FileTreeAction handlers as file/folder nodes (F021-R20, R21)
- Parked `ssh://` rows remain inactive, use the shared current/legacy parser, show literal host/non-default port plus only `…/basename`, omit user/ancestors, hash the accessibility identifier, and expose only Activate Project and Remove Project (F021-R24)

## Static Test Inventory and Execution Status

Final validation evidence is production build and test-build/compilation only; no test case was executed and no test pass is claimed.

| Scope | Static Test File / Gap |
|---|---|
| Canonical SSH persistence | `VibeSpaceManagementServiceTests.testCanonicalRemoteIdentifierMigratesPriorRawFullIdentifierAndAllProjectState` directly covers full-config migration from the prior raw full identifier, alias deletion, browser/shortcut reads, canonical `loadProjectConfigs`, parked deduplication, and immediate rewrite of a trusted parent. Earlier tests cover raw-path and malformed-normalization aliases. Runtime preservation of every unresolved/parked settings dictionary remains production-source inspection. |
| Park/unpark model transitions, shortcut uniqueness, and same-root board identity | Static source exists in `VibeSpaceStateParkingTests`, `VibeSpaceStateTestsOverridesAndPaths`, `VibeSpaceStatePropertyTests`, and `VibeSpaceTerminalBoardStoreBulkMoveTests`; none ran. |
| Close serialization and retained dirty buffers | `DocumentBufferStoreTests.test_closeBuffer_waitsForActiveSaveThenFlushesLaterEdit` and `.test_closeBuffer_retainsDirtyBufferWhenFlushFails`; these do not test the coordinator's true timeout race or exactly-once shutdown. |
| Per-tab provider/worker retention | `EditorGroupStoreTests.testDockedFileViewerCoordinatorRemoveGroupFlushesAfterViewModelRelease` and `.testCloseAllTabsFlushesNonActiveDirtyFileThroughItsOwnProvider`; displaced/outstanding project-key tracking remains production-source inspection only. |
| Remote source control | `VibeSpaceSourceControlViewModelTests.testDiscoverRepositoriesUsesRemoteGitExplorerBackend` and `.testRemoteRepositoryRefreshUsesGitExplorerState` cover discovery/refresh plumbing only. Exact same-root attachment, non-empty staged-then-working concatenation in a preloaded qualified tab, and exact untracked provider routing remain production-source inspection only. |
| Spotlight identity | `SpotlightEnhancementTests.testDetachedFactoryAttachesEveryDirectKindAndRetainsCanonicalCallbacksAndIdentity` checks every direct persistent source kind copied by detached attachment. Its temporary-shortcut and permanent-standalone tests cover those narrow detached routes; the complete direct/temporary/split/permanent/ACP/link/file/browser/editor matrix remains production-source inspection. |
| Browser migration/persistence and lifecycle orchestration | Qualified-plus-unambiguous-legacy querying, qualified-only persistence, unpinned cleanup, project-keyed outstanding flush collection, the true 30-second race, exactly-once shutdown, eager VibeSpace pruning, and mounted window behavior remain production-source inspection/manual gaps. |

---

## Open Questions

- Should bulk park (multi-select) be added in a future iteration? Currently single-project only (F021-R13).

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-10-23 | Added F021-R35/S46 for canonical SSH migration across trusted parent state, complete per-project aliases, live/unresolved/parked loading, and dormant runtime settings/shortcut preservation; corrected final static/build inventory. | — |
| 2026-10-23 | Added F021-R32–R34/S43–S45 for exact remote repository/diff/provider ownership, complete Spotlight and unique shortcut identity, project-keyed displaced/outstanding flushes, a true flush-vs-30-second-timeout race, and exactly-once shutdown; narrowed evidence to static/build-only source. | — |
| 2026-10-23 | Added F021-R30–R31/S41–S42 for save-safe project/VibeSpace teardown and canonical browser snapshot persistence; corrected shutdown deferral, unpinned preview cleanup, qualified-plus-legacy query versus qualified-only persistence, and compile/static-only coverage. | — |
| 2026-10-20 | Added F021-R25–R29/S36–S40 for automatic board cleanup, host-qualified fail-closed ownership, and ownership-preserving restoration; later lifecycle corrections are recorded above. | — |
| 2026-10-20 | Corrected park orchestration and remote publication boundary semantics; validation evidence remained compile/static only with no executed pass. | — |
| 2026-09-09 | Enabled creating and immediately selecting a new directory in local Add Project pickers (F021-R22, S32). | — |
| 2026-07-07 | Expanded the shared project-node context menu across both explorer surfaces (F021-R20–R21, S27–S31). | — |
| 2026-06-03 | Added active and parked project removal (F021-R18–R19, S25–S26), with no confirmation prompt. | — |
| 2026-05-22 | Added project parking (F021-R09–R14), click-to-select (F021-R15–R17), and cross-surface scenarios S16–S24. | — |
| 2026-04-15 | Initial draft — extracted from F014 Navigation. | — |
