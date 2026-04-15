# shellcheck shell=bash
# Shared GHCR helpers for MOTIS push scripts. Source after setting MOTIS_ROOT.
# Set MOTIS_DOCKER_PUSH=true before calling _motis_ghcr_docker_login.

_motis_ghcr_owner() {
  local o="${GHCR_OWNER:-}"
  if [[ -z "${o}" ]]; then
    o="$(git -C "${MOTIS_ROOT}" config --get github.organization 2>/dev/null || true)"
  fi
  if [[ -z "${o}" ]]; then
    o="$(git -C "${MOTIS_ROOT}" config --global --get github.organization 2>/dev/null || true)"
  fi
  echo "${o:-flowride}"
}

# GitHub username for "docker login ghcr.io -u …" (must match the PAT owner for correct GHCR actor).
_motis_ghcr_login_user() {
  local u="${GHCR_LOGIN_USERNAME:-}"
  if [[ -z "${u}" ]]; then
    u="$(git -C "${MOTIS_ROOT}" config --get github.ghcr-login 2>/dev/null || true)"
  fi
  if [[ -z "${u}" ]]; then
    u="$(git -C "${MOTIS_ROOT}" config --global --get github.ghcr-login 2>/dev/null || true)"
  fi
  echo "${u:-flowride}"
}

_motis_ghcr_docker_login() {
  [[ "${MOTIS_DOCKER_PUSH:-}" == "true" ]] || return 0
  local token="${GHCR_TOKEN:-}"
  [[ -n "${token}" ]] || token="${GITHUB_TOKEN:-}"
  local user
  user="$(_motis_ghcr_login_user)"
  if [[ -z "${token}" ]]; then
    echo "Avertissement: pas de GITHUB_TOKEN ni GHCR_TOKEN — utilisation des identifiants Docker déjà en cache." >&2
    echo "Pour que GHCR enregistre les pushes sous le compte « ${user} »: export GITHUB_TOKEN=… (PAT de ce compte) puis relance." >&2
    return 0
  fi
  echo "${token}" | docker login ghcr.io -u "${user}" --password-stdin
}
