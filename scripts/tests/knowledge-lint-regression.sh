#!/usr/bin/env bash
# knowledge-lint-regression.sh — regression suite for scripts/knowledge-lint.sh (plan O6, O4
# item 4, O12, O8). Pins: every per-note code and exemption, the summary lines, each
# contradiction rule, each --refs outcome, each canned graph query, the missing-graph exit 1,
# the usage/IO exit codes and the "report never edits" guarantee.
#
# MECHANICS — synthetic HOME and knowledge dir under mktemp -d; the REAL script is called with
# /bin/bash (no reimplementation). Never touches the real ~/.claude or the real mirror. All
# values are invented. bash 3.2 compatible. Usage: /bin/bash scripts/tests/knowledge-lint-regression.sh
# check() evals its condition lazily: single-quoted conditions are expanded at eval time.
# shellcheck disable=SC2016 # single quotes are intended: eval bodies expand at run time
# shellcheck disable=SC2034 # variables are assigned for the files sourced into this shell
#
# LAYOUT — fixtures: scripts/tests/lib/klint-fixtures.sh; cases: scripts/tests/lib/klint-cases.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$REPO_ROOT/scripts/knowledge-lint.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \xe2\x9c\x85 %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \xe2\x9d\x8c %s\n     %s\n' "$1" "$2"; }
check() { local l="$1" d="$2"; if eval "$3"; then ok "$l"; else bad "$l" "$d"; fi; }
summary() {
  echo
  echo "knowledge-lint-regression: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

if [ ! -f "$LINT" ]; then bad "script under test exists" "script not found: $LINT"; summary; fi

T="$(mktemp -d "${TMPDIR:-/tmp}/klint-regress.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
H="$T/home"; OUT="$T/out"; ERR="$T/err"; mkdir -p "$H/.claude"

# lint <knowledge-root> [args...] -> $OUT, $ERR, $RC (HOME is the synthetic one)
lint() { local r=$1; shift; CLAUDE_KNOWLEDGE_DIR="$r" HOME="$H" /bin/bash "$LINT" "$@" > "$OUT" 2> "$ERR"; RC=$?; }
has() { grep -qE -- "$2" "$1"; }          # has <file> <ERE>
hasnt() { ! grep -qE -- "$2" "$1"; }
# line <SEV> <code> <path>: the report names exactly that finding
line() { has "$OUT" "^$1 $2 $3( |\$)"; }
noline() { hasnt "$OUT" "^[A-Z]+ $1 $2( |\$)"; }

# shellcheck source=lib/klint-fixtures.sh
. "$SCRIPT_DIR/lib/klint-fixtures.sh"
# shellcheck source=lib/klint-cases.sh
. "$SCRIPT_DIR/lib/klint-cases.sh"

summary
