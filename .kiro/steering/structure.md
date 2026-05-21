# Project Structure

## Repository Layout

```
crispyvibes-ide/                       ← monorepo root
  .kiro/steering/                ← Kiro CLI steering docs (this folder)
  projects/crispyvibes/                ← main macOS app
    crispyvibes.xcodeproj/
    crispyvibes/
      App/                       ← app entry, delegate, diagnostics, updates, AppContainer
      ContentView.swift          ← root app shell
      Protocols/                 ← shared protocol definitions
      Data/
        Persistence/             ← workspace, layout, app-state persistence (JSON + HMAC)
        Services/                ← image scanning, raster persistence
      Features/
        ACP/                     ← Agent Conversation Protocol
        ContentViewer/           ← file preview/edit tab management
        Editor/                  ← markdown/code/html editing
        Home/                    ← dashboard, welcome, walkthrough, shelf
        Local/                   ← local project session implementation
        Remote/                  ← SSH, SFTP, remote projects
        Settings/                ← app and workspace settings UI + auth
        Shared/                  ← cross-feature shared views
        Terminal/                ← terminal sessions, board, presets
        VibeCast/                ← VibeCast feature
        Workspace/               ← explorer, canvas, settings, pane workers, file watchers
      Models/                    ← app data structures and state types
      Shared/                    ← shared components and support types
      Themes/                    ← theme palette, syntax themes, resolver
      Resources/                 ← runtime assets, icons, GhosttyRuntime, MarkdownRuntime
  projects/crispyvibes/tests/          ← test targets
    unit/                        ← unit tests
    behavioral/                  ← behavioral tests
    integration/                 ← integration tests
    property/                    ← property-based tests
    ui/                          ← UI tests (CrispyVibesUITests)
  specs/
    technical/                   ← architecture, stack, coding conventions
    features/
      CONVENTION.md              ← feature doc convention and numbering
      INDEX.md                   ← feature registry
      {domain}/{feature}/        ← feature docs (spec, technical-design, threat-model, usage-guide)
  docs/                          ← root documentation
  scripts/                       ← dev setup and build scripts
```

## Feature Organization

Features are organized as vertical slices under `Features/`. Each feature folder contains its own Views, ViewModels, and Services:

```
Features/{FeatureName}/
  Views/           ← SwiftUI views
  ViewModels/      ← ObservableObject view models
  Services/        ← feature-scoped services
  Models/          ← feature-scoped types (if needed)
```

## Spec Organization

Feature docs follow a 4-document convention per feature, nested under domain folders:

```
specs/features/{domain}/{feature-name}/
  spec.md              ← requirements and scenarios (F{NNN}-R{NN}, F{NNN}-S{NN})
  technical-design.md  ← architecture, data flow, API contracts
  threat-model.md      ← attack surfaces, mitigations (F{NNN}-T{NN})
  usage-guide.md       ← end-user workflows
```

## Key Entry Points

- `App/CrispyVibesApp.swift` — app entry point
- `App/AppContainer.swift` — composition root (dependency injection)
- `ContentView.swift` — root app shell and workspace layout
- `Protocols/` — shared protocol definitions used across features

## Required Reading

Before working on any feature, consult:
- `specs/technical/architecture.md` — app architecture and patterns
- `specs/technical/coding-conventions.md` — coding rules and examples
- `specs/features/CONVENTION.md` — feature doc structure and ID formats
