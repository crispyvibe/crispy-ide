# Coding Guidelines

This guide defines implementation standards for `projects/crispyvibes`.

## Design Principles

- Prefer clear ownership boundaries:
  - `Views/`: rendering and UI composition.
  - `ViewModels/`: UI state transitions and user-intent orchestration.
  - `Services/`: external process, filesystem, persistence, and integration logic.
  - `Models/`: serializable state and domain types.
- Keep behavior user-centric and scenario-driven (`specs/features/**/feature.md`).
- Reduce coupling by passing dependencies explicitly when practical.

## File and Type Organization

- Keep files focused on one responsibility.
- Extract helper types/extensions when a file becomes hard to scan.
- Avoid giant utility files that mix unrelated concerns.
- Use consistent naming aligned with behavior (`MarkdownViewModel`, `TerminalSessionHostView`, etc.).

## Implementation Practices

- Prefer immutable state where possible (`let` by default).
- Minimize side effects inside computed properties.
- Keep main-thread UI mutations explicit (`@MainActor` or main-thread dispatch as needed).
- Surface recoverable failures as user-friendly messages; avoid silent failure paths.
- Add accessibility identifiers for UI elements that are exercised by UI tests.

## Testing Expectations

- New user-visible behavior requires at least one automated test at the right layer.
- Bug fixes should include regression coverage.
- UI automation should validate stable flows, not brittle pixel-sensitive behavior.
- Keep test fixtures deterministic and isolated from machine-specific state.

## Documentation Expectations

For feature work:

1. Update scenario documentation in `specs/features/`.
2. Update scenario metadata mappings in `specs/features/scenario-metadata.tsv`.
3. Update project-local test/doc references if suite placement changed.

## Review Checklist

- Code follows layer ownership and keeps responsibilities narrow.
- Naming and structure are consistent with existing project conventions.
- Tests are added/updated and pass locally/CI.
- Scenario docs and traceability mappings are current.
