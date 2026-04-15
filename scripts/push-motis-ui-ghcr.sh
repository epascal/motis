#!/usr/bin/env bash
set -euo pipefail

# Build ui/Dockerfile and tag for GitHub Container Registry.
# Default: ghcr.io/flowride/motis-ui (github.organization, GHCR_OWNER, or flowride).
#
# Same GHCR auth as push-motis-ghcr.sh: GITHUB_TOKEN / GHCR_TOKEN and GHCR_LOGIN_USERNAME
# (or git config github.ghcr-login), typically the flowride GitHub user that owns the PAT.
#
# Usage:
#   ./scripts/push-motis-ui-ghcr.sh           # build + tag only
#   ./scripts/push-motis-ui-ghcr.sh --push  # login (if token set) + build + docker push

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOTIS_ROOT="${ROOT}"
# shellcheck source=scripts/ghcr.inc.sh
source "${ROOT}/scripts/ghcr.inc.sh"
UI_DIR="${ROOT}/ui"
cd "${UI_DIR}"

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
GHCR_IMAGE="${GHCR_IMAGE:-motis-ui}"

if [[ ! -f "${UI_DIR}/openapi.yaml" ]]; then
  if [[ -f "${ROOT}/openapi.yaml" ]]; then
    echo "Copie de openapi.yaml depuis la racine du dépôt MOTIS..."
    cp "${ROOT}/openapi.yaml" "${UI_DIR}/openapi.yaml"
  else
    echo "Erreur: openapi.yaml introuvable (${UI_DIR}/openapi.yaml ou ${ROOT}/openapi.yaml)" >&2
    exit 1
  fi
fi

SHORT="$(git -C "${ROOT}" rev-parse --short HEAD)"
REF="${GHCR_OWNER}/${GHCR_IMAGE}"
FULL_BASE="ghcr.io/${REF}"
OCI_SOURCE="https://github.com/${GHCR_OWNER}/motis"

echo "Build MOTIS UI → ${FULL_BASE}:latest et :${SHORT} (owner=${GHCR_OWNER})"
docker build -f Dockerfile \
  --build-arg "OCI_VENDOR=Flowride" \
  --build-arg "OCI_SOURCE=${OCI_SOURCE}" \
  --build-arg "OCI_TITLE=MOTIS web UI" \
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
