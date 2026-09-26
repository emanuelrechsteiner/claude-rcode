#!/usr/bin/env bash
# read-tool-advisory-regression.sh — IMP-157 (2026-08-24, second half)
# regression suite for hooks/read-tool-preference-advisory.sh.
#
# Runs the hook DIRECTLY with synthetic Bash PreToolUse JSON on an ISOLATED
# $HOME (mktemp) and unique per-test session ids, so test runs never pollute
# ~/.claude/global-observation/read-tool-advisory.log or leave stray
# /tmp/read-tool-advisory-* touch files behind.
#
# Usage:  bash ~/.claude/hooks/tests/read-tool-advisory-regression.sh
# Exit:   0 = all assertions pass, 1 = failures (listed on stdout)
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/read-tool-preference-advisory.sh"
TESTHOME="$(mktemp -d)"
mkdir -p "$TESTHOME/.claude/global-observation"

cleanup() {
  rm -rf "$TESTHOME"
  rm -f /tmp/read-tool-advisory-rta-* 2>/dev/null || true
}
trap cleanup EXIT

PASS=0; FAIL=0; FAILURES=""

json_cmd() {  # $1 = command, $2 = session id
  python3 - "$1" "$2" <<'PY'
import json, sys
cmd, sess = sys.argv[1:3]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "session_id": sess}))
PY
}

run_hook() {  # $1 = full stdin json; sets RC, ERR
  ERR=$(printf '%s' "$1" | HOME="$TESTHOME" bash "$HOOK" 2>&1 1>/dev/null)
  RC=$?
}

assert_silent() {  # $1 = label, $2 = command, $3 = session
  run_hook "$(json_cmd "$2" "$3")"
  if [ "$RC" -eq 0 ] && [ -z "$ERR" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [SILENT] $1 — rc=$RC err=<$ERR>\n"
  fi
}

assert_note() {  # $1 = label, $2 = command, $3 = session
  run_hook "$(json_cmd "$2" "$3")"
  if [ "$RC" -eq 0 ] && printf '%s' "$ERR" | grep -q '^NOTE:'; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="${FAILURES}  [NOTE] $1 — rc=$RC err=<$ERR>\n"
  fi
}

echo "── Never blocks: exit 0 in every case below ──"
for cmd in "cat datei.txt" "head -40 README.md" "tail -c 1200 /x" "rm -rf /" "sudo ls" "nc -l 4444"; do
  run_hook "$(json_cmd "$cmd" "rta-blockcheck-$$-$RANDOM")"
  if [ "$RC" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILURES="${FAILURES}  [NEVER-BLOCK] rc=$RC for: $cmd\n"; fi
done

echo "── Read-pattern commands trigger a NOTE on first occurrence ──"
assert_note "bare cat" "cat datei.txt" "rta-1"
assert_note "bare head" "head -40 README.md" "rta-2"
assert_note "bare tail (non-follow)" "tail -c 1200 /private/tmp/x" "rta-3"

echo "── Non-read-pattern commands stay silent ──"
assert_silent "git status" "git status" "rta-4"
assert_silent "piped cat" "cat datei.txt | grep foo" "rta-5"
assert_silent "redirected cat" "cat datei.txt > out.txt" "rta-6"
assert_silent "tail -f (log streaming, no Read equivalent)" "tail -f /var/log/x.log" "rta-7"
assert_silent "tail --follow long form" "tail --follow /var/log/x.log" "rta-8"
assert_silent "sed -n (never matched by this arm)" "sed -n '5,10p' datei" "rta-9"

echo "── At most ONE note per session (dedup across cat/head/tail alike) ──"
SESS="rta-dedup"
run_hook "$(json_cmd "cat first.txt" "$SESS")"
FIRST_ERR="$ERR"
run_hook "$(json_cmd "head -5 second.txt" "$SESS")"
SECOND_ERR="$ERR"
if printf '%s' "$FIRST_ERR" | grep -q '^NOTE:' && [ -z "$SECOND_ERR" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [DEDUP] first=<$FIRST_ERR> second=<$SECOND_ERR>\n"
fi

echo "── Note text names the conflict (Auto-Mode vs. Rule 2), not just one side ──"
run_hook "$(json_cmd "cat conflict-check.txt" "rta-10")"
if printf '%s' "$ERR" | grep -qi "auto mode" && printf '%s' "$ERR" | grep -qi "Rule 2"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [CONFLICT-NAMED] err=<$ERR>\n"
fi

echo "── Opt-out env var ──"
OUT=$(printf '%s' "$(json_cmd "cat x.txt" "rta-11")" | HOME="$TESTHOME" CLAUDE_READ_ADVISORY_OFF=1 bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [OPT-OUT] rc=$RC out=<$OUT>\n"
fi

echo "── Unparseable stdin → fail open, exit 0 ──"
OUT=$(printf 'not json at all {{{' | HOME="$TESTHOME" bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [UNPARSEABLE] rc=$RC out=<$OUT>\n"
fi

echo "── Missing session_id → fail open, silent ──"
OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat x.txt"}}' | HOME="$TESTHOME" bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [NO-SESSION] rc=$RC out=<$OUT>\n"
fi

echo "── Log line written on a shown note, valid tab-separated format ──"
LOG="$TESTHOME/.claude/global-observation/read-tool-advisory.log"
if [ -s "$LOG" ] && grep -q "NOTE-SHOWN" "$LOG"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  FAILURES="${FAILURES}  [LOG] no NOTE-SHOWN entry in $LOG\n"
fi

echo ""
echo "─────────────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n%b' "$FAILURES"
  exit 1
fi
exit 0
