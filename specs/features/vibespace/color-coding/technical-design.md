# Project Color Coding — Technical Design

## Overview

Every project in a vibespace is assigned a unique color tag as its visual identity. The color appears across 13 UI locations. Colors are auto-assigned deterministically using FNV-1a hashing of the normalized file path, manually overridable, and stored as hex strings in per-project config files.

## Architecture

### Data Model

`ProjectColorTag` — RGBA value (four `Double` components: red, green, blue, alpha, each clamped 0.0–1.0).

**Storage format:** Hex string in `ProjectConfigFile.colorTag`:
- `#RRGGBB` when alpha is fully opaque (255)
- `#RRGGBBAA` when alpha is not fully opaque
- Each component: 0.0–1.0 → 0–255 (rounded) → two-digit uppercase hex
- Parsing accepts 6 or 8 char hex, with or without `#`, case-insensitive (uppercased before parse), whitespace trimmed

**Dictionary key:** Normalized file path string in `projectColorTagsByPath`.

## Data Flow

### Auto-Assignment Algorithm (FNV-1a)

Deterministic — same normalized path always produces the same color.

```
1. Normalize path: strip escaped slashes, standardize via URL(fileURLWithPath:).standardizedFileURL.path
2. FNV-1a hash (64-bit):
   - Offset basis: 1469598103934665603 (non-standard offset basis)
   - Prime: 1099511628211
   - For each UTF-8 byte: hash = (hash XOR byte) &* prime
3. Decompose hash into HSV:
   - Hue:        (hash % 360) / 360.0                           → [0, 1)
   - Saturation:  0.58 + 0.24 × (((hash >> 9) & 0xFF) / 255.0)  → [0.58, 0.82]
   - Brightness:  0.72 + 0.20 × (((hash >> 17) & 0xFF) / 255.0) → [0.72, 0.92]
4. Convert HSV → RGB (standard conversion)
5. Store as ProjectColorTag with alpha 1.0
```

Saturation/brightness ranges produce colors vivid enough to distinguish but not overly intense — suitable for both light and dark themes.

**Triggers:**
- VibeSpace initialization (all project paths including unresolved)
- New project added via `assignAutoColorTagIfNeeded(forPath:)` (only if no tag exists)

### Manual Override

Via vibespace settings per-project config:
- `ColorPicker` (no opacity support) for quick selection
- "More" button → popover with full `ColorPicker` + "Clear Color"
- "Clear" button (visible when override set) → removes tag entry

Manual color created from chosen `Color` via `NSColor` sRGB conversion. Clearing sets entry to `nil`; auto-assigned color not restored until next `assignAutoColorTagIfNeeded` call (e.g., next vibespace load).

### State Lifecycle

- **Restoration:** `VibeSpaceState` init from `VibeSpaceConfigFile` reads `projectConfigs`, parses each `colorTag` via `ProjectColorTag(storageToken:)`, populates `projectColorTagsByPath`
- **Pruning:** `pruneColorTags()` removes entries for paths not in active or unresolved projects
- **Move:** `moveProjectAssociatedState` transfers color tag from old path to new path
- **Remove:** `removeProjectAssociatedState` deletes color tag for removed path

## 13 UI Locations

| # | Location | Usage |
|---|----------|-------|
| 1 | Focused project header bar | 2pt color bar at top of `FocusedProjectView` |
| 2 | Stacked project rail cards | Vertical pill indicator (4pt wide, 28pt tall), shortcut badge text/bg/border, card outer border (18% opacity) |
| 3 | Hidden rail terminal chips | Eye icon tint, border stroke (22% opacity) |
| 4 | Terminal board tile cards | Header terminal icon, git branch badge bg (18%), active tile border (58%, 0.9pt), active shadow (30%, 8pt radius) |
| 5 | Terminal board minimized tab bar | Terminal icon, border stroke (30% opacity) |
| 6 | Terminal board VibeCast tile | Passed as accent colors for terminal source entries |
| 7 | Terminal spotlight overlay | Header terminal/scope icon, tab strip navigation dots (6pt colored circle per tab) |
| 8 | Sidebar files pane | Project section header accent color |
| 9 | Sidebar source control pane | 8pt colored circle on repository section header (first attached project's color) |
| 10 | VibeSpace settings project list | 9pt filled circle next to project name |
| 11 | VibeSpace settings per-project row | 10pt colored circle with border stroke |
| 12 | Content viewer tab strip | Tab color resolved by longest matching project root path in `projectColorTagsByPath` |
| 13 | VibeCast message dots | 7pt circle on message group headers, compose target indicator, target selection popover (icon/title tint, selected row bg at 14%) |

Fallback: theme accent color when no color tag exists.

### Rail Card Color Details

- Pill indicator opacity: 0.92 active, 0.48 idle
- Shortcut badge: text color = project color, bg tint = 14% opacity, border = 28% opacity
- Card border: 18% opacity

## WCAG Luminance

`ProjectColorTag.relativeLuminance` computes WCAG relative luminance for contrast decisions:

```
1. Linearize each sRGB channel:
   - If value ≤ 0.03928: channel / 12.92
   - Otherwise: ((value + 0.055) / 1.055) ^ 2.4
2. Luminance = 0.2126 × R + 0.7152 × G + 0.0722 × B
```

Standard sRGB-to-luminance per WCAG 2.x.

## State Management

| State | Storage | Notes |
|-------|---------|-------|
| `projectColorTagsByPath` | `VibeSpaceState` (in-memory) | Keyed by normalized path |
| `colorTag` | `ProjectConfigFile` (on disk) | Hex string, optional |
| Auto-assignment | Computed from path hash | Not stored separately |

## Dependencies (frameworks, libraries)

- SwiftUI (`ColorPicker`)
- AppKit (`NSColor` for sRGB conversion)

## Platform Considerations

- macOS only — `NSColor` for color space conversion
- FNV-1a uses wrapping multiplication (Swift `&*` operator)

## Performance Constraints

- FNV-1a hash is O(n) on path length — negligible
- Color tag pruning runs once on vibespace restoration

## Migration / Rollout Notes

- Legacy named project-color token decoding removed; hex-only format
- Parsing is backward-compatible with both 6 and 8 char hex strings
