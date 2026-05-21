# Office Document Preview — Technical Design

## Overview

Integrates macOS Quick Look (`QLPreviewView`) into the Content Viewer to render Office documents (Word, PowerPoint, Excel) as read-only previews within editor tabs.

## Architecture

```
FileExplorer / Shelf
       │
       ▼
ContentViewer (pluggable registry, F006-R07)
       │
       ├── .md  → MarkdownPlugin (WKWebView)
       ├── .pdf → PDFPlugin (PDFKit)
       ├── .swift, .ts, ... → CodeEditorPlugin
       └── .docx, .pptx, .xlsx, ... → OfficeDocumentPlugin (QLPreviewView)
```

### New Components

| Component | Type | Location |
|-----------|------|----------|
| `OfficeDocumentPlugin` | Plugin registration (conforms to editor plugin protocol) | `Features/ContentViewer/Services/` |
| `OfficeDocumentPreviewView` | `NSViewRepresentable` | `Features/ContentViewer/Views/` |
| `OfficeDocumentPreviewViewModel` | `ObservableObject` | `Features/ContentViewer/ViewModels/` |

## Data Flow

1. User opens a file → Content Viewer receives the file URL and extension.
2. Pluggable registry matches the extension against registered plugins (per F006-R07).
3. `OfficeDocumentPlugin` claims Office extensions (`.docx`, `.doc`, `.pptx`, `.ppt`, `.xlsx`, `.xls`).
4. Plugin instantiates `OfficeDocumentPreviewView` with the file URL.
5. `OfficeDocumentPreviewView` wraps a `QLPreviewView` via `NSViewRepresentable`.
6. `QLPreviewView` loads and renders the document natively.
7. On failure, the view model sets an error state → fallback UI is shown.

## API / Command Contracts

### OfficeDocumentPreviewView

```swift
struct OfficeDocumentPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView { ... }
    func updateNSView(_ nsView: QLPreviewView, context: Context) { ... }
}
```

### OfficeDocumentPreviewViewModel

```swift
@MainActor
final class OfficeDocumentPreviewViewModel: ObservableObject {
    @Published private(set) var state: PreviewState // .loading | .rendered | .error(String)
    let fileURL: URL

    init(fileURL: URL) { ... }
    func load() { ... }
    func openInExternalApp() { ... }
}
```

### Plugin Registration

Register the Office document plugin with the Content Viewer's pluggable registry at app startup:

```swift
registry.register(
    plugin: OfficeDocumentPlugin(),
    for: [.docx, .doc, .pptx, .ppt, .xlsx, .xls]
)
```

No changes to a central view-body switch are needed (per F006-S19).

## State Management

- `PreviewState` enum: `.loading`, `.rendered`, `.error(String)`
- State lives in `OfficeDocumentPreviewViewModel`, observed by the view.
- No global state changes — self-contained within the tab.

## Dependencies (frameworks, libraries)

- `QuickLookUI` (system framework) — provides `QLPreviewView`
- No third-party dependencies

## Platform Considerations

- `QLPreviewView` is AppKit-only → requires `NSViewRepresentable` bridge.
- Available on macOS 10.6+; no minimum OS concern given macOS 26+ target.
- Quick Look renders in-process; no XPC or network calls.

## Performance Constraints

- Quick Look handles rendering asynchronously internally.
- For files > 50 MB, show a loading indicator (QL may take several seconds).
- Memory: QL manages its own rendering buffers; releasing the view frees resources.

### Cleanup on Tab Close

`OfficeDocumentPreviewViewModel` implements `shutdown()` to:
- Set `QLPreviewView.previewItem = nil` to release rendering buffers.
- Cancel any in-flight loading task.
- Nil the view reference to allow deallocation.

This follows the project convention for types with long-lived resources.

## Migration / Rollout Notes

- No data migration required.
- Feature is additive — no changes to existing preview types.
- Can be feature-flagged by gating the plugin registration.

## Behavioral Inheritance

Because the plugin registers through F006-R07, **all tab lifecycle behavior is inherited from the Content Viewer with no additional implementation**:

- Tab open/close/activate routes through `EditorGroupStore`.
- Preview vs persistent tab handling routes through `previewFile(at:)` / `openFileInTab(at:)`.
- Detached windows route through the existing `MarkdownViewModel` factory pattern.
- Session snapshot/restore uses `EditorPaneSnapshot.openFiles` (a `FileDocumentReference` list — Office docs are file references like any other).
- File rename retargeting uses `retargetFileSystemLocation(from:to:)` at the `ContentViewerStore` level.
- External file change reload routes through the existing file watcher.

The plugin's responsibility is **only** to render the document content. Tab state, persistence, and lifecycle are handled by the host. Any divergence from F006 contracts is a bug.
