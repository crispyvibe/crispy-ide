# Testing Strategy

Crispy's tests are organized into five layers by intent, each targeting a different scope of verification. Tests are wired into three Xcode test targets: `CrispyVibesUnitTests` (unit + property), `CrispyVibesIntegrationTests` (behavioral + integration), and `CrispyVibesUITests` (UI).

## Test Structure

| Layer | Directory | Scope |
|---|---|---|
| Unit | `tests/unit/Models/`, `Features/`, `App/`, `Data/`, `Shared/`, `Property/`, `Support/` | Isolated logic for individual types |
| Behavioral | `tests/behavioral/Features/VibeSpace/`, `Features/Terminal/`, `Features/Editor/`, `App/AppShell/` | Multi-component flows without UI |
| Integration | `tests/integration/Data/Persistence/` | Cross-component persistence round-trips and performance |
| Property | `tests/unit/Property/` | Randomized invariant checking over many iterations |
| UI | `tests/ui/` | End-to-end flows against the running app via XCUITest |

## Unit Tests

Unit tests live under `tests/unit/` in the following subdirectories: `Models/`, `Features/`, `App/`, `Data/`, `Shared/`, `Property/`, `Support/`.

### Models (`tests/unit/Models/`)
Tests for pure data types and domain logic. Covers:
- `VibeSpaceConfigFile` and `ProjectConfigFile` JSON encode/decode round-trips.
- `AppStateFile` behavior: touch-to-front ordering, deduplication, max count enforcement, pruning of non-existent IDs, preservation of sidebar width and disclaimer flag across pruning.
- `VibeSpaceState` initialization: deduplication of project URLs, tracking of unresolved paths, focused project assignment, color tag assignment.
- Config round-trip fidelity: vibespace config → `VibeSpaceState` → config preserves focused project, color tags, startup settings, and shell preferences.
- Board interaction controller, hit testing, cursor regions, and spatial navigation.
- Terminal session restorer logic (preset vs. ad-hoc restore actions, missing preset recreation).
- App update service version comparison and manifest decoding.
- Split pane layout normalization.
- Source control settings normalization (deduplication, clamping, sorting of ignored directory names).

### View Models (`tests/unit/Features/`)
Tests for `@MainActor` view model classes. Covers:
- `TerminalViewModel`: tab creation/closure, Combine `objectWillChange` publish counts, session and activity state cleanup on close, tab restoration from persisted entries, diagnostics, escaping, and execution flows.
- `FolderExplorerViewModel`: root folder loading, worker status transitions, file item visibility (hidden vs. git-ignored vs. visible), drop planning.
- `ContentViewerStore`: file preview routing, tab management, memory lifecycle.
- `MarkdownViewModel`: document type detection, file URL binding.
- `VibeSpaceSourceControlViewModel`: repository scanning, settings propagation.
- `ProjectSessionState`: terminal persistence round-trips through the session layer.
- `PaneWorkerExecutor`: file read/write operations, git operations via worker requests.
- View composition smoke tests: instantiate SwiftUI views with real dependencies to catch compile-time and init-time regressions.
- Memory lifecycle tests for terminal and content viewer to verify cleanup on deallocation.

### Services (`tests/unit/App/`)
Tests for standalone service classes:
- `DiagnosticsTests`: diagnostic output formatting and content verification.
- `TerminalPasteTargetingTests`: paste target resolution logic.
- `GitHeadWatcherTests`: HEAD ref file monitoring.
- `TextProcessorServiceTests`: text transformation and CLI preset catalog behavior.

### Isolation Approach
Each test class creates its own `AppContainer` via `AppContainer.makeDefault()` and its own temp directory via `makeTempDirectory(prefix:)`. The container provides factory methods for all major types (`makeVibeSpaceState`, `makeTerminalViewModel`, `makeFolderExplorerViewModel`, `makeContentViewerStore`, `makePaneWorker`). Teardown removes the temp directory and nils the container. Tests that touch `UserDefaults` use isolated suites with `UserDefaults(suiteName:)` and clean up via `removePersistentDomain`.

## Behavioral Tests

Behavioral tests live under `tests/behavioral/` and exercise multi-component flows without launching the UI. They use the same `AppContainer.makeDefault()` + temp directory pattern as unit tests.

