#!/usr/bin/env bash
# scripts/sync/check-divergence.sh — chandr1000/SukiSU-Ultra divergence report
# Plan: sukisu-upstream-susfs-sync-plan v1.0.1 §9.1 (Phase 5A). Cron-able and READ-ONLY:
# fetches refs only — never merges, never pushes, never edits branches.
#
# Crontab example (weekly, Mondays 02:30 UTC, before the 03:00 sync bot):
#   30 2 * * 1 /path/to/SukiSU-Ultra/scripts/sync/check-divergence.sh >> /tmp/sukisu-divergence.log 2>&1
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for r in ksu suki susfs; do
  git remote get-url "$r" >/dev/null 2>&1 || { echo "remote '$r' missing — run plan §4.1 first" >&2; exit 1; }
done

git fetch ksu suki --prune                       # GitHub remotes: cheap
# susfs is kernel-sized: read the pinned branch via ls-remote (refs only, no object fetch).
# Manifest, not assumptions — R6 mitigation in plan §11.
SUSFS_BRANCH=$(awk '/^branch:/{print $2; exit}' docs/sync/SUSFS_VERSION 2>/dev/null || true)
if [ -n "${SUSFS_BRANCH:-}" ]; then
  SUSFS_SHA=$(git ls-remote --heads susfs "refs/heads/$SUSFS_BRANCH" | awk '{print $1}')
else
  SUSFS_BRANCH="(docs/sync/SUSFS_VERSION missing)"
  SUSFS_SHA="n/a"
fi

verify() { git rev-parse --verify -q "$1" >/dev/null 2>&1; }

if verify ksu/main && verify builtin; then
  L=$(git rev-list --left-right --count ksu/main...builtin)      # prints: ancestor-side ours-side
else
  L="n/a (needs ksu/main + local builtin — plan §5)"
fi
if verify suki/builtin && verify builtin; then
  S=$(git rev-list --left-right --count suki/builtin...builtin)
else
  S="n/a (needs suki/builtin + local builtin — plan §5)"
fi

echo "ksu/main↔builtin: $L | suki/builtin↔builtin: $S | susfs stable ($SUSFS_BRANCH): ${SUSFS_SHA:-unresolvable}"
