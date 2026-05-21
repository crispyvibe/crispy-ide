#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

GHOSTTY_REPO_URL="${CRISPYVIBES_GHOSTTY_REPO_URL:-https://github.com/manaflow-ai/ghostty.git}"
GHOSTTY_COMMIT="${CRISPYVIBES_GHOSTTY_COMMIT:-7dd589824d4c9bda8265355718800cccaf7189a0}"
DEFAULT_CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/Library/Caches}/crispyvibes/ghostty-build"
CACHE_ROOT="${CRISPYVIBES_GHOSTTY_CACHE_DIR:-$DEFAULT_CACHE_ROOT}"
SOURCE_OVERRIDE="${CRISPYVIBES_GHOSTTY_SOURCE_DIR:-}"

CHECKOUT_ROOT="$CACHE_ROOT/src"
ARTIFACT_ROOT="$CACHE_ROOT/artifacts/$GHOSTTY_COMMIT"
CHECKOUT_DIR="$CHECKOUT_ROOT/ghostty-$GHOSTTY_COMMIT"

PROJECT_FRAMEWORK_DIR="$PROJECT_ROOT/vendor/GhosttyKit.xcframework"
PROJECT_RUNTIME_ROOT="$PROJECT_ROOT/crispyvibes/Resources/GhosttyRuntime"
PROJECT_GHOSTTY_DIR="$PROJECT_RUNTIME_ROOT/ghostty"
PROJECT_TERMINFO_DIR="$PROJECT_RUNTIME_ROOT/terminfo"
PROJECT_STAMP_FILE="$PROJECT_RUNTIME_ROOT/.ghostty-build.json"

ARTIFACT_FRAMEWORK_DIR="$ARTIFACT_ROOT/GhosttyKit.xcframework"
ARTIFACT_GHOSTTY_DIR="$ARTIFACT_ROOT/ghostty"
ARTIFACT_TERMINFO_DIR="$ARTIFACT_ROOT/terminfo"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--force]

Build or install the pinned Ghostty artifacts required by CrispyVibes.

Environment overrides:
  CRISPYVIBES_GHOSTTY_SOURCE_DIR   Reuse an existing Ghostty checkout instead of cloning
  CRISPYVIBES_GHOSTTY_REPO_URL     Ghostty git remote to clone when no source dir is provided
  CRISPYVIBES_GHOSTTY_COMMIT       Pinned Ghostty commit to build
  CRISPYVIBES_GHOSTTY_CACHE_DIR    Cache directory for checkout and built artifacts
                             (default: $DEFAULT_CACHE_ROOT)
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: required command '$1' is not installed." >&2
        exit 1
    fi
}

artifact_cache_complete() {
    [[ -d "$ARTIFACT_FRAMEWORK_DIR" && -d "$ARTIFACT_GHOSTTY_DIR" && -d "$ARTIFACT_TERMINFO_DIR" ]]
}

patch_ghostty_checkout() {
    local checkout_dir="$1"
    local libtool_step="$checkout_dir/src/build/LibtoolStep.zig"

    if [[ ! -f "$libtool_step" ]]; then
        echo "Error: Ghostty build step not found at $libtool_step" >&2
        exit 1
    fi

    perl -0pi -e 's#//! A zig builder step that runs "libtool" against a list of libraries\n//! in order to create a single combined static library\.#//! A zig builder step that runs "zig ar" against a list of libraries\n//! in order to create a single combined static library\.#' "$libtool_step"
    perl -0pi -e 's#const run_step = RunStep\.create\(b, b\.fmt\("libtool \{s\}", \.\{opts\.name\}\)\);\n\s*run_step\.addArgs\(&\.\{ "libtool", "-static", "-o" \}\);#const run_step = RunStep.create(b, b.fmt("ar {s}", .{opts.name}));\n    run_step.addArgs(&.{ "zig", "ar", "qcLs" });#' "$libtool_step"
}

