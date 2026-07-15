# Terminal Presets — Spec

Status: draft

## Overview

Terminal Presets provides a launcher for AI coding-agent CLIs from the terminal. Presets are exposed through the **Agent CLI** submenu inside the terminal commands menu (alongside Signals, tmux, and Shortcuts), available both in the detailed-view terminal toolbar and on terminal board tiles. It manages per-agent launch mode selection (Standard / Full Trust), tool availability diagnostics, preset execution, and error handling for missing executables.

Launch behavior differs by surface: the detailed-view launcher opens the agent in a new named terminal tab; a board tile launches the agent into that tile's own session.

## Dependencies

- F001 (Sessions & Tabs) — presets launch terminal sessions in named tabs

## Requirements

### F005-R01: Per-Agent Launch Mode Selection

Launch mode MUST be selected per agent at launch time, not via a global persisted selector. An agent that defines a full-trust command mapping MUST present a nested submenu offering both `Standard` and `Full Trust`; selecting one MUST launch the agent using that mode's command mapping. An agent without a full-trust mapping MUST launch directly in `Standard` mode from a single menu item.

### F005-R02: Installed Agents Shown in Agent CLI Menu

Tool diagnostics MUST run against preset executables on PATH and standard fallback install directories. Only installed agent presets MUST be listed (Kiro, Claude, Codex, Gemini, OpenCode, Copilot). When no agents are detected, the menu MUST show a non-actionable "No agents on PATH" item rather than hiding the menu. Launching an agent MUST send the preset command to a terminal session and move keyboard focus to it:
- In the detailed-view launcher, launching MUST create a new terminal tab named with the preset short label and dispatch the command there.
- On a terminal board tile, launching MUST dispatch the command into that tile's existing session.

### F005-R03: Full-Trust Presented Only When Supported

An agent that defines a full-trust command mapping MUST expose the Standard / Full Trust nested submenu. An agent with no full-trust mapping MUST NOT present a Full Trust option and MUST launch in Standard mode.

### F005-R04: Missing Preset Executable Shows Non-Blocking Error

When a preset executable is not present on PATH or fallback install directories, no new preset tab MUST be created. The terminal pane MUST show an inline error banner with dismiss control.

## Scenarios

### Scenario F005-S01: Per-agent launch mode selection

**Given** the Agent CLI submenu is open in the terminal commands menu
**When** the user opens a full-trust-capable agent's nested submenu and picks `Standard` or `Full Trust`
**Then** the agent launches using the selected mode's command mapping
**And** agents without a full-trust mapping launch in `Standard` from a single item

### Scenario F005-S02: Installed agents are shown and launch per surface

**Given** tool diagnostics runs against preset executables on PATH and standard fallback install directories
**When** the user opens the **Agent CLI** submenu and launches an agent
**Then** only installed agents are listed (Kiro, Claude, Codex, Gemini, OpenCode, Copilot), or "No agents on PATH" when none are detected
**And** from the detailed-view launcher a new terminal tab is created with the preset short name and the command is dispatched there
**And** from a terminal board tile the command is dispatched into that tile's existing session
**And** keyboard focus moves to the launched session

### Scenario F005-S03: Full trust presented only when supported

**Given** the Agent CLI submenu is open
**When** an agent defines a full-trust command mapping
**Then** that agent shows a nested submenu with `Standard` and `Full Trust`
**And** an agent without a full-trust mapping shows a single item that launches in `Standard`

### Scenario F005-S04: Missing preset executable shows non-blocking error

**Given** a preset executable is not present on PATH or fallback install directories
**When** the user launches that preset from the detailed-view launcher
**Then** no new preset tab is created
**And** terminal pane shows an inline error banner with dismiss control

## Acceptance Criteria

- Tool diagnostics complete within 500ms (PERF-4).
- Preset launch creates tab (detailed view) or dispatches to the tile session (board) and sends command within 200ms (PERF-3).
- Missing executable error is non-blocking and dismissible (A11Y-2).
- Trust mode is chosen per agent at launch; no global terminal launch-mode toggle is required (the Agent CLI menu always renders when enabled, showing "No agents on PATH" when empty).
- Preset launches logged (OBS-1).

## Open Questions

- Should presets support user-defined custom entries beyond the built-in AI tools?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-029–032) | — |
| 2026-07-01 | Launcher moved into the terminal commands menu as the "Agent CLI" submenu (detailed view + board tiles); replaced the standalone Tools dropdown and global launch-mode selector with per-agent Standard/Full Trust nesting; board tiles launch into the tile session | — |
