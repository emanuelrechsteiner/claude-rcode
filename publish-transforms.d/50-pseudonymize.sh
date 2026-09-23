#!/usr/bin/env bash
# 50-pseudonymize.sh — replace private project/location names with neutral
# placeholders, driven by a PRIVATE, NEVER-VERSIONED name list.
#
# WHY THIS IS SEPARATE FROM 30-placeholder-scan.sh: that script's rules are
# a deliberately SHORT, HARDCODED list — each rule's real-value literal is
# baked into the tracked source because the values it clears (a machine
# username, a volume name, two retired identity fragments, one project
# codename in a security comment) are few, stable, and safe to keep in a
# public file BECAUSE `hooks/security-audit.sh`'s secret-shaped patterns
# don't match plain names. This script covers a different, much longer-
# tailed category: real project/client codenames that accumulate over time
# as evidence in rule prose, ledger history, and agent transcripts (~85
# occurrences across 34 files measured 2026-09-23; see the private list
# file's header). Hardcoding THAT list here would defeat its own purpose —
# the list of private names would itself ship in a tracked file. So the
# names live in a git-ignored, never-published TSV
# (publish-pseudonyms.local.tsv, repo root) and this script's OWN SOURCE
# contains zero real private terms — only generic mechanics. Verify this
# claim yourself: `grep -f <(cut -f1 publish-pseudonyms.local.tsv)
# publish-transforms.d/50-pseudonymize.sh` must report nothing.
#
# FAIL LOUD ON A MISSING LIST: this transform does NOT silently no-op when
# the private list is absent — an empty pseudonymization pass would let
# every name below sail through to the public tree with nobody the wiser.
# Missing list -> hard FAIL (exit 1). If you genuinely want to publish
# without pseudonymizing (e.g. a from-scratch fork with no private names
# yet), create an empty (comments-only) list file explicitly — an
# intentional empty list is not the same as a missing one, and this script
# treats them differently on purpose.
#
# LIST FORMAT: see the header comment in publish-pseudonyms.local.tsv
# itself (repo root) — "<real term>\t<placeholder>" per line, '#' comments,
# blank lines ignored.
#
# MATCHING: every real term is a LITERAL substring match (perl \Q...\E, no
# regex interpretation, no word-boundary) — same style as
# 30-placeholder-scan.sh, for the same reason (a name can appear inside an
# identifier, a path segment, or free prose, and word-boundary rules would
# have to special-case all three). Rules are applied LONGEST-REAL-TERM-
# FIRST regardless of the list file's own line order, so a short term that
# happens to be a substring of a longer one (e.g. a bare project codename
# that is itself a prefix of a longer "<codename>-Server" variant) can
# never corrupt an already-applied longer replacement — the longer one is
# always substituted first, leaving nothing for the shorter rule to
# (mis)match inside it.
#
# SELF-EXCLUSION: scripts/scrub-check.sh and scripts/scrub-allowlist.txt
# are skipped by this transform, mirroring scrub-check.sh's own SELF_EXCLUDE
# for its PII/rebrand scan. scrub-check.sh's existing _proj_a.._proj_h
# fragment-assembled literals are deliberately split so the file's raw
# bytes never contain their own flagged substrings contiguously — but nothing
# stops a SHORTER, unrelated real term below from landing inside one of those
# splits by coincidence (this happened during this transform's own build:
# a bare project-name term happened to be a byte-contiguous substring of an
# existing fragment there). Rewriting that file's bytes here would corrupt a
# security-relevant literal outside this transform's remit. This transform
# itself (this file) is also excluded from its own run for the same reason
# stated in the header above — it must never come to contain a real term.
#
# Usage: 50-pseudonymize.sh <staging-dir>
set -euo pipefail

STAGING="${1:?usage: $0 <staging-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$REPO_ROOT/publish-pseudonyms.local.tsv"

if [[ ! -f "$LIST" ]]; then
  echo "50-pseudonymize: FAIL — $LIST not found." >&2
  echo "  This is fatal, not a skip: without this list, private project/" >&2
  echo "  location names would ship into the public tree unmasked. Create" >&2
  echo "  the file locally (see docs/PUBLISHING.md \"Pseudonymization\" for" >&2
  echo "  the format) — or, if this fork genuinely has no private names yet," >&2
  echo "  create an empty (comments-only) file to make that explicit." >&2
  exit 1
fi

# Self-excluded files: relative to $STAGING, matched by exact suffix so this
# works regardless of how $STAGING is rooted.
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

