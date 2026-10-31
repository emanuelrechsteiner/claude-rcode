#!/bin/bash
# background-agent-check-regression.sh — regression suite for the P-IMP-260 Stop NOTE
# ─────────────────────────────────────────────────────────────────────────────
# Covers hooks/background-agent-check.sh only (pairing logic is covered by
# background-watchdog-regression.sh). Pins three things:
#   - Stop: a NOTE line appears exactly when open > 0 for THIS session, and
#     never when open == 0 (no false alarm on a clean session);
#   - Stop: the NOTE is not age-gated (a fresh open helper still prints it);
#   - UserPromptSubmit: never prints the NOTE; its JSON output stays valid.
#   - No tail window: this session's rows are found behind 600+ foreign rows
#     (cases 8-10; the old `tail -n 500` lost them).
#
# Fixture logs live in a mktemp directory under ${TMPDIR:-/tmp}; the hook is
# pointed there via CLAUDE_DISPATCH_LOG / CLAUDE_SUBAGENT_STOPS_LOG, so the
# real ~/.claude/global-observation/ is never read or written.
#
# BSD-only: the hook's age line uses `date -j`, and the UPS cases need it to
# produce JSON. On other platforms this suite exits 2 loudly instead of passing.
#
# Usage: bash hooks/tests/background-agent-check-regression.sh
# ─────────────────────────────────────────────────────────────────────────────
set -u

if ! date -u -j -f %s 0 +%s >/dev/null 2>&1; then
    printf 'FAIL: BSD date (date -j) required; this suite cannot run on this platform\n'
    exit 2
fi

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="${CLAUDE_BG_CHECK_HOOK:-$HOOKS_DIR/background-agent-check.sh}"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/bg-agent-check-regression.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export CLAUDE_DISPATCH_LOG="$SCRATCH/dispatch-capture.jsonl"
export CLAUDE_SUBAGENT_STOPS_LOG="$SCRATCH/subagent-stops.jsonl"
export CLAUDE_BG_STALE_MIN=20

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }

# ── helpers ──────────────────────────────────────────────────────────────
reset_logs() {
    : > "$CLAUDE_DISPATCH_LOG"
    : > "$CLAUDE_SUBAGENT_STOPS_LOG"
}

# ts_minutes_ago N -> ISO8601 UTC timestamp N minutes before now
ts_minutes_ago() {
    local now
    now=$(date -u +%s)
    date -u -j -f %s "$(( now - $1 * 60 ))" +%Y-%m-%dT%H:%M:%SZ
}

dispatch_row() {  # $1=session $2=ts
    jq -nc --arg sid "$1" --arg ts "$2" '{session_id:$sid, ts:$ts, tool_name:"Agent"}' >> "$CLAUDE_DISPATCH_LOG"
}

stop_row() {  # $1=session $2=ts
    jq -nc --arg sid "$1" --arg ts "$2" '{session_id:$sid, ts:$ts, status:"normal"}' >> "$CLAUDE_SUBAGENT_STOPS_LOG"
}

# run_hook EVENT SESSION -> sets OUT (stdout, trailing newlines stripped) and RC
run_hook() {
    local event="$1" sid="$2"
    OUT=$(jq -nc --arg ev "$event" --arg sid "$sid" '{hook_event_name:$ev, session_id:$sid, prompt:"x"}' \
        | bash "$CHECKER" 2>"$SCRATCH/stderr")
    RC=$?
}

NOTE_PREFIX="NOTE (P-IMP-260):"
note_for() {  # $1=count -> the exact NOTE line for N open helpers
    printf '%s %s helper(s) of this session may still be running — a "Done: yes" verdict is not valid until they have stopped.' "$NOTE_PREFIX" "$1"
}

echo "── background-agent-check regression (P-IMP-260 Stop NOTE) ──"

# 1. Stop, open == 0 (one dispatch, one stop, same session) -> no NOTE, empty stdout
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 2)"
stop_row "sess-A" "$(ts_minutes_ago 1)"
run_hook Stop "sess-A"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "Stop with open=0 prints nothing (no NOTE, exit 0)"
else
    bad "Stop with open=0 prints nothing" "rc=0, stdout empty" "rc=$RC, stdout=$OUT"
fi

# 2. Stop, open == 2 with fresh dispatches -> exactly one NOTE line, byte-exact
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 3)"
dispatch_row "sess-A" "$(ts_minutes_ago 2)"
dispatch_row "sess-A" "$(ts_minutes_ago 1)"
stop_row "sess-A" "$(ts_minutes_ago 1)"
run_hook Stop "sess-A"
EXPECT="$(note_for 2)"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$EXPECT" ]; then
    ok "Stop with open=2 (fresh) prints exactly the NOTE line with count 2"
else
    bad "Stop with open=2 prints the NOTE with count 2" "$EXPECT" "rc=$RC, stdout=$OUT"
fi

# 3. Stop, session scoping: sess-A has 1 open, sess-B has 4 open -> NOTE says 1
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 2)"
dispatch_row "sess-B" "$(ts_minutes_ago 2)"
dispatch_row "sess-B" "$(ts_minutes_ago 2)"
dispatch_row "sess-B" "$(ts_minutes_ago 2)"
dispatch_row "sess-B" "$(ts_minutes_ago 2)"
run_hook Stop "sess-A"
EXPECT="$(note_for 1)"
if [ "$OUT" = "$EXPECT" ]; then
    ok "NOTE counts only this session's open helpers (other session ignored)"
