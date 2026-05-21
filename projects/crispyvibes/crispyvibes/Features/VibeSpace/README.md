# VibeSpace Feature Map

This folder is organized by **user-facing capability first**, then by layer.

## Views
- `Views/Canvas/`
  - Main vibespace canvas composition, file preview/edit actions, and canvas hydration behavior.
- `Views/Explorer/`
  - Project/file explorer UI, sidebar content, and file-tree row rendering.
- `Views/Settings/`
  - VibeSpace settings UI rows and settings sheet content.
- `Views/TerminalBoard/`
  - Terminal board UI (tile rendering, board layout interactions, create-terminal sheet, and standalone vibespace terminal support).
- `Views/ContentViewRailLayout.swift`
  - Shared top-level rail layout wiring used by the vibespace shell.

## ViewModels
- `ViewModels/Explorer/`
  - Explorer state lifecycle, actions/helpers, and project session orchestration.

## Services
- `Services/PaneWorker/`
  - Pane worker execution, infrastructure, and git/explorer worker helpers.
- `Services/FileSystem/`
  - File-system watchers and directory monitoring services.

## Support
- `Support/`
  - Small vibespace support types shared by settings/vibespace views.

## Placement Rules
- New code should be added under the **capability folder first** (`Canvas`, `Explorer`, `TerminalBoard`, etc).
- If a file is shared across multiple capabilities, place it in `Support/`.
- Avoid adding new generic `ContentView*` files outside capability folders.

## Terminal Board Ownership Model
- `VibeSpaceTerminalBoardStore` is the terminal board state source of truth in terminal-only mode.
- Board tiles can target two scopes:
  - Project-scoped terminals (shared `ProjectSession.terminalViewModel` tabs used by detailed view).
  - Standalone vibespace terminals (`No Project (VibeSpace)`), stored under the vibespace-level standalone `TerminalViewModel`.
- Standalone terminals are intentionally not mapped to a project, but their tile/session state persists across mode switches via board layout + standalone registry.
