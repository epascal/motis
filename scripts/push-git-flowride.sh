#!/usr/bin/env bash
set -euo pipefail

# Push all local branches and tags to the Flowride GitHub fork.
# Matches the GraphHopper workspace convention: origin like
#   git@github.com-flowride:flowride/graphhopper.git
#
# Requires SSH access as the Flowride GitHub account. Typical ~/.ssh/config:
#   Host github.com-flowride
#     HostName github.com
#     User git
#     IdentityFile ~/.ssh/id_ed25519_flowride
#     IdentitiesOnly yes
#
# Environment:
#   FLOWRIDE_REMOTE_NAME   default: flowride
#   FLOWRIDE_GITHUB_REPO   default: flowride/motis  (owner/repo, no .git)
#   GITHUB_SSH_HOST        default: github.com-flowride  (same Host as graphhopper)
#
# Optional repo config (this clone), same as graphhopper:
#   git config github.organization flowride
#   git config github.ghcr-login flowride
#
# If master is rejected (remote has commits you lack): fetch, then either merge remote
#   git fetch flowride && git checkout master && git merge flowride/master && git push flowride master
# or overwrite the fork branch only if you intend to (dangerous if others use it):
#   git push --force-with-lease flowride master

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

REMOTE="${FLOWRIDE_REMOTE_NAME:-flowride}"
REPO="${FLOWRIDE_GITHUB_REPO:-flowride/motis}"
SSH_HOST="${GITHUB_SSH_HOST:-github.com-flowride}"
URL="git@${SSH_HOST}:${REPO}.git"

if git remote get-url "${REMOTE}" &>/dev/null; then
  git remote set-url "${REMOTE}" "${URL}"
else
  git remote add "${REMOTE}" "${URL}"
fi

echo "Remote ${REMOTE} → ${URL}"
echo "Poussée de toutes les branches locales et des tags…"
set +e
git push "${REMOTE}" --all
branch_push_status=$?
git push "${REMOTE}" --tags
tags_push_status=$?
set -e

if [[ "${branch_push_status}" -ne 0 ]]; then
  echo "" >&2
  echo "Une branche a été refusée (souvent master). Les autres refs peuvent déjà être à jour sur le remote." >&2
  echo "  Voir commits distants: git fetch ${REMOTE} && git log --oneline master..${REMOTE}/master" >&2
  echo "  Intégrer puis pousser: git checkout master && git merge ${REMOTE}/master && git push ${REMOTE} master" >&2
  echo "  Ou écraser master du fork (prudent): git push --force-with-lease ${REMOTE} master" >&2
fi

if [[ "${branch_push_status}" -eq 0 && "${tags_push_status}" -eq 0 ]]; then
  echo "Terminé."
fi

if [[ "${branch_push_status}" -ne 0 || "${tags_push_status}" -ne 0 ]]; then
  exit 1
fi
