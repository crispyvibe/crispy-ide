# App Settings — Technical Design

## Overview

App Settings is a split-view sheet with a sidebar listing app-level categories and a detail panel. Categories: Account, Appearance, Keyboard Shortcuts, Terminal, AI Services, Agents, Updates, Experimental, Connections, and Reset. Settings are persisted via UserDefaults with compiled defaults as fallbacks.

## Architecture

### Surface

- Split-view panel: sidebar category list (left) + detail panel (right).
- Sheet title from `AppStrings.Settings.appTitle` / `appSubtitle`.
- "Done" button closes the sheet.
- Categories defined in `AppSettingsCategory` enum.
- Connections category is always visible and owns SSH profile management.
- VibeSpace-scoped command shortcuts and project settings are not edited inline in App Settings. They remain in VibeSpace Settings.

### Category Summary

| Category | Subtitle | Key Controls |
|---|---|---|
| Account | Sign in to enable cloud-backed features | Apple sign-in via Cognito, sign-out |
| Appearance | Visual, typography, and chrome defaults | Display mode, theme presets (28), custom palette editing, font family, font size, rail font scale, text color, border shape, border visibility, default rail position, app side menu dock |
| VibeSpaces | Open and remove vibespaces from the full library | Multi-select Table, search by name or path, per-row Open + Delete icons, comma-separated Finder-link directory names, async batched load |
| Keyboard Shortcuts | App-wide keyboard shortcut customization | Shortcut bindings, terminal inline trigger |
| Terminal | Shell defaults, rendering backend, and tmux behavior | Default shell (zsh/bash), terminal engine (Ghostty/SwiftTerm), tmux enablement and behavior |
| Updates | Automatic checks and update feed configuration | Auto-check toggle, feed URL, check now, reset feed |
| AI Services | CLI command defaults and reusable prompt templates | CLI profile, trust mode, command, arguments, agent, rephrase/research prompts |
| Agents | Agent Conversation Protocol settings | ACP default agent, trust mode, model, reasoning, custom agents |
| Experimental | Preview features that are still in development | Terminal insight and ACP observability toggles |
| Connections | Connect to remote machines over SSH | SSH profile management and import |
| Reset | Clear local overrides and start from a fresh machine state | Start Fresh destructive action |

## Data Flow

### Theme Resolution

1. Appearance preference determines resolved `ColorScheme` (auto defers to macOS).
2. `system` preset → `systemLight` or `systemDark` based on resolved scheme.
3. Named preset → corresponding static palette.
4. `custom` preset → decode stored JSON; fallback to system palette on decode failure.
5. Each palette declares `preferredColorScheme` based on window background luminance (dark if < 0.28).

### Theme Presets

28 presets defined in enum order: System Vibes, Midnight Mono Vibes, Graphite Dark Vibes, Ocean Dusk Vibes, Forest Night Vibes, Nord Frost Vibes, Dracula Night Vibes, Solarized Night Vibes, Sunlit Paper Vibes, Pearl Light Vibes, Mint Light Vibes, Latte Bloom Vibes, Alucard Light Vibes, Beach Day Vibes, Mall Goth Vibes, Gas Station Slushie Vibes, Citrus Deadline Vibes, Mossy Fax Machine Vibes, Arcade Carpet Vibes, Tomato Bisque Vibes, Pool Tile Vibes, Radioactive Spreadsheet Vibes, Christmas Vibes, St. Patrick Vibes, Diwali Vibes, 4th of July Vibes, After Hours Vibes, Custom Vibes.

### Palette Color Roles

10 user-editable roles: `windowBackground`, `canvasBackground`, `canvasSecondaryBackground`, `borderColor`, `accent`, `success`, `warning`, `error`, `selectionBackground`, `terminalForeground`.

Derived colors (computed): `accentStrong`, `selectionText`, `terminalCaret`, `terminalSelectionBackground`, `primaryTextColor`, `secondaryTextColor`, `tertiaryTextColor`, `directoryIconColor`, git status colors.

### Custom Theme Editing

- Per-role color pickers and hex token fields (`#RRGGBB` or `#RRGGBBAA`).
- Invalid tokens show inline errors.
- "Reset Custom" and "Use Midnight Base" reset to Midnight Mono palette.
- Switching to custom from another preset copies current palette as starting draft.

### Typography

| Setting | Options | Default |
|---|---|---|
| Font family | System Monospace, SF Mono, Menlo, Monaco, Courier | System Monospace |
| Base size | 1–100pt slider | 13pt |
| Rail terminal font scale | 1/4 (0.25×), 1/2 (0.50×), 1:1 (1.00×) | 1/2 |

### Container Style

| Setting | Options | Default |
|---|---|---|
| Border shape | Square (0pt), Rounded (8pt) | Square |
| Show borders | Toggle | On |

### Chrome Layout

These controls live in Appearance because they affect app chrome and visual organization rather than vibespace content.

| Setting | Options | Default |
|---|---|---|
| Default rail position | Left, Right, Bottom, Hidden | First-run layout default |
| App side menu dock | Left, Right | First-run app setting |

### Shell Preference Resolution

If no explicit user selection (`terminalShellPreferenceExplicitSelection` flag), stored `zsh` is treated as "no preference" and system default is used.

### AI Services

