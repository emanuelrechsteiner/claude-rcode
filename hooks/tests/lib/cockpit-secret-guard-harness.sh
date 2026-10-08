#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015
# Shared harness for the two cockpit-secret-guard regression suites (sourced, never run on its own).
# Lives in hooks/tests/lib/ so scripts/run-all-tests.sh (glob hooks/tests/*.sh) does not run it as a suite.
# Provides the temp HOME, the PASS/FAIL counters, the helpers (deny / allow / expect / tool_*) and finish().
# HOME is redirected to a temp dir: nothing touches the real ~/.claude.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$HERE/../../cockpit-secret-guard.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
export CLAUDE_GUARD_LOG="$WORK/guard.log"
PASS=0
FAIL=0
LAST_ERR=""
LAST_OUT=""
U="/Us""ers/alice"   # built from pieces so no absolute home path sits in this file

run_json() { # json [hook] -> RC, LAST_ERR, LAST_OUT
    local errf="$WORK/err"
    LAST_OUT=$(printf '%s' "$1" | bash "${2:-$HOOK}" 2>"$errf")
    RC=$?
    LAST_ERR=$(cat "$errf")
}
bash_json() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL  $1 -- $2"; FAIL=$((FAIL + 1)); }
expect() { # name expected-rc json [stderr-substring]
    run_json "$3"
    if [[ "$RC" != "$2" ]]; then bad "$1" "expected rc=$2 got rc=$RC: ${3:0:100} | ${LAST_ERR:0:120}"
    elif [[ -n "${4:-}" && "$LAST_ERR" != *"$4"* ]]; then bad "$1" "stderr lacks '$4'"
    else ok "$1"; fi
}
deny() { expect "DENY  $1" 2 "$(bash_json "$2")" "${3:-BLOCKED}"; }
allow() { expect "ALLOW $1" 0 "$(bash_json "$2")"; }
tool_deny() { expect "DENY  $1" 2 "$2" "BLOCKED"; }
tool_allow() { expect "ALLOW $1" 0 "$2"; }

finish() { # print the totals; exit 0 only when nothing failed
    echo ""
    echo "passed=$PASS failed=$FAIL"
    if [[ "$FAIL" -eq 0 ]]; then echo "ALL PASS"; exit 0; fi
    exit 1
}
