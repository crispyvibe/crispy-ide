# F014 — Navigation

Status: draft

Sub-feature of **App Shell**.
Covers window management, canvas layout, sidebar tab system, title bar,
developer tools shortcut, and diagnostics export.

> **VibeSpace domain migration (2026-04-15):** VibeSpace lifecycle, project management,
> vibespace settings, and color coding scenarios are now authoritative in the VibeSpace
> domain (D2). Scenarios below that overlap with F020–F023 are retained here as
> navigation-context cross-references. The VibeSpace specs are the source of truth for:
>
> - **F020** `vibespace/lifecycle/` — vibespace creation, catalog, dashboard, view modes, file integrity
> - **F021** `vibespace/projects/` — add/remove projects, focus, hydration, layout persistence
> - **F022** `vibespace/settings/` — vibespace settings, startup defaults, shortcut assignment
> - **F023** `vibespace/color-coding/` — project color tags, auto-assignment, clearing

---

## Scenarios

### F014-S01 · App starts in UI mode when no pane task arguments are supplied (APP-001)

```gherkin
Given the app is launched normally
When command line arguments do not include `--pane-task <pane>`
Then the main window is created with `ContentView`
And the window enforces a minimum size of 960x620
```

### F014-S02 · App starts in worker mode when pane task arguments are supplied (APP-002)

```gherkin
Given the app is launched with `--pane-task <pane-kind>`
When a pane task request is read from stdin
Then the app executes the pane worker operation
And returns a JSON response on stdout
And exits without launching the UI
```

### F014-S03 · Bundle metadata uses Crispy identity (APP-010)

```gherkin
Given application bundle metadata is loaded from `Info.plist`
When app identity keys are evaluated
Then `CFBundleDisplayName` is `Crispy`
And `CFBundleName` is `Crispy`
And `CFBundleIdentifier` is `com.crispyvibe.app`
```

### F014-S04 · App icon resolves from AppIcon asset catalog (APP-011)

```gherkin
Given application bundle metadata is loaded from `Info.plist`
When icon keys are evaluated
Then `CFBundleIconName` is `AppIcon`
And app icon assets are resolved from `Assets.xcassets/AppIcon.appiconset`
```

### F014-S05 · User places project rail on the left or right (APP-014)

```gherkin
Given at least one project is open
When the user selects rail position `Left` or `Right`
Then the UI uses a horizontal split layout
And the rail width is constrained to configured limits
```

### F014-S06 · App activity rail can dock on the left or right (APP-014A)

```gherkin
Given the main app shell is visible
When the user selects app side menu dock `Left` or `Right`
Then the app activity rail docks to that edge
And its paired sidebar content docks on the same edge
And if the project rail is on the right in `Detailed` mode the app activity rail remains on the left
```

### F014-S07 · User places project rail on the top or bottom (APP-015)

```gherkin
Given at least one project is open
When the user selects rail position `Top` or `Bottom`
Then the UI uses a vertical split layout
And stacked project cards flow left-to-right in a horizontal list
```

### F014-S08 · Rail position is remembered per VibeSpace (APP-016)

```gherkin
Given a VibeSpace has a previously selected rail position
When the app relaunches and that VibeSpace is opened
Then the same rail position is restored from app layout state store
```

### F014-S09 · Left and right rail widths are persisted independently (APP-017)

```gherkin
Given a VibeSpace has rail position `Left` with a custom width
And the same VibeSpace has rail position `Right` with a different custom width
When the user switches between `Left` and `Right`
Then each position restores its own persisted width
```

### F014-S10 · Top and bottom rail heights are persisted independently (APP-018)

```gherkin
Given a VibeSpace has rail position `Top` with a custom height
And the same VibeSpace has rail position `Bottom` with a different custom height
When the user switches between `Top` and `Bottom`
Then each position restores its own persisted height
```

### F014-S11 · Add Project supports selecting multiple folders (APP-019)

