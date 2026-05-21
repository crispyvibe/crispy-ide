# Stack and Project Layout

## Technology Stack

- Language: Swift 5
- UI: SwiftUI with AppKit bridges where needed
- Platform target: macOS 26+
- Terminal: Ghostty (GhosttyKit) as primary engine, SwiftTerm as fallback
- Rendering: `WKWebView` with bundled markdown runtime assets
- App identity: `Crispy` (`com.crispyvibe.app`)

## Project Layout

```text
crispyvibes/
  App/                          ← app entry, delegate, diagnostics, updates
  ContentView.swift             ← root app shell
  Protocols/                    ← protocol definitions (ProjectProviding, FolderExploring, GitExploring, TerminalProviding, CommandExecuting, FileContentProviding)
  Data/
    Persistence/                ← vibespace, layout, and app-state persistence
    Services/                   ← image scanning and raster persistence
    Repositories/               ← (reserved)
  Features/
    ACP/                        ← Agent Conversation Protocol feature
    ContentViewer/              ← file preview/edit tab management
    Editor/                     ← markdown/code/html editing
    Home/                       ← dashboard, welcome, walkthrough, shelf
    Local/                      ← local project session implementation
    Remote/                     ← remote project session implementation
    Settings/                   ← app and vibespace settings UI + auth
    Shared/                     ← cross-feature shared views
    Terminal/                   ← terminal sessions, board, presets
    VibeCast/                   ← VibeCast feature
    VibeSpace/                  ← explorer, canvas, settings, pane workers, file watchers
  Models/                       ← app data structures and state types
  Shared/                       ← shared components and support types
  Themes/                       ← theme palette, syntax themes, resolver
  Resources/                    ← runtime assets, icons, GhosttyRuntime, MarkdownRuntime
```

Key areas:

- `App/`: app entry point, delegate, diagnostics, update checking
- `Features/`: feature-scoped Views, ViewModels, and Services organized by capability
- `Data/`: persistence layer (vibespace management, layout, app state) and data services
- `Models/`: app data structures (vibespace state, terminal board layout, preferences)
- `Themes/`: centralized theme palette, syntax themes, and resolver
- `Resources/`: runtime assets (markdown scripts/styles, GhosttyRuntime, Seti icons)
