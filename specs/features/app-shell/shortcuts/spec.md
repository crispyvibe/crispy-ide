# F016 — Shortcuts

Status: draft

Sub-feature of **App Shell**.
Covers application commands and menu behavior, keyboard shortcut customization,
app-wide shortcuts settings, app-level settings, and remote SSH settings.

---

## Scenarios

### F016-S01 · Save command triggers document save behavior (APP-003)

```gherkin
Given a markdown/html document is open
When the user runs `Save Document` (`Cmd+S`)
Then the app posts `saveCurrentMarkdown`
And the editor save flow is invoked
```

### F016-S02 · Find command opens find behavior (APP-004)

```gherkin
Given an editable document is open
When the user runs `Find in Document` (`Cmd+F`)
Then the app posts `showFindInDocument`
And the find bar is opened in the editor pane
```

### F016-S03 · Replace command opens replace behavior (APP-005)

```gherkin
Given an editable document is open
When the user runs `Replace in Document` (`Cmd+Shift+H`)
Then the app posts `showReplaceInDocument`
And replace controls are shown in the editor pane
```

### F016-S04 · Terminal clipboard commands target active terminal tab (APP-006)

```gherkin
Given a terminal tab is active
When the user runs `Copy in Terminal` or `Paste in Terminal`
Then the app posts terminal clipboard notifications
And terminal copy/paste is applied to the active tab only
```

### F016-S05 · Numbered project shortcuts are available (APP-007)

```gherkin
Given projects are open in the active VibeSpace
When the user runs `Cmd+1` through `Cmd+9`
Then the app resolves the mapped project for that shortcut slot
And if a mapped project exists it becomes the focused project
And if no explicit mapping exists the app falls back to positional focus for compatibility
```

### F016-S06 · App visibility commands are available in command menu (APP-008)

```gherkin
Given the app is running
When the user selects hide/show visibility actions
Then the app performs native macOS hide, hide others, or show all behavior
```

### F016-S07 · About command opens CrispyVibes website (APP-009)

```gherkin
Given the app menu is available
When the user selects `About Crispy`
Then the default browser opens `https://crispyvibe.com`
```

### F016-S08 · App settings are available from toolbar and Cmd+, (APP-050)

```gherkin
Given the app is running
When user clicks `App Settings` in the toolbar or runs `Settings…` (`Cmd+,`)
Then a dedicated full-page `App Settings` view is presented in the main window
And settings use split navigation with categories on the left and selected detail content on the right
And settings changes persist in app storage keys
```

### F016-S09 · App settings provide global appearance, layout, and service defaults (APP-051)

```gherkin
Given `App Settings` view is open
When user configures settings within `General`, `Layout`, or `Text Services`
Then appearance supports `Auto`, `Light`, and `Dark`
And quick-select theme presets include both dark and light palettes
And custom token editing is available in `General`
And typography controls include font family, base font size, compact rail font size, and global text color token
And compact rail terminal text size is clamped to allowed range
And global rail layout defaults are stored for new VibeSpaces
And text service CLI profile, command, arguments, pass-agent toggle, default agent, and prompt templates are persisted
```

### F016-S10 · Keyboard shortcuts navigate projects without leaving current vibespace canvas (APP-055)

```gherkin
Given a VibeSpace contains multiple Projects
When user runs `Cmd+1` to `Cmd+9` or `Cmd+Option+[ / ]`
Then mapped/adjacent Project selection changes
And active terminal focus is requested for the selected Project
```

### F016-S11 · Keyboard shortcuts navigate terminal tabs within selected project (APP-056)

```gherkin
Given selected Project has one or more terminal tabs
When user runs `Cmd+Option+Up` / `Cmd+Option+Down`
Then the selected Project cycles terminal tabs with wrap-around behavior
And keyboard focus is requested for the new active terminal tab
```

### F016-S12 · App-wide keyboard shortcut customization in settings (APP-077)

```gherkin
Given `App Settings` view is open
When the user selects the `Shortcuts` category
Then the user can view and customize app-wide keyboard shortcuts
And changes persist in app storage
```

### F016-S13 · Dedicated SSH profile management in app settings (APP-078)

```gherkin
Given `App Settings` view is open
When the user selects the `Remote SSH` category
Then the user can manage SSH connection profiles
And this feature is marked as experimental
```

---

## Requirements

| ID | Requirement |
|----|-------------|
| F016-R01 | Cmd+S, Cmd+F, Cmd+Shift+H trigger save, find, and replace via notification posts |
| F016-R02 | Terminal clipboard commands target the active terminal tab only |
| F016-R03 | Cmd+1–9 resolve mapped project shortcuts with positional fallback |
| F016-R04 | App visibility commands perform native macOS hide/show behavior |
| F016-R05 | About Crispy opens crispyvibe.com in the default browser |
| F016-R06 | App Settings opens via toolbar or Cmd+, with split navigation layout |
| F016-R07 | App Settings provides appearance, layout, typography, and text service configuration |
| F016-R08 | Cmd+Option+[/] navigates adjacent projects; Cmd+Option+Up/Down cycles terminal tabs |
| F016-R09 | App-wide keyboard shortcuts are customizable in the Shortcuts settings category |
| F016-R10 | SSH profile management is available in App Settings → Connections |
