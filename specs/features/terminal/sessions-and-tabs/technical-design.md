# Terminal Sessions & Tabs — Technical Design

## Overview

Technical design pending. This document will cover the architecture, data flow, and implementation details for terminal session lifecycle, tab management, shell resolution, environment setup, metadata tracking, clipboard commands, restore/restart behavior, shortcut commands, interactive targets, remote terminal activation, vibespace sessions browser, terminal insight, focus coordination, and compose input.

## Architecture

_Pending._

## Data Flow

_Pending._

## API / Command Contracts

_Pending._

## State Management

### Terminal Ordering Models

Terminal ordering is intentionally scoped by surface:

- Project tab order lives in each project's `TerminalViewModel.tabs` array and is persisted with that project's terminal session entries. It controls project-local terminal tab presentation and lazy restore order.
- VibeSpace Spotlight order is a vibespace-scoped linear list of stable terminal identities stored in the centralized vibespace persistence model. Each identity must include project scope plus terminal tab ID so terminals from different projects can be interleaved without rewriting project-local tab arrays.
- Terminal board order lives in `VibeSpaceTerminalBoardState` as per-surface board layout. It controls visible board placement, minimized tile order, and terminal-board Spotlight carousel order for that surface.

These models must not be collapsed into one another. A vibespace Spotlight drag can reorder terminals across projects without changing project tab order. A board Spotlight drag can reorder the active board surface without changing vibespace Spotlight order. A project tab-bar drag can reorder tabs inside one project without defining cross-project Spotlight order.

On restore, terminal tabs are restored first from project persistence. VibeSpace Spotlight order is then reconciled against the live terminal identity set: missing identities are pruned, newly created identities are appended in default project/tab traversal order, and the stored cross-project order remains authoritative for resolved identities.

## Dependencies (frameworks, libraries)

_Pending._

## Platform Considerations

_Pending._

## Performance Constraints

_Pending._

## Migration / Rollout Notes

_Pending._

## File Structure

**Applies to:** `projects/crispyvibes/crispyvibes/` (macOS app target)

### Runtime Structure

#### Core Session Services (`Features/Terminal/Services/`)

- `GhosttyTerminalEngine.swift`
  - Primary terminal rendering engine via GhosttyKit (Metal-accelerated).
  - Handles Ghostty surface lifecycle, input routing, and clipboard integration.

- `TerminalSession.swift`
  - Owns terminal process lifecycle and engine selection (Ghostty primary, SwiftTerm fallback).
  - Resolves shell selection (`TerminalShellResolver`) and launch environment (`CommandPathResolver`).
  - Tracks readiness, activity, and command dispatch gating.
  - Exposes first-output and activity callbacks used by UI hosts.

- `TerminalHostOwnershipCoordinator.swift`
  - Manages terminal view ownership transfer between focused pane and rail card containers.

- `TerminalFocusCoordinator.swift`
  - Terminal focus management across views and project switches.

- `TerminalPresetServices.swift`
  - Installed CLI tool detection and preset management.

- `TerminalSessionAppearance.swift`
  - `TerminalSession` extension for appearance and density configuration.

- `TerminalSessionCommandDispatch.swift`
  - `TerminalSession` extension for command dispatch gating and pending command queue.

- `TmuxService.swift`
  - tmux binary detection, session lifecycle (create/kill/list/exists), server option management.
  - Provides `launchArguments` for tmux-backed session launch and `applyServerOptions` for mouse/scrollback/status/escape-time.
  - Static enum with no instance state.

- `TerminalSessionDelegateAndView.swift`
  - Terminal session delegate callbacks and view hosting.

- `TerminalSessionSupportTypes.swift`
  - Shared support types for terminal session infrastructure.

- `GhosttyTerminalViewLifecycle.swift`
  - Terminal view lifecycle management.

- `GhosttyTerminalViewInput.swift`
  - NSTextInputClient conformance and keyboard input.

- `GhosttyTerminalViewMenu.swift`
  - Context menu handling.

- `GhosttyTerminalRuntimeCallbacks.swift`
  - Ghostty runtime callback handlers.

- `GhosttyTerminalEngineInput.swift`
  - Engine input handling.

- `GhosttyTerminalEngineSurfaceConfig.swift`
  - Surface configuration.

- `GhosttyTerminalEngineOutputTracking.swift`
  - Output tracking for insight.

- `GhosttyTerminalRuntime.swift`
  - Ghostty runtime singleton.

- `GhosttyTerminalSupport.swift`
  - Support types.

- `TerminalShellResolution.swift`
  - Shell discovery and resolution.

- `TerminalSessionLaunchSupport.swift`
  - Session launch helpers.

