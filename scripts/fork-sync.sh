#!/usr/bin/env bash
# Daily upstream sync driver.
#
# Runs from .github/workflows/fork-sync.yml (or manually via
# DRY_RUN=1). The flow:
#
#   1. resolve the latest upstream *release* (never a raw main commit)
#   2. exit if it is already merged into our main
#   3. exit if a sync PR for it is already open
#   4. branch sync/upstream-<ver> off main and `git merge` the release
#      tag — fork patches are carried by git itself, they are never
#      replayed by hand. The fork's .github/workflows is pinned to our
#      version during the merge (the GITHUB_TOKEN cannot push workflow
#      files, and the fork maintains its own workflow set), and the
#      version files are reset to the fork version.
#   5. verify the fork patch set (scripts/verify-fork-patches.sh)
#   6. push the branch and open a PR (merge stays manual)
#
# On merge conflicts the script aborts the merge and opens a tracking
# issue instead of guessing a resolution.
#
# Merge conflicts and patch-gate failures exit non-zero on purpose:
# both must be loud.
#
# Environment overrides (mainly for testing):
#   UPSTREAM_REPO_SLUG  default actions/runner
#   UPSTREAM_REMOTE    default https://github.com/$UPSTREAM_REPO_SLUG
#   UPSTREAM_TAG       force a tag instead of querying releases/latest
#   DRY_RUN=1          stop before pushing / creating the PR
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UPSTREAM_REPO_SLUG="${UPSTREAM_REPO_SLUG:-actions/runner}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-https://github.com/${UPSTREAM_REPO_SLUG}.git}"
BRANCH_PREFIX="sync/upstream-"
DRY_RUN="${DRY_RUN:-0}"
GH_REPO="${GH_REPO:-}"   # gh infers the repo from the origin remote otherwise

log() { echo "[fork-sync] $*"; }

# --- repository state ------------------------------------------------------

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_REMOTE"
fi

git fetch origin main --tags --quiet
git fetch upstream --tags --quiet

git config user.name "fork-sync bot"
git config user.email "fork-sync@adguard.com"

# --- 1. latest upstream release --------------------------------------------

if [ -n "${UPSTREAM_TAG:-}" ]; then
    TAG="$UPSTREAM_TAG"
else
    TAG="$(gh api "repos/${UPSTREAM_REPO_SLUG}/releases/latest" --jq .tag_name)"
fi
git rev-parse -q --verify "refs/tags/${TAG}^{commit}" >/dev/null \
    || { echo "tag $TAG not found after fetching upstream" >&2; exit 1; }

UPSTREAM_VER="${TAG#v}"
FORK_VER="2.10${UPSTREAM_VER#2.}"          # 2.337.0 -> 2.10337.0
BRANCH="${BRANCH_PREFIX}${UPSTREAM_VER}"

# --- 2. already synced? ------------------------------------------------------

if git merge-base --is-ancestor "refs/tags/${TAG}^{commit}" origin/main; then
    log "upstream $UPSTREAM_VER is already merged into main; nothing to do"
    exit 0
fi

# --- 3. sync PR already open? ----------------------------------------------

if [ "$DRY_RUN" != "1" ]; then
    existing_pr="$(gh pr list --state open --head "$BRANCH" --json number --jq '.[].number' || true)"
    if [ -n "$existing_pr" ]; then
        log "PR #$existing_pr for $UPSTREAM_VER is already open; leaving it alone"
        gh pr comment "$existing_pr" \
            --body "Daily check: upstream **$UPSTREAM_VER** still pending merge. Merge this PR and the next run will pick up any newer release."
        exit 0
    fi
fi

# --- 4. merge the release tag ----------------------------------------------

git checkout -B "$BRANCH" origin/main

# Merge without committing: the expected conflicts are resolved
# mechanically below before the merge is concluded.
git merge --no-commit --no-edit "${TAG}" || true

# The fork owns .github/workflows. Mirror our version over whatever
# upstream did to them:
#   1. the GITHUB_TOKEN used to push the branch is not allowed to
#      create or update workflow files at all, so the sync branch must
#      not carry any workflow-file deltas relative to main;
#   2. the fork deliberately maintains its own workflow set (unused
#      upstream workflows are dropped), so upstream changes and
#      re-additions must not resurrect them.
git rm -r -q -f -- .github/workflows >/dev/null 2>&1 || true
rm -rf .github/workflows
git checkout origin/main -- .github/workflows

# releaseVersion/src/runnerversion conflict on every sync by
# construction: upstream's release commit sets the upstream version
# in the same line where we carry our fork version.
printf '%s\n' "$FORK_VER" > releaseVersion
printf '%s\n' "$FORK_VER" > src/runnerversion
git add releaseVersion src/runnerversion

# Anything still unresolved needs a human.
other_conflicts="$(git diff --name-only --diff-filter=U)"
if [ -n "$other_conflicts" ]; then
    git merge --abort || true
    log "merge of $UPSTREAM_VER conflicts; a human must resolve:"
    echo "$other_conflicts"
    if [ "$DRY_RUN" != "1" ]; then
        gh issue create \
            --title "fork-sync: $UPSTREAM_VER has merge conflicts" \
            --body "Merging upstream \`$TAG\` into \`main\` conflicts in:
\`\`\`
$other_conflicts
\`\`\`
Resolve manually:
\`\`\`bash
git fetch upstream --tags
git checkout -B $BRANCH main
git merge $TAG
# resolve, test, then update scripts/fork-patches.txt if patches were absorbed upstream
\`\`\`"
    fi
    exit 1
fi

# Conclude the merge (the version files and workflow pin are part of
# the merge commit).
git commit --no-edit --quiet

# --- 6. fork patch gate ------------------------------------------------------

if ! scripts/verify-fork-patches.sh HEAD; then
    log "fork patch set is broken after the merge; NOT opening a PR"
    exit 1
fi

# --- 7. push + PR ------------------------------------------------------------

patch_table="$(while IFS= read -r p; do
    [ -z "$p" ] && continue
    echo "- $p"
done < scripts/fork-patches.txt)"

body="Automated upstream sync.

- Merges upstream release [$TAG](https://github.com/${UPSTREAM_REPO_SLUG}/releases/tag/${TAG})
- Fork version: \`$FORK_VER\` (upstream $UPSTREAM_VER)
- Fork patch gate: **passed** (all patches listed in \`scripts/fork-patches.txt\` carried over)
- Upstream changes: see the [release notes](https://github.com/${UPSTREAM_REPO_SLUG}/releases/tag/${TAG})

Fork patches verified on this branch:
${patch_table}

Review the diff, wait for CI, then merge manually.
"

if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN: would push $BRANCH and open a PR titled 'chore: sync with upstream $UPSTREAM_VER'"
    git log --oneline origin/main..HEAD
    exit 0
fi

git push -u origin "$BRANCH"
gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "chore: sync with upstream $UPSTREAM_VER" \
    --body "$body"
log "sync PR for $UPSTREAM_VER is open for review"