### VibeSpace (`tests/behavioral/Features/VibeSpace/`)
- Add and remove projects flow: verifies project count changes correctly through add/remove operations.
- Config and layout round-trip: creates a vibespace with existing and missing project directories, sets color tags and focused project, serializes to config, restores from config, and verifies all state survives. Then sets layout properties (rail position, rail size, pane layout) and verifies they persist and reload correctly.
- Git workflow: initializes a local repo with a bare remote, stages 12 randomized files via `PaneWorkerExecutor`, commits, pushes, switches branches, and verifies commit history and per-file history through the worker API.
- Explorer behavioral property: initializes a git repo with hidden directories, git-ignored directories, and visible directories, then verifies the `FolderExplorerViewModel` correctly marks each entry's `isHidden` and `isGitIgnored` flags.

### Terminal (`tests/behavioral/Features/Terminal/`)
- Terminal persistence round-trip: creates a `ProjectSession` with full dependency wiring (persistence store, layout store, terminal dependencies with isolated `UserDefaults`), creates a user tab, waits for debounced persistence, verifies the session was saved, then creates a new `ProjectSession` from the same root and verifies tabs restore.

### Editor (`tests/behavioral/Features/Editor/`)
- Explorer selection routes to markdown preview: creates a `ProjectSession`, wires `onFileOpenRequested` to a `ContentViewerStore`, selects a markdown file in the explorer, and verifies the markdown view model receives the correct file URL and document type.
- Open request cleared after consumption: verifies that `folderExplorerViewModel.openRequest` is nil after the Combine sink consumes it.

### App Shell (`tests/behavioral/App/AppShell/`)
- VibeSpace create and load round-trip: creates an `AppPersistenceDataStore` with a temp directory, saves a vibespace config through `VibeSpaceManagementService`, touches recent, then verifies `recentVibeSpaceIDs` returns the correct ID and `loadVibeSpace` returns the config with `trusted: true`.

## Integration Tests

Integration tests live under `tests/integration/Data/Persistence/` and verify cross-component workflows with real file I/O.

### Persistence Round-Trips (`VibeSpacePersistenceIntegrationTests`)
- Worker editor flow: creates a vibespace, writes a markdown file via `PaneWorkerExecutor`, reads it back, verifies content matches, confirms `MarkdownViewModel.isSupportedMarkdownFile` returns true, and reconciles project availability.
- VibeSpace config hydration performance: encodes/decodes 4 vibespaces × 4 projects each, measures clock time via `XCTClockMetric`.
- Terminal tab switch latency performance: creates 6 tabs, cycles through all tabs 120 times, measures clock time.
- VibeSpace steady-state memory performance: hydrates 5 vibespaces × 5 projects in an `autoreleasepool`, measures both `XCTMemoryMetric` and `XCTClockMetric`.

## Property Tests

Property-based tests live under `tests/unit/Property/` and use randomized inputs over many iterations to verify invariants.

### VibeSpace State Properties (`VibeSpaceStatePropertyTests`)
- Snapshot round-trip (75 iterations): randomizes existing/missing project counts with duplicates, creates a vibespace, serializes to config, restores, and asserts project path sets and unresolved path sets are equal.
- Shortcut uniqueness (120 iterations): randomly assigns shortcut slots to 6 projects and asserts all assigned shortcuts remain unique and within 1–9.
- Normalized path idempotency (220 iterations): generates randomized path segments with escape characters, normalizes twice, and asserts the result is stable and contains no escaped slashes.
- Effective terminal shell resolution (200 iterations): randomizes app default, vibespace default, and per-project override, then asserts the resolved shell follows the precedence chain (vibespace default → app default).

### Layout Persistence Properties (`LayoutPersistencePropertyTests`)
- Pane layout round-trip idempotency (80 iterations): generates random pane layout values (including out-of-range), sets them, reads back, asserts the normalized result matches, then sets again and asserts no change.

### App Update and Walkthrough Properties
- Version comparator antisymmetry (320 iterations): randomized version strings, asserts `compare(a, b)` is the inverse of `compare(b, a)`.
- Automatic update schedule (260 iterations): randomizes check-enabled flag, interval, and elapsed time, asserts the schedule decision matches the expected logic.
- Manifest decoding (180 iterations): randomizes JSON key aliases, whitespace, and optional fields, asserts trimming and defaults are applied correctly.
- Manifest blank build defaults (120 iterations): asserts blank or missing build fields default to `"0"`.
- Feature walkthrough UI test mode (80 iterations): asserts completion is persisted to a `.ui-test` suffixed key when UI test mode is active.