- `ProjectActivityTracker.swift`
  - Per-project terminal activity tracking.

#### Insight (`Features/Terminal/Insight/`)

- `TerminalInsightObserver.swift`
  - Grid diffing observer, input capture, streaming detection.

- `TerminalGridDiff.swift`
  - Grid snapshot comparison with scroll detection.

- `TerminalGridSnapshot.swift`
  - Per-line hash snapshot of terminal grid.

- `TerminalChangeEvent.swift`
  - Change classification enum (7 cases).

- `TerminalInsightOverlay.swift`
  - Last-command overlay view.

#### View Model Layer (`Features/Terminal/ViewModels/`)

- `TerminalViewModel.swift`
  - Manages tab state, active tab routing, and per-tab `TerminalSession` instances.
  - Routes preset/shortcut execution and startup workflows into sessions.

- `TerminalViewModelPresets.swift`
  - Preset terminal command management.

- `TerminalViewModelShortcuts.swift`
  - Terminal keyboard shortcut handling.

- `TerminalViewModelStartup.swift`
  - Terminal startup and hydration workflows.

- `TerminalViewModelTabs.swift`
  - Tab lifecycle, creation, and selection.

#### View Layer (`Features/Terminal/Views/`)

- `TerminalSessionHostView.swift`
  - SwiftUI/AppKit bridge for rendering a `TerminalSession` host view.
  - Supports density-specific rendering (`regular`, `compact`) and font overrides.

- `TerminalView.swift`
  - Terminal tab chrome and focused terminal presentation.

- `TmuxSessionManagerView.swift`
  - Settings sheet for managing CrispyVibes-owned local tmux sessions.
  - Shows active (attached) and orphaned (detached) sessions with kill actions.

#### Terminal Board (`Features/VibeSpace/Views/TerminalBoard/`)

- `VibeSpaceTerminalOnlyView.swift`
  - Terminal-only vibespace board surface.
  - Renders draggable/resizable terminal tiles in adaptive grid layout.

- `VibeSpaceTerminalBoardStore.swift`
  - Board tile/layout state source of truth.
  - Maps tile scope to either project terminal tabs or standalone vibespace terminals.
  - Reconciles/persists tile bindings with live tabs across mode switches.

- `VibeSpaceTerminalCreateSheet.swift`
  - New-terminal flow for project-scoped or standalone vibespace terminals.
  - Supports `No Project (VibeSpace)` selection and vibespace-base default directory fallback.

#### VibeSpace Sessions Browser (`Features/VibeSpace/Canvas/`)

- `VibeSpaceSidebarSessionsPane.swift`
  - Sidebar pane entry point for vibespace-scoped tmux browsing.
  - Orders current vibespace first and renders the shared refresh and empty-state surface.

- `VibeSpaceSidebarSessionsSectionView.swift`
  - Tree rendering for vibespace, project, and session rows.
  - Surfaces preview, open-in-project, and terminate actions directly on each row.

- `VibeSpaceSidebarSessionBrowser.swift`
  - Local and remote tmux discovery, parsing, and project assignment.
  - Resolves user-facing session titles and remote fallback parsing.

#### Terminal Support (`Features/Terminal/Support/`)

- Terminal-specific support types and utilities.

#### Terminal File Drop Support (`Features/Terminal/Support/`)

- `TerminalFileDropSupport`
  - Centralized file drop handling extracted from `TerminalContainerView`.
  - Multi-file support with relative/absolute path resolution.
  - Shell escaping using single quotes, trailing space appended after paths.
  - Focus reclaim with retry (3 attempts).
  - Registered on both `GhosttyTerminalView` and `MonitoredTerminalView`.
  - Also wired into `ComposeTextView`.
  - Interactive target hover and activation use shared terminal-target detection, with per-engine geometry and overlay rendering.

### Supporting Models (`Models/`)

- `TerminalTab.swift`
- `TmuxSessionBehavior.swift`
- `VibeSpaceStartupSettings.swift`
- `VibeSpaceState.swift`
- `ProjectColorTag.swift`
- `VibeSpaceTerminalBoardLayout.swift`
- `VibeSpaceTerminalBoardLayoutMutations.swift`
- `BoardInteractionController.swift`
- `BoardHitTesting.swift`
- `BoardCursorRegions.swift`
- `BoardSpatialNavigation.swift`
- `ProjectTerminalCycler.swift`

### Current Architecture Notes

