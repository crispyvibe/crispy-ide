#!/usr/bin/env bash
#
# Build and launch the local CrispyLocal.app for the current worktree.
#
# Resolves the build output directory from `xcodebuild -showBuildSettings`
# instead of globbing `~/Library/Developer/Xcode/DerivedData/crispyvibes-*`,
# which can match a sibling worktree's stale build.
#
# Usage:
#   ./scripts/run-local.sh             # build + launch
#   ./scripts/run-local.sh --no-build  # launch the existing build only
#   ./scripts/run-local.sh --print     # print the resolved app path and exit
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/projects/crispyvibes/crispyvibes.xcodeproj"
SCHEME="crispyvibes-local"
CONFIGURATION="DebugLocal"
APP_NAME="CrispyLocal.app"

RUN_BUILD=1
PRINT_ONLY=0

while (($# > 0)); do
    case "$1" in
        --no-build)
            RUN_BUILD=0
            shift
            ;;
        --print)
            PRINT_ONLY=1
            RUN_BUILD=0
            shift
            ;;
        -h|--help)
            sed -n '3,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

command -v xcodebuild >/dev/null 2>&1 || {
    printf 'Error: xcodebuild not found. Install Xcode command line tools.\n' >&2
    exit 1
}

if (( RUN_BUILD )); then
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -quiet
fi

# Ask xcodebuild for this project's actual output directory. This is robust
# across multiple worktrees because Xcode hashes the project path and gives
# each worktree its own DerivedData root.
BUILT_PRODUCTS_DIR=$(
    xcodebuild -showBuildSettings \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}'
)

if [[ -z "$BUILT_PRODUCTS_DIR" ]]; then
    printf 'Error: could not resolve BUILT_PRODUCTS_DIR from xcodebuild settings.\n' >&2
    exit 1
fi

APP_PATH="$BUILT_PRODUCTS_DIR/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
    printf 'Error: %s does not exist. Run without --no-build to build it first.\n' "$APP_PATH" >&2
    exit 1
fi

if (( PRINT_ONLY )); then
    printf '%s\n' "$APP_PATH"
    exit 0
fi

open "$APP_PATH"