```gherkin
Given the user clicks `Add Project`
When the folder picker returns multiple directories
Then one project is created per selected folder
And duplicates in the same picker result are ignored by normalized path
```

### F014-S12 · Existing project folder is not duplicated (APP-020)

```gherkin
Given a selected folder is already open as a project
When the same folder is selected again in Add Project
Then no duplicate project is created
And the existing project becomes focused
```

### F014-S13 · New project becomes focused (APP-021)

```gherkin
Given one or more folders are selected
When project creation succeeds
Then the last processed project becomes focused
And an active terminal is ensured for that project root
```

### F014-S14 · Empty state is shown when no projects exist (APP-022)

```gherkin
Given no projects are open
When ContentView renders
Then an empty state panel is shown
And the primary call to action is `Add Project(s)`
And terminal-only vibespace mode also shows an `Add Project(s)` call to action instead of empty terminal panels
```

### F014-S15 · Focused project pane is shown when projects exist (APP-023)

```gherkin
Given one or more projects are open
When ContentView renders
Then one project is shown in the focused pane
And all other projects appear in the project rail
```

### F014-S16 · Detailed view uses sidebar for file navigation (APP-023A)

```gherkin
Given one or more projects are open
And vibespace canvas mode is `Detailed`
When ContentView renders
Then the focused project canvas shows project header, editor content, and terminal content
And file navigation is owned by the vibespace sidebar instead of an embedded per-project explorer
```

### F014-S17 · Focused project shows full terminal when no file is active (APP-023B)

```gherkin
Given one or more projects are open
And the focused Project has no active previewed or opened file
When the focused project canvas renders
Then the terminal takes the full main canvas area below the project header
```

### F014-S18 · Focused project splits editor above terminal when a file is active (APP-023C)

```gherkin
Given one or more projects are open
And the focused Project has an active previewed or opened file
When the focused project canvas renders
Then the editor is shown above the terminal
And the terminal remains available below the editor
```

### F014-S18A · Detailed view terminal tray can collapse to prioritize the main view (APP-023D)

```gherkin
Given one or more projects are open
And vibespace canvas mode is `Detailed`
And the focused project terminal tray is visible below the main view
When the user collapses the terminal tray
Then the main editor/content area expands to consume the released space
And the focused project terminal session remains available without being terminated
And the collapsed state is restored when that VibeSpace is reopened
```

### F014-S18B · Detailed view shows only one terminal session in the bottom tray (APP-023E)

```gherkin
Given one or more projects are open
And the focused Project has multiple terminal tabs
When the detailed canvas renders
Then the bottom terminal tray shows only the active terminal session
And no side-by-side terminal split presentation is shown in that tray
And other terminal tabs remain available through normal terminal tab selection
```

### F014-S19 · Stacked project rail encourages adding projects when only one project exists (APP-024)

```gherkin
Given exactly one project is open
When ContentView renders
Then the project rail shows an `Add Project(s)` call to action
And the rail does not show a passive `No Stacked Projects` placeholder
```

### F014-S20 · Selecting a stacked project card focuses it (APP-025)

```gherkin
Given multiple projects are open
When the user clicks a stacked project card
Then that project becomes focused
And terminal availability is ensured for the focused project
And keyboard focus moves to the focused project's active terminal
```

### F014-S21 · VibeSpace open hydrates focused terminal first and rail terminals next (APP-026)

```gherkin
Given a VibeSpace has multiple projects
When the user opens that VibeSpace
Then the focused project terminal is ensured first
And non-focused project terminals are hydrated progressively for rail previews
And non-focused project terminal sessions are started in background hydration order
```

### F014-S22 · Closing focused project falls back safely (APP-027)

```gherkin
Given multiple projects are open and one is focused
When the focused project is closed
Then it is removed from project list
And focus falls back to the last remaining project
```

### F014-S23 · Closing last project returns to empty state (APP-028)

