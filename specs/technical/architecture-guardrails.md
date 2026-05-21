# Architecture Guardrails

Use these rules during refactors and reviews to stop recurring regressions.

## 1. Ownership

- A view must not create heavy runtime state unless it truly owns that feature for its full lifetime.
- Hidden UI must not initialize terminals, hydration, git refresh, or other expensive work.
- Parent views may own feature objects, but only the subtree that renders them should observe them.
- `ContentView` should own shell state only. Feature state belongs to feature stores or coordinators.
- No new production `.shared` usage without a written justification in code review.

## 2. Structural Identity

- Do not conditionally move the same content between different parent containers.
- Do not use `if` or `switch` in a way that changes the structural identity of AppKit-backed trees unless full recreation is intentional.
- Any `.id(...)` on terminal, editor, split-view, or AppKit-hosted surfaces must include a short comment explaining why forced recreation is required.
- `NSViewRepresentable` wrappers should update synchronously unless async behavior is required for correctness and documented.

## 3. Main-Thread Budget

- Main actor is for UI mutation and AppKit or SwiftUI interaction only.
- Planning, scanning, hydration preparation, git decoding, and persistence I/O should happen off-main.
- Expensive work triggered from `body`, `onAppear`, or `onChange` is not allowed without profiling justification.
- Runtime callbacks should do minimal work on main and hand off non-UI work elsewhere.

## 4. API and Composition

- No new closure-bag coordinators with large stored closure sets.
- Persistent coordinators should hold direct store and service references.
- If a child view grows beyond roughly 8 to 10 init parameters, bundle related actions or config into typed structs.
- Context wrappers must narrow access. No 1:1 passthrough wrappers.

## 5. Feature Activation

- Expensive surfaces should initialize lazily on first activation when possible.
- Preserving view identity is good, but only after first activation. Do not eagerly initialize hidden modes just to keep switching fast.
- Terminal-heavy features must not create sessions merely because they are present in an off-screen or hidden subtree.

## 6. Dependency Injection

- The composition root creates long-lived services and stores.
- Feature code should not discover dependencies through globals.
- Platform helpers like `NSVibeSpace.shared` should live behind injected services where they affect app behavior.
- Tests should use explicit dependency construction, not production globals.

## 7. Verification

- Any refactor touching view identity must test:
  - sidebar toggle
  - canvas mode switch
  - vibespace switch
  - terminal creation and restoration
- Any refactor touching terminal or session ownership must run terminal lifecycle tests.
- Any performance fix should name the teardown or recreation path it prevents.

## 8. Large File Policy

- Splitting a file is not enough by itself. Ownership must move with the split.
- A new file in `Views/` should not silently absorb state, orchestration, and persistence logic.
- When a file exceeds a few hundred lines, review whether it mixes rendering, state ownership, orchestration, and external I/O.
