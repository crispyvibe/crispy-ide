# AGENTS.md - projects/crispyvibes

Scope: applies to everything under `projects/crispyvibes/`.

See the root [AGENTS.md](../../AGENTS.md) for setup commands, code style, and project structure.

## Feature and Use-Case Management

- Source of truth for behavior is `specs/features/**/spec.md`.
- Every user-visible change must map to one or more scenario IDs (`F{NNN}-S{NN}`).
- Feature registry: `specs/features/INDEX.md`.
- Doc convention: `specs/features/CONVENTION.md`.

## Test Organization

- `tests/unit/` — logic-level tests, organized by `Features/{Domain}/`
- `tests/behavioral/` — cross-component workflow tests
- `tests/integration/` — persistence and data layer tests
- `tests/ui/` — end-to-end XCUITest interaction tests
- `tests/unit/Property/` — randomized invariant tests

Detailed test structure: `./TEST_ORGANIZATION.md`

## Coding Guidelines

- Keep boundaries clean across `Views`, `ViewModels`, `Services`, and `Models`.
- Prefer focused files with one responsibility.
- Add regression coverage for bug fixes.
- Keep accessibility identifiers stable for UI-testable controls.

Detailed coding standards: `./CODING_GUIDELINES.md`

## Build Schemes

| Scheme | Config | Bundle ID | Use |
|--------|--------|-----------|-----|
| `crispyvibes` | Debug/Release | `com.crispyvibe.app` | Main app + tests |
| `crispyvibes-local` | DebugLocal/ReleaseLocal | `com.crispyvibe.app.local` | Separate instance for testing |
| `crispyvibes-no-tests` | CrispyVibesNoTests | `com.crispyvibe.app.dev` | Fast build without test targets |

## Local Build Notes

- Local builds require the generated Ghostty artifacts from `./projects/crispyvibes/scripts/setup-ghostty.sh`.
- Local builds also require Rust/Cargo because Xcode compiles the bundled path-search helper from `projects/crispyvibes/rust/crispyvibes-path-search`.
- If Xcode fails with `cargo is required to build the bundled path-search helper`, install Rust/Cargo locally and rebuild.
