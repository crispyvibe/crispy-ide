# Terminal Board Dock — Technical Design

## Overview

Terminal Board Dock extends the terminal board with dockable non-terminal content: file tiles, browser tiles, VibeCast tiles, and ACP tiles. It integrates with the spotlight system for preview-to-pin workflows and persists docked content across sessions. The dock reuses the board's existing tile grid, interaction system, and persistence infrastructure.

## Architecture

### Tile Content Kinds

The board tile model is extended with a content kind discriminator:

| Content Kind | Backing State | Persistence | Spotlight Navigation |
|-------------|--------------|-------------|---------------------|
| Terminal | `TerminalViewModel` + tab UUID | Project path + tab ID + working dir | Yes (persistent carousel) |
| File | Editor group / file viewer state | File path | Yes (persistent carousel) |
| Browser | Browser session state | Session snapshot | Yes (persistent carousel) |
| VibeCast | `VibeCastStore` | Flag only | Yes (persistent carousel) |
| ACP | `ACPStandalonePaneSnapshot` | Snapshot blob | Yes (persistent carousel) |

All content kinds follow the same board interaction rules: drag, resize, swap, minimize, restore, focus.

### Pin Workflow Architecture

```
Spotlight Preview (temporary)
  ├── Canvas mode = terminalOnly
  │   └── Pin action → create docked tile on board
  │       └── Blocked if board at capacity (no tile created, preview stays)
  └── Canvas mode = detailed
      └── Pin action → promote to detailed content viewer
          └── NOT blocked by board capacity
```

### Spotlight Integration

```
TerminalSpotlightCoordinator
├── Temporary previews (file, browser, terminal)
│   ├── Excluded from carousel navigation
│   ├── Dismiss restores previous spotlight item (restore chain)
│   └── Pin available only for transient file/browser previews in terminal-only mode
└── Persistent docked content (file, browser, VibeCast, ACP, terminal)
    ├── Participate in carousel navigation
    └── Double-click docked tile → open in spotlight using same viewer state
```

## Data Flow

### File Explorer Activation Flow

**Terminal-only mode:**
1. User activates file from explorer → canvas mode remains `terminalOnly`.
2. File opens as temporary spotlight preview over the board.
3. Uses existing editor/content-viewer infrastructure.
4. Activating another file replaces current preview (no stacking from explorer activation).
5. Pin action → create docked file tile; editor group assigned to tile.

**Detailed mode:**
1. User activates file from explorer → opens in detailed content viewer/editor surface.
2. No terminal-board spotlight preview shown.

### Pin-to-Board Flow

1. User clicks pin action on spotlight preview.
2. Check board capacity:
   - If free capacity → create docked tile via standard `insertNewTile` placement strategy.
   - If no capacity → reject; spotlight preview remains visible.
3. Assign live state to tile:
   - File: editor group transferred to tile.
   - Browser: live browser session transferred to tile.
4. Dismiss spotlight preview.
5. Persist layout.

### Nested Preview Restore Chain

1. User opens temporary preview from another spotlight item.
2. Dismiss nested preview → previous spotlight item restored.
3. Spotlight state cleared only when no restore target remains.
4. Applies to close button, Escape, and backdrop click dismissals.

### Docked Tile Spotlight Flow

1. User double-clicks docked file/browser tile content.
2. File/browser opens in spotlight using same viewer state (not a copy).
3. Spotlight chrome does NOT show a second pin action for already-docked content.

## API / Command Contracts

### Pin Action Availability

| Canvas Mode | Spotlight Content | Pin Available | Pin Target |
|------------|------------------|---------------|------------|
| terminalOnly | Temporary file/browser preview | Yes | Board tile |
| terminalOnly | Docked file/browser in spotlight | No (already docked) | — |
| detailed | Any file/browser content | Yes | Detailed content viewer |
| detailed (board full) | Any file/browser content | Yes | Detailed content viewer (not blocked by board capacity) |
| terminalOnly (board full) | Temporary file/browser preview | No (rejected) | — |

### Board Interaction Decorations

During drag and resize of docked tiles, the board renders the same visual decorations as terminal tiles:
- Docking guide overlay with compass drop zones.
- Layout preview overlay showing projected arrangement.
- Drop hint badge showing action name.

### Board Metrics

On layout change, `VibeSpaceTerminalBoardMetrics` recalculates positions, sizes, and capacity for all tile types uniformly. Content kind does not affect metrics computation.

## State Management

### Docked Content Persistence

Docked tiles persist as part of `VibeSpaceTerminalBoardLayout` (Codable):

| Content Kind | Persisted Fields |
|-------------|-----------------|
| Terminal | Project path, tab ID, working directory, height/width weights |
| File | File path, height/width weights |
| Browser | Session snapshot, height/width weights |
| VibeCast | Flag, height/width weights |
| ACP | `ACPStandalonePaneSnapshot`, height/width weights |

### Session Restoration

On vibespace reopen:
1. Layout decoded from persisted JSON.
2. Terminal tiles: rebound to project/standalone VMs (existing board sync logic).
3. File tiles: file content reopened from persisted path. Missing files pruned gracefully (removed from layout, no crash).
4. Browser tiles: session snapshot restored.
5. VibeCast/ACP tiles: restored from persisted state.
6. Minimized tiles restored in minimized tab bar in previous order.

### Layout Sync

Board layout state is persisted on every change: drag, resize, pin, minimize, restore. Uses the same `LayoutPersistenceService` and normalization pipeline as terminal tiles.

## Dependencies

- `VibeSpaceTerminalBoardStore` — tile grid, placement strategy, persistence
- `VibeSpaceTerminalBoardMetrics` — frame computation for all tile types
- `BoardInteractionController` — drag/resize/swap state machine
- `TerminalSpotlightCoordinator` — preview/pin workflow, carousel navigation
- Editor infrastructure — file viewer state for docked file tiles
- Browser infrastructure — session state for docked browser tiles
- `VibeCastStore` — VibeCast tile content
- `ACPStandalonePaneSnapshot` — ACP tile persistence

## Platform Considerations

- File tiles use the same editor/content-viewer infrastructure as the detailed mode editor pane.
- Browser tiles host `WKWebView` content within board tile frames.
- Docked content tiles support the same AppKit cursor rects and drag proxy rendering as terminal tiles.

## Performance Constraints

- File and browser tiles pin to board within 100ms.
- Docked tiles persist and restore across sessions without data loss.
- Missing file tiles prune without crash on restore.
- Spotlight carousel includes docked content without additional latency.
- Board layout sync persists on every change within 200ms.