## UI Tests

UI tests live under `tests/ui/` and run against the full `Crispy.app` (or `CrispyLocal.app`) via XCUITest. They extend `CrispyVibesUIBaseTestCase`, which captures a screenshot on failure or when `CRISPYVIBES_UI_TEST_CAPTURE_SCREENSHOTS=1` is set.

### Environment Variable Overrides
The app is launched with environment variables that control test behavior:
- `CRISPYVIBES_UI_TEST_MODE=1` — enables test mode in the app.
- `CRISPYVIBES_UI_TEST_RESET_STATE=1` — resets persisted state before the test.
- `CRISPYVIBES_UI_TEST_VIBESPACE_CATALOG` — JSON string containing a fixture vibespace catalog that the app hydrates on launch instead of loading from disk.
- `CRISPYVIBES_UI_TEST_APPEARANCE=dark` — forces dark mode.
- `CRISPYVIBES_UI_TEST_START_IN_VIBESPACE=1` — skips the welcome screen and opens directly into a vibespace.
- `CRISPYVIBES_UI_TEST_DISABLE_AUTO_WALKTHROUGH=1` — disables automatic feature walkthroughs.
- `CRISPYVIBES_UI_TEST_RESET_WALKTHROUGH=1` — resets walkthrough completion state.

### Fixture Injection
`makeFixture(projectCount:)` creates a temp directory tree with project folders containing sample files (markdown, Swift, JavaScript, SQL, R, PNG, SVG). It builds a JSON vibespace catalog string with a `VibeSpaceConfigFile`-shaped dictionary, project color tags, and source control settings. This catalog is passed via the `CRISPYVIBES_UI_TEST_VIBESPACE_CATALOG` environment variable.

`makeApplication(fixture:)` constructs an `XCUIApplication` with all required launch arguments and environment variables, and ensures any previously running instance of the app is terminated (including force-kill with `SIGKILL` on the process group).

### Test Coverage
UI test files cover:
- VibeSpace lifecycle: verifies per-vibespace directory creation on disk, `vibespace.json` contains version 2, per-project config files exist in the `projects/` subdirectory.
- VibeSpace navigation and multi-project switching.
- VibeSpace integrity verification.
- Vibe space creation flows.
- Terminal interaction, rename, and board interaction.
- Terminal rail hydration.
- Editor workflows.
- Chrome and settings UI.

## Test Support

Shared test helpers live in `tests/unit/Support/TestSupport.swift`:

- `makeTempDirectory(prefix:)` — creates a uniquely named temp directory under `FileManager.temporaryDirectory`. Every test class that needs file I/O calls this in `setUp` and removes it in `tearDown`.
- `AppContainer.makeDefault()` — each test creates its own container instance, providing isolated factory methods for all major types. The container is set to nil in teardown.
- `waitForCondition(timeout:pollInterval:condition:)` — async polling helper for waiting on asynchronous state changes in `@MainActor` tests.
- `decodeJSON<T>(_:)` — convenience wrapper for decoding JSON strings in assertions.
- `captureUserDefaultsSnapshot` / `restoreUserDefaultsSnapshot` / `withUserDefaultsSnapshot` — snapshot and restore `UserDefaults` keys to prevent test pollution.
- `loadRepositoryInfoPlist()` — resolves the app's Info.plist from either the built product bundle or the repository file tree.
- `runProcess(executable:arguments:workingDirectory:)` — synchronous process runner used by behavioral tests that invoke git.
- `gitAvailable()` — checks whether git is available; tests that require git use `XCTSkip` when it is not.

### Teardown Pattern
Every test class follows the same teardown pattern:
1. Remove the temp directory if it exists (`try? FileManager.default.removeItem(at: tempRoot)`).
2. Nil out the `AppContainer` and any view models to release retained state.
3. Tests using isolated `UserDefaults` suites call `removePersistentDomain(forName:)`.

### Structure Validation
`UnitSuiteStructureTests` verifies that the `unit/` and `behavioral/` directories exist on disk, acting as a canary that the test folder structure has not been accidentally broken.
