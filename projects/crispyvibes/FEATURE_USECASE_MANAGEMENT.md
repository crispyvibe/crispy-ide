# Feature and Use-Case Management

This document defines how `projects/crispyvibes` work maps to user-facing behavior and acceptance criteria.

## Source Of Truth

- Feature behavior: `specs/features/**/feature.md`
- Scenario status and test mappings: `specs/features/scenario-metadata.tsv`
- Generated traceability matrix: `specs/features/scenario-traceability.md`
- Phase requirements and acceptance criteria: `specs/features/planning/*.md`

Project-local rule: implementation must follow those docs; this file defines the workflow to keep them current.

## Scenario Structure

Use the scenario heading format:

- `### Scenario <ID>: <name>`

ID prefixes in current use:

- `APP-*` app shell and vibespace lifecycle
- `BRW-*` in-app browser and browser spotlight behavior
- `SDB-*` sidebar behavior
- `SDF-*` folder explorer behavior
- `SDG-*` git explorer behavior
- `EDT-*` editor behavior
- `TRM-*` terminal behavior
- `TXT-*` text services
- `WRK-*` worker/filesystem behavior
- `DCK-*` terminal board dock behavior

## Change Workflow

1. Identify impacted feature category file in `specs/features/`.
2. Add/update scenario(s) using `Given / When / Then`.
3. If behavior is part of a roadmap phase, update the matching `specs/features/planning/phase-*.md`.
4. Add or update scenario rows in `specs/features/scenario-metadata.tsv`.
5. Implement code changes in `projects/crispyvibes/`.
6. Add or update tests in `projects/crispyvibes/tests/` and map fully-qualified test names in metadata.
7. Regenerate and validate traceability.

## Required Commands

From repo root:

```bash
echo "Keep specs/features/scenario-metadata.tsv and specs/features/scenario-traceability.md in sync manually."
```

Optional strict validation:

```bash
echo "Fail CI when active scenarios are unmapped in scenario-traceability.md."
```

## Definition Of Done

- Behavior is documented in a feature file.
- Scenario metadata row exists and is accurate.
- Acceptance assertions are documented for phase-gated features.
- Tests pass for changed scope (unit/integration/UI as needed).
- No orphan scenario IDs or stale test mappings remain.