```gherkin
Given only one project is open
When the project is closed
Then no focused project remains
And the app returns to empty state UI
```

### F014-S24 · Restart Project restarts all pane workers/sessions (APP-029)

```gherkin
Given a focused project is open
When the user clicks `Restart Project`
Then explorer worker restarts
And editor worker restarts and reloads the current file if one is open
And terminal pane restarts and recreates an active tab
```

### F014-S25 · Close Project removes the focused project (APP-030)

```gherkin
Given a focused project is open
When the user clicks the close icon in project header
Then the project is removed from state
And focus fallback behavior is applied
```

### F014-S26 · Stacked card shows grouped compact terminal preview (APP-031)

```gherkin
Given a stacked project has at least one terminal session
When the stacked card renders
Then one representative terminal is displayed for that project
And that representative terminal is chosen using activity-first, then recency-based ordering within the project's visible rail terminals
And additional visible terminals for that project remain grouped behind the representative terminal until hover or keyboard focus expands the stack
And terminal density is compact for higher information density
```

### F014-S27 · Stacked card surfaces project activity state (APP-032)

```gherkin
Given a stacked project has terminal output activity in any tab
When the stacked card header renders
Then the stack icon keeps the Project color treatment
And the header shows the same inline activity indicator style used in terminal tabs until activity goes idle
```

### F014-S28 · Stacked card handles missing terminal (APP-033)

```gherkin
Given a stacked project has no terminal session
When the stacked card renders
Then a `Loading Terminal` placeholder is shown until session hydration completes
```

### F014-S29 · Stacked card opens temporary terminal spotlight (APP-033A)

```gherkin
Given a stacked project card has an available terminal session
When user double-clicks that stacked card
Then app shows a centered `Terminal Spotlight` overlay for that terminal
And focused project, file preview, and main terminal pane selection are unchanged
And stacked rail/card layout is unchanged
And spotlight dismisses on double-click, `Esc`, or backdrop click
```

### F014-S30 · VibeCast tile opens unified spotlight (APP-033B)

```gherkin
Given terminal board has a VibeCast tile
When user double-clicks the VibeCast tile
Then app shows a centered `Terminal Spotlight` overlay with VibeCast content (unified spotlight system)
And VibeCast compose input is auto-focused
And the terminal compose bar is hidden (VibeCast has its own)
And spotlight dismisses on double-click, `Esc`, or backdrop click
And two-finger horizontal swipe cycles through terminals and VibeCast in sequence
```

### F014-S31 · Dashboard summarizes active vibespace health and quick actions (APP-034)

```gherkin
Given a VibeSpace is active
When the Dashboard is shown
Then the header displays the active VibeSpace name
And summary chips show Project count and missing-path count when unresolved folders exist
And quick actions include `Create VibeSpace`, `Add Project`, and `VibeSpace Settings`
```

### F014-S32 · Creating a vibespace replaces the current active vibespace context (APP-035)

```gherkin
Given an active VibeSpace is open
When the user runs `Create VibeSpace` from the toolbar or Dashboard
Then selected folders become Projects in a new VibeSpace snapshot
And the new VibeSpace becomes the only active VibeSpace in memory
And catalog persistence stores only that active VibeSpace snapshot
```

### F014-S33 · Catalog hydration restores one active vibespace and reconciles paths (APP-036)

```gherkin
Given persisted vibespace catalog contains one or more VibeSpace snapshots
When the app hydrates the catalog on launch
Then one VibeSpace is selected as active for UI rendering
And existing folders load as Projects
And unavailable folders remain tracked as unresolved paths
```

### F014-S34 · User removes one unresolved folder path (APP-037)

```gherkin
Given a VibeSpace has unresolved paths
When user clicks `Remove` on a specific missing path
Then that missing path entry is removed from that VibeSpace
And the updated catalog is persisted
```

### F014-S35 · User relinks one unresolved folder path (APP-038)

