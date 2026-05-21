# F022 — VibeSpace Settings

Status: draft

Domain: **VibeSpace (D2)**.
Covers vibespace settings view, startup defaults, per-folder startup overrides,
shortcut assignment, and vibespace maintenance actions.

> Cross-reference: F014 (Navigation) retains the title bar action that opens
> VibeSpace Settings. The settings content and behavior live here.

---

## Dependencies

- F020 (VibeSpace Lifecycle) — vibespace must exist to have settings
- F021 (VibeSpace Projects) — project folders referenced in settings
- F005 (Terminal Presets) — startup profiles reference presets

---

## Scenarios

### F022-S01 · VibeSpace settings open in dedicated full-page settings view (APP-044)

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

### F022-S02 · VibeSpace startup defaults apply across hydrated Projects (APP-045)

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

### F022-S03 · Per-folder startup overrides supersede vibespace defaults (APP-046)

```gherkin
Given VibeSpace settings include an enabled startup override for a specific folder path
When startup is applied for that Project
Then the folder override command/preset is used for launch
And override controls are only shown when that folder's override toggle is enabled
And VibeSpace defaults are used for folders without overrides
```

### F022-S04 · VibeSpace settings assign deterministic shortcuts per project folder (APP-047)

```gherkin
Given VibeSpace settings are open with one or more project folders
When user selects a `Shortcut` value (`Cmd+1` to `Cmd+9`) for a folder row
Then that folder is mapped to the selected shortcut slot
And mapping persists in VibeSpace metadata by normalized folder path
And shortcut mapping is restored when the VibeSpace is reloaded
```

### F022-S05 · Shortcut slots remain unique across folders (APP-048)

```gherkin
Given one folder is already mapped to a shortcut slot
When user assigns the same shortcut slot to a different folder
Then the new folder takes ownership of that slot
And the previous folder is reassigned during normalization so no duplicate slot remains
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F022-R01 | VibeSpace Settings uses split navigation with vibespace, shortcuts, and projects categories |
| F022-R02 | Startup defaults apply per-vibespace with per-folder overrides |
| F022-R03 | Each startup profile supports None, Preset, or Command mode |
| F022-R04 | Shortcut slots (Cmd+1–9) are unique across folders with deterministic assignment |
| F022-R05 | VibeSpace-creation controls remain outside VibeSpace Settings |

---

## Acceptance Criteria

- Settings view renders split navigation with all three categories
- Startup defaults apply to focused project first, deferred for others
- Per-folder overrides take precedence over vibespace defaults
- Duplicate shortcut slots are resolved automatically

---

## Open Questions

- Should settings support import/export for vibespace configuration sharing?

---

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Initial draft — extracted from F014 Navigation | — |
