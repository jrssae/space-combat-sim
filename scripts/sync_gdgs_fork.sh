#!/usr/bin/env bash
# Copies addons/gdgs_scs/ to the project's GitHub fork of GDGS, commits it there and pushes, so the fork always holds what
# the game runs. Then pins that commit in scripts/vendor_addons.sh. Run it from a clean tree after committing a change to
# the addon, and commit the new pin. Usage: scripts/sync_gdgs_fork.sh "<commit subject>"
set -euo pipefail

SUBJECT="${1:?usage: scripts/sync_gdgs_fork.sh \"<commit subject>\"}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="https://github.com/jrssae/godot-gaussian-splatting"
BRANCH="space-combat-sim"
CLONE="${ROOT}/.tools/gdgs_fork"

if [[ -n "$(git -C "${ROOT}" status --porcelain addons/gdgs_scs)" ]]; then
    echo "addons/gdgs_scs has uncommitted changes; commit them first" >&2
    exit 1
fi
if [[ ! -d "${CLONE}/.git" ]]; then
    git clone -q --branch "${BRANCH}" "${URL}" "${CLONE}"
fi
git -C "${CLONE}" checkout -q "${BRANCH}"
git -C "${CLONE}" pull -q --ff-only origin "${BRANCH}"
rm -rf "${CLONE}/addons/gdgs_scs"
cp -R "${ROOT}/addons/gdgs_scs" "${CLONE}/addons/gdgs_scs"
# Forced: the fork's own .gitignore skips the .uid files the game keeps.
git -C "${CLONE}" add -A -f addons/gdgs_scs
if git -C "${CLONE}" diff --cached --quiet; then
    echo "the fork already matches"
else
    git -C "${CLONE}" commit -q -F - <<MSG
${SUBJECT}

From jrssae/space-combat-sim@$(git -C "${ROOT}" rev-parse HEAD)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
    git -C "${CLONE}" push -q origin "${BRANCH}"
fi
PIN="$(git -C "${CLONE}" rev-parse HEAD)"
sed -i -E "s#(\"gdgs_scs\|[^|]*\|)[0-9a-f]{40}#\1${PIN}#" "${ROOT}/scripts/vendor_addons.sh"
echo "fork at ${PIN}; commit the new pin in scripts/vendor_addons.sh"
