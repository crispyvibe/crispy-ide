# Theming — Technical Design

## Overview

The theme system provides a centralized palette of 10 color roles, 28 presets (including a user-editable custom preset), typography controls, and container style settings. All app surfaces consume colors from the resolved palette. Theme state is persisted to UserDefaults and restored on launch.

## Architecture

### Theme Resolution Pipeline

1. Appearance preference → resolved `ColorScheme` (`auto` defers to macOS)
2. If preset is `system` → palette is `systemLight` or `systemDark` based on resolved scheme
3. Named preset → corresponding static palette returned directly
4. `custom` → decode stored JSON; on failure, fall back to `systemLight` / `systemDark`
5. Each palette declares `preferredColorScheme` based on window background luminance (dark if luminance < 0.28)

When a non-System preset is active, a warning banner appears in settings explaining the theme overrides the appearance setting, with a quick-action to switch back to System.

### Display Mode

| Option | Behavior |
|--------|----------|
| Auto | Follows macOS system appearance |
| Light | Forces light appearance |
| Dark | Forces dark appearance |

## Data Flow

### Palette Color Roles

Each palette defines 10 editable color roles:

| Role | Key | Usage |
|------|-----|-------|
| Window | `windowBackground` | Window frame and title bar chrome |
| Canvas | `canvasBackground` | Primary pane/canvas surface |
| Canvas Secondary | `canvasSecondaryBackground` | Secondary pane cards, tool sections, elevated surfaces |
| Border | `borderColor` | Split lines, strokes, separator outlines |
| Accent | `accent` | Primary interactive emphasis, highlights, active controls |
| Success | `success` | Positive statuses and completion indicators |
| Warning | `warning` | Warning and caution statuses |
| Error | `error` | Error and destructive states |
| Selection Background | `selectionBackground` | Selection highlight color |
| Terminal Foreground | `terminalForeground` | Default editor and terminal text color |

### Derived Colors (computed, not user-editable)

`accentStrong`, `selectionText`, `terminalCaret` (= accent), `terminalSelectionBackground`, `primaryTextColor`, `secondaryTextColor`, `tertiaryTextColor`, `directoryIconColor`, git status colors (added / modified / deleted / renamed / conflict).

### Theme Presets

28 presets in enum order:

| # | Name | Key | Category |
|---|------|-----|----------|
| 1 | System Vibes | `system` | Adaptive |
| 2 | Midnight Mono Vibes | `midnightMono` | Dark |
| 3 | Graphite Dark Vibes | `graphiteDark` | Dark |
| 4 | Ocean Dusk Vibes | `oceanDusk` | Dark |
| 5 | Forest Night Vibes | `forestNight` | Dark |
| 6 | Nord Frost Vibes | `nordFrost` | Dark |
| 7 | Dracula Night Vibes | `draculaNight` | Dark |
| 8 | Solarized Night Vibes | `solarizedNight` | Dark |
| 9 | Sunlit Paper Vibes | `sunlitPaper` | Light |
| 10 | Pearl Light Vibes | `pearlLight` | Light |
| 11 | Mint Light Vibes | `mintLight` | Light |
| 12 | Latte Bloom Vibes | `latteBloom` | Light |
| 13 | Alucard Light Vibes | `alucardLight` | Light |
| 14 | Beach Day Vibes | `beachDay` | Light |
| 15 | Mall Goth Vibes | `mallGoth` | Dark |
| 16 | Gas Station Slushie Vibes | `gasStationSlushie` | Dark |
| 17 | Citrus Deadline Vibes | `citrusDeadline` | Light |
| 18 | Mossy Fax Machine Vibes | `mossyFaxMachine` | Light |
| 19 | Arcade Carpet Vibes | `arcadeCarpet` | Dark |
| 20 | Tomato Bisque Vibes | `tomatoBisque` | Light |
| 21 | Pool Tile Vibes | `poolTile` | Light |
| 22 | Radioactive Spreadsheet Vibes | `radioactiveSpreadsheet` | Dark |
| 23 | Christmas Vibes | `christmas` | Dark |
| 24 | St. Patrick Vibes | `stPatrick` | Dark |
| 25 | Diwali Vibes | `diwali` | Dark |
| 26 | 4th of July Vibes | `fourthOfJuly` | Dark |
| 27 | After Hours Vibes | `ph` | Dark |
| 28 | Custom Vibes | `custom` | User-defined |

### Custom Theme Editing

Available when preset is `custom`:
- Per-role color pickers and hex token fields for all 10 roles
- Accepts `#RRGGBB` or `#RRGGBBAA` hex tokens; invalid tokens show inline errors
- "Reset Custom" and "Use Midnight Base" both reset draft to Midnight Mono palette
- Switching to `custom` from another preset copies current palette as starting draft

### Palette Preview

Five swatches in a row: Window → Canvas → Canvas Secondary → Border → Accent, with legend labels.

## State Management

### Typography

| Setting | Control | Options / Range | Default |
|---------|---------|-----------------|---------|
| Font family | Picker (5 options) | System Monospace (`NSFont.monospacedSystemFont`), SF Mono, Menlo, Monaco, Courier | System Monospace |
| Code + terminal base size | Slider | 1–100 pt | 13 pt |
| Rail terminal font scale | Segmented picker | 1/4 (0.25×), 1/2 (0.50×), 1:1 (1.00×) | 1/2 |
| Code + terminal text color | Color picker + hex field | Edits `terminalForeground` role | — |

Font family candidates:

| Option | Font Candidates |
|--------|----------------|
| System Monospace | `NSFont.monospacedSystemFont` |
| SF Mono | SFMono-Regular, SF Mono Regular, SFMono-Medium |
| Menlo | Menlo-Regular, Menlo |
| Monaco | Monaco, Monaco-Regular |
| Courier | Courier, CourierNewPSMT |

### Container Style

| Setting | Control | Options | Default |
|---------|---------|---------|---------|
| Border shape | Segmented picker | Square (0pt radius), Rounded (8pt radius) | Square |
| Show borders | Toggle | On / Off | On |

### Persistence Keys

| Key | Store |
|-----|-------|
| `crispyvibesThemeBorderShape` | UserDefaults |
| `crispyvibesThemeBorderVisible` | UserDefaults |
| `codeFontFamily` | UserDefaults |
| Theme preset + custom JSON | UserDefaults (app storage) |
| Appearance mode | UserDefaults (app storage) |

## Dependencies (frameworks, libraries)

- SwiftUI (`ColorPicker`, `@AppStorage`)
- AppKit (`NSFont` for font resolution)

## Platform Considerations

- macOS only — `NSFont.monospacedSystemFont` for system monospace resolution
- Dark/light scheme detection via `NSApp.effectiveAppearance`

## Performance Constraints

- Theme changes propagate reactively via SwiftUI environment; no restart required
- Custom theme JSON decode failure falls back to system palette (no crash path)

## Migration / Rollout Notes

- Legacy named project-color token decoding removed; color tokens are hex-only
- Custom theme JSON schema must remain backward-compatible across versions
