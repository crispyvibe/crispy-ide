# Data and State Flow

This is the typical app-shell flow with VibeSpace + Project state.

1. App launches and `ContentView` restores vibespace from per-vibespace directory via `VibeSpaceManagementService`.
2. `VibeSpaceManagementService` reads `app-state.json` for recent vibespace IDs, loads `vibespaces/<uuid>/vibespace.json` for the most recent vibespace.
3. `VibeSpaceState` reconstructs project sessions from saved project paths. `ProjectSession` is behind a `ProjectProviding` protocol abstraction with `LocalProjectSession` and `RemoteProjectSession` implementations. The vibespace state stores `[AnyProjectSession]` (type-erased wrappers) instead of concrete `[ProjectSession]`.
4. `AnyProjectSession` (via `ProjectProviding`) restores:
   - Project pane layout from `LayoutPersistenceService` (per-vibespace `layout.json`).
   - Terminal tabs from `vibespaces/<uuid>/projects/<hash>.json` via `VibeSpaceManagementService`.
5. `ContentView` restores vibespace rail position and rail size from `LayoutPersistenceService` (per-vibespace `layout.json`).
6. User interactions update runtime state:
   - Project focus, vibespace metadata -> persisted to `vibespaces/<uuid>/vibespace.json` via `VibeSpaceManagementService`.
   - Per-project config (color tags, shortcuts, startup overrides, shell overrides) -> persisted to `vibespaces/<uuid>/projects/<hash>.json`.
   - Rail position and rail sizes -> persisted to per-vibespace `layout.json`.
   - Terminal tab changes -> persisted to `vibespaces/<uuid>/projects/<hash>.json`.

## Storage Structure

```
~/Library/Application Support/<AppName>/
├── app-state.json                    ← recentVibeSpaceIDs, sidebarWidth, hasAcceptedDisclaimer
├── vibespaces/
│   └── <uuid>/
│       ├── vibespace.json            ← vibespace config (HMAC-signed)
│       ├── layout.json               ← rail, canvas, board layout (unsigned)
│       ├── editor-session.json       ← editor split/pane state
│       ├── session.json              ← vibespace session URL slot
│       └── projects/
│           └── <sha256>.json         ← per-project config + terminal state (HMAC-signed)
└── vibespace-session-state/
    └── <uuid>.json                   ← per-vibespace runtime session snapshots
```

## AppPersistenceDataStore Internals

`AppPersistenceDataStore` is the low-level file I/O layer. It is a singleton (`AppPersistenceDataStore.shared`) but also accepts injected `FileManager` and `appDirectoryURL` for testing.

- Resolves the app support directory URL from system conventions and Info.plist overrides (`CrispyVibesAppSupportDirectoryName`, falling back to `CFBundleName`, then `"CrispyVibes"` as a legacy code fallback).
- Generates file URLs via `appFileURL(relativePath:isDirectory:)` relative to the app directory.
- Provides generic `load<T: Decodable>` and `save<T: Encodable>` methods using `JSONEncoder`/`JSONDecoder`.
- All file operations are serialized through an `NSLock`.
- Parent directories are created automatically on save via `createDirectory(withIntermediateDirectories: true)`.
- Supports `removeFile(at:)` and `removeDirectoryIfEmpty(_:)` for cleanup.
- Provides `resetAppStorage()` which deletes the entire app directory.
- Offers integrity-signed variants (`saveWithIntegrity` / `loadWithIntegrity`) that wrap payloads in an HMAC-SHA256 signed envelope (base64 payload + hex signature).

## VibeSpace Session State

`VibeSpaceSessionStateService` manages a separate directory (`vibespace-session-state/`) for runtime session snapshots. Each vibespace gets a `<UUID>.json` file containing `VibeSpaceSessionState`, which captures:
- Per-project terminal session state (entries and active directory)
- Vibe cast target tab ID
- Editor session state (split tree, pane snapshots, active pane, split ratios, viewer scope)

This is separate from vibespace config — configs define the baseline, session state captures the runtime delta.

### Editor Session State (`editor-session.json`)

Stored per-vibespace at `vibespaces/<UUID>/editor-session.json`:
- Split tree structure (recursive leaf/split nodes with UUIDs and orientations)
- Per-pane snapshots (open file paths, active file, terminal tab references)
- Active pane ID
- Split ratios keyed by node UUID
- Viewer scope

## State Ownership

- Recent vibespace list: `app-state.json` (runtime-only active vibespace ID per window)
- VibeSpace config + lifecycle: `VibeSpaceManagementService` → `VibeSpacePersistenceStore`
- Per-project config + terminal state: `VibeSpaceManagementService` → per-project files
- Layout persistence: `LayoutPersistenceService` → per-vibespace `layout.json`
- VibeSpace runtime model: `VibeSpaceState`
- Project runtime model: `AnyProjectSession` (via `ProjectProviding`)
- Explorer state: `FolderExplorerViewModel`
- Document/edit state: `MarkdownViewModel`
- Terminal tab/session state: `TerminalViewModel`
- Shelf state: `ShelfStore` → `shelf-state.json`

## File Integrity

- `vibespace.json` and `projects/<hash>.json` are HMAC-SHA256 signed with a Keychain-stored key (scoped per app variant: Crispy vs CrispyLocal).
- On load, signature is verified. Untrusted files load for display but block startup command execution.
- `layout.json` and `app-state.json` are unsigned (no executable content).
- Keychain access is lazy — key loaded only when first vibespace is opened, cached in memory for the session.

### Keychain Key Resolution

The signing key is a 256-bit symmetric key stored in the macOS Keychain under the service name resolved from the Info.plist key `CrispyVibesConfigSigningKeychainService` (defaulting to `com.crispyvibe.app.config-signing`) and account `vibespace-hmac-key`.

