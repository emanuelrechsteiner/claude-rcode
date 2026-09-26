#!/usr/bin/env bash
# publish-manifest-regression.sh — regression suite for publish-manifest.txt's
# rsync --exclude-from ANCHORING (IMP-219, plans/vault-by-design-2026-09-25.md).
#
# Befund: an unanchored directory pattern (no leading "/") in
# publish-manifest.txt is matched by rsync against a directory's BASENAME AT
# ANY DEPTH (rsync(1) FILTER RULES: a pattern with no internal, non-trailing
# slash is compared only to the final path component, at any level of the
# tree — the leading "/" is what anchors a pattern to the transfer root
# instead). The bare line "vault/" therefore did not just hide the
# root-level runtime vault DATA dir (gitignored, machine-local) — it also
# swallowed scripts/vault/ (vault.sh, lib.sh, public-names.txt), the
# tracked, PUBLISHABLE vault TOOL, out of every publish run. Fixed by
# anchoring the line to "/vault/", matching the convention .gitignore
# already uses for its own vault entry. This suite pins that fix and guards
# the same error class recurring on this or any other manifest line.
#
# Verified by hand before this suite existed, via
# `rsync -a --dry-run --itemize-changes`: the unanchored "vault/" pattern
# drops scripts/vault/ from the transfer entirely (0 files); the anchored
# "/vault/" pattern excludes only the root-level dir and ships all 3
# scripts/vault/ files untouched.
#
# MECHANICS — mirrors scripts/publish.sh's own steps 2-3 exactly (same code
# path, not a reimplementation, per rules/testing-quality.md "Verify Via the
# Same Code Path"): `git archive HEAD` into a throwaway dir, then a REAL
# (non-dry-run) `rsync -a --exclude-from=<publish-manifest.txt>` — same two
# flags publish.sh's own step 3 uses — into a second throwaway dir. The
# manifest is read from the LIVE working-tree path ($REPO_ROOT/publish-
# manifest.txt), exactly like publish.sh's own MANIFEST variable — so this
# suite also catches a manifest regression BEFORE it is committed, not only
# after. Two synthetic, root-level fixtures (vault/secret-fixture,
# env.local.sh) are written directly into the archived copy — NEVER into
# this repo's own working tree — to prove the exclusion still fires for its
# intended target; without them the "excluded" assertions would be
# vacuously true (nothing there to fail to exclude).
#
# plans/ and *.local.md are NOT manifest-level exclusions at all — they are
# kept out of every publish by .gitignore, which stops them from ever being
# TRACKED, so they cannot survive `git archive HEAD` in the first place. This
# suite asserts that invariant directly against the freshly archived tree
# (no synthetic injection needed or possible — there is no tracking step to
# bypass here) rather than by testing a manifest line that does not exist
# for this category.
#
# This suite only READS the real repo (git archive HEAD) and writes
# exclusively under its own mktemp scratch dir — it never touches this
# repo's working tree and never touches ~/.claude/vault.
#
# bash 3.2 compatible (stock macOS) — no mapfile, no associative arrays, no
# ${var,,}; matches the convention in scripts/scrub-check.sh.
#
# Usage: bash scripts/tests/publish-manifest-regression.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/publish-manifest.txt"

[[ -f "$MANIFEST" ]] || { echo "ERROR: required source not found: $MANIFEST" >&2; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync is required" >&2; exit 1; }
command -v git   >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }

# assert_in_list <label> <newline-list> <exact-relpath> — exact, full-line
# match against a sorted file listing (never a substring grep: "env.local.sh"
# is itself a substring of "templates/env.local.sh.template", so a plain
# grep -F would false-positive one for the other).
assert_in_list() {
  local label="$1" list="$2" relpath="$3"
  if printf '%s\n' "$list" | grep -qxF -- "$relpath"; then
    ok "$label"
  else
    bad "$label" "expected '$relpath' to be TRANSFERRED (present), not found"
  fi
}

