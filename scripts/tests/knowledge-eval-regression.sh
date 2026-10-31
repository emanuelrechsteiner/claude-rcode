#!/usr/bin/env bash
# knowledge-eval-regression.sh - regression suite for scripts/knowledge-eval.sh (the retrieval ruler).
#
# Pins: hit@1, hit@3-only, miss, "-" unscored rows, structural SKIP, "|" alternatives, unknown extra
# columns ignored, quoted phrases kept whole, unconfirmed counting, the tta proxy, EVAL SKIP + exit 3,
# malformed-input exits, --no-history and the 11-column history line.
#
# MECHANICS - synthetic library under mktemp -d; the REAL eval script and the REAL knowledge-lookup.sh
# run under /bin/bash (no reimplementation). Never touches the real library. bash 3.2 compatible.
# Usage: /bin/bash scripts/tests/knowledge-eval-regression.sh
# check() evals its condition lazily: single-quoted conditions are expanded at eval time.
# shellcheck disable=SC2016 # single quotes are intended: eval bodies expand at run time
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVAL="$REPO_ROOT/scripts/knowledge-eval.sh"
LK="$REPO_ROOT/scripts/knowledge-lookup.sh"

PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check() { local l="$1" d="$2"; if eval "$3"; then ok "$l"; else bad "$l" "$d"; fi; }
summary() {
  echo
  echo "knowledge-eval-regression: $PASS passed, $FAIL failed"
  [ "$SKIP" -eq 0 ] || echo "knowledge-eval-regression: $SKIP skipped (see NOTE above)"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

for f in "$EVAL" "$LK"; do
  [ -f "$f" ] || { bad "script under test exists" "not found: $f"; summary; }
done
T="$(mktemp -d "${TMPDIR:-/tmp}/ke-regress.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

echo "-- knowledge-eval.sh --"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/ke-fixtures.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/ke-cases.sh"

# ---- locale: the EVAL line keeps a decimal point under a comma-decimal locale (IMP-254) ----
# alphatok is rank 1 and betatok's b3 is rank 3 -> mrr10 = (1 + 1/3) / 2 = 0.667
echo "-- knowledge-eval.sh under a comma-decimal locale --"
LOC_DE=""
LOCALES=$(locale -a 2>/dev/null) || LOCALES=""   # here-string, not a pipe: grep -q under pipefail would SIGPIPE locale
for cand in de_DE.UTF-8 de_DE.utf8; do
  if grep -qx "$cand" <<< "$LOCALES"; then LOC_DE=$cand; break; fi
done
if [ -n "$LOC_DE" ]; then
  LQ="$T/q-locale.tsv"
  mkq "$LQ" "$(qrow LC1 dev alphatok memory/p/a1.md lookup yes)" "$(qrow LC2 dev betatok memory/p/b3.md lookup yes)"
  LC_ALL="$LOC_DE" CLAUDE_KNOWLEDGE_DIR="$K" /bin/bash "$EVAL" --set dev --questions "$LQ" --no-history >"$OUT" 2>"$ERR" </dev/null
  RC=$?
  check "EVAL line under $LOC_DE keeps a point: mrr10=0.667, no decimal comma" "rc=$RC $(cat "$OUT" "$ERR")" 'test "$RC" -eq 0 && evalline | grep -qF " mrr10=0.667 " && ! evalline | grep -q "mrr10=[0-9]*,"'
else
  SKIP=$((SKIP + 1))
  echo "  NOTE: no de_DE UTF-8 locale installed (locale -a); the EVAL decimal-comma case is NOT exercised"
fi

summary
