> This file references the legacy docs/features/ structure. The canonical feature specs are now in specs/features/.

# Source Coverage Map (Behavior Documentation)

This map records which behavior category covers each source file.

## App Shell
- `crispyvibes/CrispyVibesApp.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/AppDelegate.swift` -> `docs/features/app-shell/feature.md`, `docs/features/text-services/feature.md`
- `crispyvibes/Info.plist` -> `docs/features/app-shell/feature.md`, `docs/features/text-services/feature.md`
- `crispyvibes/Resources/Assets.xcassets/AppIcon.appiconset/*` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Resources/CrispyVibes.icns` -> `docs/features/app-shell/feature.md`

## Models
- `crispyvibes/Models/AppPreferences.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Models/ProjectColorTag.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Models/VibeSpaceDisplayTypes.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Models/VibeSpaceStartupSettings.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Models/FileItem.swift` -> `docs/features/sidebar/folder-explorer/feature.md`
- `crispyvibes/Models/TerminalTab.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Models/VibeSpaceState.swift` -> `docs/features/app-shell/feature.md`

## Project Composition
- `crispyvibes/ContentView.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Features/Settings/Views/AppSettingsSheetView.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Features/VibeSpace/ViewModels/Explorer/ProjectSession.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Features/VibeSpace/Views/Explorer/FocusedProjectView.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Shared/Components/NativeSplitView.swift` -> `docs/features/app-shell/feature.md`
- `crispyvibes/Features/Home/Views/StackedProjectCardView.swift` -> `docs/features/app-shell/feature.md`, `docs/features/terminal/feature.md`

## Explorer + Git
- `crispyvibes/Features/VibeSpace/ViewModels/Explorer/FolderExplorerViewModel.swift` -> `docs/features/sidebar/feature.md`, `docs/features/sidebar/folder-explorer/feature.md`, `docs/features/sidebar/git-explorer/feature.md`
- `crispyvibes/Features/VibeSpace/Views/Explorer/FolderExplorerView.swift` -> `docs/features/sidebar/feature.md`, `docs/features/sidebar/folder-explorer/feature.md`, `docs/features/sidebar/git-explorer/feature.md`

## Editor + Preview
- `crispyvibes/Features/Editor/ViewModels/MarkdownViewModel.swift` -> `docs/features/editor/shared/feature.md`, `docs/features/editor/markdown/feature.md`, `docs/features/editor/html/feature.md`, `docs/features/editor/rich-text-shared/feature.md`, `docs/features/editor/code/feature.md`, `docs/features/editor/image/feature.md`, `docs/features/editor/pdf/feature.md`
- `crispyvibes/Features/Editor/Views/MarkdownEditorView.swift` -> `docs/features/editor/shared/feature.md`, `docs/features/editor/markdown/feature.md`, `docs/features/editor/html/feature.md`, `docs/features/editor/rich-text-shared/feature.md`, `docs/features/editor/code/feature.md`, `docs/features/editor/image/feature.md`, `docs/features/editor/pdf/feature.md`
- `crispyvibes/Resources/MarkdownRuntime/editor.html` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/html/feature.md`, `docs/features/editor/rich-text-shared/feature.md`
- `crispyvibes/Resources/MarkdownRuntime/github-markdown.min.css` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/rich-text-shared/feature.md` (visual styling behavior context)
- `crispyvibes/Resources/MarkdownRuntime/highlight-github-dark.min.css` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/rich-text-shared/feature.md` (syntax highlight styling context)
- `crispyvibes/Resources/MarkdownRuntime/highlight.min.js` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/rich-text-shared/feature.md` (syntax highlight runtime context)
- `crispyvibes/Resources/MarkdownRuntime/marked.umd.js` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/rich-text-shared/feature.md` (markdown render runtime context)
- `crispyvibes/Resources/MarkdownRuntime/turndown.js` -> `docs/features/editor/markdown/feature.md`, `docs/features/editor/rich-text-shared/feature.md` (HTML-to-markdown sync context)

## Browser
- `crispyvibes/Features/VibeSpace/Services/Browser/*` -> `docs/features/browser/feature.md`
- `crispyvibes/Features/VibeSpace/Canvas/State/ContentViewTerminalSpotlightBrowser.swift` -> `docs/features/browser/feature.md`, `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Canvas/Views/ContentViewTerminalLinkPreview.swift` -> `docs/features/browser/feature.md`, `docs/features/terminal/feature.md`, `docs/features/terminal-board-dock/feature.md`

## Terminal
- `crispyvibes/Features/Terminal/ViewModels/TerminalViewModel.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/Terminal/Views/TerminalView.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/Terminal/Views/TerminalSessionHostView.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/Terminal/Services/TerminalSession.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/Terminal/Support/TerminalInteractiveTargetDetector.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/Terminal/Support/VibeSpaceShortcutProvider.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyView.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyViewLifecycle.swift` -> `docs/features/terminal/feature.md`, `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardStore.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalCreateSheet.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Models/VibeSpaceTerminalBoardLayout.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/BrowserBoardTileView.swift` -> `docs/features/browser/feature.md`, `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/DockPinnedFileView.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/DockPreviewBridge.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/DockPreviewPanel.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardDockingOverlays.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardInteractionDecorations.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardMetrics.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardLayoutSync.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardStoreSync.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardStoreSyncSupport.swift` -> `docs/features/terminal-board-dock/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardStandaloneRegistry.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardViewSupport.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardTileCard.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyViewTileCards.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyViewTileSupport.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyViewBoardChrome.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalOnlyViewContent.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceDirectoryCandidate.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/VibeSpaceTerminalBoardStoreInteractions.swift` -> `docs/features/terminal/feature.md`
- `crispyvibes/Features/VibeSpace/Views/TerminalBoard/BoardSpatialNavigation.swift` -> `docs/features/terminal/feature.md`

## Persistence
- `crispyvibes/Data/Persistence/LayoutPersistenceService.swift` -> `docs/features/app-shell/feature.md`

## Worker + Services
- `crispyvibes/Features/VibeSpace/Services/PaneWorker/PaneWorkerInfrastructure.swift` -> `docs/features/worker/feature.md`
- `crispyvibes/Features/Editor/Services/TextProcessorService.swift` -> `docs/features/text-services/feature.md`
- `crispyvibes/Resources/THIRD_PARTY_NOTICES.md` -> reference/legal only (non-behavioral)

## Non-Behavioral/Reference Files
- No additional behavior-bearing source files remain outside the mappings above.