- Rail cards render a compact terminal host view for each project card.
- Terminal-only board supports mixed project-scoped and standalone vibespace terminals.
- `No Project (VibeSpace)` terminals are intentionally unmapped from `ProjectSession`.
- Legacy named project-color token decoding has been removed; color tokens are hex-only.
- VibeSpace startup settings decode from `startupProfiles` and do not migrate legacy single-terminal keys.
- Ghostty is the primary terminal engine; SwiftTerm is used as fallback.
- Interactive terminal targets use a shared parser across Ghostty and SwiftTerm.
- Hovering links and file paths shows a local underline/highlight overlay.
- Plain click on an interactive target shows an AppKit context menu tailored to the detected target type.
- `Cmd`-click activates the target directly using the existing CrispyVibes routing path.
- Target-type action mapping is explicit:
  - web URL / hyperlink:
    - `Open in Crispy` -> in-app browser spotlight
    - `Open in Default Browser` -> `NSVibeSpace` browser open
    - `Copy Link` -> pasteboard copy of original link string
  - file target:
    - `Open` -> CrispyVibes file preview routing
    - `Open in Shelf` -> Shelf add/open flow
    - `Open in System` -> `NSVibeSpace` open
    - `Reveal in Finder` -> Finder reveal
    - `Copy Path` -> pasteboard copy of resolved file path
  - directory target:
    - `Open` -> CrispyVibes directory routing
    - `Open in System` -> Finder open
    - `Copy Path` -> pasteboard copy of resolved directory path
- Interactive target menu dispatch is intentionally ephemeral:
  - the AppKit menu uses a stateless shared selector target
  - each menu item's command object is stored on that `NSMenuItem`
  - no popup command state is stored in global registries or long-lived terminal state
- tmux mouse mode remains enabled for normal clicks, while `Cmd`-click is intercepted for Crispy navigation in local and remote sessions.
- Terminal interactive-target popup behavior remains covered by the existing terminal memory lifecycle guarantees:
  - `MonitoredTerminalView` removes local event monitors and tracking areas in `deinit`
  - `GhosttyTerminalView` removes screen observers and releases Ghostty callback context in `deinit`
  - `GhosttyTerminalEngine.terminate()` resets action-handler closures
  - `TerminalSession.terminate()` clears first-output observers and pending work
  - `TerminalMemoryLifecycleTests` must continue to pass after interactive-target changes

### tmux Integration (Experimental)

- When enabled, `TerminalSession.startProcess` routes through `TmuxService.launchArguments` instead of launching the shell directly.
- Local tabs get a unique tmux session name (`crispyvibes-<id>`) persisted in `TerminalSessionEntry.tmuxSessionName`.
- Remote project tabs persist `TerminalSessionEntry.tmuxSessionName` too, but seed it from a stable hash of the SSH project identifier when no saved name exists.
- On restore, `tmux new-session -A` reattaches to existing sessions or creates new ones.
- Startup preset commands are skipped when reattaching (checked via `TmuxService.sessionExists` before `startIfNeeded`).
- `TmuxService.applyServerOptions` runs before each session launch to ensure mouse, scrollback, status, and escape-time settings.
- Quit/close behavior is configurable: detach (keep alive) or terminate (kill session).
- `TmuxSessionManagerView` provides settings-time cleanup for Crispy-owned local sessions.
- `VibeSpaceSidebarSessionsPane` is the primary in-vibespace browser for local and remote tmux sessions.

### Terminal Board Refactor Status

The core board interaction refactor is complete:
- `BoardInteractionController` — enum-based state machine replacing 16+ scattered `@State` variables
- `BoardHitTesting` — explicit pointer hit-testing for tile headers, dividers, and body regions
- `BoardCursorRegions` — AppKit cursor rect computation for resize handles
- `BoardSpatialNavigation` — keyboard-driven tile navigation
- Named coordinate space (`"terminalBoard"`) used for all gesture tracking

#### Remaining View-Level Cleanup

- Replace `ZStack` + manual `.offset()` positioning with a custom `Layout` conforming to SwiftUI's `Layout` protocol
- Move tile move gesture from individual tile cards to board-level interaction overlay
- Remove per-method `self = normalized()` calls in `VibeSpaceTerminalBoardLayoutMutations` (keep normalization only at persistence boundary)

## External Integration

### Ghostty (GhosttyKit)

Purpose:

- Primary terminal rendering engine
- GPU-accelerated terminal display via Metal

Behavior:

- Embedded as `GhosttyKit.xcframework` (locally built, gitignored)
- Runtime resources bundled in `Resources/GhosttyRuntime`
- Pinned to a specific commit for reproducible builds
- Setup: `./projects/crispyvibes/scripts/setup-ghostty.sh`

### SwiftTerm

Purpose:

- Fallback terminal rendering engine
- PTY-backed local shell process management

Behavior:

- Used when Ghostty engine is unavailable
- Starts shell from `SHELL` environment variable
- Falls back to `/bin/zsh`
- Maintains terminal state per tab session
