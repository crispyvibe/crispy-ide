# CrispyVibes Test Scaffolding

This folder is organized by test type first, then by the production module it exercises:

- `unit`
  - `App`, `Models`, `Data`, `Features`, `Shared`
  - `Support` stays at the unit root for suite-wide fixtures and helpers
  - `Property` keeps property-style tests grouped by the same production modules
- `behavioral`
  - `App`
  - `Features`
- `integration`
  - `Data`
- `ui`
  - `App`
  - `Features`
  - `Support`

Examples:

- `tests/unit/Features/Terminal/ViewModels/TerminalViewModelTests.swift`
- `tests/unit/Data/Persistence/LayoutPersistenceServiceTests.swift`
- `tests/behavioral/Features/VibeSpace/VibeSpaceBehavioralTests.swift`
- `tests/integration/Data/Persistence/VibeSpacePersistenceIntegrationTests.swift`
- `tests/ui/Features/Terminal/TerminalInteractionUITests.swift`

Notes:

- Test targets are wired into `crispyvibes.xcodeproj`:
  - `CrispyVibesUnitTests` -> `tests/unit/**`
  - `CrispyVibesIntegrationTests` -> `tests/behavioral/**` + `tests/integration/**`
  - `CrispyVibesUITests` -> `tests/ui/**`
- Latest non-UI validation run (2026-03-03):
  - `211` unit tests passed
  - `9` integration/behavioral tests passed
  - Coverage report: `CrispyVibes.app 63.56%`
- Performance report:
  - `docs/testing/STARTUP_PERFORMANCE.md`
