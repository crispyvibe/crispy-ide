# VibeSpace Settings — Technical Design

## Overview

VibeSpace Settings is a modal sheet with split-view layout: category sidebar on the left, scrollable detail panel on the right. Two categories: VibeSpace (startup defaults, naming, maintenance, source control) and Projects (per-project color, shell, startup, shortcuts).

## Architecture

### Sheet Structure

- Title: "VibeSpace Settings" with current vibespace name as subtitle
- "Done" button closes the sheet
- VibeSpace category selected by default on open

### Categories

| Category | Icon | Title | Subtitle |
|----------|------|-------|----------|
| VibeSpace | `slider.horizontal.3` | VibeSpace Settings | Startup defaults, naming, and maintenance |
| Projects | `folder.badge.gearshape` | Projects | Manage project order, shortcuts, colors, and overrides |

## Data Flow

### VibeSpace Category

Four settings cards stacked vertically:

#### VibeSpace Identity

- Text field (max width 300) + "Save" button
- Pre-filled with current name on appear
- Save disabled when trimmed draft is empty or matches current name
- Enter or Save commits rename; empty draft resets to current name

#### VibeSpace Defaults

**Default terminal shell:**

| Option | Stored Value |
|--------|-------------|
| Use App Default | `nil` (no override) |
| zsh | `TerminalShellPreference.zsh` |
| bash | `TerminalShellPreference.bash` |

**Startup terminals:** Stepper 1–8 (default 1). Controls how many startup profile rows appear.

**Startup profile row** (per terminal, labeled "Terminal N"):

Mode picker with three options:

| Mode | Behavior |
|------|----------|
| None | Clears profile. No additional fields. |
| Preset | Shows preset picker + optional trust level chips |
| Command | Shows free-text command field (1–3 lines, max width 420) |

Mode inferred on appear: preset ID or matching command → Preset; non-empty non-preset command → Command; otherwise None.

**Preset sub-fields:**
- Preset picker (max width 420) — lists available presets as "ShortLabel (command)". Filtered to installed presets; all built-in shown as fallback if none detected.
- Trust level chips — shown only when preset supports full trust. Capsule buttons: Standard, Full Trust.
- Command summary — read-only resolved command, prefixed with trust mode label when applicable.

**Focus terminal on project switch:** Toggle, default on.

#### VibeSpace Maintenance

"Reindex Project Folders" button (`arrow.triangle.2.circlepath`) — async reconcile project availability, clear startup flags, persist catalog, re-hydrate terminals if active vibespace.

#### Source Control

| Setting | Control | Range | Default |
|---------|---------|-------|---------|
| Ignored folders | Multi-line text field (2–4 lines, max 420) | Comma-separated | `.build`, `.cache`, `.derived`, `.next`, `.nuxt`, `.swiftpm`, `Build`, `Carthage`, `DerivedData`, `Pods`, `SourcePackages`, `build`, `checkouts`, `dist`, `node_modules`, `out` |
| Scan depth | Stepper | 1–16 | 8 |
| Max discovered repos | Stepper | 1–256 | 64 |
| Rendered repos | Stepper | 1–min(48, max discovered) | 12 |

Normalization: ignored folders split on commas/newlines, trimmed, deduplicated case-insensitively, sorted. Rendered repos clamped to ≤ max discovered repos.

### Projects Category

**Toolbar:** "Add Project Folder" (primary, `folder.badge.plus`) → `NSOpenPanel` multi-select directory. "Refresh Availability" (text, `arrow.triangle.2.circlepath`) → reindex.

**Project list:** Width 300, min height 360. Each row: colored circle (9×9), project title (semibold), path (caption, middle-truncated), shortcut badge ("Cmd+N" monospaced). Drag to reorder. Auto-select first if no selection.

**Per-project detail card** (when selected):

| Setting | Control | Notes |
|---------|---------|-------|
| Color | ColorPicker + "More" popover (width 220) + "Clear" | No opacity support. Clear removes tag → accent fallback. |
| Shell | Picker: "Use VibeSpace Default" / zsh / bash | Inherit stores `nil` |
| Shortcut | Picker: None / 1–9 (⌘ prefix) | Maps to Cmd+N |
| Startup behavior | Picker: "Use VibeSpace Default" / "Custom Override" | Override shows stepper + profile rows identical to vibespace-level |

Remove button (destructive, trash icon) — removes project, selects next in list.

### Trust Level

Per-startup-profile setting, visible only when preset supports full trust.

| Preset | Standard Command | Full Trust Command |
|--------|------------------|--------------------|
| Kiro CLI | `kiro-cli` | `kiro-cli chat --trust-all-tools` |
| Claude Code | `claude` | `claude --dangerously-skip-permissions` |
| Codex | `codex` | `codex --dangerously-bypass-approvals-and-sandbox` |
| Gemini CLI | `gemini` | `gemini --approval-mode yolo` |
| OpenCode | `opencode` | — (no full trust) |
| GitHub Copilot CLI | `copilot` | `copilot --allow-all` |

## State Management

All settings changes persisted to vibespace catalog immediately on mutation.

### Side Effects

| Change | Side Effect |
|--------|-------------|
| Startup settings / override | Clear startup execution flags, re-hydrate vibespace terminals if active |
| Shell (vibespace or project) | Refresh terminal shell resolution contexts |
| Source control settings | Update source control view model if active |
| Project reorder | Persist immediately; shortcuts reindexed |
| Project removal | Clear startup execution flags for removed path |
| VibeSpace rename | Sync window title if active vibespace |

## Dependencies (frameworks, libraries)

- SwiftUI (sheet, pickers, steppers, `ColorPicker`)
- AppKit (`NSOpenPanel` for directory selection)

## Platform Considerations

- macOS only — `NSOpenPanel` for folder selection
- Preset availability filtered by installed CLI tools on system

## Performance Constraints

- Settings changes persist immediately (no batch save)
- Reindex runs async filesystem checks off main thread

## Migration / Rollout Notes

- Startup settings decode from `startupProfiles`; legacy single-terminal keys not migrated
- Trust level only visible for presets with `fullTrustCommand` defined