else
    bad "NOTE counts only this session's open helpers" "$EXPECT" "$OUT"
fi

# 4. Stop, open == 1 and stale (30 min) -> existing LINE1 first, NOTE second, nothing else
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 30)"
run_hook Stop "sess-A"
LINE_COUNT=$(printf '%s' "$OUT" | grep -c .)
SECOND=$(printf '%s\n' "$OUT" | sed -n 2p)
FIRST=$(printf '%s\n' "$OUT" | sed -n 1p)
if [ "$LINE_COUNT" -eq 2 ] && [ "$SECOND" = "$(note_for 1)" ] && printf '%s' "$FIRST" | grep -q '⏳'; then
    ok "Stop with a stale open helper prints the stale line, then the NOTE (2 lines)"
else
    bad "Stop stale: stale line then NOTE" "2 lines: ⏳ line, then $(note_for 1)" "$LINE_COUNT line(s): $OUT"
fi

# 5. UserPromptSubmit, open == 2, stale -> valid JSON, stale line present, no NOTE
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 30)"
dispatch_row "sess-A" "$(ts_minutes_ago 30)"
run_hook UserPromptSubmit "sess-A"
CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 \
   && printf '%s' "$CTX" | grep -q '⏳' && ! printf '%s' "$CTX" | grep -q 'NOTE (P-IMP-260)'; then
    ok "UserPromptSubmit stays JSON-valid and carries no NOTE"
else
    bad "UserPromptSubmit: valid JSON, stale line, no NOTE" "jq-valid JSON with ⏳ and no NOTE" "rc=$RC, stdout=$OUT"
fi

# 6. UserPromptSubmit, open == 2, fresh -> silent (NOTE is Stop-only, old exit preserved)
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 1)"
dispatch_row "sess-A" "$(ts_minutes_ago 1)"
run_hook UserPromptSubmit "sess-A"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "UserPromptSubmit with fresh open helpers prints nothing (no NOTE)"
else
    bad "UserPromptSubmit fresh open helpers print nothing" "rc=0, stdout empty" "rc=$RC, stdout=$OUT"
fi

# 7. Stop with the stops log missing -> silent, exit 0 (pre-existing early exit kept)
reset_logs
rm -f "$CLAUDE_SUBAGENT_STOPS_LOG"
dispatch_row "sess-A" "$(ts_minutes_ago 1)"
run_hook Stop "sess-A"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "Stop with missing stops log stays silent (exit 0)"
else
    bad "Stop with missing stops log stays silent" "rc=0, stdout empty" "rc=$RC, stdout=$OUT"
fi

# 8. Stop, open == 2 written FIRST, then 600 foreign dispatch rows -> NOTE count 2
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 3)"
dispatch_row "sess-A" "$(ts_minutes_ago 2)"
jq -nc --arg ts "$(ts_minutes_ago 1)" '[range(600)] | .[] | {session_id:"sess-foreign", ts:$ts, tool_name:"Agent"}' >> "$CLAUDE_DISPATCH_LOG"
run_hook Stop "sess-A"
EXPECT="$(note_for 2)"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$EXPECT" ]; then
    ok "Stop: NOTE survives 600 foreign dispatch rows written after this session's rows"
else
    bad "Stop: NOTE behind 600 foreign dispatch rows" "$EXPECT" "rc=$RC, stdout=$OUT"
fi

# 9. Stop, stale open helper written FIRST, then 600 foreign dispatch rows ->
#    the stale ⏳ line (oldest-age pairing) and the NOTE both still print
reset_logs
dispatch_row "sess-A" "$(ts_minutes_ago 30)"
jq -nc --arg ts "$(ts_minutes_ago 1)" '[range(600)] | .[] | {session_id:"sess-foreign", ts:$ts, tool_name:"Agent"}' >> "$CLAUDE_DISPATCH_LOG"
run_hook Stop "sess-A"
LINE_COUNT=$(printf '%s' "$OUT" | grep -c .)
if [ "$RC" -eq 0 ] && [ "$LINE_COUNT" -eq 2 ] && printf '%s\n' "$OUT" | sed -n 1p | grep -q '⏳' \
   && [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$(note_for 1)" ]; then
    ok "Stop: stale line and NOTE survive 600 foreign dispatch rows (oldest dispatch not lost)"
else
    bad "Stop: stale line + NOTE behind 600 foreign rows" "2 lines: ⏳ line, then $(note_for 1)" "$LINE_COUNT line(s): $OUT"
fi

# 10. Stop, abnormal stop (status:"abnormal", 5 min ago) written FIRST, then
#     600 foreign stop rows -> the 💀 line still prints
reset_logs
jq -nc --arg ts "$(ts_minutes_ago 5)" '{session_id:"sess-A", ts:$ts, agent_type:"general-purpose", agent_id:"fixture", stop_reason:"rate_limit", status:"abnormal", preview:"fixture"}' >> "$CLAUDE_SUBAGENT_STOPS_LOG"
jq -nc --arg ts "$(ts_minutes_ago 1)" '[range(600)] | .[] | {session_id:"sess-foreign", ts:$ts, status:"normal"}' >> "$CLAUDE_SUBAGENT_STOPS_LOG"
run_hook Stop "sess-A"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '💀 Background troop general-purpose/fixture ended abnormally'; then
    ok "Stop: abnormal-stop line survives 600 foreign stop rows written after it"
else
    bad "Stop: abnormal-stop line behind 600 foreign stop rows" "💀 line for general-purpose/fixture" "rc=$RC, stdout=$OUT"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