# ---------------------------------------------------------------------------
# Parse the list into two parallel arrays, skipping comments/blank lines.
# Not using an associative array — bash 3.2 (stock macOS) doesn't have one.
# ---------------------------------------------------------------------------
TERMS=()
PLACEHOLDERS=()
while IFS=$'\t' read -r term placeholder; do
  [[ -z "$term" || "$term" == \#* ]] && continue
  if [[ -z "${placeholder:-}" ]]; then
    echo "50-pseudonymize: FAIL — malformed line in $LIST (missing TAB or placeholder): '$term'" >&2
    exit 1
  fi
  TERMS+=("$term")
  PLACEHOLDERS+=("$placeholder")
done < "$LIST"

if [[ ${#TERMS[@]} -eq 0 ]]; then
  echo "50-pseudonymize: OK — $LIST is present but empty (comments/blank only); nothing to pseudonymize (explicit, not a silent skip)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Sort indices by descending term length (longest-first application) —
# bash 3.2 has no native sort-by-key, so shell out to `sort` via a
# length<TAB>index stream.
# ---------------------------------------------------------------------------
ORDER=()
while IFS= read -r idx; do
  [[ -n "$idx" ]] && ORDER+=("$idx")
done < <(
  i=0
  while [[ $i -lt ${#TERMS[@]} ]]; do
    printf '%d\t%d\n' "${#TERMS[$i]}" "$i"
    i=$((i + 1))
  done | sort -rn -k1,1 | cut -f2
)

# ---------------------------------------------------------------------------
# is_text_file <path> — text/binary classifier, deliberately `git grep
# --no-index -I`, NOT plain `grep -I` (found 2026-09-23 auditing
# scheduled-tasks/daily-docs/bin/logbook-count.sh: that file embeds 5
# literal NUL bytes on purpose, at byte offset ~20088, as field separators
# inside a `python3 -c "...".join(...)` one-liner in its own source — it is
# unambiguously a text/source file, and `git`'s binary heuristic samples
# only a bounded prefix and agrees, but PLAIN `grep -I` scans the whole
# file, hits the NUL, and calls the entire file binary). That mismatch
# matters here specifically because scripts/scrub-check.sh's
# --require-pseudonym-list gate (the check this transform exists to satisfy
# — see the file header) scans the staging tree with `git grep -nIF`, i.e.
# with GIT's classifier. If this transform used the plain-grep classifier
# instead, it would silently skip rewriting a file the gate then reads as
# text and flags as a leak — the writer and the reader disagreeing about
# what counts as text is exactly the failure mode
# rules/testing-quality.md's "Verify Via the Same Code Path, Not a
# Reimplementation" warns about, so both sides now share one classifier.
# `git -C "$(dirname ...)"` (not a bare `git grep --no-index` from whatever
# the caller's cwd happens to be) is required: `--no-index` still refuses a
# target outside the invoking process's OWN repository if the cwd sits
# inside one (the staging tree is a plain extracted directory with no
# `.git` at the point this transform runs, but the shell invoking this
# script may itself be sitting inside THIS repo) — anchoring to the
# target's own directory sidesteps that repo-boundary check entirely.
# ---------------------------------------------------------------------------
is_text_file() {
  local f="$1"
  git -C "$(dirname -- "$f")" grep --no-index -Iq . -- "$(basename -- "$f")" 2>/dev/null
}

# ---------------------------------------------------------------------------
# apply_rule <find> <replace> — same file-selection logic as
# 30-placeholder-scan.sh (skip .git, skip binaries via `is_text_file`, skip
# self-excluded files), literal substring match via perl \Q...\E.
#
# WHY THE PERL CALL GOES THROUGH $ENV, NOT SHELL INTERPOLATION (2026-09-23):
# the previous form built the perl SOURCE by bash-interpolating $find/$replace
# directly into the -e string ("s/\Q${find}\E/${replace}/g"). That makes any
# character in a real term or its placeholder part of the perl CODE, not
# data — a "/" in $find closes the s/// pattern early and corrupts or aborts
# the substitution, and a "$"/"@" in $replace is interpolated by perl as a
# variable/array sigil inside the replacement (which is itself a double-
# quote-like context). Passing both as environment variables and reading
# them back via \Q$ENV{...}\E (pattern) / $ENV{...} (replacement) fixes
# this structurally: the perl SOURCE text is now the same fixed string on
# every call ('s/\Q$ENV{PSEUDO_FIND}\E/$ENV{PSEUDO_REPLACE}/g'), compiled
# once with "/" as delimiter regardless of what the terms contain; the
# actual term/placeholder values are fetched at RUN TIME as plain data and
# spliced in verbatim — \Q...\E still escapes regex metachars in the
# pattern, and the replacement side is a hash lookup, not a re-parsed
# string, so "$", "@", "\", "&" in the placeholder are inserted literally.
# ---------------------------------------------------------------------------
apply_rule() {
  local find="$1" replace="$2"
  local matches=0
  local binary_hits=()
  while IFS= read -r -d '' f; do
    case "$f" in */.git/*) continue ;; esac
    is_self_excluded "$f" && continue
    if is_text_file "$f"; then
      if grep -qF -- "$find" "$f" 2>/dev/null; then
        PSEUDO_FIND="$find" PSEUDO_REPLACE="$replace" \
          perl -pi -e 's/\Q$ENV{PSEUDO_FIND}\E/$ENV{PSEUDO_REPLACE}/g' "$f"
        matches=$((matches + 1))
      fi
    else
      # Binary file — never rewritten (perl -pi on binary content risks
      # corrupting it), but a real term hit inside one must be reported
      # LOUDLY, not silently dropped: a skipped check must never look like
      # a clean one (rules/fail-loud.md).
      if grep -qaF -- "$find" "$f" 2>/dev/null; then
        binary_hits+=("$f")
      fi
    fi
  done < <(find "$STAGING" -type f -print0)
  echo "50-pseudonymize: '${find}' -> '${replace}': ${matches} file(s)"
  if [[ ${#binary_hits[@]} -gt 0 ]]; then
    echo "50-pseudonymize: WARNING — '${find}' also found inside ${#binary_hits[@]} BINARY file(s), left untouched (not text-safe to rewrite):" >&2
    local bf
    for bf in "${binary_hits[@]}"; do
      echo "  $bf" >&2
    done
  fi
}

echo "50-pseudonymize: applying ${#TERMS[@]} rule(s) from $LIST (longest-term-first)"
for idx in "${ORDER[@]}"; do
  apply_rule "${TERMS[$idx]}" "${PLACEHOLDERS[$idx]}"
done

echo "50-pseudonymize: OK"
