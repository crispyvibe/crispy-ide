# AGENTS.md

Crispy is a native macOS terminal-first workspace IDE built with Swift and SwiftUI.

## Setup commands

- Install dev tools and build GhosttyKit: `./scripts/setup-dev.sh`
- Install Rust/Cargo for the bundled path-search helper if it is not already available: `brew install rustup-init && rustup-init`
- Open Xcode project: `open projects/crispyvibes/crispyvibes.xcodeproj`
- Build (local scheme): `xcodebuild build -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes-local -configuration DebugLocal -destination 'platform=macOS'`
- Run tests: `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests`
- Launch local build: `./scripts/run-local.sh` (builds and launches `CrispyLocal.app` from the current worktree's DerivedData)

## Local build prerequisites

- `./scripts/setup-dev.sh` covers Xcode command line tools, Homebrew, Zig, Metal toolchain, Ghostty artifacts, and an initial build check.
- The terminal inline path-search helper is compiled from `projects/crispyvibes/rust/crispyvibes-path-search` during Xcode builds.
- Fresh developer machines still need Rust/Cargo installed locally or the build will fail with `cargo is required to build the bundled path-search helper`.

## Code style

- Swift 5, SwiftUI + AppKit, macOS 26+
- `@MainActor` on all UI types (views, view models, coordinators)
- Initializer injection via `AppContainer` composition root — no singletons
- `ObservableObject` for view models, not `@Observable`
- Factory closures for dependency injection
- `AppStrings` for all user-facing text (localization)
- File splitting: views ≤400 LOC, view models ≤200 LOC per file
- PascalCase for files and types, camelCase for functions and properties

## Project structure

```
projects/crispyvibes/crispyvibes/
  App/                    ← Entry point, AppContainer, AppDelegate
  Features/               ← Feature modules (ACP, ContentViewer, Editor, Home, Local, Remote, Settings, Shared, Terminal, VibeCast, Workspace)
  Protocols/              ← Shared protocol definitions
  Data/                   ← Persistence layer
  Shared/                 ← Cross-feature components
  Resources/              ← Assets, GhosttyRuntime, SetiIcons
specs/                    ← All documentation
  features/               ← 35 features × 4 docs (spec, technical-design, threat-model, usage-guide)
  features/INDEX.md       ← Feature registry with domains and prefixes
  features/CONVENTION.md  ← Doc convention rules
  nfr/                    ← Non-functional requirements
  planning/               ← Active plans and roadmaps
  technical/              ← Cross-cutting architecture docs
  security/               ← Threat models
  learnings/              ← Investigation records
  adr/                    ← Architecture decision records
```

## Testing instructions

- Unit tests: `xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests`
- All tests must pass before pushing
- `@MainActor` on test classes, fresh `AppContainer.makeDefault()` per test
- Add regression tests for bug fixes
- Test files mirror source structure: `tests/unit/Features/{Domain}/`

## Important rules

- Never kill the main `Crispy.app` process — use `crispyvibes-local` scheme (`CrispyLocal.app`) for testing
- Feature docs follow the 4-doc convention: see `specs/features/CONVENTION.md`
- Scenario IDs use `F{NNN}-S{NN}` format (e.g., `F001-S01`)
- Commit in logical groups with descriptive messages
- Do not modify or remove unit tests unless explicitly requested
- Do not include secret keys in code
