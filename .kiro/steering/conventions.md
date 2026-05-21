# Code Conventions

## Swift

- Write minimal code — no verbose implementations or code that doesn't directly contribute to the solution
- `@MainActor` on all UI-bound types (views, view models, stores, coordinators, use cases, context structs)
- All public types and functions must have doc comments
- Use `ObservableObject` with `@Published` for reactive state
- Protocols for all service boundaries — concrete types injected via `AppContainer`
- Initializer injection, never service locator or singleton access
- `Sendable` on value types crossing concurrency boundaries
- `[weak self]` in all `Task` and `DispatchWorkItem` closures
- Explicit `shutdown()` for types owning long-lived resources

## Naming

- Swift: `camelCase` for functions/variables, `PascalCase` for types, `SCREAMING_SNAKE` for constants
- Files: `PascalCase` matching the primary type (e.g., `TerminalSession.swift`)
- Feature folders: `PascalCase` under `Features/` (e.g., `Features/Terminal/`)
- Spec feature folders: `kebab-case` (e.g., `specs/features/terminal/spotlight/`)

## Documentation

- Feature requirements: `F{NNN}-R{NN}` (e.g., `F001-R01`)
- Feature scenarios: `F{NNN}-S{NN}` (e.g., `F001-S01`)
- Feature threats: `F{NNN}-T{NN}` (e.g., `F001-T01`)
- Every feature has 4 docs: `spec.md`, `technical-design.md`, `threat-model.md`, `usage-guide.md`
- No feature ships without all 4 docs reviewed
- Usage guides include YAML frontmatter for crispyvibe.com and in-app help integration

## Git

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- One concern per commit
- Commit in logical groups with descriptive messages

## Testing

- Test classes are `@MainActor`
- Fresh `AppContainer.makeDefault()` per test in `setUp`
- Teardown: unfocus terminal coordinator, nil container, remove temp directories
- Test names describe behavior: `test_closingLastTab_fallsBackToNone`
- External dependencies injected via protocols — test doubles for unit tests

## Process Rules

- Never kill the main `Crispy.app` process during development — use Xcode's stop button
- Measure performance before and after major refactors (no regression > 5% for startup, hydration, tab switch, memory)
- Lock files and project files: changes reviewed in PRs
