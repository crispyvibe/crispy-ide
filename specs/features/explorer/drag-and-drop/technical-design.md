# Drag & Drop — Technical Design

## Overview

Drag and drop covers file explorer transfers (move/copy), editor drop zones (tab splitting), external file drops, project reorder, sidebar project transfers, and terminal board tile drag. The system uses `ExplorerItemDropPlanner` for file transfer validation and `EditorDropZoneOverlay` for split-zone detection.

## Architecture

### File Explorer Transfers

#### Drag Payload

Every dragged explorer item encoded as `VibeSpaceDragPayload` with the file's standardized path. Written to three pasteboard representations simultaneously:

- Custom type (`dev.crispyvibesde.vibespace-item`) — JSON-encoded path data.
- Plain string — path text.
- `fileURL` — file URL representation.

Decoding priority: custom type → file URL → plain string. `NSItemProvider`-based drops (SwiftUI) use async loading via `DispatchGroup`.

#### Operation Resolution

`ExplorerItemDropPlanner.resolveOperation` determines move vs. copy per item:

- Finds longest-matching project root URL for source and target.
- **Same project** (shared root) → **move**.
- **Cross-project** (different roots) → **copy**.
- **No matching root** → defaults to **copy**.

`uniformOperation` check: if all items resolve to the same operation, that operation is used. Mixed batch → no drag badge, progress title "Organizing."

#### Validation Rules

Drop plan rejected (item silently excluded) if:

1. Source does not exist on disk.
2. Target is not an existing directory.
3. Self-drop (destination URL identical to source after standardization).
4. Overwrite conflict (file/directory already exists at destination).
5. Move into descendant (directory moved into its own subfolder).

All paths standardized (symlinks resolved, trailing slashes normalized) before comparison.

### Editor Drop Zones

3-column detection grid (`EditorDropZoneOverlay.zone(at:in:)`):

| Cursor Position | Zone |
|----------------|------|
| Left third (x < width/3) | `.left` |
| Right third (x > width×2/3) | `.right` |
| Center third, upper half (y < height/2) | `.top` |
| Center third, lower half (y ≥ height/2) | `.bottom` |
| Zero-size area | `.center` |

Drop behavior:

- **Center** — tab moved into current group (no split).
- **Left/Right** — horizontal split created.
- **Top/Bottom** — vertical split created.
- At split limit (`canSplit` false) — all zones behave as center.

Accepted types: `ContentViewerTabDragSupport.dropTypes` (existing tabs or file URLs).

Visual overlay: semi-transparent accent fill (15% opacity), 2px accent stroke (50% opacity), 4pt corner radius. Non-interactive (`allowsHitTesting(false)`).

### Embedded Drop Bridge

`ContentViewerEmbeddedDropBridge` forwards drag events from embedded AppKit editor back to SwiftUI drop zone system, ensuring consistent zone detection inside editor content area.

### Terminal Board Tile Drag

#### Layout Model

- Max **4 columns**, **4 rows per column**, **16 tiles total**.
- Each column has `widthWeight`, each tile has `heightWeight` (normalized proportional fractions).
- Tiles can be minimized to a tray and restored.

#### Drag Initiation

`BoardInteractionController` hit-tests to distinguish: tile header (move drag), column divider (resize), row divider (resize), tile body/empty (no drag).

#### 5 Drop Intents

Docking guide resolves intent based on cursor position relative to target tile:

| Intent | Condition | Result |
|--------|-----------|--------|
| Insert Left | Near left edge | New column to the left |
| Insert Right | Near right edge | New column to the right |
| Insert Above | Near top edge (center third H) | Above target in same column |
| Insert Below | Near bottom edge (center third H) | Below target in same column |
| Swap | Center region | Tiles swap positions |

Dock target resolution: center inset region (24–40% from each edge, min 20px) → swap. Outside center → closest edge determines direction.

#### Docking Compass Overlay

- Semi-transparent scrim (48% opacity) over entire board.
- Target tile outlined with dual stroke (primary text 44% + accent 98%).
- Indicator bar along corresponding edge (accent 52%) or full area fill for swap (accent 24%).
- Compass widget (92–146px, 42% of smaller tile dimension) with 5 directional segments.
- Drop hint badge (capsule) below compass with action name.

#### Column and Row Resizing

- Column dividers: hit area = spacing + 8px (min 14px). Adjusts `widthWeight` proportionally, min 12% per column.
- Row dividers: same behavior vertically, min 12% per row.
- Changes applied live, committed on release. Escape reverts.

### Terminal File Drop

`TerminalFileDropSupport` is registered on `GhosttyTerminalView` and `MonitoredTerminalView` (defined in `TerminalSessionSupportTypesInteractiveTargeting.swift`) as a centralized file drop handler. On drop:

- File paths are shell-escaped via a quoting utility.
- Paths within the terminal's current working directory are converted to relative paths; all others use absolute paths.
- Multiple paths are joined with spaces and a trailing space is appended.
- The resulting string is written to the terminal session as keyboard input.

## Data Flow

### Transfer Execution

Validated plans executed sequentially via pane worker. Each item moved/copied with **20-second timeout**. On success: selection updated to destination path (moves), tree refreshed after all transfers. On failure: error message shown, worker status set to unavailable.

### External File Drop

Entire app window accepts `.fileURL` drops. Files load asynchronously from `NSItemProvider`, directories are filtered out, and the remaining files are added to Shelf (front of list, deduplicated). When a vibespace is available, the Files sidebar is revealed and the first selected Shelf file opens in the main content viewer. State persists to `shelf-state.json`.

### Project Reorder

VibeSpace settings list with `.onMove`. After reorder: shortcut indices reassigned (first 9 projects get shortcuts 1–9), selected project preserved, vibespace catalog persisted immediately.

### Sidebar Project Transfer

Each project section acts as drop target via `AppKitTreeView`. `ExplorerItemDropPlanner` generates plans using target project root as destination. Same validation rules. Delegates to `transferItems(using:)` on target `FolderExplorerViewModel`.

## State Management

- Drag operation cursor: `.move` for same-project, `.copy` for cross-project, empty if no valid plans.
- Terminal board layout (columns, tiles, weights, active tile, minimized tiles) persisted per vibespace via `LayoutPersistenceService` after every mutation.
- Minimized tiles auto-pruned when terminal tabs no longer exist.

## API / Command Contracts

| Command | Timeout | Purpose |
|---------|---------|---------|
| Worker move item | 20 s | Move file/folder within project |
| Worker copy item | 20 s | Copy file/folder across projects |

### Pasteboard Types

- `dev.crispyvibesde.vibespace-item` — explorer item payload.
- `com.crispyvibe.app.content-viewer-tab` — editor tab payload.
- `UTType.fileURL` — external file drops.

## Dependencies (frameworks, libraries)

- `ExplorerItemDropPlanner` — transfer validation and operation resolution
- `EditorDropZoneOverlay` — split-zone detection
- `ContentViewerEmbeddedDropBridge` — AppKit-to-SwiftUI drag forwarding
- `BoardInteractionController` — terminal tile drag hit-testing
- `LayoutPersistenceService` — board layout persistence
- `PaneWorkerClient` — file transfer execution

## Platform Considerations

- `NSItemProvider` for SwiftUI drag-and-drop interop.
- `NSDragOperation` for cursor feedback.
- `NSPasteboard` with multiple simultaneous representations.
- Board tile drag uses custom hit-testing on `NSView` coordinate space.

## Performance Constraints

- Transfer timeout: 20 seconds per item (sequential execution).
- Board resize changes applied live during drag for responsive feedback.
- Docking guide uses Euclidean distance for nearest-tile selection.
