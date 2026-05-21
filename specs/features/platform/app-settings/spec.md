# App Settings — Spec

Status: draft

## Overview

App Settings covers app-level preferences: account state, appearance, app-wide keyboard shortcuts, terminal defaults, AI service defaults, agent defaults, update delivery, experimental feature gates, connection profiles, and reset controls. VibeSpace and project settings are covered by F022 and are not edited inline in App Settings.

## Dependencies

- F034 (SSH Remote Development) — SSH profile management
- F015 (Theming) — appearance, typography, and chrome controls
- F016 (Keyboard Shortcuts) — app-wide shortcut customization
- F010 (tmux Integration) — tmux app setting placement
- F011 (ACP) — agent defaults and custom agents

## Requirements

### F036-R01: App Settings View

App Settings MUST open in a dedicated full-page view with split navigation and category support.

### F036-R02: Keyboard Shortcut Customization

App-wide keyboard shortcuts and terminal inline trigger shortcut MUST be viewable and customizable in app settings.

### F036-R03: SSH Profile Management

SSH connection profiles MUST be manageable in app settings.

### F036-R04: Category Ownership

App Settings MUST contain app-level settings only. VibeSpace command shortcuts, project shortcuts, project colors, startup overrides, and project shell overrides MUST remain in VibeSpace Settings.

### F036-R05: Appearance Category

Appearance MUST include visual, typography, and app chrome defaults: display mode, theme preset, custom palette, font family, font size, rail terminal font scale, text color, border style, default rail position, and app side menu dock.

### F036-R06: Terminal Category

Terminal MUST include terminal shell defaults, terminal rendering engine selection, and tmux integration controls. The terminal engine selector MUST expose explicit engine choices instead of an `Auto` option.

## Scenarios

### Scenario F036-S01: App settings open in dedicated full-page settings view

**Given** the app is running
**When** user clicks `App Settings` from toolbar/menu or presses `Cmd+,`
**Then** a dedicated `App Settings` view is presented in the main window
**And** settings use split navigation with categories on the left and selected detail content on the right
**And** categories include `Account`, `Appearance`, `Keyboard Shortcuts`, `Terminal`, `AI Services`, `Agents`, `Updates`, `Experimental`, `Connections`, and `Reset`
**And** category selection supports full-row click hit targets (not text-only taps)
**And** rows use labeled controls with aligned fields for consistent layout
**And** vibespace/project controls remain outside App Settings

### Scenario F036-S02: App-wide keyboard shortcut customization in settings

**Given** `App Settings` view is open
**When** the user selects the `Keyboard Shortcuts` category
**Then** the user can view and customize app-wide keyboard shortcuts and terminal inline trigger shortcut
**And** vibespace command shortcuts are not edited inline in App Settings
**And** changes persist in app storage

### Scenario F036-S03: Dedicated SSH profile management in app settings

**Given** `App Settings` view is open
**When** the user selects the `Connections` category
**Then** the user can manage SSH connection profiles

### Scenario F036-S04: Appearance owns visual and chrome controls

**Given** `App Settings` view is open
**When** the user selects `Appearance`
**Then** visual theme, typography, text color, border style, default rail position, and app side menu dock controls are shown together

### Scenario F036-S05: Terminal owns rendering engine

**Given** `App Settings` view is open
**When** the user selects `Terminal`
**Then** default shell and terminal engine controls are shown together
**And** the terminal engine picker defaults to `Ghostty` and does not show `Auto`
**And** tmux enablement and behavior controls are shown in the Terminal category

## Acceptance Criteria

- App Settings opens within 200ms.
- Split navigation categories are clickable with full-row hit targets.
- Shortcut customization persists across app restarts.
- SSH profile management is available from Connections.
- App Settings does not inline-edit vibespace/project-scoped state.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Extracted from docs/features/app-shell/feature.md (APP-044, APP-077, APP-078) | — |
| 2026-04-27 | Re-scoped App Settings to app-level categories and moved visual/chrome settings under Appearance | — |
