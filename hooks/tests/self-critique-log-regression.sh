#!/bin/bash
# self-critique-log-regression.sh - regression suite for hooks/self-critique-log.sh
# (Stop hook. Appends one single-line JSON record per session to
# $HOME/.claude/global-observation/self-critique.jsonl and prints a note only when
# uncommitted files > 5 AND recent edits > 20. recent_edits counts the session's own
# Edit/Write lines in signals.jsonl (IMP-082); with no session_id it falls back to a
# tail-1000 proxy.) Every case runs in a fresh throwaway HOME and git project dir.
# Usage: bash hooks/tests/self-critique-log-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../self-critique-log.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/self-critique-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
N=0

# new_case: fresh HOME, git project on branch feat-x, no signals yet
new_case() {
    N=$((N+1)); CASE="$WORK/c$N"
    FAKE_HOME="$CASE/home"; PROJ="$CASE/proj"
    mkdir -p "$FAKE_HOME/.claude/global-observation" "$PROJ"
    git init -q "$PROJ" && git -C "$PROJ" symbolic-ref HEAD refs/heads/feat-x
    LOGF="$FAKE_HOME/.claude/global-observation/self-critique.jsonl"
    SIGF="$FAKE_HOME/.claude/global-observation/signals.jsonl"
}
add_untracked() { local i; for i in $(seq 1 "$1"); do : > "$PROJ/f$i.txt"; done; }
add_signal() { printf '{"session_id":"%s","tool":"%s"}\n' "$1" "$2" >> "$SIGF"; }
# run_hook <stdin-text> -> sets RC, OUT (stdout), ERR (stderr); runs in $PROJ
run_hook() {
    OUT=$(printf '%s' "$1" | (cd "$PROJ" && env -i HOME="$FAKE_HOME" PATH="$PATH" bash "$HOOK") 2>"$CASE/err"); RC=$?
    ERR=$(cat "$CASE/err")
}
last_line() { tail -1 "$LOGF"; }
field() { jq -r ".$1" <<< "$(last_line)"; }
pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s out=%s err=%s)\n' "$1" "$RC" "$OUT" "$ERR"; }

echo "-- self-critique-log.sh regression --"

# Acting path: one valid single-line JSON record with git and per-session counts.
new_case; add_untracked 2
add_signal s1 Edit; add_signal s1 Write; add_signal s1 Read
run_hook '{"session_id":"s1"}'
if [[ "$RC" -eq 0 && "$(wc -l < "$LOGF" | tr -d ' ')" -eq 1 ]] \
   && jq -e . <<< "$(last_line)" >/dev/null 2>&1 \
   && [[ "$(field session_id)" == s1 && "$(field branch)" == feat-x \
      && "$(field uncommitted_files)" == 2 && "$(field recent_edits)" == 2 ]] \
   && [[ "$OUT" == *"Session-end log"* ]]; then
    pass "acting: one JSON record (branch, 2 uncommitted, 2 session edits), rc 0"
else fail "acting: one JSON record (branch, 2 uncommitted, 2 session edits), rc 0"; fi

# Quiet path: below both thresholds, the record is written but no note is printed.
new_case; add_untracked 2
run_hook '{"session_id":"s2"}'
if [[ "$RC" -eq 0 && "$OUT" != *"Note:"* && "$(field recent_edits)" == 0 ]]; then
    pass "quiet: below thresholds, record written, no Note line"
else fail "quiet: below thresholds, record written, no Note line"; fi

# Edge (IMP-082): recent_edits counts only the current session, not other sessions.
new_case
add_signal s1 Edit; add_signal s1 Read; add_signal s2 Edit; add_signal s2 Write; add_signal s2 Edit
run_hook '{"session_id":"s1"}'
if [[ "$RC" -eq 0 && "$(field recent_edits)" == 1 ]]; then
    pass "per-session count: s1 sees 1 edit, s2's 3 edits are excluded"
else fail "per-session count: s1 sees 1 edit, s2's 3 edits are excluded"; fi

# Threshold note: more than 5 uncommitted and more than 20 session edits.
new_case; add_untracked 6
for _ in $(seq 1 21); do add_signal s3 Edit; done
run_hook '{"session_id":"s3"}'
if [[ "$RC" -eq 0 && "$OUT" == *"Note: 6 uncommitted files with 21 recent edits"* ]]; then
    pass "over both thresholds: Note line printed"
else fail "over both thresholds: Note line printed"; fi

# Empty stdin: no session id, so the record has an empty session_id; rc 0.
new_case
add_signal s4 Edit; add_signal s5 Write
run_hook ""
if [[ "$RC" -eq 0 && "$(wc -l < "$LOGF" | tr -d ' ')" -eq 1 \
   && "$(field session_id)" == "" && "$(field recent_edits)" == 2 ]]; then
    pass "empty stdin: record with empty session_id, proxy count 2, rc 0"
else fail "empty stdin: record with empty session_id, proxy count 2, rc 0"; fi

# Malformed JSON on stdin: same fallback as empty input, rc 0, one valid record.
new_case
run_hook '{"session_id": '
if [[ "$RC" -eq 0 && "$(wc -l < "$LOGF" | tr -d ' ')" -eq 1 ]] \
   && jq -e . <<< "$(last_line)" >/dev/null 2>&1 && [[ "$(field session_id)" == "" ]]; then
    pass "malformed JSON: one valid record with empty session_id, rc 0"
else fail "malformed JSON: one valid record with empty session_id, rc 0"; fi

# No Edit/Write line for the session (signals exist, none match): rc 0, record with 0 edits.
# Under set -euo pipefail a grep -c with no match used to end the hook with exit 1.
new_case
add_signal s6 Read; add_signal s6 Grep; add_signal s7 Edit
run_hook '{"session_id":"s6"}'
if [[ "$RC" -eq 0 && "$(wc -l < "$LOGF" | tr -d ' ')" -eq 1 && "$(field recent_edits)" == 0 ]]; then
    pass "no Edit line for the session: rc 0, one record with recent_edits 0"
else fail "no Edit line for the session: rc 0, one record with recent_edits 0"; fi

# Same without a session id (tail-1000 proxy) and no Edit/Write line anywhere: rc 0.
new_case
add_signal s8 Read
run_hook ""
if [[ "$RC" -eq 0 && "$(wc -l < "$LOGF" | tr -d ' ')" -eq 1 && "$(field recent_edits)" == 0 ]]; then
    pass "no session id and no Edit line in signals: rc 0, one record with recent_edits 0"
else fail "no session id and no Edit line in signals: rc 0, one record with recent_edits 0"; fi

echo "-- summary --"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
