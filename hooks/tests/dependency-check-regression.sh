#!/usr/bin/env bash
# dependency-check-regression.sh — jq-dependency suite (2026-11-06).
#
# Runs the hooks DIRECTLY on an ISOLATED $HOME with synthetic input, in two modes:
#   nojq — PATH holds a symlinked toolset WITHOUT jq (precondition-checked);
#   jq   — the normal PATH, where behaviour must be unchanged.
# Without jq: guard-unsafe and mcp-agency-gate fail CLOSED (deny, naming the fix);
# file-protection and parallel-lock-check stay fail-open but print a NOTE;
# dependency-check.sh warns at SessionStart.
#
# Usage:  bash hooks/tests/dependency-check-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)

set -u
export LC_ALL=C
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/.claude/global-observation"
BASH_BIN="$(type -P bash)"

# ── No-jq PATH: symlink every tool the hooks use, except jq ──
NOJQ_BIN="$TESTHOME/nojq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash cat date dirname grep sed awk tr head tail cut mkdir printf sort wc env sh python3 rm cp mv mktemp basename readlink stat sleep uname touch ls chmod id; do
    tool_path="$(type -P "$tool")"
    if [ -n "$tool_path" ]; then ln -sf "$tool_path" "$NOJQ_BIN/$tool"; fi
done
if [ -n "$(env -i PATH="$NOJQ_BIN" "$BASH_BIN" -c 'command -v jq' 2>/dev/null)" ]; then
    echo "FATAL: jq is still resolvable on the no-jq PATH; the suite would prove nothing."
    exit 1
fi

G="$HOOKS_DIR/guard-unsafe.sh"
M="$HOOKS_DIR/mcp-agency-gate.sh"
F="$HOOKS_DIR/file-protection.sh"
P="$HOOKS_DIR/parallel-lock-check.sh"
D="$HOOKS_DIR/dependency-check.sh"

PASS=0; FAIL=0; FAILURES=""
RC=0; OUT=""; ERR=""

run_hook() {  # $1 = nojq|jq, $2 = absolute hook path, $3 = JSON → sets RC OUT ERR
    local path_val="$PATH"
    if [ "$1" = "nojq" ]; then path_val="$NOJQ_BIN"; fi
    OUT=$(printf '%s' "$3" | env -i HOME="$TESTHOME" PATH="$path_val" LC_ALL=C "$BASH_BIN" "$2" 2>"$TESTHOME/stderr")
    RC=$?
    ERR=$(cat "$TESTHOME/stderr")
}

check() {  # $1 = label, $2... = condition (exit 0 = pass)
    local label="$1"; shift
    if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILURES="${FAILURES}  FAIL: ${label}\n"; fi
}

has() { printf '%s' "$1" | grep -qF -- "$2"; }  # has <text> <fixed substring>
silent() { [ -z "$OUT" ] && [ -z "$ERR" ]; }

echo "== no jq: fail-closed and loud fail-open"
run_hook nojq "$G" '{"tool_input":{"command":"ls"}}'
check "guard-unsafe no-jq: exit 2 (refuses even a benign command)" [ "$RC" -eq 2 ]
check "guard-unsafe no-jq: stderr names jq" has "$ERR" "jq is not installed"
check "guard-unsafe no-jq: stderr gives brew fix" has "$ERR" "brew install jq"
check "guard-unsafe no-jq: stdout empty" [ -z "$OUT" ]
run_hook nojq "$G" '{"tool_input":{"command":"rm -rf /"}}'
check "guard-unsafe no-jq: CRITICAL-floor command also refused" [ "$RC" -eq 2 ]

run_hook nojq "$M" '{"tool_name":"mcp__x__apply_migration","tool_input":{}}'
check "mcp-gate no-jq: exit 0 with a JSON decision" [ "$RC" -eq 0 ]
check "mcp-gate no-jq: permissionDecision deny" has "$OUT" '"permissionDecision":"deny"'
check "mcp-gate no-jq: reason names brew install jq" has "$OUT" "brew install jq"
run_hook nojq "$M" '{"tool_name":"mcp__x__list_tables","tool_input":{}}'
check "mcp-gate no-jq: read-only MCP call also denied" has "$OUT" '"permissionDecision":"deny"'

