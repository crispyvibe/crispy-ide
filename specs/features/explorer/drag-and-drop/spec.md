# Drag & Drop — Spec

Status: draft

## Overview

Drag & Drop covers file and folder reorganization within the explorer sidebar. Users can move items within a project or copy items across project boundaries via drag-and-drop gestures.

## Dependencies

- F024 (File Explorer) — tree presentation and selection state

## Requirements

### F025-R01: Intra-Project Move

Dragging a file or folder onto another directory within the same project MUST execute a move operation with validation against self/descendant moves and destination collisions.

### F025-R02: Cross-Project Copy

Dragging a file or folder from one project root onto a directory in another project root MUST execute a copy operation, leaving the original in place.

## Scenarios

### Scenario F025-S01: Drag and drop reorganizes files and folders within a project

**Given** a file or folder row is dragged onto another directory row or root list surface
**When** drop is accepted
**Then** worker `moveItem` executes with source and destination directory paths
**And** move validation prevents self/descendant moves and destination collisions
**And** tree selection paths remap to moved destination when applicable
**And** tree refresh runs

### Scenario F025-S02: Drag and drop copies items when the target is in a different project

**Given** a file or folder row is dragged from one project root onto a directory in another project root
**When** drop is accepted
**Then** worker `copyItem` executes with source and destination directory paths
**And** the original source item remains in place
**And** cross-project validation still prevents self/descendant drops and destination collisions
**And** tree refresh runs

## Acceptance Criteria

- Move/copy operations complete within 200ms for typical file sizes (PERF-3).
- Invalid drop targets provide visual feedback (A11Y-2).
- All drag-drop operations logged (OBS-1, OBS-2).

## Open Questions

- None at this time.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/sidebar/folder-explorer (SDF-020, SDF-024) | — |
