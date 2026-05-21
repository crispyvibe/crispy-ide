# Localization Guidelines

All user-facing text in Crispy must go through the centralized string catalog. No raw strings in views or view models.

## Architecture

```
Localizable.xcstrings          ← source of truth for all translations
        ↑
AppStrings.swift               ← Swift access layer using String(localized:)
        ↑
Views / ViewModels             ← reference AppStrings only, never raw text
```

## Rules

1. **Never use raw string literals** for user-facing text in SwiftUI views or view models. Use `AppStrings.<Feature>.<element>` instead.
2. **All display text lives in `Localizable.xcstrings`** at `Resources/Localizable.xcstrings`. Each entry has a key and an English translation.
3. **`AppStrings.swift`** at `Shared/Support/AppStrings.swift` provides typed access via `String(localized:)`. Group entries by feature using nested enums.
4. **Key naming convention**: `{feature}.{context}.{element}` — e.g., `settings.experimental.tmux.title`.
5. **Accessibility identifiers are not localized** — they use dot-separated code identifiers, not display text.

## Adding a New String

1. Add the key + English value to `Localizable.xcstrings`:
   ```json
   "myFeature.myElement.title" : {
     "localizations" : {
       "en" : {
         "stringUnit" : {
           "state" : "translated",
           "value" : "My Title"
         }
       }
     }
   }
   ```

2. Add a static property in `AppStrings.swift` under the appropriate feature enum:
   ```swift
   enum MyFeature {
       static let title = String(localized: "myFeature.myElement.title")
   }
   ```

3. Reference it in your view:
   ```swift
   Text(AppStrings.MyFeature.title)
   ```

## What Counts as User-Facing Text

- Button labels, menu items, tab titles
- Headings, descriptions, placeholder text
- Error messages, alerts, confirmation dialogs
- Tooltip text, accessibility labels
- Settings category names and descriptions

## What Does NOT Need Localization

- Log messages and diagnostics
- Debug-only text
- Accessibility identifiers
- Code-level string keys (UserDefaults keys, notification names)
- File paths and URLs

## Existing Coverage

`AppStrings.swift` currently has ~200 entries across these feature groups:

| Enum | Area |
|---|---|
| `Common` | Shared action labels (Done, Cancel, Save, etc.) |
| `AppUpdate` | Update check UI |
| `Sidebar` | Navigation rail labels |
| `Explorer` | File tree actions and context menus |
| `Terminal` | Terminal chrome, presets, board |
| `Editor` | Editor actions and status |
| `Settings` | App settings categories and controls |
| `VibeSpaceSettings` | VibeSpace settings UI |
| `Walkthrough` | First-run walkthrough |
| `VibeSpace` | VibeSpace creation flow |
| `SourceControl` | Git sidebar |
