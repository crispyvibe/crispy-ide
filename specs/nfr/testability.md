# NFR: Testability

## Scope

Requirements for test infrastructure, coverage expectations, and test design across all components.

## Requirements

### TEST-1: Test Layers

All code MUST be testable at the appropriate layer:

| Layer | Scope | Speed | OS Resources |
|-------|-------|-------|-------------|
| Unit | Single function/module, no I/O | <10ms per test | None |
| Integration | Cross-module, real I/O (filesystem, processes) | <5s per test | Temp dirs, child processes |
| End-to-end | Full application, UI interaction | <30s per test | Window, WebView, PTY |

### TEST-2: Coverage Expectations

- Core logic crates MUST maintain ≥80% line coverage.
- Platform abstraction traits MUST have integration tests on each supported OS.
- Every spec scenario (F{NNN}-S{NN}) MUST have at least one automated test mapped to it.
- Bug fixes MUST include a regression test.

### TEST-3: Dependency Injection

- All external dependencies (filesystem, process spawning, network, OS services) MUST be injectable via traits.
- Production code MUST NOT use global singletons or static mutable state.
- Test doubles (mocks, fakes, stubs) MUST be constructible without OS resources for unit tests.

### TEST-4: Test Isolation

- Tests MUST NOT depend on machine-specific state (home directory contents, installed tools, network availability).
- Tests requiring OS resources MUST create and clean up their own fixtures (temp directories, child processes).
- Tests MUST be runnable in parallel — no shared mutable state between test cases.

### TEST-5: Frontend Testing

- Frontend logic (state management, IPC contracts) MUST have unit tests.
- UI interactions MUST be testable via stable `data-testid` identifiers (A11Y-6).
- End-to-end tests MUST use Tauri's test harness or equivalent WebDriver-based tooling.

### TEST-6: CI Requirements

- All tests MUST pass on every PR — no flaky test tolerance.
- Tests MUST run on all supported platforms (OS-7).
- Test results MUST report: pass/fail count, duration, coverage delta.
- Flaky tests MUST be quarantined and tracked as defects.

## Verification

- CI enforces coverage thresholds per crate.
- CI fails on any test that exceeds its layer's time budget.
- Quarterly audit of scenario-to-test traceability.
