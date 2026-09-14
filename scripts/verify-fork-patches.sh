#!/usr/bin/env bash
# Verifies that every fork patch is present on a ref.
#
# A fork patch is a non-merge commit that lives on our main but is not
# part of upstream (actions/runner). The authoritative list of expected
# patches is scripts/fork-patches.txt.
#
# Version churn commits are ignored, because every upstream sync creates
# new ones by design:
#   - our own bumps:     "chore: bump version to ..."
#   - upstream tag tips: "Update releaseVersion" (enters our history
#                         through the merged release tag)
#
# Exits non-zero when any listed patch is missing. This is the guard
# that prevents a silent patch loss during an upstream sync; the sync
# workflow (scripts/fork-sync.sh) and the fork-patches CI job both run
# it, and the job should be configured as a required status check.
#
# Usage: scripts/verify-fork-patches.sh [<ref>]     (default: origin/main)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UPSTREAM_REPO_SLUG="${UPSTREAM_REPO_SLUG:-actions/runner}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-https://github.com/${UPSTREAM_REPO_SLUG}.git}"
REF="${1:-origin/main}"

if ! git rev-parse --verify --quiet "$REF" >/dev/null 2>&1; then
    git fetch origin main --quiet
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_REMOTE"
fi
git fetch upstream main --quiet

expected="$(mktemp)"
actual="$(mktemp)"
trap 'rm -f "$expected" "$actual"' EXIT

grep -v '^[[:space:]]*$' scripts/fork-patches.txt | sort > "$expected"

# All fork commits on $REF, minus version churn.
git log --no-merges --format='%s' "upstream/main..$REF" \
    | grep -vE '^(chore: bump version|Update releaseVersion)' \
    | sort > "$actual"

missing="$(comm -23 "$expected" "$actual" | grep -v '^$' || true)"
unlisted="$(comm -13 "$expected" "$actual" | grep -v '^$' || true)"

if [ -n "$missing" ]; then
    while IFS= read -r subject; do
        echo "MISSING : $subject"
    done <<< "$missing"
    echo
    echo "ERROR: fork patches listed in scripts/fork-patches.txt are absent"
    echo "       from $REF. If a patch was dropped intentionally (e.g."
    echo "       upstream absorbed our fix), remove it from the manifest"
    echo "       in the same PR."
    exit 1
fi

while IFS= read -r subject; do
    echo "ok      : $subject"
done < "$expected"

# Informational: fork commits that exist but are not tracked yet. Adding
# a new fork patch should come with a manifest update in the same PR,
# but forgetting it only produces noise in the log, not a failure.
while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    echo "note    : unlisted fork commit: $subject"
done <<< "$unlisted"

echo
echo "All listed fork patches are present on $REF."