```gherkin
Given a VibeSpace has unresolved paths
When user clicks `Relink` and chooses a replacement folder
Then the missing path entry is replaced by the chosen folder
And if the replacement folder exists it is loaded as a Project
And the updated catalog is persisted
```

### F014-S36 · User drags editor and terminal splitters (APP-039)

```gherkin
Given focused Project view is visible
When user drags explorer/editor or editor/terminal dividers
Then layout fractions are updated in memory for that Project
And fractions are persisted in app layout state store using normalized Project path key
```

### F014-S37 · Reopen restores persisted Project layout (APP-040)

```gherkin
Given a Project has persisted pane layout in app layout state store
When the Project is reopened
Then explorer/editor split ratio is restored
And terminal pane height ratio is restored
```

### F014-S38 · VibeSpace settings open in dedicated full-page settings view (APP-044)

```gherkin
Given a VibeSpace is active
When user clicks `VibeSpace Settings` from toolbar or Dashboard
Then a dedicated `VibeSpace Settings` view is presented in the main window
And settings use split navigation with categories on the left and selected detail content on the right
And categories include `vibespace` (VibeSpace Settings), `shortcuts` (Shortcuts), and `projects` (Projects)
And category selection supports full-row click hit targets (not text-only taps)
And rows use labeled controls with aligned fields for consistent layout
And vibespace-creation controls remain outside VibeSpace Settings
```

### F014-S39 · VibeSpace startup defaults apply across hydrated Projects (APP-045)

```gherkin
Given a VibeSpace defines startup defaults (terminal count, per-terminal startup profiles)
When user opens that VibeSpace
Then focused Project startup is applied first
And remaining Projects defer vibespace-default startup profiles until their first focus to avoid multi-project startup contention
And remaining Projects still hydrate terminal sessions in background order for live rail previews
And each startup profile can launch either a preset or a custom command for its terminal slot
And each terminal row selects startup mode (`None`, `Preset`, `Command`) before showing mode-specific inputs
And startup defaults are applied once per Project for that session
```

### F014-S40 · Per-folder startup overrides supersede vibespace defaults (APP-046)

```gherkin
Given VibeSpace settings include an enabled startup override for a specific folder path
When startup is applied for that Project
Then the folder override command/preset is used for launch
And override controls are only shown when that folder's override toggle is enabled
And VibeSpace defaults are used for folders without overrides
```

### F014-S41 · VibeSpace settings assign deterministic shortcuts per project folder (APP-047)

```gherkin
Given VibeSpace settings are open with one or more project folders
When user selects a `Shortcut` value (`Cmd+1` to `Cmd+9`) for a folder row
Then that folder is mapped to the selected shortcut slot
And mapping persists in VibeSpace metadata by normalized folder path
And shortcut mapping is restored when the VibeSpace is reloaded
```

### F014-S42 · Shortcut slots remain unique across folders (APP-048)

```gherkin
Given one folder is already mapped to a shortcut slot
When user assigns the same shortcut slot to a different folder
Then the new folder takes ownership of that slot
And the previous folder is reassigned during normalization so no duplicate slot remains
```

### F014-S43 · VibeSpace maintenance can reindex project folders (APP-049)

```gherkin
Given VibeSpace settings are open
When user clicks `Reindex Project Folders`
Then VibeSpace availability reconciliation runs immediately
And recovered folders move from missing paths into live projects
And unavailable folders remain tracked as unresolved paths
```

### F014-S44 · VibeSpace toggles between Detailed and Terminal Only modes on demand (APP-052)

```gherkin
Given a VibeSpace is open
When user switches vibespace view mode from toolbar picker or keyboard command
Then canvas mode updates between `Detailed` and `Terminal Only`
And switching mode does not restart terminal sessions
And selected mode is persisted per VibeSpace layout state
```

### F014-S45 · Terminal Only mode renders stable per-project terminal panes (APP-053)

