# Feature Documentation Convention

## Structure

Each feature in `specs/features/` MUST have its own folder containing exactly four documents:

```
specs/features/{domain}/{feature-name}/
  spec.md              ← What the feature does (requirements, scenarios, acceptance criteria)
  technical-design.md  ← How it is built (architecture, data flow, API contracts, dependencies)
  threat-model.md      ← What can go wrong (attack surfaces, trust boundaries, mitigations)
  usage-guide.md       ← How the user uses it (workflows, screenshots, keyboard shortcuts, tips)
```

For the feature registry (domains, prefixes, folders, status), see [INDEX.md](INDEX.md).

## Naming Convention

- Feature folder: lowercase kebab-case (e.g., `file-explorer`, `vibespace-lifecycle`).
- Document names are fixed — always `spec.md`, `technical-design.md`, `threat-model.md`, `usage-guide.md`.
- Features are nested under their domain folder: `specs/features/{domain}/{feature-name}/`.

## ID Formats

| Document | Format | Example |
|----------|--------|---------|
| spec.md | `F{NNN}-R{NN}` (requirement) | `F001-R01`, `F001-R02` |
| spec.md | `F{NNN}-S{NN}` (scenario) | `F001-S01`, `F001-S02` |
| threat-model.md | `F{NNN}-T{NN}` (threat) | `F001-T01`, `F001-T02` |

NFR IDs (`SEC-1`, `DEP-3`, `OBS-2`, etc.) are cross-referenced but never duplicated — feature docs link to them, not redefine them.

## Document Outlines

### spec.md

```
# {Feature Name} — Spec
Status: draft | review | approved | implemented | shipped
## Overview
## Dependencies
## Requirements
### {FEAT-ID}: {Requirement title}
## Scenarios
### Scenario {ID}: {Name} (Given / When / Then)
## Acceptance Criteria
## Open Questions
## Change History
```

### technical-design.md

```
# {Feature Name} — Technical Design
## Overview
## Architecture
## Data Flow
## API / Command Contracts
## State Management
## Dependencies (frameworks, libraries)
## Platform Considerations
## Performance Constraints
## Migration / Rollout Notes
```

### threat-model.md

```
# {Feature Name} — Threat Model
## Overview
## Trust Boundaries
## Attack Surfaces
## Threats
### {THREAT-ID}: {Title}
- Vector:
- Impact:
- Likelihood:
- Mitigation:
## Residual Risks
## NFR Compliance (references to SEC-*, A11Y-*, etc.)
```

### usage-guide.md

Frontmatter is required for crispyvibe.com integration and in-app rendering:

```
---
title: "{Feature Name}"
feature: "F{NNN}"
domain: "{domain}"
audience: "user"
version: "1.0"
sidebar:
  label: "{Short Label}"
  order: {N}
---

# {Feature Name}
## Overview
## Getting Started
## Workflows
## Keyboard Shortcuts
## Settings / Configuration
## Troubleshooting
## Known Limitations
```

| Field | Required | Purpose |
|-------|----------|---------|
| `title` | Yes | Page title for website and in-app help |
| `feature` | Yes | Feature ID (e.g., `F001`) |
| `domain` | Yes | Domain name (e.g., `terminal`) |
| `audience` | Yes | `user` for end-user docs, `developer` for internal |
| `version` | Yes | Doc version, bumped on significant changes |
| `sidebar.label` | Yes | Short name for crispyvibe.com sidebar |
| `sidebar.order` | Yes | Sort order within the domain group |

### Documentation Pipeline

Usage guides serve three targets from a single source:

1. **In-app help**: Rendered in the SwiftUI help panel via a markdown renderer. Frontmatter is stripped, content is displayed.
2. **Website (crispyvibe.com)**: Published to crispyvibe.com. Frontmatter drives navigation, sidebar, and metadata.
3. **Repository**: Readable as plain markdown on GitHub/GitLab.

Content rules for portability:
- Use relative image paths: `./images/{name}.png` (co-located in the feature folder)
- No framework-specific components — plain markdown only
- Use standard markdown links, not framework-specific syntax
- Keep headings hierarchical (h2 → h3 → h4, never skip levels)

## Rules

- No feature may ship without all four documents reviewed and merged.
- Threat model MUST reference applicable NFR requirement IDs (SEC-1, SEC-3a, etc.).
- Spec scenarios MUST have matching test coverage documented in the spec or a linked test plan.
- Usage guide MUST be written for end users — no implementation jargon.

## Document Status

Each feature folder MUST track status in the spec header:

```
Status: draft | review | approved | implemented | shipped
```

When a spec is updated post-ship, add an entry to a `## Change History` section at the bottom.

## Cross-Feature Dependencies

If a feature depends on another feature, the spec MUST declare it:

```
## Dependencies
- F001 (Terminal) — required for spotlight terminal rendering
- F008 (Themes) — required for accent color resolution
```