run_hook nojq "$F" '{"tool_input":{"file_path":"/x/.env"}}'
check "file-protection no-jq: fail-open exit 0" [ "$RC" -eq 0 ]
check "file-protection no-jq: NOTE names file-protection and jq" has "$ERR" "NOTE: file-protection.sh"
check "file-protection no-jq: NOTE gives brew fix" has "$ERR" "brew install jq"

run_hook nojq "$P" '{"tool_name":"Edit","tool_input":{"file_path":"/x/a.ts"},"session_id":"s1"}'
check "parallel-lock-check no-jq: fail-open exit 0" [ "$RC" -eq 0 ]
check "parallel-lock-check no-jq: NOTE names parallel-lock-check and jq" has "$ERR" "NOTE: parallel-lock-check.sh"
check "parallel-lock-check no-jq: NOTE gives brew fix" has "$ERR" "brew install jq"

run_hook nojq "$D" '{}'
check "dependency-check no-jq: exit 0 (non-blocking)" [ "$RC" -eq 0 ]
check "dependency-check no-jq: warns about jq" has "$OUT" "WARNING: jq is not installed"
check "dependency-check no-jq: warning gives brew fix" has "$OUT" "brew install jq"
check "dependency-check no-jq: warning names liveness check and Stop checks" has "$OUT" "routine liveness check and the batched Stop checks"

echo "== sourced helper missing (jq present): guard-unsafe fails closed"
NOLIB_DIR="$TESTHOME/nolib"
mkdir -p "$NOLIB_DIR"
cp "$G" "$NOLIB_DIR/guard-unsafe.sh"
run_hook jq "$NOLIB_DIR/guard-unsafe.sh" '{"tool_input":{"command":"ls"}}'
check "guard-unsafe helper missing: exit 2" [ "$RC" -eq 2 ]
check "guard-unsafe helper missing: stderr names normalize-command.sh" has "$ERR" "normalize-command.sh"

echo "== jq present: behaviour unchanged"
check "precondition: jq on the normal PATH" command -v jq
run_hook jq "$G" '{"tool_input":{"command":"ls"}}'
check "guard-unsafe jq: benign command exit 0" [ "$RC" -eq 0 ]
check "guard-unsafe jq: benign command silent" silent
run_hook jq "$G" '{"tool_input":{"command":"rm -rf /"}}'
check "guard-unsafe jq: rm -rf / still blocked (exit 2)" [ "$RC" -eq 2 ]
check "guard-unsafe jq: BLOCKED message unchanged" has "$ERR" "BLOCKED: Destructive rm -rf on critical path"

run_hook jq "$M" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check "mcp-gate jq: non-MCP tool exit 0" [ "$RC" -eq 0 ]
check "mcp-gate jq: non-MCP tool silent" silent
run_hook jq "$M" '{"tool_name":"mcp__x__apply_migration","tool_input":{}}'
check "mcp-gate jq: ESCALATE still asks" has "$OUT" 'permissionDecision": "ask"'

run_hook jq "$F" '{"tool_input":{"file_path":"/tmp/x.txt"}}'
check "file-protection jq: normal path exit 0" [ "$RC" -eq 0 ]
check "file-protection jq: normal path silent" silent
run_hook jq "$F" '{"tool_input":{"file_path":"/x/.env"}}'
check "file-protection jq: .env still blocked (exit 2)" [ "$RC" -eq 2 ]

run_hook jq "$P" '{"tool_name":"Edit","tool_input":{"file_path":"/x/a.ts"},"session_id":"s1"}'
check "parallel-lock-check jq: exit 0" [ "$RC" -eq 0 ]
check "parallel-lock-check jq: silent" silent

run_hook jq "$D" '{}'
check "dependency-check jq: exit 0" [ "$RC" -eq 0 ]
check "dependency-check jq: silent" silent

echo "── dependency-check-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
    printf "%b" "$FAILURES"
    exit 1
fi
exit 0
