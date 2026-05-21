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

---

## Acceptance Criteria

- Multi-folder selection creates one project per folder with no duplicates
- Focus fallback chain works correctly when projects are removed
- Terminal hydration order prioritizes focused project
- Layout splitter positions survive app restart

---

## Open Questions

- Should project removal prompt for confirmation?

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Initial draft — extracted from F014 Navigation | — |
