# Coding Guidelines

## Design Principles

- Clear ownership boundaries: each feature owns its types, logic, and persistence.
- Behavior is scenario-driven — implementation follows from spec scenarios (`F{NNN}-S{NN}`).
- Dependencies are passed explicitly. No type discovers its dependencies through globals.
- Composition over inheritance. Use protocols for abstraction, structs for state.

## Architecture Rules

### Layering

```
SwiftUI Views → ViewModels (ObservableObject) → Services → Protocols
                                               → Models
```

Views never call services directly. ViewModels mediate all state and logic. Services don't know about views.

### Composition Root

`AppContainer` is the single composition root. It is a plain `struct` with stored service properties and `make*()` factory methods. `AppContainer.makeDefault()` is called once in `CrispyVibesApp`.

- No singletons in production code.
- Every dependency is received through `init`.
- `AppContainer` is passed to coordinators that need to create further objects.

### Dependency Injection

- Initializer injection for all dependencies.
- Factory closures for deferred creation (e.g., `projectSessionFactory`, `editorGroupFactory`, `PaneWorkerFactory`).
- Protocols in `Protocols/`, concrete implementations in `Data/` or feature `Services/`.
- Environment injection only for app-wide shared dependencies.

## State Management

- `@MainActor` on all UI types: every `ObservableObject`, store, coordinator, view model, context struct, and use case.
- `ObservableObject` for view models and stores with `@Published` properties.
- `@Published private(set)` with mutation-through-methods for collection state.
- Enum-based state machines for navigation (`ActiveSurface`, `ActiveModalSheet`).
- State transitions through named methods, never by setting properties directly from views.

## Patterns

### Coordinator Pattern
`@MainActor final class` conforming to `ObservableObject`. Orchestrates multi-step workflows spanning multiple stores and services. All dependencies via `init`. `Task` closures capture `[weak self]`.

### Use Case Pattern
`@MainActor struct` with no stored mutable state. Pure business logic with all dependencies as method parameters. May compose other use cases as stored properties.

### Context Structs
`@MainActor struct` wrapping a store. Exposes only the subset of state and actions a specific view needs. Created as computed properties on the parent view.

### Factory Closures
Stored as properties, invoked lazily. Used for child object creation and breaking circular dependencies. `AppContainer` captures `[self]` to close over its `make*` methods.

## Concurrency

- `@MainActor` at the type level, not per-method.
- `[weak self]` in every `Task` closure and `DispatchWorkItem` that captures self.
- Tracked tasks stored in properties and cancelled before replacement.
- `Sendable` conformance on value types that cross concurrency boundaries.
- `@unchecked Sendable` with explicit locking only when unavoidable.
- CPU-intensive work dispatched to dedicated serial `DispatchQueue`, results coalesced back to main.

## Memory Management

- Explicit `shutdown()` methods on types with long-lived resources (nil closures, cancel subscriptions, terminate processes).
- `deinit` for `NSEvent` monitors and `NotificationCenter` observers.
- `WorkspaceCatalogStore` calls `shutdownProjects()` before removing workspaces.
- Registry types (`WorkspaceTerminalBoardStandaloneRegistry`) release and shutdown view models explicitly.

## Error Handling

- Use `Result` and `throws` for fallible operations.
- Propagate errors with `try` — don't swallow silently.
- User-facing errors should be structured types, not raw strings.
- Log errors at the point of handling, not creation.

## File Organization

- One primary type per file. Small helpers can coexist if tightly coupled.
- File names match the primary type in PascalCase (e.g., `TerminalSession.swift`).
- Files over 400 LOC: consider splitting by responsibility.
- Types over 200 LOC: split impl into extensions in separate files.
- Keep heavy logic out of SwiftUI `body`.

## String Localization

- All user-facing strings in `AppStrings` enum namespace using `String(localized:)`.
- Naming: `{feature}.{context}.{element}` (e.g., `"explorer.deleteItem.title"`).
- Non-localized brand constants in `AppStrings.Brand`.
- Backed by `Localizable.xcstrings`.

## Anti-Patterns

- No singletons (`SomeService.shared`) in production dependency flow.
- No force unwraps in production code without a comment explaining safety.
- No direct store property mutation from views — use named methods.
- No heavy sync work in the SwiftUI render path.
- No `todo()` / `fatalError()` in merged code for unimplemented features.
- No global mutable state.