- CLI profile picker from tool catalog. Trust mode picker (Standard/Full Trust, visible for non-custom profiles).
- Command, arguments, default agent fields auto-populated on profile switch.
- Agent resolution: tool-specific env var → `CRISPYVIBES_KIRO_AGENT` → UserDefaults → compiled default.
- Rephrase and research prompt templates with `{{text}}` placeholder support.
- Reset Defaults button restores all text service settings.

### Agents

- Default ACP agent picker from discovered available agents.
- Direct integrations expose trust mode, model, and reasoning defaults.
- Custom agents can be added or deleted from app-level storage.

### VibeSpaces

The VibeSpaces panel is built around three pieces:

- `AppSettingsVibeSpacesContext` (Features/Settings/Support) — bundles `VibeSpaceManaging`, `onOpenVibeSpace: (VibeSpaceConfigFile) -> Void`, and `onDeleteVibeSpaces: (Set<UUID>) -> Void`. Threaded through `AppSettingsSheetView.init` like the existing `AppShortcutVibeSpaceContext`. Constructed in `ContentViewVibeSpaceSettingsActions.appSettingsSheet()`.
- `ManageVibeSpacesViewModel` (Features/Settings/ViewModels) — `@MainActor ObservableObject`. `@Published entries`, `isLoading`, `selection: Set<UUID>`, `searchQuery`. `filteredEntries` matches name + any project path. Public API: `load`, `open(_:)`, `openSelected`, `deleteSelected`, `deleteIDs(_:)`. Async load batches per-vibespace JSON+HMAC reads in groups of 25 with `Task.yield()` between batches; a `loadGeneration` token cancels stale loads.
- `AppSettingsSheetViewVibeSpaces.swift` (Features/Settings/Views) — extension on `AppSettingsSheetView` providing `vibespacesCategoryContent`. The panel is a `SettingsCard` containing search + toolbar + SwiftUI `Table(_, selection:)` with three columns (Name, Project Folders, Actions) + footer. The Project Folders cell renders each path as a `Button(.link)` whose `.help(_:)` exposes the full path; tap calls `NSWorkspace.shared.open(URL(fileURLWithPath:))`. The Actions cell hosts borderless Open / Delete icons. `contextMenu(forSelectionType: UUID.self)` provides right-click + double-click handlers via `primaryAction`. All metrics (`spacing`, `chromeSize`, `controlSize`) flow through `crispyvibesUIScale`; all text uses `AppTypographyTokens.scaledChromeSystem(13)`.

Bulk delete routes through `HomeCatalogCoordinator.deleteVibeSpaces(ids:)`, which closes the active session if its ID is in the set, then calls `VibeSpaceManagementService.deleteVibeSpace(id:)` per entry.

## API / Command Contracts

### Reset (Start Fresh)

`resetLocalAppState` executes in order:

1. Cancel catalog loading and vibespace hydration
2. Shut down displayed vibespaces and standalone terminal boards
3. `removePersistentDomain(forName:)` — wipe all UserDefaults
4. Prune vibespace catalog
5. Reset app storage, layout, shelf store, walkthrough controller
6. Clear displayed vibespaces, shell store, hydration flags
7. Cancel welcome vibespace creation
8. Dismiss terminal spotlight and link preview
9. Clear expanded sidebar project paths
10. Re-apply compiled default preferences
11. Restore auth defaults from Info.plist

## State Management

### Key UserDefaults Keys

| Key | Purpose |
|---|---|
| `crispyvibesThemeBorderShape` | Border shape preference |
| `crispyvibesThemeBorderVisible` | Border visibility toggle |
| `codeFontFamily` | Font family selection |
| `terminalShellPreferenceExplicitSelection` | Whether user explicitly chose a shell |
| `crispyvibes.terminal.engine` | Terminal engine selection |
| `autoUpdateChecksEnabled` | Auto update check toggle |
| `appUpdateFeedURL` | Update feed URL override |
| `featureWalkthroughCompleted` | Walkthrough completion flag |

### Feature Walkthrough

Currently disabled (`isWalkthroughEnabled = false`). 6-step onboarding overlay controlled by `FeatureWalkthroughController`. Auto-presentation evaluates once per session when a vibespace becomes available. Can be triggered manually from toolbar. Environment variables for UI testing: `CRISPYVIBES_UI_TEST_FORCE_WALKTHROUGH`, `CRISPYVIBES_UI_TEST_DISABLE_AUTO_WALKTHROUGH`, `CRISPYVIBES_UI_TEST_RESET_WALKTHROUGH`, `CRISPYVIBES_UI_TEST_MODE`.

## Dependencies (frameworks, libraries)

- `SwiftUI` — settings views, color pickers, segmented controls
- `AppKit` — `NSFont` for font resolution, `NSColorPanel`
- `Sparkle` — update settings integration
- `AuthenticationServices` — account sign-in (via CognitoAuthService)

## Platform Considerations

- Display mode "Auto" defers to macOS system appearance; non-system theme presets override the appearance setting (warning banner shown).
- Default rail position applies to new vibespaces only; existing vibespaces retain their saved layout.
- Side menu auto-moves to left when vibespace rail is docked on right.
- Surface Occlusion setting was removed after restore regressions.

## Performance Constraints

- Theme palette changes apply immediately via `@Observable` propagation.
- UserDefaults writes are lightweight; no batching needed.

## Migration / Rollout Notes

_None._

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-26 | Added VibeSpaces management category architecture (panel, view model, context) | — |
