# Crispy

A native macOS terminal-first workspace IDE built with Swift and SwiftUI.

[crispyvibe.com](https://crispyvibe.com)

## Quick Start

1. Run the dev setup script (installs Xcode CLI tools, Homebrew, Zig, builds GhosttyKit):

    ```bash
    ./scripts/setup-dev.sh
    ```

2. Open `projects/crispyvibes/crispyvibes.xcodeproj` in Xcode.

3. Select the `crispyvibes` scheme (build product: `Crispy.app`).

4. Build and run (`Cmd+R`).

## Repository Structure

```
projects/crispyvibes/          ← macOS app (Swift, SwiftUI, AppKit)
projects/crispyvibes/tests/    ← unit, behavioral, integration, property, ui tests
projects/showcase-vibespaces/  ← test fixture vibespaces
specs/                   ← All documentation
  features/              ← 35 features × 4 docs (spec, technical-design, threat-model, usage-guide)
  technical/             ← Cross-cutting architecture docs
  planning/              ← Active plans and roadmaps
  security/              ← Threat models
  learnings/             ← Investigation records
  adr/                   ← Architecture decision records
  nfr/                   ← Non-functional requirements
scripts/                 ← Dev setup, build, release scripts
```

## Build Schemes

| Scheme | Config | Bundle ID | Use |
|--------|--------|-----------|-----|
| `crispyvibes` | Debug / Release | `com.crispyvibe.app` | Main app + test targets |
| `crispyvibes-local` | DebugLocal / ReleaseLocal | `com.crispyvibe.app.local` | Separate instance for testing alongside the main app |
| `crispyvibes-no-tests` | CrispyVibesNoTests | `com.crispyvibe.app.dev` | Fast build without test targets |

Use `crispyvibes-local` during development — it runs as `CrispyLocal.app` with its own bundle ID, app-support directory, and keychain services, so it won't interfere with the production `Crispy.app`. Never kill the main `Crispy.app` process during testing.

## Commands

```bash
# Create a ready-to-build worktree
./scripts/create-worktree.sh ../crispyvibes-ide-feature feature/my-change

# Build (local scheme for testing)
xcodebuild build -project projects/crispyvibes/crispyvibes.xcodeproj \
  -scheme crispyvibes-local -configuration DebugLocal -destination 'platform=macOS'

# Run tests
xcodebuild test -project projects/crispyvibes/crispyvibes.xcodeproj \
  -scheme crispyvibes -destination 'platform=macOS' -only-testing:CrispyVibesUnitTests

# Launch local build
open ~/Library/Developer/Xcode/DerivedData/crispyvibes-*/Build/Products/DebugLocal/CrispyLocal.app
```

## Worktrees

Use `./scripts/create-worktree.sh` instead of raw `git worktree add`. The script creates the worktree, installs the generated Ghostty framework/runtime from a shared cache, resolves Swift packages, and verifies the `crispyvibes-local` build by default.

Ghostty artifacts are cached outside individual worktrees at `~/Library/Caches/crispyvibes/ghostty-build` unless `CRISPYVIBES_GHOSTTY_CACHE_DIR` is set. Rust/Cargo is still a machine-level prerequisite because Xcode compiles the bundled helper binaries during app builds.

## Documentation

- Feature specs: [`specs/features/INDEX.md`](specs/features/INDEX.md)
- Doc convention: [`specs/features/CONVENTION.md`](specs/features/CONVENTION.md)
- Architecture: [`specs/technical/architecture.md`](specs/technical/architecture.md)
- Security: [`specs/security/THREAT_MODEL.md`](specs/security/THREAT_MODEL.md)

## License

Crispy is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
