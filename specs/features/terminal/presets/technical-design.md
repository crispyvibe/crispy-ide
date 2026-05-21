# Terminal Presets — Technical Design

## Overview

Terminal Presets provides a launcher menu for AI coding tools and CLI presets. Built-in presets are sourced from `CLIToolCatalog`, which maps CLI tool definitions to `TerminalPresetDefinition` entries. Availability is determined by `TerminalPresetAvailabilityDiagnostics`, which checks executables on the system PATH. The view model exposes `availablePresets` (filtered to installed tools) and supports two launch modes: Standard and Full Trust.

## Architecture

### Component Hierarchy

```
Terminal Tab Bar
└── Tools Dropdown Menu
    ├── Mode Selector (Standard / Full Trust)
    └── Preset Items (filtered by availability)
        └── Brand SVG Icon + Preset Title

TerminalPresetServices
├── CLIToolCatalog (static preset definitions)
├── TerminalPresetAvailabilityDiagnostics (PATH scanning + caching)
└── TerminalPresetDefinition (id, title, shortLabel, symbolName, command, fullTrustCommand)
```

### Preset Definition Model

Each `TerminalPresetDefinition` carries:
- `id` — unique identifier
- `title` — display name
- `shortLabel` — tab name when launched
- `symbolName` — brand SVG icon reference
- `defaultCommand` — default (Standard mode) command string
- `fullTrustCommand` — optional Full Trust mode command string (nil if unsupported)
- `isCustomIcon: Bool` — whether the preset uses a custom icon
- `supportsFullTrust: Bool` — whether the preset supports Full Trust mode

### Built-in Tool Catalog

Presets are defined in `CLIToolCatalog` for: Kiro, Claude, Codex, Gemini, OpenCode, Copilot.

## Data Flow

### Availability Detection Flow

1. `TerminalPresetAvailabilityDiagnostics` scans each preset's executable against:
   - System PATH directories.
   - Standard fallback install directories (e.g., `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`).
2. Results cached in UserDefaults with a version key to avoid repeated filesystem scans.
3. Cache invalidated on version key change (app update).
4. View model exposes `availablePresets` filtered to installed tools.
5. Refresh on demand via explicit call.

**UI test override:** `CRISPYVIBES_UI_TEST_TERMINAL_TOOLS` environment variable overrides availability results.

### Preset Launch Flow

1. User selects preset from Tools dropdown.
2. Resolve command: if current mode is Full Trust and preset has `fullTrustCommand`, use it; otherwise use `defaultCommand`.
3. Create new terminal tab with preset `shortLabel` as custom name.
4. Set tab origin to preset-based (not ad-hoc).
5. Send resolved command to terminal session.
6. Move keyboard focus to the new session.

### Error Flow (Missing Executable)

1. Preset executable not found on PATH or fallback directories.
2. No new tab is created.
3. Terminal pane shows inline error banner with dismiss control.
4. Error is non-blocking — user can dismiss and continue.

## API / Command Contracts

### Launch Mode

| Mode | Command Source | Persistence |
|------|---------------|-------------|
| Standard | `TerminalPresetDefinition.defaultCommand` | Persisted in app storage |
| Full Trust | `TerminalPresetDefinition.fullTrustCommand` | Persisted in app storage |

If Full Trust is selected and a preset has no `fullTrustCommand`, that preset menu item is disabled.

### View Model API

| Method / Property | Description |
|-------------------|-------------|
| `availablePresets` | Filtered list of installed preset definitions |
| `refreshPresets()` | Re-run availability diagnostics |
| `launchPreset(_:)` | Create tab + send command for selected preset |
| `currentLaunchMode` | Current Standard/Full Trust selection (persisted) |

## State Management

### Availability Cache

- Storage: UserDefaults, keyed by preset ID.
- Version key: prevents stale cache across app updates.
- Structure: `[PresetID: Bool]` mapping preset to installed/not-installed.
- Invalidation: version key mismatch triggers full rescan.

### Launch Mode

- Persisted in app storage (UserDefaults).
- Toggled via mode selector in Tools dropdown.
- Affects command resolution for all subsequent launches.

### Tab Origin Tracking

Tabs created from presets have their `origin` set to preset-based (vs. ad-hoc). This is used by startup/restore logic to distinguish user-created terminals from preset-launched ones.

## Dependencies

- `TerminalViewModel` — tab creation and command dispatch
- `TerminalSession` — shell process and command execution
- `CommandPathResolver` — PATH resolution for executable detection
- UserDefaults — availability cache and launch mode persistence

## Platform Considerations

- PATH scanning includes macOS-specific directories: `/opt/homebrew/bin` (Apple Silicon Homebrew), `/usr/local/bin` (Intel Homebrew), `~/.local/bin`.
- Brand SVG icons (Kiro, Claude, Codex, Gemini, OpenCode, Copilot) are bundled as asset catalog entries.

## Performance Constraints

- Tool diagnostics complete within 500ms.
- Preset launch (tab creation + command send) within 200ms.
- Availability cache avoids repeated filesystem scans on every menu open.
