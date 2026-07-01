# Terminal Presets — Technical Design

## Overview

Terminal Presets provides an agent-CLI launcher surfaced through the **Agent CLI** submenu of the terminal commands menu. Built-in presets are sourced from `CLIToolCatalog`, which maps CLI tool definitions to `TerminalPresetDefinition` entries. Availability is determined by `TerminalPresetAvailabilityDiagnostics`, which checks executables on the system PATH. The view model exposes `availablePresets` (filtered to installed tools). Trust mode (Standard / Full Trust) is chosen per agent at launch time rather than via a global persisted selector.

## Architecture

### Component Hierarchy

```
TerminalCommandsMenu  (shared: detailed-view toolbar + board tile)
└── Agent CLI submenu            (rendered when showsAgentCLIMenu == true)
    ├── "No agents on PATH"      (when availablePresets is empty)
    └── Per agent (filtered by availability):
        ├── full-trust-capable → nested submenu: Standard / Full Trust
        └── otherwise           → single item (Standard)

TerminalPresetServices
├── CLIToolCatalog (static preset definitions)
├── TerminalPresetAvailabilityDiagnostics (PATH scanning + caching)
└── TerminalPresetDefinition (id, title, shortLabel, symbolName, command, fullTrustCommand)
```

The standalone "Tools" dropdown (sparkles) and its global launch-mode picker were removed; agent launching is unified into `TerminalCommandsMenu`. Standard / Full Trust labels reuse `CLITrustMode.title`.

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

1. User selects an agent from the Agent CLI submenu, choosing `Standard` or `Full Trust` for full-trust-capable agents (others launch in Standard directly).
2. Resolve command via `TerminalPresetDefinition.command(for:)`: Full Trust uses `fullTrustCommand`, otherwise `defaultCommand`.
3. Dispatch by surface:
   - **Detailed view** (`TerminalView.launchAgentPreset(_:mode:)`): create a new terminal tab named with the preset `shortLabel`, set preset-based origin, and send the resolved command to the new session.
   - **Board tile** (`VibeSpaceTerminalBoardTileCard.launchAgentInTileSession(_:mode:)`): send the resolved command into the tile's existing session.
4. Move keyboard focus to the target session.

### Error Flow (Missing Executable)

1. Preset executable not found on PATH or fallback directories.
2. No new tab is created.
3. Terminal pane shows inline error banner with dismiss control.
4. Error is non-blocking — user can dismiss and continue.

## API / Command Contracts

### Launch Mode

| Mode | Command Source | Selection |
|------|---------------|-----------|
| Standard | `TerminalPresetDefinition.defaultCommand` | Per launch (default) |
| Full Trust | `TerminalPresetDefinition.fullTrustCommand` | Per launch, only offered when the agent defines a full-trust mapping |

Trust mode is chosen at launch time from the agent's submenu; there is no global persisted terminal launch-mode toggle. (The `crispyvibes.terminal.presetLaunchMode` app-storage key still exists but is used by VibeSpace startup-profile settings, not by this launcher.)

### View Model API

| Method / Property | Description |
|-------------------|-------------|
| `availablePresets` | Filtered list of installed preset definitions |
| `refreshAvailablePresets()` | Re-run availability diagnostics |
| `launchPreset(_:mode:directoryURL:)` | Create tab (detailed view) + send command for the selected preset at the given mode |

## State Management

### Availability Cache

- Storage: UserDefaults, keyed by preset ID.
- Version key: prevents stale cache across app updates.
- Structure: `[PresetID: Bool]` mapping preset to installed/not-installed.
- Invalidation: version key mismatch triggers full rescan.

### Launch Mode

- Chosen per launch from the agent's Standard / Full Trust submenu (full-trust-capable agents only).
- Not persisted by this launcher; each launch resolves the command via `TerminalPresetDefinition.command(for:)`.
- Affects command resolution only for that launch.

### Tab Origin Tracking

Tabs created from presets have their `origin` set to preset-based (vs. ad-hoc). This is used by startup/restore logic to distinguish user-created terminals from preset-launched ones.

## Dependencies

- `TerminalViewModel` — tab creation and command dispatch
- `TerminalSession` — shell process and command execution
- `CommandPathResolver` — PATH resolution for executable detection
- UserDefaults — availability cache

## Platform Considerations

- PATH scanning includes macOS-specific directories: `/opt/homebrew/bin` (Apple Silicon Homebrew), `/usr/local/bin` (Intel Homebrew), `~/.local/bin`.
- Brand SVG icons (Kiro, Claude, Codex, Gemini, OpenCode, Copilot) are bundled as asset catalog entries.

## Performance Constraints

- Tool diagnostics complete within 500ms.
- Preset launch (tab creation + command send) within 200ms.
- Availability cache avoids repeated filesystem scans on every menu open.
