#!/usr/bin/env bash
# scripts/sync/prepare-sync-pr.sh — wraps plan §6.1 (Lane A) then §6.2 (Lane B)
#
# Delivery model (§3): one PR per lane per cycle. This script NEVER pushes to
# main/builtin; it pushes integrate/* branches only and opens PRs via gh
# (fallback: prints the manual commands). pre-sync/<date> tags are taken on
# origin/builtin BEFORE the Lane B merge (§10 rollback points).
#
# On merge conflicts the script ABORTS (rerere preimages are kept for your
# manual re-merge) and opens a conflict ISSUE instead of a conflicted PR:
# a pushable conflicted PR would need an "ours"-placeholder commit, which
# would poison rerere memory and force history rewrites later (G4/G5).
# Plan G4 explicitly allows "a sync PR (or a conflict issue)".
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DATE=$(date +%F)
LANE_A="integrate/ksu-$DATE"
LANE_B="integrate/builtin-$DATE"
CONFLICTS="conflicts.txt"
REPORT="docs/sync/$DATE.md"

for r in ksu suki; do
  git remote get-url "$r" >/dev/null 2>&1 || { echo "remote '$r' missing — run plan §4.1 first" >&2; exit 1; }
done
git config rerere.enabled true
git config rerere.autoUpdate true
if command -v gh >/dev/null 2>&1; then GH=1; gh label create merge-conflict --force >/dev/null 2>&1 || true
else GH=0; echo "gh CLI not found — manual commands will be printed instead"; fi

git fetch ksu suki origin --prune --tags
if [ "$(git rev-parse origin/main)" != "$(git rev-parse suki/main)" ]; then
  echo "NOTE: origin/main != suki/main — fork is behind. Prefer running Phase 1 (§5, Sync fork) first."
fi

# ---------- Lane A: ancestor -> main lineage (§6.1) ----------
git switch -C "$LANE_A" origin/main
if git merge --no-ff --no-edit ksu/main; then
  A_STATE=clean
  NCONF=0
else
  A_STATE=conflict
  git diff --name-only --diff-filter=U > "$CONFLICTS"
  NCONF=$(wc -l < "$CONFLICTS")
  echo "Lane A conflicted ($NCONF files). List dumped to $CONFLICTS; aborting merge (rerere keeps preimages)."
  git merge --abort
fi

if [ "$A_STATE" = conflict ]; then
  if [ "$GH" = 1 ]; then
    gh issue create --label merge-conflict \
      --title "⚠️ upstream sync CONFLICTS ($DATE): Lane A needs manual resolution" \
      --body "Lane A merge of ksu/main into the main lineage conflicted ($NCONF files).
Resolve on a local integrate branch (§6.1); if >15 files use the ladder fallback.
Conflicted files:
$(cat "$CONFLICTS")" \
      || echo "issue create failed — resolve manually using $CONFLICTS"
  else
    echo "manual: resolve conflicts from $CONFLICTS (ladder §6.1 if >15 files), then push + PR"
  fi
  exit 2   # §6.2 runs only after Lane A is green
fi

git push -u origin "$LANE_A"
if [ "$GH" = 1 ]; then
  gh pr create --base main --head "$LANE_A" \
    --title "upstream sync: tiann/KernelSU main ($DATE)" \
    --body "Lane A (§6.1): clean textual merge of ksu/main (+$(git rev-list --count "origin/main..ksu/main") ancestor commits).
Gates V1–V4 (§8) must pass before merge." \
    || echo "PR create failed — open manually: main <- $LANE_A"
else
  echo "manual: open PR main <- $LANE_A"
fi

# ---------- Lane B: Lane A result -> builtin (§6.2) ----------
if ! git rev-parse --verify -q origin/builtin >/dev/null; then
  echo "origin/builtin missing — run Phase 1 (§5) first. Lane B skipped."
  exit 0
fi
if git tag "pre-sync/$DATE" origin/builtin 2>/dev/null; then
  git push origin "refs/tags/pre-sync/$DATE"
else
  echo "pre-sync/$DATE already exists — rollback point unchanged"
fi
git switch -C "$LANE_B" origin/builtin
if git merge --no-ff --no-edit "$LANE_A"; then
  B_STATE=clean
else
  B_STATE=conflict
  git diff --name-only --diff-filter=U > "$CONFLICTS"
  NCONF=$(wc -l < "$CONFLICTS")
  echo "Lane B conflicted ($NCONF files) — hotspot map: docs/sync/susfs-surface.txt"
  git merge --abort
fi

if [ "$B_STATE" = conflict ]; then
  if [ "$GH" = 1 ]; then
    gh issue create --label merge-conflict \
      --title "⚠️ upstream sync CONFLICTS ($DATE): Lane B needs manual resolution" \
      --body "Lane B merge of $LANE_A into builtin conflicted ($NCONF files).
Resolve on a local integrate branch (§6.2) using docs/sync/susfs-surface.txt as the hotspot map.
Conflicted files:
$(cat "$CONFLICTS")" \
      || echo "issue create failed — resolve manually using $CONFLICTS"
  else
    echo "manual: resolve conflicts from $CONFLICTS (hotspots: docs/sync/susfs-surface.txt)"
  fi
  exit 3
fi

git push -u origin "$LANE_B"
if [ "$GH" = 1 ]; then
  gh pr create --base builtin --head "$LANE_B" \
    --title "upstream sync: builtin ← ksu/main ($DATE)" \
    --body "Lane B (§6.2): carries the Lane A result into the SUSFS carrier.
Gates V1–V4 (§8) must pass before merge; V5–V6 before flashing/tagging a release." \
    || echo "PR create failed — open manually: builtin <- $LANE_B"
else
  echo "manual: open PR builtin <- $LANE_B"
fi

# ---------- Per-cycle report (§6.3) ----------
mkdir -p docs/sync
{
  echo "# sync cycle $DATE"
  echo "- merge-base: $(git merge-base ksu/main "$LANE_B")"
  echo "- ancestor-side: $(git rev-list --count ksu/main "^$LANE_B")"
  echo "- ours: $(git rev-list --count "$LANE_B" "^ksu/main")"
  echo "- lane A: $A_STATE | lane B: $B_STATE | conflicted files: $NCONF"
  echo "- rollback point: pre-sync/$DATE -> $(git rev-parse --short "pre-sync/$DATE")"
} | tee "$REPORT"
echo "Commit $REPORT with the cycle summary (plan §6.3)."
