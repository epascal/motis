#!/usr/bin/env bash
set -euo pipefail

# Build Dockerfile.runtime and tag for GitHub Container Registry.
# Default image: ghcr.io/flowride/motis (github.organization, GHCR_OWNER, or flowride).
#
# GHCR must authenticate as the GitHub user that should appear as package publisher (often the
# flowride bot/user). Set a PAT on that account and:
#   export GITHUB_TOKEN=ghp_…
#   export GHCR_LOGIN_USERNAME=flowride   # optional; default flowride, or git config github.ghcr-login
#
# Usage:
#   ./scripts/push-motis-ghcr.sh           # build + tag only
#   ./scripts/push-motis-ghcr.sh --push  # login (if token set) + build + docker push

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTIS_ROOT="${ROOT}"
# shellcheck source=scripts/ghcr.inc.sh
source "${ROOT}/scripts/ghcr.inc.sh"
cd "$ROOT"

DO_PUSH=false
for a in "$@"; do
  case "$a" in
    --push) DO_PUSH=true ;;
    -h | --help)
      sed -n '1,25p' "$0"
      exit 0
      ;;
  esac
done

if [[ -z "${GHCR_OWNER:-}" ]]; then
  GHCR_OWNER="$(_motis_ghcr_owner)"
fi
GHCR_IMAGE="${GHCR_IMAGE:-motis}"

BIN="${ROOT}/build/docker-relwithdebinfo/motis"
if [[ ! -x "${BIN}" ]]; then
  echo "Erreur: binaire MOTIS introuvable ou non exécutable: ${BIN}" >&2
  echo "Compile d'abord (ex. docker compose -f docker-compose.build.yml run --rm motis-build)." >&2
  exit 1
fi

SHORT="$(git rev-parse --short HEAD)"
REF="${GHCR_OWNER}/${GHCR_IMAGE}"
FULL_BASE="ghcr.io/${REF}"
OCI_SOURCE="https://github.com/${GHCR_OWNER}/${GHCR_IMAGE}"

echo "Build runtime image → ${FULL_BASE}:latest et :${SHORT} (owner=${GHCR_OWNER})"
docker build -f Dockerfile.runtime \
  --build-arg "OCI_VENDOR=Flowride" \
  --build-arg "OCI_SOURCE=${OCI_SOURCE}" \
  --build-arg "OCI_TITLE=MOTIS server runtime" \
  -t "${FULL_BASE}:${SHORT}" -t "${FULL_BASE}:latest" .

if [[ "${DO_PUSH}" == "true" ]]; then
  MOTIS_DOCKER_PUSH=true
  _motis_ghcr_docker_login
  docker push "${FULL_BASE}:latest"
  docker push "${FULL_BASE}:${SHORT}"
  echo "Poussé: ${FULL_BASE}:latest, ${FULL_BASE}:${SHORT}"
else
  echo "Sans --push. Pour publier: $0 --push"
fi
