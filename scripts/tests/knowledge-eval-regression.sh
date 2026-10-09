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

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check() { local l="$1" d="$2"; if eval "$3"; then ok "$l"; else bad "$l" "$d"; fi; }
summary() {
  echo
  echo "knowledge-eval-regression: $PASS passed, $FAIL failed"
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
summary
