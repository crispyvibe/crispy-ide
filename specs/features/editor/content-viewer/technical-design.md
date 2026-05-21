# Content Viewer — Technical Design

## Overview

The content viewer is the vibespace-level coordinator for all editor panes. It delegates file and tab operations to the active `EditorGroupStore` via the `SplitViewStore`. It manages tab lifecycle (preview, persistent, close), split pane layout, file type detection, session persistence, detached editor windows, and file system retargeting.

## Architecture

### Active Group Delegation

All file operations on `ContentViewerStore` (preview, open, close, git diff) forward to the active `EditorGroupStore` determined by `SplitViewStore.activeGroup`. Each pane owns its own `EditorGroupStore` and `MarkdownViewModel`.

### Tab Types

| Kind | Identifier Format |
|------|-------------------|
| File | `file:<normalized-path>` |
| VibeCast | `vibeCast` |
| Web Page | `web:<url>` |
| Terminal | `terminal:<projectID>:<tabID>` |

### Viewer Scope

Two modes control tab visibility in a pane's tab strip:

- **Focused Project** — filters file tabs to paths under the focused project root.
- **All Projects** — shows every tab regardless of project.

**Sidebar project expansion:** Expanding a collapsed project in the sidebar activates the project and ensures the explorer is loaded before expanding. All expansion state changes go through `setExpandedVibeSpaceSidebarProjectPaths` (not direct mutation).

Non-file tabs (VibeCast, web page, terminal) are always visible in both scopes.

### File Type Detection

Detection follows a strict priority order:

1. **Extension-based** — lowercased extension checked against known sets: markdown → python → JSON → R → PDF → HTML → image → plain text → code language extensions.
2. **UTType fallback** — `UTType(filenameExtension:)` conformance checked: `.pdf` → `.image` → `.html` → `.plainText` / `.text`.
3. **Unsupported** — if both fail, classified as unsupported. The editor attempts to read content; if successful, promoted to `plainText`.

Code language detection is a separate lookup: lowercased extension matched against `codeLanguageByExtension` for `CodeLanguageKind` syntax highlighting.

### File Size Limit

Text files larger than **6 MB** cannot be opened. Image and PDF files are not affected.

### Tab Icons

Resolved by file extension:

| Extension/Type | Icon |
|----------------|------|
| Image extensions | `photo` |
| `.pdf` | `doc.text.image` |
| `.md`, `.markdown`, `.html`, `.htm` | `doc.richtext` |
| Other files | `doc.text` |
| VibeCast | `antenna.radiowaves.left.and.right` |
| Web Page | `globe` |
| Terminal | `terminal` |

### Project Color Tags

File tabs display a project accent color resolved by matching the file path against registered project root paths. The longest (most specific) matching project root wins.

## Data Flow

### Tab Lifecycle

- **Preview** (`previewFile(at:)`) — loads file into `MarkdownViewModel` with `activeEditorTabID = nil`. "Preview" badge displayed. Previewing another file replaces the current preview. If the file is already a persistent tab, that tab is activated instead.
- **Persistent** (`openFileInTab(at:)`) — adds file to tab strip, sets as active. If already exists, activates it. Opening converts any existing preview into a persistent tab.
- **Close** — removes from tab strip, clears markup view mode. Falls back to nearest tab by index (clamped to last). If no tabs remain, document cleared. In split mode, closing the last tab in a pane auto-closes the pane.

### Git Integration

- `previewGitDiff` — loads unified diff via pane worker `.gitDiff` command (12-second timeout). Title: `<relativePath> (Changes)`. Empty diff falls back to markdown message with status code.
- `previewGitFileContent` — loads previous file version via `.gitFileContent` (12-second timeout). Title: `<relativePath> (<titleSuffix>)`.
- Both are read-only, rendered by `GitDiffPreview` (sections → files → hunks with color-coded addition/deletion/context rows).
- Opening any new file cancels in-flight git diff and file open tasks via unique request IDs.

### File System Retargeting

When a file or directory is renamed/moved, all open documents, tabs, editor tab strips, and markup view mode preferences are retargeted from old path to new path across all panes. Uses standardized file URLs with exact match and prefix-based child path remapping.

## State Management

### Split Pane Layout

