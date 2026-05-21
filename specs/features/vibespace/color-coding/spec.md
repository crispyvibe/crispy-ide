# F023 — Project Color Coding

Status: draft

Domain: **VibeSpace (D2)**.
Covers project color selection, stacked card color display, clearing colors,
and automatic first-time color assignment.

> Cross-reference: F015 (Theming) covers theme-level accent colors.
> Scenarios here focus on per-project color tags within a vibespace.

---

## Dependencies

- F020 (VibeSpace Lifecycle) — vibespace metadata stores color tags
- F021 (VibeSpace Projects) — projects must exist to receive colors
- F015 (Theming) — accent color resolution from theme tokens

---

## Scenarios

### F023-S01 · Focused Project color selection persists (APP-041)

```gherkin
Given a focused Project is open
When user clicks the Project color swatch and selects a color from the picker popover
Then focused Project title text uses the selected color
And focused Project folder icon uses the selected color
And focused Project frame accent uses the selected color
And project color is persisted in VibeSpace metadata
```

### F023-S02 · Stacked Project cards show persisted Project colors (APP-042)

```gherkin
Given VibeSpace metadata contains Project colors
When stacked rail cards render
Then each card shows its colorized stack icon and colored border accent
And stacked Project title text uses that Project color
```

### F023-S03 · Clearing Project color restores default styling (APP-043)

```gherkin
Given a Project has a selected custom color
When user clears that Project color in the color popover
Then Project title styling falls back to default text color
And Project accent styling falls back to default accent behavior
And no custom Project color is persisted for that Project
```

### F023-S04 · Newly added folders receive a first-time auto-assigned color (APP-063)

```gherkin
Given a VibeSpace is created or folders are added to an existing VibeSpace
When a folder path is first registered as a Project in that VibeSpace
Then the app assigns an initial color tag automatically
And that auto-assigned color persists with VibeSpace metadata
And any user-selected color override remains unchanged on later hydration
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F023-R01 | Focused project color applies to title, folder icon, and frame accent |
| F023-R02 | Stacked cards display persisted project colors on icon and border |
| F023-R03 | Clearing color restores default styling and removes persisted value |
| F023-R04 | New projects receive an auto-assigned color on first registration |
| F023-R05 | User-selected color overrides are preserved across hydration |

---

## Acceptance Criteria

- Color picker popover sets color on focused project and persists to vibespace metadata
- Stacked cards render with correct per-project colors
- Clearing color removes custom value and falls back to defaults
- Auto-assignment produces a color for every new project folder

---

## Open Questions

- Should auto-assigned colors use a deterministic palette rotation or random selection?

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Initial draft — extracted from F014 Navigation and APP-063 | — |
