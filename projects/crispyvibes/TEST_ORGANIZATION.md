# Test Case and File Organization

This document defines where tests belong in `projects/crispyvibes/tests` and how new test files should be organized.

## Test Layers

- `tests/unit`: fast logic tests for models, view models, services, and pure helpers.
- `tests/integration`: cross-component workflows that still avoid full UI automation.
- `tests/ui`: end-to-end user workflows via `XCTest` UI tests.

## UI Suite Structure

UI tests are split by user workflow category:

- `BaseUITestCase.swift`: shared setup/teardown helpers.
- `VibeSpaceAndNavigationUITests.swift`: vibespace shell, project switching, dashboard, rail navigation.
- `TerminalInteractionUITests.swift`: terminal sessions, tabs, terminal-only layout, preset/interaction flows.
- `EditorWorkflowsUITests.swift`: editor routes, markdown commands, previewers, find/replace, file-type handling.
- `ChromeAndSettingsUITests.swift`: title bar actions, project color controls, app/vibespace settings surfaces.

## File Placement Rules

1. Put tests close to the behavior boundary they validate.
2. Add a new file only when an existing suite would become mixed-purpose.
3. Keep helpers in `TestSupport.swift` or `UITestSupport.swift`, not duplicated across suites.
4. Prefer one concern per test method; long cross-feature flows belong in integration/UI, not unit.

## Naming Conventions

- File names end with `Tests.swift` (or `UITests.swift` for UI suites).
- Test method names use `test<BehaviorDescription>()`.
- Names should describe user-visible behavior, not implementation details.

## Traceability Expectation

When a test is added, updated, moved, or renamed:

1. Update `docs/features/scenario-metadata.tsv` test mappings.
2. Regenerate `docs/features/scenario-traceability.md`.
3. Verify metadata and matrix are in sync.

## Common Commands

From repo root:

```bash
xcodebuild -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS,arch=arm64' test
```

Targeted runs:

```bash
xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS,arch=arm64' -only-testing:CrispyVibesUnitTests
xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS,arch=arm64' -only-testing:CrispyVibesIntegrationTests
xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes-local -destination 'platform=macOS,arch=arm64' -only-testing:CrispyVibesUITests
```
