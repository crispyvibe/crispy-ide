# Clone Repository — Spec

Status: draft

## Overview

Clone Repository provides the ability to clone a Git repository from the source control sidebar. It integrates with GitHub CLI for repository browsing when available, and adds the cloned folder to the active vibespace as a new project.

## Dependencies

- F026 (Git Operations) — repository discovery after clone
- F020 (VibeSpace Lifecycle) — vibespace project management

## Requirements

### F027-R01: Clone Repository Flow

The clone action MUST check for GitHub CLI availability, allow selecting from existing GitHub repositories or pasting a URL, clone to a chosen destination, and add the result as a vibespace project.

### F027-R02: Empty State Clone Button

When no repositories are discovered, the sidebar MUST show an empty state with a Clone Repository button.

## Scenarios

### Scenario F027-S01: Clone repository adds the cloned folder to the active vibespace

**Given** the active VibeSpace is open in the `Git` sidebar
**When** the user chooses `Clone Repository…` from the header or empty state
**Then** the app first checks whether GitHub repository browsing is already available on the machine
**And** the user can select from existing GitHub repositories when available or paste a repository URL otherwise
**When** the user submits a valid repository source plus destination
**Then** the app clones the repository into the chosen destination folder
**And** the cloned folder is added to the active VibeSpace as a Project
**And** the cloned Project becomes available to vibespace source control discovery

### Scenario F027-S02: Empty repository state with Clone button

**Given** the vibespace has no discovered repositories
**When** the Git sidebar loads
**Then** the sidebar shows an empty state message
**And** the empty state includes a Clone Repository button

## Acceptance Criteria

- Clone operation provides progress feedback (A11Y-2).
- Clone errors surface user-facing dismissible alerts (REL-6).
- All clone operations logged (OBS-1, OBS-2).

## Open Questions

- None at this time.

## Change History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-15 | Migrated from docs/features/sidebar/source-control-vibespace (SCM-113, SCM-127) | — |