The split layout is a binary tree of `SplitPaneNode`:

- **Leaf** — single pane identified by UUID.
- **Split** — two children with orientation and ratio.

Constraints:

- Maximum **4 panes** (`SplitPaneNode.maxPanes`).
- Split ratio defaults to **0.5**, clamped to **0.1–0.9**.
- Minimum pane size: **100 points** per side.

Operations:

| Operation | Behavior |
|-----------|----------|
| Split (H/V) | Replaces target leaf with split node; new pane becomes active. |
| Close pane | Collapses split node, promotes sibling. First remaining leaf becomes active if closed pane was active. |
| Toggle orientation | Flips parent split between horizontal and vertical. |
| Split with tab | Removes tab from active pane, splits, opens tab in new pane. If max panes reached, tab reopened in source. |
| Move tab | Removes tab from any pane, opens in target pane. |

One pane is always active (accent-colored top border). Clicking anywhere in a pane activates it.

### Session Persistence

`EditorSessionState` captures:

- **Split tree** — full binary tree serialized as `SplitNodeSnapshot` (leaf IDs, orientations, ratios).
- **Per-pane state** — open file paths, active file path, terminal tab references (project ID + tab ID), active terminal tab ID.
- **Active pane ID**.
- **Split ratios** — `[UUID string: Double]` map.
- **Viewer scope** — focused project or all projects.

Save triggers:

- On split view change — debounced 0.5-second delay.
- On view disappear — immediate.
- On vibespace switch — outgoing state saved before incoming restored.

Restore behavior: split tree rebuilt, editor groups recreated per leaf, files reopened in order. Missing files skipped. Terminal tabs restored by reference. Empty panes collapsed. If previously active pane gone, first available becomes active.

### Detached Editor Windows

- Keyed by normalized file path; reopening brings existing window to front.
- Each window gets its own `MarkdownViewModel` (factory-created).
- Default size: **980 × 680 pt**, minimum: **760 × 520 pt**.
- Style: titled, closable, miniaturizable, resizable.
- On close, entry removed from registry and observer cleaned up.

## API / Command Contracts

### Pane Worker Commands

| Command | Timeout | Purpose |
|---------|---------|---------|
| `.gitDiff` | 12 s | Fetch unified diff for a file |
| `.gitFileContent` | 12 s | Fetch previous version of a file |
| File write (autosave/manual) | 10 s | Persist text content to disk |

## Dependencies (frameworks, libraries)

- `SplitViewStore` — binary tree layout engine
- `EditorGroupStore` — per-pane tab and document management
- `MarkdownViewModel` — document rendering
- `PaneWorkerClient` — file I/O and git operations
- `PDFKit` — PDF rendering
- `WKWebView` — HTML/markdown rendering

## Platform Considerations

- `NativeSplitView` enforces `minPrimary=100` and `minSecondary=100`.
- Detached windows use standard macOS `NSWindow` style masks.
- Tab drag uses `NSItemProvider` with custom pasteboard type `com.crispyvibe.app.content-viewer-tab`.

### Content Area Drop Type Filtering

`ContentViewerTabDragSupport.contentAreaDropTypes(for:)` returns accepted drop types based on the active tab kind. When the active tab is a terminal, file URL types are excluded so that file drops fall through to the terminal's own drop handler. Non-terminal tabs accept both tab drags and file URLs.

### Detailed Tray Terminal Portability

The detailed bottom terminal tray is a source of terminal-session drags into the content viewer.

- The drag payload must resolve to a terminal tab reference (`projectID + tabID`), not to a copied terminal object.
- Center drops reuse the existing target pane and open or activate the corresponding `.terminal` tab.
- Edge drops reuse the existing split-zone behavior and create a new pane hosting the `.terminal` tab.
- Closing the content-viewer terminal tab removes only that presentation. The underlying `TerminalSession` stays owned by the project's `TerminalViewModel`.
- Ownership handoff remains the responsibility of the terminal host ownership coordinator; the content viewer never becomes the source of truth for terminal lifetime.

## Performance Constraints

- File size limit: 6 MB for text documents.
- Session save debounced at 0.5 seconds to avoid excessive writes.
- Autosave debounced at 0.45 seconds.
- Git operations have 12-second timeouts; stale responses discarded via request IDs.
