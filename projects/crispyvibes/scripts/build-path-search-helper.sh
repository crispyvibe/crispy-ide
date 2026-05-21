#!/bin/sh
set -euo pipefail

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
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

resolve_cmake() {
  if command -v cmake >/dev/null 2>&1; then
    command -v cmake
    return 0
  fi

  for candidate in \
    "${CMAKE:-}" \
    "/opt/homebrew/bin/cmake" \
    "/usr/local/bin/cmake"
  do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

CARGO_BIN="$(resolve_cargo)" || {
  echo "error: cargo is required to build the bundled path-search helper." >&2
  echo "error: searched PATH='${PATH:-}' plus ~/.cargo/bin, /opt/homebrew/bin, and /usr/local/bin." >&2
  exit 1
}

CMAKE_BIN="$(resolve_cmake)" || {
  echo "error: cmake is required to build the bundled libSQL persistence helper." >&2
  echo "error: install it with: brew install cmake" >&2
  echo "error: searched PATH='${PATH:-}' plus /opt/homebrew/bin and /usr/local/bin." >&2
  exit 1
}

SRCROOT="${SRCROOT:?SRCROOT is required}"
TARGET_BUILD_DIR="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
EXECUTABLE_FOLDER_PATH="${EXECUTABLE_FOLDER_PATH:?EXECUTABLE_FOLDER_PATH is required}"
PROJECT_TEMP_DIR="${PROJECT_TEMP_DIR:?PROJECT_TEMP_DIR is required}"

HELPER_MANIFEST="${SRCROOT}/rust/crispyvibes-path-search/Cargo.toml"
HELPER_NAME="crispyvibes-path-search-helper"
PERSISTENCE_MANIFEST="${SRCROOT}/rust/crispyvibes-persistence/Cargo.toml"
PERSISTENCE_NAME="crispyvibes-persistence-helper"
EXTERNAL_SESSIONS_MANIFEST="${SRCROOT}/rust/crispyvibes-external-sessions/Cargo.toml"
EXTERNAL_SESSIONS_NAME="crispyvibes-external-sessions-helper"
CLI_MANIFEST="${SRCROOT}/rust/crispyvibes-cli/Cargo.toml"
CLI_BIN_NAME="crispy"
RUST_TARGET_DIR="${PROJECT_TEMP_DIR}/crispyvibes-rust"

PROFILE_ARGS=""
PROFILE_DIR="debug"
if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
  PROFILE_ARGS="--release"
  PROFILE_DIR="release"
fi

export CARGO_TARGET_DIR="${RUST_TARGET_DIR}"
export CMAKE="${CMAKE_BIN}"

mkdir -p "${RUST_TARGET_DIR}" "${RUST_TARGET_DIR}/${PROFILE_DIR}"

"${CARGO_BIN}" build --manifest-path "${HELPER_MANIFEST}" ${PROFILE_ARGS}
"${CARGO_BIN}" build --manifest-path "${PERSISTENCE_MANIFEST}" ${PROFILE_ARGS}
"${CARGO_BIN}" build --manifest-path "${EXTERNAL_SESSIONS_MANIFEST}" ${PROFILE_ARGS}
"${CARGO_BIN}" build --manifest-path "${CLI_MANIFEST}" ${PROFILE_ARGS}

DESTINATION_DIR="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}"
mkdir -p "${DESTINATION_DIR}"

for name in "${HELPER_NAME}" "${PERSISTENCE_NAME}" "${EXTERNAL_SESSIONS_NAME}"; do
  SOURCE_BINARY="${RUST_TARGET_DIR}/${PROFILE_DIR}/${name}"
  if [ ! -f "${SOURCE_BINARY}" ]; then
    echo "error: expected helper binary at ${SOURCE_BINARY}" >&2
    exit 1
  fi
  install -m 755 "${SOURCE_BINARY}" "${DESTINATION_DIR}/${name}"
done

# Install the agent CLI binary inside Contents/Resources/bin/ so we can prepend
# that directory to PATH when spawning terminals.
CLI_DESTINATION_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/bin"
mkdir -p "${CLI_DESTINATION_DIR}"
CLI_SOURCE_BINARY="${RUST_TARGET_DIR}/${PROFILE_DIR}/${CLI_BIN_NAME}"
if [ ! -f "${CLI_SOURCE_BINARY}" ]; then
  echo "error: expected agent CLI binary at ${CLI_SOURCE_BINARY}" >&2
  exit 1
fi
install -m 755 "${CLI_SOURCE_BINARY}" "${CLI_DESTINATION_DIR}/${CLI_BIN_NAME}"