```gherkin
Given Terminal Only mode is active
When vibespace canvas renders
Then each Project is shown in its own terminal pane
And selecting a pane does not move or reflow surrounding panes
And user can type directly in the selected terminal session
```

### F014-S46 · Terminal Only orientation is user-selectable per VibeSpace (APP-054)

```gherkin
Given Terminal Only mode is active
When user switches terminal-only orientation between `Vertical` and `Horizontal`
Then pane arrangement updates to the selected orientation
And selected orientation is persisted per VibeSpace
```

### F014-S47 · Terminal Only shortcut cycles terminals across vibespace panes (APP-057)

```gherkin
Given Terminal Only mode is active
And vibespace has one or more terminal tabs across one or more projects
When user runs `Ctrl+Shift+Left` or `Ctrl+Shift+Right`
Then terminal focus moves through a single wrap-around sequence across all project panes
And selected Project updates automatically when traversal crosses project boundaries
```

### F014-S48 · Title bar exposes categorized controls when a vibespace is active (APP-059)

```gherkin
Given a VibeSpace is active
When the title bar renders
Then App actions include appearance and `App Settings`
And VibeSpace actions include vibespace view mode, `Add Project`, `VibeSpace Settings`, `Close VibeSpace`, and `Create VibeSpace`
```

### F014-S49 · Active vibespace identity is shown as plain window title text (APP-060)

```gherkin
Given a VibeSpace is active
When the active VibeSpace changes
Then the macOS window title updates to the active VibeSpace name
And VibeSpace identity is not shown as a toolbar picker control
```

### F014-S50 · VibeSpace-only actions are hidden when no vibespace is active (APP-061)

```gherkin
Given no VibeSpace is active
When the title bar renders
Then VibeSpace action controls are hidden
And App actions and VibeSpace management actions remain visible
```

### F014-S51 · Window dragging is limited to title bar regions (APP-062)

```gherkin
Given the main app window is visible
When the user clicks and drags inside standard content surfaces (editor, terminal, rail, or dashboard body)
Then the window does not move
And window movement remains available from title bar and toolbar drag regions only
```

### F014-S52 · Automatic update check runs on launch when enabled and interval elapsed (APP-064)

```gherkin
Given app settings have automatic update checks enabled
And the last successful update check is older than the configured interval or has not run yet
When the app finishes launching
Then the app requests update manifest JSON from the configured update feed URL
And startup UI remains usable while the check runs in background
And the successful check timestamp is persisted
```

### F014-S53 · Launch guard intercepts transient installs before normal startup (APP-078)

```gherkin
Given Crispy is launched from a transient install location that should be moved
When `applicationDidFinishLaunching` begins
Then the install-location guard runs before service registration and other startup work
And if the user accepts the move prompt the transient instance relaunches from /Applications and terminates
And if the user declines the move prompt normal startup continues in the current instance
```

### F014-S54 · Manual check for updates always performs a fresh check (APP-065)

```gherkin
Given the app menu is available
When the user selects `Check for Updates…`
Then the app bypasses automatic interval gating
And the app requests update manifest JSON from the configured update feed URL
And result feedback is shown to the user
```

### F014-S55 · Manual check reports up-to-date status clearly (APP-066)

