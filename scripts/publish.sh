#!/usr/bin/env bash
# publish.sh — one-way publisher: private source-of-truth -> public
# generated-artifact repo (claude-rcode). See docs/PUBLISHING.md for the
# full architecture writeup; this header covers only the mechanics.
#
# The public repo is NEVER hand-edited and this script NEVER pushes —
# publishing a new version means running this script, reviewing the
# resulting commit in the public repo's working copy, then running the
# printed `git push` command yourself.
#
# Steps (see inline comments below for the "why" of each):
#   1. Refuse if the private tree is dirty.
#   2. `git archive HEAD` into a fresh temp staging dir — never `.git`.
#   3. Apply publish-manifest.txt exclusions (rsync --exclude-from).
#   4. Run every executable script in publish-transforms.d/ in numeric
#      order, each given the staging dir as $1.
#   5. Run scrub-check.sh AGAINST THE STAGING TREE. Any finding aborts —
#      the public dir is never touched.
#   6. --dry-run (default): print a file manifest + diff summary vs the
#      public dir, then stop.
#   7. --publish: rsync staging -> public dir, commit, print the push
#      command for a human to run.
#
# Usage:
#   scripts/publish.sh [--dry-run] --public-dir <path>
#   scripts/publish.sh --publish --public-dir <path> --version <vX.Y.Z>
#
# bash 3.2 compatible (stock macOS) — no mapfile, no associative arrays,
# no `${var,,}`; while-read loops throughout, matching the existing
# convention in scripts/scrub-check.sh.
set -euo pipefail

# ---------------------------------------------------------------------------
# 0a. HARD DISABLE (maintainer decision, 2026-08-12)
#
# Publishing is disabled until further notice, by the maintainer's own
# deliberate decision.
#
# Re-activation ONLY via a deliberate edit of this file: set the
# PUBLISH_DISABLED line below to "0". No env-var bypass -- intentional.
# ---------------------------------------------------------------------------
PUBLISH_DISABLED=1
if [[ "$PUBLISH_DISABLED" == "1" ]]; then
  echo "publish.sh: STILLGELEGT (2026-08-12, Nutzerentscheidung)." >&2
  echo "  Dieser Publisher ist auf Entscheidung des Maintainers deaktiviert." >&2
  echo "  Reaktivierung nur durch bewussten Edit dieser Datei: PUBLISH_DISABLED=0" >&2
  echo "  setzen (kein Env-Override) -- siehe Kommentarblock oberhalb dieser Meldung." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 0. Arg parsing
# ---------------------------------------------------------------------------
MODE="dry-run"
PUBLIC_DIR=""
VERSION=""

usage() {
  cat <<'EOF'
Usage:
  publish.sh [--dry-run] --public-dir <path>
  publish.sh --publish --public-dir <path> --version <vX.Y.Z>

Flags:
  --dry-run          Build + scrub-check the staging tree, print a manifest
                      and diff summary vs --public-dir, then stop. This is
                      the DEFAULT if no mode flag is given — publishing is
                      opt-in, never accidental.
  --publish          Actually sync the scrubbed staging tree into
                      --public-dir, commit there, and print the push
                      command. Requires --version.
  --public-dir PATH  Path to the public repo's local working copy
                      (claude-rcode clone). Required in both modes.
  --version vX.Y.Z   Release version tag for the commit message. Required
                      with --publish; ignored (and not required) for
                      --dry-run.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --publish)
      MODE="publish"
      shift
      ;;
    --public-dir)
      PUBLIC_DIR="${2:?--public-dir requires a value}"
      shift 2
      ;;
    --version)
      VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "publish.sh: ABORT — unrecognized argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PUBLIC_DIR" ]]; then
  echo "publish.sh: ABORT — --public-dir is required." >&2
  echo "  Fix: re-run with --public-dir <path to your local claude-rcode clone>." >&2
  exit 1
fi

if [[ "$MODE" == "publish" && -z "$VERSION" ]]; then
  echo "publish.sh: ABORT — --publish requires --version <vX.Y.Z>." >&2
  echo "  Fix: re-run with e.g. --version v1.4.0." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/publish-manifest.txt"
