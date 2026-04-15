#!/usr/bin/env bash
set -euo pipefail

# Build MOTIS (C++ via Docker Compose) and MOTIS UI (Svelte/Vite via pnpm on the host).
# Same Docker compile flow as otp-tools/scripts/motis/restart-local-motis-compiled.sh
# (ADR overlay, incremental CMake by default).
#
# Usage:
#   ./scripts/build-motis-and-ui.sh
#   ./scripts/build-motis-and-ui.sh --cmake-fresh
#   ./scripts/build-motis-and-ui.sh --motis-only
#   ./scripts/build-motis-and-ui.sh --ui-only
#   ./scripts/build-motis-and-ui.sh --no-toolchain-image   # skip "docker compose build motis-build"
#
# Environment:
#   MOTIS_ROOT              repo root (default: parent of scripts/)
#   MOTIS_BUILD_COMPOSE_FILE  (default: ${MOTIS_ROOT}/docker-compose.build.yml)
#   ADR_SOURCE_DIR          optional checkout; only src/ and include/ are mounted onto deps/adr
#   MOTIS_CMAKE_FRESH=1     same as --cmake-fresh
#   PNPM_INSTALL_FLAGS      extra args for pnpm install (e.g. --frozen-lockfile)

MOTIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTIS_BUILD_COMPOSE_FILE="${MOTIS_BUILD_COMPOSE_FILE:-${MOTIS_ROOT}/docker-compose.build.yml}"
ADR_SOURCE_DIR="${ADR_SOURCE_DIR:-${MOTIS_ROOT}/../adr}"
UI_DIR="${MOTIS_ROOT}/ui"

MOTIS_ONLY=false
UI_ONLY=false
NO_TOOLCHAIN_IMAGE=false
MOTIS_CMAKE_FRESH=false
case "${MOTIS_CMAKE_FRESH:-}" in 1 | true | yes) MOTIS_CMAKE_FRESH=true ;; esac

for arg in "$@"; do
  case "$arg" in
    --motis-only) MOTIS_ONLY=true ;;
    --ui-only) UI_ONLY=true ;;
    --cmake-fresh) MOTIS_CMAKE_FRESH=true ;;
    --no-toolchain-image) NO_TOOLCHAIN_IMAGE=true ;;
    -h | --help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
  esac
done

if [[ "${MOTIS_ONLY}" == "true" && "${UI_ONLY}" == "true" ]]; then
  echo "Error: use only one of --motis-only or --ui-only" >&2
  exit 1
fi

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    echo "Error: ${label} not found: ${path}" >&2
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: command not found: $1" >&2
    exit 1
  fi
}

ensure_motis_toolchain_image() {
  require_file "${MOTIS_BUILD_COMPOSE_FILE}" "MOTIS docker-compose.build file"
  echo "Building Docker image motis-build (toolchain)..."
  (cd "${MOTIS_ROOT}" && docker compose -f "${MOTIS_BUILD_COMPOSE_FILE}" build motis-build)
}

compile_motis_in_docker() {
  require_file "${MOTIS_BUILD_COMPOSE_FILE}" "MOTIS docker-compose.build file"
  require_file "${MOTIS_ROOT}/deps/adr/CMakeLists.txt" \
    "MOTIS deps/adr — run pkg in the MOTIS repo if missing"

  local adr_mount=()
  if [[ -f "${ADR_SOURCE_DIR}/CMakeLists.txt" ]]; then
    if [[ -d "${ADR_SOURCE_DIR}/src" ]]; then
      adr_mount+=(--volume "${ADR_SOURCE_DIR}/src:/work/deps/adr/src")
    fi
    if [[ -d "${ADR_SOURCE_DIR}/include" ]]; then
      adr_mount+=(--volume "${ADR_SOURCE_DIR}/include:/work/deps/adr/include")
    fi
    if [[ ${#adr_mount[@]} -gt 0 ]]; then
      echo "ADR compile overlay: ${ADR_SOURCE_DIR} -> /work/deps/adr/{src,include}"
    else
      echo "ADR: ${ADR_SOURCE_DIR} has no src/include — using MOTIS deps/adr only"
    fi
  else
    echo "ADR: no separate tree at ${ADR_SOURCE_DIR}, using MOTIS deps/adr"
  fi

  local inner
  if [[ "${MOTIS_CMAKE_FRESH}" == "true" ]]; then
    echo "CMake: --fresh (full reconfigure)"
    inner='cmake --fresh -S . -B build/docker-relwithdebinfo -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DNO_BUILDCACHE=ON -DUSE_RES_TZ_DB=OFF -DUSE_SYSTEM_TZ_DB=ON && cmake --build build/docker-relwithdebinfo -- -j$(nproc)'
  else
    echo "CMake: incremental (use --cmake-fresh or MOTIS_CMAKE_FRESH=1 for clean configure)"
    inner='cmake -S . -B build/docker-relwithdebinfo -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DNO_BUILDCACHE=ON -DUSE_RES_TZ_DB=OFF -DUSE_SYSTEM_TZ_DB=ON && cmake --build build/docker-relwithdebinfo -- -j$(nproc)'
  fi

  echo "Compiling MOTIS in Docker -> ${MOTIS_ROOT}/build/docker-relwithdebinfo/"
  (
    cd "${MOTIS_ROOT}"
    # shellcheck disable=SC2086
    docker compose -f "${MOTIS_BUILD_COMPOSE_FILE}" run --rm \
      "${adr_mount[@]}" \
      motis-build bash -lc "${inner}"
  )
  require_file "${MOTIS_ROOT}/build/docker-relwithdebinfo/motis" "compiled MOTIS binary"
  echo "MOTIS binary: ${MOTIS_ROOT}/build/docker-relwithdebinfo/motis"
}

build_motis() {
  require_cmd docker
  if [[ "${NO_TOOLCHAIN_IMAGE}" != "true" ]]; then
    ensure_motis_toolchain_image
  else
    echo "Skipping toolchain image build (--no-toolchain-image)"
  fi
  compile_motis_in_docker
}

build_ui() {
  require_cmd pnpm
  require_file "${UI_DIR}/package.json" "ui/package.json"
  require_file "${UI_DIR}/pnpm-lock.yaml" "ui/pnpm-lock.yaml"

  echo "Installing UI dependencies (pnpm)..."
  # shellcheck disable=SC2086
  (cd "${UI_DIR}" && pnpm install ${PNPM_INSTALL_FLAGS:-})

  echo "Building UI (vite build)..."
  (cd "${UI_DIR}" && pnpm run build)

  echo "UI build output: ${UI_DIR}/build (adapter-static)"
}

# --- main ---
if [[ "${UI_ONLY}" == "true" ]]; then
  build_ui
  exit 0
fi

if [[ "${MOTIS_ONLY}" == "true" ]]; then
  build_motis
  exit 0
fi

build_motis
build_ui
echo "Done: MOTIS + MOTIS UI"
