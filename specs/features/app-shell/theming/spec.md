# F015 — Theming

Status: draft

Sub-feature of **App Shell**.
Covers theme presets, custom tokens, light/dark mode, border shape/visibility/color,
font family, project color coding, and theme persistence.

---

## Scenarios

### F015-S01 · User chooses automatic theme (APP-012)

```gherkin
Given the title bar theme picker is visible
When the user selects `Auto`
Then the app uses system color scheme
And the preference is persisted in app storage
```

### F015-S02 · User chooses forced light or dark mode (APP-013)

```gherkin
Given the title bar theme picker is visible
When the user selects `Light` or `Dark`
Then the app enforces that color scheme across panes
And the selection is persisted in app storage
```

### F015-S03 · Focused Project color selection persists (APP-041)

```gherkin
Given a focused Project is open
When user clicks the Project color swatch and selects a color from the picker popover
Then focused Project title text uses the selected color
And focused Project folder icon uses the selected color
And focused Project frame accent uses the selected color
And project color is persisted in VibeSpace metadata
```

### F015-S04 · Stacked Project cards show persisted Project colors (APP-042)

```gherkin
Given VibeSpace metadata contains Project colors
When stacked rail cards render
Then each card shows its colorized stack icon and colored border accent
And stacked Project title text uses that Project color
```

### F015-S05 · Clearing Project color restores default styling (APP-043)

```gherkin
Given a Project has a selected custom color
When user clears that Project color in the color popover
Then Project title styling falls back to default text color
And Project accent styling falls back to default accent behavior
And no custom Project color is persisted for that Project
```

### F015-S06 · Packaged themes and custom token editing are managed in App Settings (APP-058)

```gherkin
Given `App Settings` view is open
When user selects a packaged theme preset or switches to `Custom`
Then all app surfaces consume colors from the centralized theme palette
And custom token edits are persisted as JSON in app storage
And status colors (including Git state badges) resolve from theme semantic tokens instead of view-level hardcoded colors
```

### F015-S07 · Newly added folders receive a first-time auto-assigned color (APP-063)

```gherkin
Given a VibeSpace is created or folders are added to an existing VibeSpace
When a folder path is first registered as a Project in that VibeSpace
Then the app assigns an initial color tag automatically
And that auto-assigned color persists with VibeSpace metadata
And any user-selected color override remains unchanged on later hydration
```

### F015-S08 · Border shape setting toggles all pane corners (APP-080)

```gherkin
Given the user opens theme settings
When the user changes border shape between square and rounded
Then all container views (sidebar, terminal board, file previewer, Vibe Cast, settings panels, explorer, git explorer) update their corner style immediately
And no app restart is required
```

### F015-S09 · Border visibility setting shows or hides pane borders (APP-081)

```gherkin
Given the user opens theme settings
When the user toggles border visibility on or off
Then all container views show or hide their borders immediately
And the change propagates reactively to all subscribed views
```

### F015-S10 · Border color setting applies across all panes (APP-082)

```gherkin
Given border visibility is enabled
When the user picks a border color in theme settings
Then all container views render borders in the selected color immediately
```

### F015-S11 · Font family setting updates all text (APP-083)

```gherkin
Given the user opens theme settings
When the user selects a different font family
Then all text across the app updates to the selected font family immediately
And font size remains controlled by existing resize mechanisms independently
```

### F015-S12 · Theme preferences persist and restore on launch (APP-084)

```gherkin
Given the user has customized border shape, border visibility, border color, and font family
When the app is quit and relaunched
Then all theme preferences are restored from app-level storage
And the app renders with the persisted theme on startup
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F015-R01 | Theme picker supports Auto, Light, and Dark modes with immediate enforcement |
| F015-R02 | Theme preference persists in app storage and restores on launch |
| F015-R03 | Project color selection applies to title, icon, and frame accent; persists in vibespace metadata |
| F015-R04 | Stacked cards render per-project colors from vibespace metadata |
| F015-R05 | Clearing project color restores default styling |
| F015-R06 | Packaged theme presets and custom token editing are centralized in App Settings |
| F015-R07 | Custom token edits persist as JSON; semantic tokens drive status colors |
| F015-R08 | Newly added folders receive auto-assigned colors that persist with vibespace metadata |
| F015-R09 | Border shape, visibility, and color apply reactively to all container views without restart |
| F015-R10 | Font family updates all text immediately; font size is independent |
| F015-R11 | All theme preferences (border shape, visibility, color, font family) persist and restore on launch |
