# CrispyVibes

A macOS Markdown editor built with SwiftUI.

-   Three-pane layout: explorer, editor/preview, terminal
-   File operations: create, rename, delete
-   Markdown rendering and autosave
-   System text services powered by `kiro-cli`

Full documentation:

-   [`../../docs/README.md`](../../docs/README.md)
-   [`../../docs/user/README.md`](../../docs/user/README.md)
-   [`../../docs/features/README.md`](../../docs/features/README.md)
-   [`../../docs/technical/README.md`](../../docs/technical/README.md)

Quick start:

1.  Install local build prerequisites:
    - `git`
    - `zig` (`brew install zig`)
    - Rust toolchain with `cargo` (`brew install rustup-init && rustup-init`, or install Rust another way that provides `cargo`)
2.  Run the repo bootstrap script if needed:
    - `./scripts/setup-dev.sh`
3.  Generate the local Ghostty artifacts if they are not already present:
    - `./projects/crispyvibes/scripts/setup-ghostty.sh`
4.  Open `crispyvibes.xcodeproj` in Xcode.
5.  Pick a scheme:
    - `crispyvibes` for the public app (`Crispy`)
    - `crispyvibes-local` for side-by-side local/dev install (`CrispyLocal`)
6.  Build and run (`Cmd+R`).
7.  Create a VibeSpace from the Dashboard and add project folders.

Worktree setup:

-   Use `./scripts/create-worktree.sh ../crispyvibes-ide-feature feature/my-change` from the repo root to create a ready-to-build worktree.
-   The script installs Ghostty artifacts into the new worktree, resolves Swift packages, and verifies the `crispyvibes-local` build by default.
-   Pass `--no-build` to skip the build verification step.

Ghostty setup notes:

-   The generated framework/runtime live at `projects/crispyvibes/vendor/GhosttyKit.xcframework` and `projects/crispyvibes/crispyvibes/Resources/GhosttyRuntime`.
-   Those paths are intentionally gitignored and must be generated locally.
-   The setup script pins Ghostty to a specific commit for reproducible builds and uses `~/Library/Caches/crispyvibes/ghostty-build` as the shared cache by default.
-   If you already have a Ghostty checkout, set `CRISPYVIBES_GHOSTTY_SOURCE_DIR=/path/to/ghostty` before running the script.

Rust helper setup notes:

-   The terminal inline path-search helper is built from `projects/crispyvibes/rust/crispyvibes-path-search`.
-   Xcode builds and bundles that helper automatically, but local developer machines must have `cargo` installed first.
-   If Xcode shows `cargo is required to build the bundled path-search helper`, install Rust/Cargo locally and rebuild.

App data locations:

-   `Crispy` uses `~/Library/Application Support/Crispy`
-   `CrispyLocal` uses `~/Library/Application Support/CrispyLocal`
-   Both can be installed and run on the same machine.

Test scaffolding:

-   `tests/unit`
-   `tests/integration`
-   `tests/ui`

Project showcase assets:

```bash
xcodebuild test \
  -project projects/crispyvibes/crispyvibes.xcodeproj \
  -scheme crispyvibes-local \
  -destination 'platform=macOS' \
  -only-testing:CrispyVibesUITests
```

Run this test to regenerate showcase artifacts, then sync outputs to `docs/demo-assets/`.
