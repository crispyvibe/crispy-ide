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

### F036-R07: VibeSpaces Management Category

App Settings MUST include a `VibeSpaces` category that lists every vibespace currently on disk (recent and non-recent) and supports the following operations:

- Open a vibespace (single-click in the row's Open icon, double-click the row, or single-row selection + toolbar `Open`); opening MUST dismiss the settings surface and route through the same flow used by the welcome recents list.
- Bulk-delete one or more vibespaces (per-row trash icon, Cmd-click multi-select + toolbar `Delete`, or right-click context menu); destructive operations MUST require explicit user confirmation via an alert with single/many message variants. Deletion MUST close any active session bound to a deleted vibespace before pruning persisted state.
- Search by vibespace name or any project path (case-insensitive substring match).
- Render every project path as a comma-separated list of clickable directory-name links; clicking a link MUST open that folder in Finder. Each link MUST expose the full path as a hover tooltip.

The list MUST load progressively (batched config reads with runloop yields between batches) so libraries with many vibespaces remain responsive. Recents MUST sort to the top in MRU order; non-recent vibespaces MUST sort alphabetically.

## Scenarios

### Scenario F036-S01: App settings open in dedicated full-page settings view

**Given** the app is running
**When** user clicks `App Settings` from toolbar/menu or presses `Cmd+,`
**Then** a dedicated `App Settings` view is presented in the main window
**And** settings use split navigation with categories on the left and selected detail content on the right
**And** categories include `Account`, `Appearance`, `VibeSpaces`, `Keyboard Shortcuts`, `Terminal`, `AI Services`, `Agents`, `Updates`, `Experimental`, `Connections`, and `Reset`
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

### Scenario F036-S06: VibeSpaces tab opens, deletes, and searches

**Given** `App Settings` view is open
**And** the user has multiple vibespaces on disk
**When** the user selects `VibeSpaces`
**Then** every vibespace is listed in a multi-select table with columns `Name`, `Project Folders`, and `Actions`
**And** recent vibespaces appear at the top in MRU order
**And** typing in the search field filters by name or any project path
**And** clicking a project-folder link opens that directory in Finder
**And** clicking the row's trash icon (or selecting rows + clicking `Delete`) opens a confirmation alert before pruning persisted state
**And** clicking the row's Open icon (or double-clicking a row) dismisses settings and opens that vibespace
**And** all interactive elements scale with the user's chrome scale

## Acceptance Criteria

- App Settings opens within 200ms.
- Split navigation categories are clickable with full-row hit targets.
- Shortcut customization persists across app restarts.
- SSH profile management is available from Connections.
- App Settings does not inline-edit vibespace/project-scoped state.
- VibeSpaces category lists all on-disk vibespaces; multi-select bulk delete confirms before pruning; search matches name and any project path; project-folder links open the chosen directory in Finder.

## Open Questions

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Extracted from docs/features/app-shell/feature.md (APP-044, APP-077, APP-078) | — |
| 2026-04-27 | Re-scoped App Settings to app-level categories and moved visual/chrome settings under Appearance | — |
| 2026-05-26 | Added F036-R07 + F036-S06 covering the VibeSpaces management category (multi-select bulk delete, search, project-folder Finder links, async batched load) | — |