```gherkin
Given a manual update check succeeds
And the feed version is not newer than the current app version/build
When the check completes
Then the app shows an explicit `You're up to date` message
And the message includes the current app version metadata
```

### F014-S56 · Available update offers direct download path (APP-067)

```gherkin
Given update feed data contains a newer version than the current app version/build
When the update check completes
Then the app shows an update prompt with target version/build
And the prompt includes `Download Update` and `Later` actions
And selecting `Download Update` opens the manifest download URL in the default browser
```

### F014-S57 · App settings provide update controls (APP-068)

```gherkin
Given `App Settings` view is open
When the user selects the `Updates` category
Then the user can toggle automatic update checks
And the user can edit the configured update feed URL
And the user can trigger `Check for Updates Now` from settings
```

### F014-S58 · Manual check surfaces invalid feed or network failures (APP-069)

```gherkin
Given the configured update feed URL is invalid or unreachable
When the user runs a manual `Check for Updates…`
Then the app shows a failure message with actionable guidance
And no download flow is started
```

### F014-S59 · Remote status control is shown only for vibespaces with remote projects (APP-070)

```gherkin
Given a VibeSpace is active
When the title bar renders
Then the remote status control is shown only if the active VibeSpace contains at least one SSH-backed Project
And local-only VibeSpaces do not show a remote status control
```

### F014-S60 · Remote status control surfaces vibespace-scoped SSH health and retry actions (APP-071)

```gherkin
Given the active VibeSpace contains one or more SSH-backed Projects
When the title bar renders
Then the remote status control summarizes only the SSH connections owned by that VibeSpace
And healthy state uses a neutral remote-host icon
And connecting state uses a progress/reconnect icon
And failed or disconnected state uses a warning icon with an issue count
When the user opens the control
Then the popover lists each remote host in that VibeSpace
And the popover offers `Retry`, `Retry All`, and `Disconnect` actions when applicable
```

### F014-S61 · VibeSpace restore preserves remote project identifiers and degrades failed remotes without removing them (APP-072)

```gherkin
Given a saved VibeSpace contains one or more SSH-backed Projects identified by `ssh://user@host:port/path` URIs
When the VibeSpace is reopened
Then the remote project identifiers are restored exactly from vibespace persistence
And local projects remain available immediately
And remote projects begin reconnecting asynchronously before editor tab restore runs
And remote projects that fail to reconnect remain in the VibeSpace as degraded entries instead of being removed
```

### F014-S62 · Remote status popover manages per-host port forwards (APP-073)

```gherkin
Given the active VibeSpace contains one or more SSH-backed Projects
When the user opens the remote status control
Then each connected host section includes a `Port Forwarding` panel
And active forwards are listed as local-to-remote mappings for that host
And the user can stop an individual forward without disconnecting the host
When the host is not connected
Then adding a new port forward is disabled until that host reconnects
```

### F014-S63 · Side menu rail provides vibespace navigation tabs (APP-074)

```gherkin
Given the main app shell is visible
When the side menu rail renders
Then rail items include `files`, `sessions`, and `git`
And the rail supports dock position `left` or `right`
```

### F014-S64 · Users can hide terminal tabs from rail preview (APP-075)

```gherkin
Given a project has multiple terminal tabs
When the user hides a terminal tab from the rail preview
Then the hidden tab is removed from the visible rail list
And an expandable hidden section shows all hidden tabs
And hidden tabs can be restored to the visible rail list
```

### F014-S65 · Developer tools shortcut opens developer tools view (APP-076)

```gherkin
Given the app is running
When the user runs `Cmd+Option+D`
Then the developer tools view is opened
```

### F014-S66 · Export diagnostics from app (APP-079)

```gherkin
Given the app is running
When the user triggers diagnostics export
Then the app collects and exports diagnostic information for troubleshooting
```

### F014-S67 · VibeSpace and project config files are HMAC-SHA256 signed on save (APP-085)

```gherkin
Given a vibespace or project config file is saved
When the persistence layer writes the file
Then the file is signed with HMAC-SHA256 using a key stored in the macOS Keychain
And the signature is persisted alongside the file content
```

### F014-S68 · Tampered config files are detected on load (APP-086)

```gherkin
Given a vibespace or project config file has been modified outside the app
When the file is loaded
Then signature verification fails
And the file is treated as untrusted
```

### F014-S69 · Untrusted config files load for display but disable startup commands (APP-087)

```gherkin
Given a config file fails signature verification
When the vibespace is opened
Then vibespace name, project list, and color tags are displayed normally
And startup commands and preset launches are not auto-executed
And a non-dismissable alert identifies the affected vibespace and states that configuration was modified outside the app and startup commands are disabled for safety
```

### F014-S70 · Re-saving settings from the app restores trust (APP-088)

```gherkin
Given a vibespace config file is currently untrusted
When the user reviews and re-saves settings through the app UI
Then the file is re-signed with HMAC-SHA256
And startup command execution is re-enabled
```

### F014-S71 · Signing logic is centralized in AppPersistenceDataStore (APP-089)

```gherkin
Given any persistence service needs to save or load a signed config file
When it calls saveWithIntegrity or loadWithIntegrity on AppPersistenceDataStore
Then HMAC signing and verification are handled centrally
And no service duplicates crypto logic
```

### F014-S72 · Layout files are exempt from signing (APP-090)

```gherkin
Given a layout file (layout.json) is saved or loaded
When the persistence layer processes the file
Then no HMAC signing or verification is applied
And the file is treated as trusted by default
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F014-R01 | App launches in UI mode by default and worker mode when `--pane-task` is supplied |
| F014-R02 | Main window enforces minimum size of 960×620 |
| F014-R03 | Bundle identity uses `com.crispyvibe.app` and `Crispy` display name |
| F014-R04 | Project rail supports left, right, top, and bottom placement with independent size persistence |
| F014-R05 | App activity rail docks left or right independently of project rail |
| F014-R06 | Add Project supports multi-select and deduplicates by normalized path |
| F014-R07 | Empty state shows `Add Project(s)` CTA in both Detailed and Terminal Only modes |
| F014-R08 | Focused project terminal hydrates first; rail terminals hydrate progressively |
| F014-R09 | Closing focused project falls back to last remaining; closing last returns to empty state |
| F014-R10 | Stacked cards show grouped compact terminal previews with representative-terminal ordering and activity indicators |
| F014-R11 | Terminal Spotlight overlay opens on double-click without changing focus state |
| F014-R12 | Dashboard shows vibespace health, project count, missing-path count, and quick actions |
| F014-R13 | VibeSpace catalog persists one active vibespace; hydration reconciles paths |
| F014-R14 | Unresolved paths support remove and relink operations |
| F014-R15 | Project layout splitter positions persist per normalized project path |
| F014-R16 | VibeSpace Settings uses split navigation with vibespace, shortcuts, and projects categories |
| F014-R17 | Startup defaults apply per-vibespace with per-folder overrides |
| F014-R18 | Shortcut slots (Cmd+1–9) are unique across folders with deterministic assignment |
| F014-R19 | Canvas mode toggles between Detailed and Terminal Only without restarting sessions |
| F014-R20 | Terminal Only orientation is user-selectable and persisted per vibespace |
| F014-R21 | Title bar shows categorized app and vibespace actions; vibespace actions hide when no vibespace is active |
| F014-R22 | Window title reflects active vibespace name as plain text |
| F014-R23 | Window dragging is restricted to title bar and toolbar drag regions |
| F014-R24 | Automatic update checks run on launch with configurable interval; manual checks bypass gating |
| F014-R25 | Remote status control appears only for vibespaces with SSH-backed projects |
| F014-R26 | Remote status popover shows per-host health, retry actions, and port forwarding management |
| F014-R27 | VibeSpace restore preserves remote project URIs and degrades failed remotes |
| F014-R28 | Sidebar rail provides files, sessions, and git tabs with configurable dock position |
| F014-R29 | Terminal tabs can be hidden from rail preview and restored from hidden section |
| F014-R30 | Developer tools open via Cmd+Option+D |
| F014-R31 | Diagnostics export collects and exports troubleshooting information |
| F014-R32 | Config files are HMAC-SHA256 signed on save; tampered files disable startup commands |
| F014-R33 | Untrusted configs display data but block auto-execution; re-saving restores trust |
| F014-R34 | Signing logic is centralized in AppPersistenceDataStore; layout files are exempt |
| F014-R35 | Launch startup can intercept transient install locations and offer relocation to /Applications before normal initialization continues |
