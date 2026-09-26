#!/usr/bin/env bash
# 50-pseudonymize.sh — replace every real vault term with its token across
# the staging tree, using the SAME matcher every other vault consumer uses
# (scripts/vault/lib.sh's vault_matcher_run, "tokenize" mode —
# rules/testing-quality.md "Verify Via the Same Code Path", no second,
# independently-written substitution routine).
#
# HISTORY (2026-09-25 rework round 5): this transform used to run TWO
# passes — a vault-sourced "Pass 0", then a "second net" that re-read
# publish-pseudonyms.local.tsv (a private, never-versioned TSV) and applied
# its own separate literal-substring substitution. The second pass is
# REMOVED here, not merely disabled: `vault.sh init --import-legacy` is now
# the list's ONLY consumer (it was always meant to be an IMPORT source
# feeding the vault, not a second parallel enforcement mechanism running
# forever alongside it — see plans/vault-by-design-2026-09-25.md §2). Two
# reasons this needed to actually happen, not just be tolerated:
#   1. The second pass had NO allowlist and NO word-boundary awareness
#      (plain `perl \Q...\E` substring match) — it rewrote D7's protected
#      attribution lines (LICENSE:3, README.md:238) whenever the list
#      happened to contain a term appearing there, independently of
#      whatever the vault pass had already decided to protect.
#   2. Once a legacy-list term becomes PUBLIC (e.g. a name the project
#      later starts using in its own public identity/tooling), the vault
#      import correctly excludes it (scripts/vault/public-names.txt), but
#      the second pass had no such concept and kept rewriting it forever —
#      measured live: 14 files including this repo's own
#      scripts/vault/public-names.txt and scripts/tests/vault-regression.sh
#      changed on a clean `git archive HEAD` specifically because of this.
# A missing vault remains FATAL (unchanged from before): this transform's
# whole job is neutralizing real values before they reach the public tree,
# so silently skipping would ship whatever it alone would have caught,
# unmasked, with no second net left to catch it.
#
# D7 (LICENSE/README.md keep one real surname on purpose) no longer needs a
# two-rules-file special case here either (removed — see git history before
# 2026-09-25 for the prior mechanism): scripts/vault/lib.sh's `tokenize`
# mode now consults the SAME allowlist `check` does directly (round 5,
# finding #1) — the allowlist is the only exemption mechanism, applied
# uniformly to every file through the one rules file below.
#
# Usage: 50-pseudonymize.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Self-excluded files: relative to $STAGING, matched by exact suffix so this
# works regardless of how $STAGING is rooted. This transform's own source
# is excluded for the same reason scrub-check.sh excludes itself: it
# legitimately discusses what it does; that is not a leak.
SELF_EXCLUDE_REL=(
  "scripts/scrub-check.sh"
  "scripts/scrub-allowlist.txt"
  "publish-transforms.d/50-pseudonymize.sh"
)

is_self_excluded() {
  local f="$1" rel
  for rel in "${SELF_EXCLUDE_REL[@]}"; do
    case "$f" in
      "$STAGING/$rel") return 0 ;;
    esac
  done
  return 1
}

# is_text_file <path> — text/binary classifier, deliberately `git grep
# --no-index -I`, NOT plain `grep -I` (found 2026-09-23 auditing
# scheduled-tasks/daily-docs/bin/logbook-count.sh: that file embeds 5
# literal NUL bytes on purpose, as field separators inside a python
# one-liner in its own source — unambiguously a text/source file, but plain
# `grep -I` samples the whole file, hits the NUL, and calls it binary,
# while `git`'s classifier samples only a bounded prefix and agrees it's
# text). scrub-check.sh's own leak checks scan with `git grep`, so both
# sides must share one classifier (rules/testing-quality.md "Verify Via the
# Same Code Path") or a file one side calls text and the other calls binary
# would silently go unrewritten yet still get flagged, or vice versa.
# `git -C "$(dirname ...)"` (not a bare `git grep --no-index` from the
# caller's cwd) is required: `--no-index` still refuses a target outside
# the invoking process's OWN repository if the cwd sits inside one, and the
# staging tree has no `.git` of its own at the point this transform runs.
is_text_file() {
  local f="$1"
  git -C "$(dirname -- "$f")" grep --no-index -Iq . -- "$(basename -- "$f")" 2>/dev/null
}

VAULT_LIB="$REPO_ROOT/scripts/vault/lib.sh"
if [[ ! -f "$VAULT_LIB" ]]; then
  echo "50-pseudonymize: FAIL — $VAULT_LIB not found." >&2
  exit 1
fi
# shellcheck source=../scripts/vault/lib.sh
. "$VAULT_LIB"
if ! vault_exists; then
  echo "50-pseudonymize: FAIL — no vault at $(vault_dir)." >&2
  echo "  This is fatal, not a skip: without it, every real value this" >&2
  echo "  transform is responsible for would ship into the public tree" >&2
  echo "  unmasked, with no second net left to catch it. Run:" >&2
  echo "  scripts/vault/vault.sh init" >&2
  exit 1
fi

ALLOWLIST="$REPO_ROOT/scripts/scrub-allowlist.txt"
[[ -f "$ALLOWLIST" ]] || ALLOWLIST=""

_vault_rules="$(mktemp "${TMPDIR:-/tmp}/pseudonymize-vault-rules.XXXXXX")"
vault_build_rules_file "$_vault_rules"

_vault_tok_files=0
while IFS= read -r -d '' f; do
  case "$f" in */.git/*) continue ;; esac
  is_self_excluded "$f" && continue
  is_text_file "$f" || continue
  _vault_tmp_out="$(mktemp "${TMPDIR:-/tmp}/pseudonymize-vault-out.XXXXXX")"
  if vault_matcher_run tokenize 0 "${f#"$STAGING"/}" "$_vault_rules" "$ALLOWLIST" 0 < "$f" > "$_vault_tmp_out"; then
    if cmp -s "$f" "$_vault_tmp_out"; then
      rm -f "$_vault_tmp_out"
    else
      # Preserve the original file's mode across the swap — see
      # scripts/vault/vault.sh's cmd_tokenize --in-place for the same fix
      # and its rationale (round 5, finding #2): mktemp+mv unconditionally
      # left mktemp's 0600 behind, silently stripping an executable
      # script's bits.
      _orig_mode="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)"
      mv "$_vault_tmp_out" "$f"
      [[ -n "$_orig_mode" ]] && chmod "$_orig_mode" "$f"
      _vault_tok_files=$((_vault_tok_files + 1))
    fi
  else
    rm -f "$_vault_tmp_out"
  fi
done < <(find "$STAGING" -type f -print0)
rm -f "$_vault_rules"
echo "50-pseudonymize: tokenized ${_vault_tok_files} file(s) (all vault kinds; allowlisted lines exempt)"

echo "50-pseudonymize: OK"