On load, `loadWithIntegrity` returns a `SignedLoadResult` containing both the decoded value and a `verified` boolean. If the signature does not match (e.g., the file was modified externally or the signing key changed), the config still loads but `verified` is `false`.

Key resolution order:
1. Attempt to read from the current keychain service (tries both data-protection and non-data-protection variants).
2. If not found, attempt to migrate from legacy keychain services.
3. If no key exists anywhere, generate a new 256-bit key and persist it.

The key is cached in memory after first resolution and can be invalidated via `invalidateSigningKeyCache()`.

## Pruning

`pruneOnLaunch()` is called at app startup and performs two cleanup passes:

1. **Invalid vibespace directory cleanup** (`pruneInvalidVibeSpaceDirectories`): Iterates all entries in the `vibespaces/` directory. Removes any entry whose name is not a valid UUID. Removes any UUID-named directory that does not contain a `vibespace.json` file.

2. **App state reconciliation**: Loads the current `AppStateFile`, filters `recentVibeSpaceIDs` to only those UUIDs that still have directories on disk, enforces the max recent count (20), and saves the pruned state back.

## Persistence Strategy

- Debounced writes: mutations set a dirty flag, 200ms debounce timer flushes to disk.
- Atomic writes: `Data.write(to:options:.atomic)` — write to temp file, rename on success.
- Crash safety: incomplete vibespace directories (missing `vibespace.json`) are pruned on launch.
- Shutdown flush: on `NSApplication.willTerminateNotification`, all dirty vibespaces flush immediately.
- Per-project writes: project config changes write only the affected `projects/<hash>.json`, not the entire vibespace.

## VibeSpace Config Schema (`vibespace.json`)

```
VibeSpaceConfigFile (Codable, HMAC-signed)
├── id: UUID
├── name: String
├── projectPaths: [String]                            — ordered, normalized
├── unresolvedProjectPaths: [String]?                 — paths that don't resolve to directories
├── focusedProjectPath: String?
├── startupSettings: VibeSpaceStartupSettings?
│   ├── startupTerminalCount: Int                     — clamped 1–8
│   ├── startupProfiles: [VibeSpaceTerminalStartupProfile]
│   │   ├── presetID: String?
│   │   └── command: String
│   └── focusTerminalOnProjectSwitch: Bool
├── defaultTerminalShell: TerminalShellPreference?
└── projectShortcuts: [String: Int]?                  — path → ⌘N shortcut index (1–9)
```

## Per-Project Config Schema (`projects/<sha256>.json`)

```
ProjectConfigFile (Codable, HMAC-signed)
├── projectPath: String                               — normalized, matches hash
├── colorTag: String?                                 — hex (#RRGGBB)
├── shortcutIndex: Int?                               — 1–9, unique across vibespace
├── startupOverride: VibeSpaceProjectStartupOverride?
├── terminalShellOverride: TerminalShellPreference?
├── terminalEntries: [TerminalSessionEntry]
│   ├── workingDirectoryPath: String
│   ├── customName: String?
│   ├── origin: TerminalOrigin (.preset | .adHoc)
│   └── tmuxSessionName: String?                      — persisted tmux session name for reattach (local unique id or remote stable SSH-derived name)
└── activeTerminalDirectory: String?
```

## Layout Schema (`layout.json`)

```
VibeSpaceRailLayoutState (Codable, unsigned)
├── railPositionRawValue: String                      — left/right/top/bottom
├── railSizes: AppRailSizeState
│   ├── leftWidth, rightWidth: Double
│   └── topHeight, bottomHeight: Double
├── canvasModeRawValue: String                        — detailed/terminalOnly
├── terminalOnlyLayoutOrientationRawValue: String     — vertical/horizontal
└── terminalBoardLayout: VibeSpaceTerminalBoardLayout
    ├── columns: [VibeSpaceTerminalBoardColumn]
    │   ├── id: UUID
    │   ├── widthWeight: Double
    │   └── tiles: [VibeSpaceTerminalBoardTile]
    │       ├── id, heightWeight, projectPath?, terminalTabID?
    │       ├── workingDirectoryPath: String
    │       └── isVibeCast: Bool
    ├── activeTileID: UUID?
    └── minimizedTiles: [VibeSpaceTerminalBoardTile]
```

## App State Schema (`app-state.json`)

`AppStateFile` contains:
- `recentVibeSpaceIDs` — ordered list of recently used vibespace UUIDs, most recent first. Capped at 20 entries. `touchVibeSpace` moves an ID to the front and deduplicates. `removeVibeSpace` removes an ID entirely.
- `sidebarWidth` — optional persisted sidebar width (Double), loaded on init with a minimum of 180pt.
- `hasAcceptedDisclaimer` — optional Boolean tracking whether the user has accepted the app disclaimer.

The `pruned(existingIDs:)` method filters the recent list to only IDs that still exist on disk, preserves `sidebarWidth` and `hasAcceptedDisclaimer`, and enforces the max count.

## Invariant Rules

The `VibeSpaceManagementService` enforces these on every mutation:

| Rule | Description |
|---|---|
| INV-001 | `startupTerminalCount` clamped to 1–8 |
| INV-002 | `startupProfiles.count` matches `startupTerminalCount` (pad/truncate) |
| INV-003 | All project paths normalized via `URL(fileURLWithPath:).standardizedFileURL.path` |
| INV-005 | `projectShortcuts` values are unique integers 1–9 |
| INV-009 | Removing a project deletes its `projects/<hash>.json` |
| INV-010 | VibeSpace name is non-empty after trimming whitespace |

## Project Color Persistence

- Project colors are stored in per-project config files (`projects/<hash>.json`) as hex tokens (`#RRGGBB`).