TRANSFORMS_DIR="$REPO_ROOT/publish-transforms.d"

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 1. Refuse if the private tree is dirty
# ---------------------------------------------------------------------------
DIRTY="$(git status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  echo "publish.sh: ABORT — private tree has uncommitted changes:" >&2
  echo "$DIRTY" >&2
  echo "  Fix: commit or stash before publishing. publish.sh always publishes" >&2
  echo "  from HEAD, never from a dirty working tree, so the release commit" >&2
  echo "  message's short-SHA is guaranteed to describe exactly what shipped." >&2
  exit 1
fi

PRIVATE_SHA="$(git rev-parse --short HEAD)"
echo "publish.sh: publishing from private HEAD $PRIVATE_SHA (mode=$MODE)"

# ---------------------------------------------------------------------------
# 2. git archive HEAD into a fresh temp staging dir — never copy .git
# ---------------------------------------------------------------------------
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/publish-staging.XXXXXX")"
ARCHIVE_DIR="$WORKDIR/archive"
STAGING="$WORKDIR/staging"
mkdir -p "$ARCHIVE_DIR" "$STAGING"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "publish.sh: archiving HEAD -> $ARCHIVE_DIR"
git archive HEAD | tar -x -C "$ARCHIVE_DIR"

# ---------------------------------------------------------------------------
# 3. Apply publish-manifest.txt exclusions (rsync --exclude-from semantics)
# ---------------------------------------------------------------------------
if [[ ! -f "$MANIFEST" ]]; then
  echo "publish.sh: ABORT — $MANIFEST not found. The publish pipeline has no" >&2
  echo "  exclusion list to apply, which means it would ship PII/secrets by" >&2
  echo "  default. Fix: restore publish-manifest.txt before publishing." >&2
  exit 1
fi

echo "publish.sh: applying exclusions from $MANIFEST"
if ! command -v rsync >/dev/null 2>&1; then
  echo "publish.sh: ABORT — rsync is required (ships with macOS/Linux by default)." >&2
  exit 1
fi
rsync -a --exclude-from="$MANIFEST" "$ARCHIVE_DIR/" "$STAGING/"

