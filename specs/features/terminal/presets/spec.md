# Terminal Presets — Spec

Status: draft

## Overview

Terminal Presets provides a launcher menu for AI coding tools and CLI presets. It manages launch mode selection (Standard / Full Trust), tool availability diagnostics, preset execution in named terminal tabs, and error handling for missing executables.

## Dependencies

- F001 (Sessions & Tabs) — presets launch terminal sessions in named tabs

## Requirements

### F005-R01: Preset Mode Selector Controls Launch Mode

When user switches launch mode between `Standard` and `Full Trust`, subsequent preset launches MUST use the selected mode mapping. The selected mode MUST be persisted in app storage.

### F005-R02: Installed Tools Shown in Tools Menu

Tool diagnostics MUST run against preset executables on PATH and standard fallback install directories. Only installed tool presets MUST be listed with their brand SVG icons (Kiro, Claude, Codex, Gemini, OpenCode, Copilot). Launching a preset MUST create a new terminal tab with preset short name, send the preset command to the terminal session, execute the command, and move keyboard focus to that session.

### F005-R03: Full-Trust Unsupported Preset Not Launchable

When current launch mode is `Full Trust` and a preset defines a full-trust command mapping, that preset menu item MUST remain enabled. If a preset has no full-trust command mapping, that preset menu item MUST be disabled.

### F005-R04: Missing Preset Executable Shows Non-Blocking Error

When a preset executable is not present on PATH or fallback install directories, no new preset tab MUST be created. The terminal pane MUST show an inline error banner with dismiss control.

## Scenarios

### Scenario F005-S01: Preset mode selector controls launch mode

**Given** terminal preset controls are visible in tab bar
**When** user switches launch mode between `Standard` and `Full Trust`
**Then** subsequent preset launches use the selected mode mapping
**And** the selected mode is persisted in app storage

### Scenario F005-S02: Installed tools are shown in Tools menu and launch in named tabs

**Given** tool diagnostics runs against preset executables on PATH
**And** preset command discovery includes app PATH and standard fallback install directories
**When** user opens the `Tools` dropdown and launches a preset
**Then** only installed tool presets are listed with their brand SVG icons (Kiro, Claude, Codex, Gemini, OpenCode, Copilot)
**Then** a new terminal tab is created with preset short name
**And** preset command is sent to terminal session
**And** preset command executes in the launched terminal session
**And** keyboard focus moves to that preset terminal session

### Scenario F005-S03: Full-trust unsupported preset is not launchable

**Given** current launch mode is `Full Trust`
**When** a preset defines a full-trust command mapping
**Then** that preset menu item remains enabled
**And** if a preset has no full-trust command mapping, that preset menu item is disabled

### Scenario F005-S04: Missing preset executable shows non-blocking error

**Given** preset executable is not present on PATH or fallback install directories
**When** user launches that preset
**Then** no new preset tab is created
**And** terminal pane shows an inline error banner with dismiss control

## Acceptance Criteria

- Tool diagnostics complete within 500ms (PERF-4).
- Preset launch creates tab and sends command within 200ms (PERF-3).
- Missing executable error is non-blocking and dismissible (A11Y-2).
- Preset mode persists across app restarts (REL-1).
- Preset launches logged (OBS-1).

## Open Questions

- Should presets support user-defined custom entries beyond the built-in AI tools?

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/terminal/feature.md (TRM-029–032) | — |
