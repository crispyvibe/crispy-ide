# Terminal Board Multi-Monitor — Spec

Status: implemented

## Overview

Terminal Board Multi-Monitor allows a single vibespace's terminal board to span multiple displays by opening detached board windows. Detached windows render terminal-board tiles only and remain tied to the owning vibespace runtime. Tiles can be transferred between board surfaces via context menu or drag.

## Dependencies

- F002 (Terminal Board) — extends the board with multi-surface support
- F003 (Terminal Spotlight) — each board window owns an independent local spotlight

## Requirements

### F048-R01: Open detached board windows

A vibespace in terminal board mode must be able to open additional detached board windows on other displays.

### F048-R02: Board content only

Detached board windows must render terminal-board content only (tiles, minimized tabs, VibeCast, ACP, browser tiles). They must not become independent vibespace shells.

### F048-R03: Mode independence

Switching the primary vibespace window from terminal board to detailed mode must not close detached board windows.

### F048-R04: Settings ownership

App settings and vibespace settings must remain owned by the primary vibespace window even when detached board windows are visible.

### F048-R05: Lifecycle coupling

Detached board windows must close when the owning vibespace closes.

### F048-R06: Placement persistence

Detached board window geometry (frame, display assignment) must persist per vibespace and restore on next open using best-effort placement.

### F048-R07: Tile transfer via context menu

Visible tile headers and minimized tab context menus must support sending the selected tile to a new board window or an existing open board window.

### F048-R08: Surface-targeted creation

New-terminal, split-terminal, and temporary-terminal-to-persistent actions initiated from a board surface must target the initiating surface.

### F048-R09: Independent spotlight

Each detached board window must own an independent local spotlight coordinator so spotlight does not jump to the primary vibespace window.

### F048-R10: Tile transfer semantics

Tile transfer must move exactly one tile between board surfaces. No cloning, no bulk-move, no blank placeholders left on the source surface.

### F048-R11: Window toolbar

Detached board windows must have a toolbar with actions to add VibeCast, Agent, and Browser tiles to that surface.

### F048-R12: Window rename

Detached board windows must support renaming via titlebar context menu.

## Scenarios

### Scenario F048-S01: Open a detached board window

**Given** the user is in terminal board mode  
**When** the user sends a tile to a new board window via context menu  
**Then** a new detached board window opens containing that tile  
**And** the tile is removed from the source surface

### Scenario F048-S02: Transfer tile to existing window

**Given** two board windows are open for the same vibespace  
**When** the user right-clicks a tile and selects "Send to Board Window > [target title]"  
**Then** the tile moves to the target surface  
**And** the tile is removed from the source surface

### Scenario F048-S03: Primary window mode change

**Given** the primary window is in terminal board mode with one detached board window  
**When** the user switches the primary window to detailed view  
**Then** the detached board window remains open and functional

### Scenario F048-S04: Vibespace close

**Given** a vibespace has two detached board windows  
**When** the user closes the vibespace  
**Then** both detached board windows close automatically

### Scenario F048-S05: Placement restoration

**Given** a vibespace previously had a detached board window on an external monitor  
**When** the vibespace is reopened with the same display topology  
**Then** the detached board window is restored at its previous frame position

### Scenario F048-S06: Spotlight in detached window

**Given** a detached board window is focused  
**When** the user triggers spotlight  
**Then** spotlight opens within the detached board window, not the primary window

### Scenario F048-S07: New terminal targets initiating surface

**Given** the user is focused on a detached board window  
**When** the user creates a new terminal tile  
**Then** the tile appears on the detached board surface, not the primary surface

### Scenario F048-S08: Empty window closes after transfer

**Given** a detached board window contains a single tile  
**When** the user transfers that tile to another board window  
**Then** the now-empty detached board window closes automatically

### Scenario F048-S09: Rename detached window

**Given** a detached board window is open  
**When** the user right-clicks the titlebar and selects "Rename Window"  
**Then** a rename prompt appears  
**And** the window title updates after confirmation

## Acceptance Criteria

- User can place terminal-board windows on multiple monitors without creating a second vibespace shell.
- Primary vibespace window can switch modes without disrupting detached board windows.
- Detached board windows close automatically with the owning vibespace.
- Detached board windows are restored using persisted surface state and best-effort window placement.
- Spotlight opens in the board window where the user initiated it.
- Settings continue to behave as primary-window shell flows.
- Persistent terminal creation from plus, split, and spotlight actions appears on the initiating board surface.
- Context-menu tile transfer moves one selected tile only, leaves no blank source placeholders, and closes emptied detached source windows.
- Transfer target menu shows current surface content labels.

## Open Questions

None — feature is implemented.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-05-20 | Initial spec from implemented feature | Kiro |
