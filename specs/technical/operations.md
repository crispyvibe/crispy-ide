# Operational Notes

- Explorer loading is recursive; very large directories may impact responsiveness.
- Markdown runtime assets are bundled in app resources and must ship with the app.
- Text services appear in macOS Settings after the app is launched at least once.
- Layout state is stored per-vibespace in `layout.json` within `~/Library/Application Support/<AppName>/vibespaces/<uuid>/`.
- App icon is provided from `crispyvibes/Resources/Assets.xcassets/AppIcon.appiconset` (`CFBundleIconName = AppIcon`).
- Runtime diagnostics, retention model, and diagnostics export behavior are documented in `docs/technical/diagnostics.md`.
- If package resolution becomes inconsistent, reset package caches in Xcode and rebuild.
