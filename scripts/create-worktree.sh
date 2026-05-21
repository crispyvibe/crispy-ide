#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { printf "${GREEN}==> %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}==> %s${NC}\n" "$1"; }
fail() { printf "${RED}Error: %s${NC}\n" "$1" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-build] [--force-ghostty] <worktree-path> <branch-name> [base-ref]

Create a ready-to-build CrispyVibes worktree and install generated local artifacts.

Examples:
  ./scripts/create-worktree.sh ../crispyvibes-ide-feature feature/my-change
  ./scripts/create-worktree.sh --no-build ../crispyvibes-ide-spike spike/research origin/main

Environment overrides:
  CRISPYVIBES_GHOSTTY_CACHE_DIR   Shared Ghostty cache directory
                            (default: ~/Library/Caches/crispyvibes/ghostty-build)
EOF
}

resolve_cargo() {
    if command -v cargo >/dev/null 2>&1; then
        command -v cargo
        return 0
    fi

    for candidate in \
        "${CARGO:-}" \
        "${HOME:-}/.cargo/bin/cargo" \
        "/opt/homebrew/bin/cargo" \
        "/usr/local/bin/cargo"
    do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

RUN_BUILD=1
FORCE_GHOSTTY=0

while (($# > 0)); do
    case "$1" in
        --no-build)
            RUN_BUILD=0
            shift
            ;;
        --force-ghostty)
            FORCE_GHOSTTY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            fail "unknown option '$1'"
            ;;
        *)
            break
            ;;
    esac
done

if (($# < 2 || $# > 3)); then
    usage >&2
    exit 1
fi

WORKTREE_PATH="$1"
BRANCH_NAME="$2"
BASE_REF="${3:-HEAD}"

command -v git >/dev/null 2>&1 || fail "git is required"
command -v rsync >/dev/null 2>&1 || fail "rsync is required"
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is required"

CARGO_BIN="$(resolve_cargo)" || {
    fail "cargo is required. Install Rust with: brew install rustup-init && rustup-init"
}
export CARGO="$CARGO_BIN"

WORKTREE_PARENT="$(dirname "$WORKTREE_PATH")"
WORKTREE_NAME="$(basename "$WORKTREE_PATH")"
mkdir -p "$WORKTREE_PARENT"
WORKTREE_PATH="$(cd "$WORKTREE_PARENT" && pwd)/$WORKTREE_NAME"

if [[ -e "$WORKTREE_PATH" ]]; then
    if [[ ! -f "$WORKTREE_PATH/.git" && ! -d "$WORKTREE_PATH/.git" ]]; then
        fail "path already exists and is not a git worktree: $WORKTREE_PATH"
    fi
    warn "Worktree already exists at $WORKTREE_PATH; reusing it."
else
    info "Creating git worktree at $WORKTREE_PATH"
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
    else
        git -C "$REPO_ROOT" worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_REF"
    fi
fi

DEFAULT_GHOSTTY_CACHE="${XDG_CACHE_HOME:-$HOME/Library/Caches}/crispyvibes/ghostty-build"
export CRISPYVIBES_GHOSTTY_CACHE_DIR="${CRISPYVIBES_GHOSTTY_CACHE_DIR:-$DEFAULT_GHOSTTY_CACHE}"

LEGACY_GHOSTTY_CACHE="$REPO_ROOT/.cache/ghostty-build"
if [[ ! -d "$CRISPYVIBES_GHOSTTY_CACHE_DIR/artifacts" && -d "$LEGACY_GHOSTTY_CACHE/artifacts" ]]; then
    info "Seeding shared Ghostty cache from existing repo cache"
    mkdir -p "$CRISPYVIBES_GHOSTTY_CACHE_DIR"
    rsync -a "$LEGACY_GHOSTTY_CACHE/" "$CRISPYVIBES_GHOSTTY_CACHE_DIR/"
fi

info "Installing Ghostty artifacts into worktree"
if [[ "$FORCE_GHOSTTY" -eq 1 ]]; then
    "$WORKTREE_PATH/projects/crispyvibes/scripts/setup-ghostty.sh" --force
else
    "$WORKTREE_PATH/projects/crispyvibes/scripts/setup-ghostty.sh"
fi

info "Resolving Swift package dependencies"
xcodebuild -resolvePackageDependencies \
    -project "$WORKTREE_PATH/projects/crispyvibes/crispyvibes.xcodeproj" \
    -scheme crispyvibes \
    -quiet

if [[ "$RUN_BUILD" -eq 1 ]]; then
    info "Verifying local worktree build"
    xcodebuild build \
        -project "$WORKTREE_PATH/projects/crispyvibes/crispyvibes.xcodeproj" \
        -scheme crispyvibes-local \
        -configuration DebugLocal \
        -destination 'platform=macOS'
fi

info "Worktree ready: $WORKTREE_PATH"
echo "Open with: open \"$WORKTREE_PATH/projects/crispyvibes/crispyvibes.xcodeproj\""