assert_not_in_list() {
  local label="$1" list="$2" relpath="$3"
  if printf '%s\n' "$list" | grep -qxF -- "$relpath"; then
    bad "$label" "expected '$relpath' to be EXCLUDED (absent), but it was transferred"
  else
    ok "$label"
  fi
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/publish-manifest-regr.XXXXXX")"
[[ -n "$SCRATCH" && -d "$SCRATCH" ]] || { echo "FATAL: mktemp failed to create a scratch dir" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT

ARCHIVE_DIR="$SCRATCH/archive"
STAGING="$SCRATCH/staging"
mkdir -p "$ARCHIVE_DIR" "$STAGING"

# --- Step 2 equivalent: git archive HEAD -> plain tree (never .git) --------
( cd "$REPO_ROOT" && git archive HEAD ) | tar -x -C "$ARCHIVE_DIR"

# ---------------------------------------------------------------------------
# plans/ and *.local.md: never tracked, so never in the archive at all.
# Checked BEFORE the synthetic fixtures below are added, against the
# archived tree exactly as `git archive HEAD` produced it.
# ---------------------------------------------------------------------------
echo "== categories protected by .gitignore (never reach git archive HEAD) =="
if [[ -e "$ARCHIVE_DIR/plans" ]]; then
  bad "plans/ is absent from the archived tree" "found $ARCHIVE_DIR/plans in the archive"
else
  ok "plans/ is absent from the archived tree (never tracked)"
fi
LOCAL_MD_COUNT="$(find "$ARCHIVE_DIR" -type f -name '*.local.md' | wc -l | tr -d ' ')"
if [[ "$LOCAL_MD_COUNT" -eq 0 ]]; then
  ok "no *.local.md file anywhere in the archived tree (never tracked)"
else
  bad "no *.local.md file anywhere in the archived tree" "found $LOCAL_MD_COUNT such file(s)"
fi

# ---------------------------------------------------------------------------
# Synthetic root-level fixtures — written directly into the archived copy,
# never into this repo. These exist only to give the manifest's belt-and-
# braces exclusion lines something to actually exclude; without them the
# "excluded" assertions below would pass vacuously (nothing there to fail to
# exclude), same failure mode a purely-declarative check would have.
# ---------------------------------------------------------------------------
mkdir -p "$ARCHIVE_DIR/vault"
printf 'synthetic root-vault fixture — never a real secret\n' > "$ARCHIVE_DIR/vault/secret-fixture"
printf 'synthetic root env.local.sh fixture\n' > "$ARCHIVE_DIR/env.local.sh"

# --- Step 3 equivalent: REAL (non-dry-run) rsync, same two flags publish.sh
# uses, into a throwaway STAGING dir. -----------------------------------
rsync -a --exclude-from="$MANIFEST" "$ARCHIVE_DIR/" "$STAGING/"

TRANSFERRED="$(find "$STAGING" -type f -print | sed "s#^$STAGING/##" | sort)"

echo "== the fix: scripts/vault/ (the TOOL) still ships ================="
assert_in_list "scripts/vault/vault.sh transferred" "$TRANSFERRED" "scripts/vault/vault.sh"
assert_in_list "scripts/vault/lib.sh transferred" "$TRANSFERRED" "scripts/vault/lib.sh"
assert_in_list "scripts/vault/public-names.txt transferred" "$TRANSFERRED" "scripts/vault/public-names.txt"

echo "== other files this manifest must still ship ======================"
assert_in_list "scripts/scrub-check.sh transferred" "$TRANSFERRED" "scripts/scrub-check.sh"
assert_in_list "scripts/git-hooks/pre-commit transferred" "$TRANSFERRED" "scripts/git-hooks/pre-commit"
assert_in_list "hooks/vault-write-gate.sh transferred" "$TRANSFERRED" "hooks/vault-write-gate.sh"
assert_in_list "templates/env.local.sh.template transferred" "$TRANSFERRED" "templates/env.local.sh.template"

echo "== the bug: root-level runtime dir/file stay excluded =============="
assert_not_in_list "root vault/secret-fixture excluded" "$TRANSFERRED" "vault/secret-fixture"
assert_not_in_list "root env.local.sh excluded" "$TRANSFERRED" "env.local.sh"

echo ""
echo "publish-manifest-regression: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0
exit 1
