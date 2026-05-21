# Glossary

Use these names consistently in tickets, docs, UI copy, and code.

## Terminology Guardrails
- `VibeSpace` is app-level only: a saved collection shown on the dashboard.
- `Project` is folder-level only: one opened root folder.
- Do not use `vibespace` to mean an opened folder.

## App Shell and Navigation

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| Dashboard | Landing view that lists saved VibeSpaces and lets users reopen them. | Also called "landing page". |
| Title Bar | macOS toolbar area hosting app-level controls like theme, rail position, and add project action. | Avoid "header". |
| Project Canvas | Main container that arranges the focused Project and Project Rail. | |
| Focused Project | The currently active Project shown in the main pane. | |
| Project Rail | Stacked list of non-focused Projects; can be left/right/top/bottom. | Also called "stack rail". |
| Rail Position | Placement of the Project Rail: `left`, `right`, `top`, `bottom`. | |
| Stacked Project Card | Compact card in the Project Rail for one non-focused Project. | |

## VibeSpace and Project Model

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| VibeSpace | App-level saved collection containing one or more Projects. | |
| VibeSpace Catalog | App-level persisted list of known VibeSpaces shown on the Dashboard. | |
| Project | One opened root folder in the app. | Current runtime entity. |
| Project Session | Runtime state object for one Project while app is running. | Current code entity. |
| Root Folder | Filesystem folder selected when creating/opening a Project. | |
| Project Window | Visual context for a Project inside the app layout. | |
| App Layout State | Per-vibespace persisted rail, canvas, and board layout metadata in `layout.json` within the vibespace directory. | Source of truth for rail + pane layout restore. |

## Main UI Regions

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| Explorer Pane | File tree/navigation pane for the current Project. | |
| Editor Pane | Markdown/text editing region. | |
| Preview Pane | File preview region for markdown/html/images/pdf. | |
| Terminal Pane | Region showing terminal tabs for the current Project. | |
| Pane Splitter | Draggable divider used to resize panes. | |

## Terminal Concepts

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| Terminal Tab | One terminal entry in the tab strip. | |
| Active Terminal | Currently selected terminal tab/session. | |
| Terminal Session | Backing process + terminal view state for one tab. | |
| Terminal Display Density | Visual density mode for terminal font size (`regular`, `compact`). | |
| Terminal Preset Button | Clickable button near terminal area that opens a new terminal with a predefined command. | |
| Terminal Profile | Saved preset command definition for a CLI tool. | |
| Launch Mode | Variant of profile flags/options (for example default vs trust mode). | |
| tmux Session | A tmux server-side session backing a terminal tab when tmux integration is enabled. Named `crispyvibes-<id>`. | Experimental feature. |
| tmux Reattach | Reconnecting to an existing tmux session on app restart via `tmux new-session -A`. | |
| Orphaned tmux Session | A tmux session alive on the server but not attached to any CrispyVibes terminal tab. | Manageable via session manager. |
| tmux Session Behavior | User setting controlling whether tmux sessions are detached (kept alive) or terminated on quit/tab close. | |

## Terminal Board and VibeSpace Views

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| Terminal Board | Grid-based terminal tile layout used in Terminal Only vibespace mode. | Max 4x4 tiles. |
| Terminal Spotlight | Unified centered overlay for a terminal session or VibeCast. Supports two-finger horizontal swipe to cycle through all terminals and VibeCast in vibespace order. Dismisses on double-click, Esc, or backdrop click. | |
| VibeSpace View Mode | Canvas mode toggle: `Detailed` (editor + terminal) or `Terminal Only` (board). | |
| Standalone Terminal | Board terminal tile not mapped to any project, scoped to the vibespace. | |

## Content Viewer and Shelf

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| Content Viewer | Tab-based file preview/edit container supporting split views. | |
| Shelf | Persistent pinned-files section shown at the top of the Files sidebar, stored in `shelf-state.json`. | |
| App Activity Rail | Global navigation rail for Home, Files, Git, Sessions, vibespace settings, and app settings. | |

## Persistence and Settings

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| App-Level Settings | Global app settings (for example theme and rail position). | |
| VibeSpace-Level Settings | Saved metadata for a VibeSpace (for example project list and Project colors). | |
| Folder-Level Settings | Per-folder startup overrides and terminal shell preferences persisted in per-project config files. | |
| Appearance Preference | Theme setting values: `auto`, `light`, `dark`. | |
| Pane Layout State | Persisted explorer/editor/terminal splitter sizes keyed by Project path in per-vibespace `layout.json`. | |
| Terminal Restore State | Persisted terminal tab entries in per-project config files (`projects/<hash>.json`) within the vibespace directory. | |
| Project Color | Persisted color for a Project title + accent treatment in focused pane and rail card. | |

## File and Path Terms

| Canonical Name | Definition | Avoid/Notes |
| --- | --- | --- |
| `.crispyvibe` Directory | (Removed) Previously used for folder-local metadata; terminal restore is now stored in vibespace persistence. | No longer created. |
| App State Store | App-level persistence file for recent vibespace IDs and global metadata (`app-state.json`). | Layout state is stored per-vibespace in `layout.json`. |