FORCE_REBUILD=0
while (($# > 0)); do
    case "$1" in
        --force)
            FORCE_REBUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

require_command rsync

if [[ "$FORCE_REBUILD" -eq 1 ]]; then
    rm -rf "$ARTIFACT_FRAMEWORK_DIR" "$ARTIFACT_GHOSTTY_DIR" "$ARTIFACT_TERMINFO_DIR"
fi

if ! artifact_cache_complete; then
    require_command git
    require_command zig
fi

mkdir -p "$CHECKOUT_ROOT" "$ARTIFACT_ROOT" "$PROJECT_ROOT/vendor" "$PROJECT_RUNTIME_ROOT"

prepare_checkout() {
    if [[ -n "$SOURCE_OVERRIDE" ]]; then
        if [[ ! -d "$SOURCE_OVERRIDE" ]]; then
            echo "Error: CRISPYVIBES_GHOSTTY_SOURCE_DIR does not exist: $SOURCE_OVERRIDE" >&2
            exit 1
        fi
        printf '%s\n' "$SOURCE_OVERRIDE"
        return
    fi

    if [[ ! -d "$CHECKOUT_DIR/.git" ]]; then
        echo "==> Cloning Ghostty source into cache..." >&2
        git clone --filter=blob:none "$GHOSTTY_REPO_URL" "$CHECKOUT_DIR" >&2
    fi

    echo "==> Syncing Ghostty checkout to $GHOSTTY_COMMIT..." >&2
    git -C "$CHECKOUT_DIR" fetch --depth=1 origin "$GHOSTTY_COMMIT" >&2
    git -C "$CHECKOUT_DIR" restore --source="$GHOSTTY_COMMIT" --staged --worktree . >/dev/null 2>&1 || true
    git -C "$CHECKOUT_DIR" checkout --detach --quiet "$GHOSTTY_COMMIT" >&2
    patch_ghostty_checkout "$CHECKOUT_DIR"
    printf '%s\n' "$CHECKOUT_DIR"
}

SOURCE_DIR_FOR_STAMP="${SOURCE_OVERRIDE:-$CHECKOUT_DIR}"

if ! artifact_cache_complete; then
    SOURCE_DIR="$(prepare_checkout)"
    SOURCE_DIR_FOR_STAMP="$SOURCE_DIR"

    if [[ -n "$SOURCE_OVERRIDE" ]]; then
        patch_ghostty_checkout "$SOURCE_DIR"
    fi

    SOURCE_FRAMEWORK_DIR="$SOURCE_DIR/macos/GhosttyKit.xcframework"
    SOURCE_GHOSTTY_DIR="$SOURCE_DIR/zig-out/share/ghostty"
    SOURCE_TERMINFO_DIR="$SOURCE_DIR/zig-out/share/terminfo"

    if [[ ! -d "$SOURCE_FRAMEWORK_DIR" || ! -d "$SOURCE_GHOSTTY_DIR" || ! -d "$SOURCE_TERMINFO_DIR" || "$FORCE_REBUILD" -eq 1 ]]; then
        echo "==> Building GhosttyKit.xcframework and runtime resources..."
        (
            cd "$SOURCE_DIR"
            zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
        )
    fi

    if [[ ! -d "$SOURCE_FRAMEWORK_DIR" ]]; then
        echo "Error: GhosttyKit.xcframework not found at $SOURCE_FRAMEWORK_DIR" >&2
        exit 1
    fi
    if [[ ! -d "$SOURCE_GHOSTTY_DIR" || ! -d "$SOURCE_TERMINFO_DIR" ]]; then
        echo "Error: Ghostty runtime resources not found under $SOURCE_DIR/zig-out/share" >&2
        exit 1
    fi

    echo "==> Refreshing cached Ghostty artifacts..."
    mkdir -p "$ARTIFACT_FRAMEWORK_DIR" "$ARTIFACT_GHOSTTY_DIR" "$ARTIFACT_TERMINFO_DIR"
    rsync -a --delete "$SOURCE_FRAMEWORK_DIR/" "$ARTIFACT_FRAMEWORK_DIR/"
    rsync -a --delete "$SOURCE_GHOSTTY_DIR/" "$ARTIFACT_GHOSTTY_DIR/"
    rsync -a --delete "$SOURCE_TERMINFO_DIR/" "$ARTIFACT_TERMINFO_DIR/"
else
    echo "==> Using cached Ghostty artifacts from $ARTIFACT_ROOT"
fi

echo "==> Installing Ghostty artifacts into CrispyVibes..."
mkdir -p "$PROJECT_FRAMEWORK_DIR" "$PROJECT_GHOSTTY_DIR" "$PROJECT_TERMINFO_DIR"
rsync -a --delete "$ARTIFACT_FRAMEWORK_DIR/" "$PROJECT_FRAMEWORK_DIR/"
rsync -a --delete "$ARTIFACT_GHOSTTY_DIR/" "$PROJECT_GHOSTTY_DIR/"
rsync -a --delete "$ARTIFACT_TERMINFO_DIR/" "$PROJECT_TERMINFO_DIR/"

cat > "$PROJECT_STAMP_FILE" <<EOF
{
  "repo_url": "$GHOSTTY_REPO_URL",
  "commit": "$GHOSTTY_COMMIT",
  "source_dir": "$SOURCE_DIR_FOR_STAMP",
  "cache_dir": "$CACHE_ROOT"
}
EOF

echo "==> Ghostty setup complete"
echo "Framework: $PROJECT_FRAMEWORK_DIR"
echo "Runtime:   $PROJECT_RUNTIME_ROOT"