# ---------------------------------------------------------------------------
# 4. Apply transforms (numeric order), each given the staging dir as $1
# ---------------------------------------------------------------------------
if [[ -d "$TRANSFORMS_DIR" ]]; then
  echo "publish.sh: running transforms from $TRANSFORMS_DIR"
  TRANSFORM_FILES=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && TRANSFORM_FILES+=("$t")
  done < <(find "$TRANSFORMS_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

  for t in "${TRANSFORM_FILES[@]}"; do
    if [[ ! -x "$t" ]]; then
      echo "publish.sh: ABORT — transform $t is not executable." >&2
      echo "  Fix: chmod +x $t" >&2
      exit 1
    fi
    echo "publish.sh: -> $(basename "$t")"
    if ! "$t" "$STAGING"; then
      echo "publish.sh: ABORT — transform $(basename "$t") failed. The staging" >&2
      echo "  tree is left in $STAGING for inspection; nothing was published." >&2
      exit 1
    fi
  done
else
  echo "publish.sh: NOTE — no $TRANSFORMS_DIR directory; skipping transforms." >&2
fi

# ---------------------------------------------------------------------------
# 5. Run scrub-check.sh AGAINST THE STAGING TREE
# ---------------------------------------------------------------------------
# scrub-check.sh assumes a git context (it uses `git grep` / `git ls-files`,
# and resolves REPO_ROOT via `git rev-parse --show-toplevel`). The staging
# dir is a plain extracted tree with no .git, so we give it one: an
# ephemeral, throwaway git-init just so `git grep`/`git ls-files` have
# something to operate on. This staging-local .git is discarded with the
# rest of $WORKDIR on exit — it is NEVER what gets rsynced to the public
# dir (step 7 excludes .git explicitly as well, belt-and-braces).
echo "publish.sh: preparing staging tree for scrub-check (ephemeral git init)"
(
  cd "$STAGING"
  git init -q .
  git config user.email "publish-pipeline@localhost"
  git config user.name "publish-pipeline"
  git add -A
)

# WHICH COPY OF scrub-check.sh RUNS THE GATE.
#
# UPDATED 2026-09-25 (IMP-219, vault-by-design): scrub-check.sh's §2 used to
# hardcode real detection literals (name/email/project-codename/mirror-
# marker values), and publish-transforms.d/60-declaw-scrub-check-pii.sh
# existed solely to rewrite the STAGING copy of that file, replacing those
# literals with inert placeholders before anything shipped — running the
# STAGING copy as the actual gate would then have meant gating a release
# with a detector whose own teeth had already been pulled. Both the
# literals and the declaw transform are gone now: real values live only in
# the vault (scripts/vault/, gitignored, never versioned), so
# scrub-check.sh's source is now IDENTICAL whether read from the private
# repo or from the staging tree — there is no longer a "weaker, declawed"
# staging copy to accidentally gate with.
#
# This script still runs the PRIVATE copy at $REPO_ROOT/scripts/
# scrub-check.sh rather than the staging one, as defense-in-depth (a future
# staging-only transform could in principle touch this file again without
# this script's author noticing) — not because it currently produces a
# different result. `cd "$STAGING"` below still makes `git rev-parse
# --show-toplevel` inside the script resolve to the staging tree's
# ephemeral git-init, so the SCANNED TREE is exactly the staging tree being
# published regardless of which copy of the script executes. Two existence
# checks follow on purpose: the private copy is what actually runs, and the
# staging copy is what the public repo ships for contributors/CI to run
# their own gate — losing either one silently would be a distinct failure
# from losing the other.
PRIVATE_SCRUB_SCRIPT="$REPO_ROOT/scripts/scrub-check.sh"
STAGING_SCRUB_SCRIPT="$STAGING/scripts/scrub-check.sh"

if [[ ! -f "$PRIVATE_SCRUB_SCRIPT" ]]; then
  echo "publish.sh: ABORT — $PRIVATE_SCRUB_SCRIPT is missing from the private" >&2
  echo "  repo. This is the detector this pipeline actually gates a publish" >&2
  echo "  with — without it, this pipeline refuses to publish." >&2
  exit 1
fi
if [[ ! -f "$STAGING_SCRUB_SCRIPT" ]]; then
  echo "publish.sh: ABORT — scripts/scrub-check.sh is missing from the staging" >&2
  echo "  tree. Either it was accidentally excluded in publish-manifest.txt," >&2
  echo "  or something is badly wrong. The public repo would ship without its" >&2
  echo "  own scrub gate for contributors/CI — either way this pipeline" >&2
  echo "  refuses to publish." >&2
  exit 1
fi
chmod +x "$PRIVATE_SCRUB_SCRIPT"

echo "publish.sh: running scrub-check.sh (PRIVATE copy) against the staging tree"
SCRUB_OUTPUT="$WORKDIR/scrub-output.txt"
# No CLAUDE_SCRUB_PSEUDONYM_LIST override needed here (removed 2026-09-25,
# IMP-219): scrub-check.sh's §7 now defaults to reading the vault directly
# (${CLAUDE_VAULT_DIR:-~/.claude/vault}), a fixed machine-global path that
# does not depend on $REPO_ROOT — unlike the old repo-relative default
# (publish-pseudonyms.local.tsv), which needed an explicit override here
# specifically BECAUSE `cd "$STAGING"` makes $REPO_ROOT resolve to the
# staging tree inside scrub-check.sh, not the private repo. The vault
# default has no such location-sensitivity, so it works correctly here
# without an override. The legacy list remains available as an explicit
# CLAUDE_SCRUB_PSEUDONYM_LIST override for anyone who still wants to point
# this at it (either format is auto-detected — see scrub-check.sh §7).
if ! (cd "$STAGING" && bash "$PRIVATE_SCRUB_SCRIPT" --require-pseudonym-list) > "$SCRUB_OUTPUT" 2>&1; then
  echo "" >&2
  echo "publish.sh: ABORT — scrub-check found findings in the staging tree:" >&2
  echo "" >&2
  cat "$SCRUB_OUTPUT" >&2
  echo "" >&2
  echo "publish.sh: WHAT TO FIX — each finding above needs either:" >&2
  echo "  (a) a new exclusion line in publish-manifest.txt, or" >&2
  echo "  (b) a new/adjusted rule in publish-transforms.d/30-placeholder-scan.sh, or" >&2
  echo "  (c) (rare, and only for TRUE false positives) a scrub-allowlist.txt entry" >&2
  echo "      in the PRIVATE repo — never edit the allowlist inside staging." >&2
  echo "  Nothing was published; the public dir at $PUBLIC_DIR was not touched." >&2
  exit 1
fi
cat "$SCRUB_OUTPUT"
echo "publish.sh: scrub-check clean on staging tree"

# ---------------------------------------------------------------------------
# 6 / 7. dry-run vs publish
# ---------------------------------------------------------------------------
echo ""
echo "publish.sh: staging file manifest ($(find "$STAGING" -type f -not -path '*/.git/*' | wc -l | tr -d ' ') files):"
find "$STAGING" -type f -not -path '*/.git/*' -print | sed "s#^$STAGING/##" | sort > "$WORKDIR/staging-manifest.txt"

if [[ "$MODE" == "dry-run" ]]; then
  if [[ -d "$PUBLIC_DIR" ]]; then
    echo "publish.sh: diff summary vs existing public dir ($PUBLIC_DIR):"
    if command -v diff >/dev/null 2>&1; then
      PUBLIC_MANIFEST="$WORKDIR/public-manifest.txt"
      find "$PUBLIC_DIR" -type f -not -path '*/.git/*' -not -path '*/.github/*' -print 2>/dev/null \
        | sed "s#^$PUBLIC_DIR/##" | sort > "$PUBLIC_MANIFEST" || true
      diff -u "$PUBLIC_MANIFEST" "$WORKDIR/staging-manifest.txt" || true
    fi
  else
    echo "publish.sh: NOTE — $PUBLIC_DIR does not exist yet; nothing to diff against." >&2
  fi
  echo ""
  echo "publish.sh: DRY RUN complete. No files were written to $PUBLIC_DIR."
  echo "  Re-run with --publish --version <vX.Y.Z> to actually publish."
  exit 0
fi

# --publish from here on.
echo "publish.sh: publishing to $PUBLIC_DIR (version $VERSION, from private $PRIVATE_SHA)"

if [[ ! -d "$PUBLIC_DIR/.git" ]]; then
  echo "publish.sh: ABORT — $PUBLIC_DIR does not look like a git repo (no .git)." >&2
  echo "  Fix: clone the public repo first, or check --public-dir." >&2
  exit 1
fi

# rsync staging -> public dir: delete extraneous files, but NEVER touch
# .git/ or any .github/ISSUE_TEMPLATE overrides the public repo maintains
# independently of what this pipeline generates (this pipeline does ship
# its own .github/ISSUE_TEMPLATE/config.yml + workflows/pr-guard.yml from
# the private tree — the exclusion here is only a safety net in case the
# public repo has maintainer-authored additions under ISSUE_TEMPLATE/ that
# the private tree doesn't know about).
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.github/ISSUE_TEMPLATE/' \
  "$STAGING/" "$PUBLIC_DIR/"

# Re-apply this pipeline's own ISSUE_TEMPLATE (it IS meant to ship) —
# the exclude above only protects a maintainer override; if the public
# dir has no pre-existing ISSUE_TEMPLATE override, ship ours.
if [[ -d "$STAGING/.github/ISSUE_TEMPLATE" && ! -d "$PUBLIC_DIR/.github/ISSUE_TEMPLATE" ]]; then
  mkdir -p "$PUBLIC_DIR/.github"
  cp -R "$STAGING/.github/ISSUE_TEMPLATE" "$PUBLIC_DIR/.github/ISSUE_TEMPLATE"
fi

(
  cd "$PUBLIC_DIR"
  git add -A
  if git diff --cached --quiet; then
    echo "publish.sh: NOTE — no changes vs. current public dir HEAD; nothing to commit." >&2
    exit 0
  fi
  git commit -q -m "release: $VERSION (from private $PRIVATE_SHA)"
  echo "publish.sh: committed in $PUBLIC_DIR: $(git log -1 --oneline)"
)

echo ""
echo "publish.sh: PUBLISH complete (local commit only — nothing was pushed)."
echo "  Review the commit in $PUBLIC_DIR, then push it yourself:"
echo ""
echo "    git -C '$PUBLIC_DIR' push origin HEAD"
echo "    git -C '$PUBLIC_DIR' tag $VERSION && git -C '$PUBLIC_DIR' push origin $VERSION"
echo ""
