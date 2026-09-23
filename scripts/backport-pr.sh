#!/usr/bin/env bash
# backport-pr.sh — back-port an accepted PR from the public claude-rcode
# repo into this private source-of-truth repo, on a new local branch.
#
# The public repo cannot be merged into directly (pr-guard.yml always
# fails PRs there) — this script is the other half of that story: it
# pulls an accepted PR's diff in, applies it here, and preserves
# attribution via a templated commit message.
#
# All WRITES are local (new branch, `git apply`, local commit). The only
# network calls are READS against GitHub (`gh pr diff` / `gh pr view`).
# Nothing is pushed, merged, or closed by this script — those are
# explicit follow-up steps for a human, printed at the end.
#
# Usage:
#   scripts/backport-pr.sh <PR-number>
#   scripts/backport-pr.sh --help
#
# bash 3.2 compatible (stock macOS).
set -euo pipefail

PUBLIC_REPO="emanuelrechsteiner/claude-rcode"

usage() {
  cat <<EOF
Usage: $(basename "$0") <PR-number>

Back-ports pull request #<PR-number> from $PUBLIC_REPO into a new local
branch (backport/pr-<n>) on this private repo.

Steps performed:
  1. gh pr view  <n> --repo $PUBLIC_REPO --json author,title,url   (READ)
  2. gh pr diff  <n> --repo $PUBLIC_REPO                           (READ)
  3. git apply --3way --check   (dry-run; reports conflicts, no writes)
  4. git checkout -b backport/pr-<n>   (from current HEAD)
  5. git apply --3way   (applies the diff onto the new branch)
  6. git add -A && git commit  (templated message, Co-Authored-By + PR URL)

Nothing is pushed. Nothing on GitHub is modified. Review + merge the new
branch to your trunk yourself, then republish (scripts/publish.sh) and
close the original PR with a comment (template printed at the end).

Requires: gh (authenticated), git, jq.
EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

PR_NUM="$1"
if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "backport-pr.sh: ABORT — <PR-number> must be a positive integer, got: $PR_NUM" >&2
  usage >&2
  exit 1
fi

for bin in gh git jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "backport-pr.sh: ABORT — required command not found: $bin" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DIRTY="$(git status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  echo "backport-pr.sh: ABORT — private tree has uncommitted changes:" >&2
  echo "$DIRTY" >&2
  echo "  Fix: commit or stash before backporting — the new backport branch" >&2
  echo "  should start from a clean, known state." >&2
  exit 1
fi

BRANCH="backport/pr-${PR_NUM}"
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "backport-pr.sh: ABORT — branch ${BRANCH} already exists." >&2
  echo "  Fix: delete it (git branch -D ${BRANCH}) if this is a re-run you" >&2
  echo "  intend to redo, or pick a different PR number." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Fetch PR metadata (READ-only against GitHub)
# ---------------------------------------------------------------------------
echo "backport-pr.sh: fetching PR #${PR_NUM} metadata from ${PUBLIC_REPO}"
PR_JSON="$(gh pr view "$PR_NUM" --repo "$PUBLIC_REPO" --json author,title,url,number)"

PR_TITLE="$(echo "$PR_JSON" | jq -r '.title')"
PR_URL="$(echo "$PR_JSON" | jq -r '.url')"
PR_AUTHOR_LOGIN="$(echo "$PR_JSON" | jq -r '.author.login')"
PR_AUTHOR_NAME="$(echo "$PR_JSON" | jq -r '.author.name // .author.login')"

if [[ -z "$PR_TITLE" || "$PR_TITLE" == "null" ]]; then
  echo "backport-pr.sh: ABORT — could not resolve PR #${PR_NUM} on ${PUBLIC_REPO}." >&2
  echo "  Fix: verify the PR number and that 'gh' is authenticated (gh auth status)." >&2
  exit 1
fi

echo "backport-pr.sh: PR #${PR_NUM} — \"${PR_TITLE}\" by @${PR_AUTHOR_LOGIN} (${PR_URL})"

# ---------------------------------------------------------------------------
# 2. Fetch the diff (READ-only against GitHub)
# ---------------------------------------------------------------------------
DIFF_FILE="$(mktemp "${TMPDIR:-/tmp}/backport-pr-${PR_NUM}.XXXXXX.diff")"
trap 'rm -f "$DIFF_FILE"' EXIT

echo "backport-pr.sh: fetching diff"
gh pr diff "$PR_NUM" --repo "$PUBLIC_REPO" > "$DIFF_FILE"

if [[ ! -s "$DIFF_FILE" ]]; then
  echo "backport-pr.sh: ABORT — the fetched diff is empty. Nothing to apply." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Dry-run apply check (no writes yet)
# ---------------------------------------------------------------------------
echo "backport-pr.sh: checking apply (git apply --3way --check) — no writes yet"
CHECK_ERR="$(mktemp "${TMPDIR:-/tmp}/backport-pr-check.XXXXXX.log")"
trap 'rm -f "$DIFF_FILE" "$CHECK_ERR"' EXIT
if ! git apply --3way --check "$DIFF_FILE" 2>"$CHECK_ERR"; then
  echo "" >&2
  echo "backport-pr.sh: ABORT — the diff does not apply cleanly (conflicts below):" >&2
  echo "" >&2
  cat "$CHECK_ERR" >&2
  echo "" >&2
  echo "backport-pr.sh: WHAT TO FIX — the private tree has diverged from the" >&2
  echo "  file paths/lines this PR touched (expected: the public tree is a" >&2
  echo "  scrubbed/placeholder-substituted VIEW of the private tree, so paths" >&2
  echo "  or identifiers this PR edited may read differently here). Options:" >&2
  echo "  (a) manually re-derive the equivalent private-tree edit and skip this" >&2
  echo "      script; (b) ask the PR author to rebase and retry; (c) apply the" >&2
  echo "      diff with 'git apply --reject' yourself and resolve the .rej files." >&2
  echo "  Nothing was written — no branch was created." >&2
  exit 1
fi
echo "backport-pr.sh: diff applies cleanly (--3way --check passed)"

# ---------------------------------------------------------------------------
# 4-5. Create the branch and apply for real
# ---------------------------------------------------------------------------
echo "backport-pr.sh: creating branch ${BRANCH}"
git checkout -q -b "$BRANCH"

echo "backport-pr.sh: applying diff"
if ! git apply --3way "$DIFF_FILE"; then
  echo "backport-pr.sh: ABORT — apply failed after check passed (unexpected)." >&2
  echo "  The new branch ${BRANCH} exists but may be left with a partial apply." >&2
  echo "  Inspect with 'git status' / 'git diff', then either resolve manually" >&2
  echo "  or clean up with: git checkout - && git branch -D ${BRANCH}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Commit with attribution
# ---------------------------------------------------------------------------
COMMIT_MSG="$(cat <<EOF
backport: ${PR_TITLE} (from claude-rcode #${PR_NUM})

Back-ported from the public claude-rcode repo. Original PR: ${PR_URL}

Co-Authored-By: ${PR_AUTHOR_NAME} <${PR_AUTHOR_LOGIN}@users.noreply.github.com>
EOF
)"

git add -A
if git diff --cached --quiet; then
  echo "backport-pr.sh: NOTE — apply produced no staged changes (diff may have" >&2
  echo "  been a no-op against this tree). Branch ${BRANCH} created but empty." >&2
else
  git commit -q -m "$COMMIT_MSG"
  echo "backport-pr.sh: committed on ${BRANCH}: $(git log -1 --oneline)"
fi

# ---------------------------------------------------------------------------
# Next steps for the human
# ---------------------------------------------------------------------------
cat <<EOF

backport-pr.sh: done. Next steps (all manual, all local-first):

  1. Review the change:
       git diff main..${BRANCH}
  2. Run the private repo's normal checks (scrub-check, tests, etc.) on
     ${BRANCH} before merging.
  3. Merge to your trunk when satisfied:
       git checkout main && git merge --no-ff ${BRANCH}
  4. Republish so the fix reaches the public repo:
       scripts/publish.sh --dry-run --public-dir <path-to-claude-rcode-clone>
       scripts/publish.sh --publish --public-dir <path> --version <next-version>
  5. Close the original PR with a comment (copy/edit this template):

     ---
     Thanks for this — backported in the next release
     via a private-repo commit (this repo is generated; see CONTRIBUTING.md
     and docs/PUBLISHING.md for why direct merges aren't possible here).
     Your authorship is preserved via Co-Authored-By in the private commit.
     Closing this PR now that the change has landed — thank you for the
     contribution!
     ---

     gh pr comment ${PR_NUM} --repo ${PUBLIC_REPO} --body-file <(cat above)
     gh pr close ${PR_NUM} --repo ${PUBLIC_REPO}

     (Both of the gh commands above are WRITES against GitHub — this script
     does not run them for you; copy/paste when you're ready.)
EOF
