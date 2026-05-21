#!/usr/bin/env bash
#
# CrispyVibes Dev Environment Setup
#
# Sets up a fresh macOS machine to build and run the CrispyVibes project.
# Run from the repo root: ./scripts/setup-dev.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}==> %s${NC}\n" "$1"; }
warn()  { printf "${YELLOW}==> %s${NC}\n" "$1"; }
fail()  { printf "${RED}Error: %s${NC}\n" "$1" >&2; exit 1; }

# ── 1. Xcode Command Line Tools ──────────────────────────────────────────────

info "Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools (this may take a while)..."
    xcode-select --install
    echo "Press Enter after the installation completes."
    read -r
fi

if ! xcodebuild -version &>/dev/null; then
    fail "Xcode is required. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
fi
echo "  Xcode: $(xcodebuild -version | head -1)"

# ── 2. Homebrew ──────────────────────────────────────────────────────────────

info "Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to current shell
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
echo "  Homebrew: $(brew --version | head -1)"

# ── 3. Zig (required for building GhosttyKit) ───────────────────────────────

info "Checking Zig..."
if ! command -v zig &>/dev/null; then
    info "Installing Zig via Homebrew..."
    brew install zig
fi
echo "  Zig: $(zig version)"

# ── 4. CMake (required for libSQL helper encryption support) ─────────────────

info "Checking CMake..."
if ! command -v cmake &>/dev/null; then
    info "Installing CMake via Homebrew..."
    brew install cmake
fi
echo "  CMake: $(cmake --version | head -1)"

# ── 5. Metal Toolchain (required for Ghostty shader compilation) ─────────────

info "Checking Metal Toolchain..."
if ! xcrun -sdk macosx metal --version &>/dev/null 2>&1; then
    info "Downloading Metal Toolchain (required for Ghostty shaders)..."
    xcodebuild -downloadComponent MetalToolchain
fi

# ── 6. Git (should exist, but verify) ───────────────────────────────────────

info "Checking Git..."
if ! command -v git &>/dev/null; then
    fail "Git not found. It should come with Xcode Command Line Tools."
fi
echo "  Git: $(git --version)"

# ── 7. Rust/Cargo (required for bundled helper binaries) ────────────────────

info "Checking Rust/Cargo..."
if ! command -v cargo &>/dev/null; then
    fail "Cargo is required to build bundled helper binaries. Install Rust with: brew install rustup-init && rustup-init"
fi
echo "  Cargo: $(cargo --version)"

# ── 8. Build GhosttyKit ─────────────────────────────────────────────────────

GHOSTTY_FRAMEWORK="$REPO_ROOT/projects/crispyvibes/vendor/GhosttyKit.xcframework"
GHOSTTY_RUNTIME="$REPO_ROOT/projects/crispyvibes/crispyvibes/Resources/GhosttyRuntime/ghostty"

if [[ -d "$GHOSTTY_FRAMEWORK" && -d "$GHOSTTY_RUNTIME" ]]; then
    info "GhosttyKit artifacts already present, skipping build."
    warn "Run ./projects/crispyvibes/scripts/setup-ghostty.sh --force to rebuild."
else
    info "Building GhosttyKit (first time takes ~5-10 minutes)..."
    "$REPO_ROOT/projects/crispyvibes/scripts/setup-ghostty.sh"
fi

# ── 9. Resolve Swift packages ───────────────────────────────────────────────

info "Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
    -project "$REPO_ROOT/projects/crispyvibes/crispyvibes.xcodeproj" \
    -scheme crispyvibes \
    -quiet 2>/dev/null || true

# ── 10. Verify build ────────────────────────────────────────────────────────

info "Verifying project builds..."
if xcodebuild build \
    -project "$REPO_ROOT/projects/crispyvibes/crispyvibes.xcodeproj" \
    -scheme crispyvibes \
    -destination 'platform=macOS' \
    -quiet 2>/dev/null; then
    info "Build succeeded!"
else
    warn "Build failed. Open projects/crispyvibes/crispyvibes.xcodeproj in Xcode to diagnose."
    exit 1
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
info "Dev environment ready!"
echo ""
echo "  Next steps:"
echo "    1. Open projects/crispyvibes/crispyvibes.xcodeproj in Xcode"
echo "    2. Select the 'crispyvibes' scheme"
echo "    3. Build and run (Cmd+R)"
echo ""
