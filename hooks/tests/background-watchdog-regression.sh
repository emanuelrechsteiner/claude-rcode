#!/bin/bash
# background-watchdog-regression.sh — regression suite for IMP-198 (+ M22/A8,
# 2026-09-23: three-state status classification)
# ─────────────────────────────────────────────────────────────────────────────
# Covers subagent-watchdog.sh (SubagentStop → subagent-stops.jsonl) and
# background-agent-check.sh (UserPromptSubmit + Stop → the "N troops without
# an end-signal" / "recent abnormal stop" notes) — the pair that turns a
# silently quota-stalled subagent troop into a within-minutes signal instead
# of a 7h10m surprise (2026-09-01 incident, see hooks/subagent-watchdog.sh).
#
# NOTE on the M22/A8 update: no test below (pre-2026-09-23) ever encoded
# "missing stop_reason = abnormal" as an assertion — every existing
# stop_payload() call already supplied an explicit stop_reason value
# ("end_turn"/"max_tokens"), so the suite never exercised the exact path
# that was broken in production (1,515/1,515 real rows have an EMPTY
# stop_reason). That gap is why the bug shipped invisibly; cases 13–17 below
# close it directly. Existing cases 1–12 needed no behavioral change and are
# kept verbatim, since none of them relied on the old "missing = abnormal"
# rule.
#
# Runs entirely against a scratch directory under $TMPDIR — NEVER touches
# ~/.claude/global-observation/ (per the task brief).
#
# Usage: bash ~/.claude/hooks/tests/background-watchdog-regression.sh
# ─────────────────────────────────────────────────────────────────────────────
set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WATCHDOG="${CLAUDE_WATCHDOG_HOOK:-$HOOKS_DIR/subagent-watchdog.sh}"
CHECKER="${CLAUDE_BG_CHECK_HOOK:-$HOOKS_DIR/background-agent-check.sh}"

SCRATCH="$(mktemp -d /tmp/bg-watchdog-regression.XXXXXX)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export CLAUDE_SUBAGENT_STOPS_LOG="$SCRATCH/subagent-stops.jsonl"
export CLAUDE_DISPATCH_LOG="$SCRATCH/dispatch-capture.jsonl"
export CLAUDE_BG_STALE_MIN=20

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }

# ── helpers ──────────────────────────────────────────────────────────────
reset_logs() {
    : > "$CLAUDE_SUBAGENT_STOPS_LOG"
    : > "$CLAUDE_DISPATCH_LOG"
}

# epoch_minutes_ago N -> ISO8601 UTC timestamp N minutes before "now"
ts_minutes_ago() {
    local mins="$1"
    local now
    now=$(date -u +%s)
    date -u -j -f %s "$(( now - mins * 60 ))" +%Y-%m-%dT%H:%M:%SZ
}

stop_payload() {  # $1=session $2=agent_id $3=agent_type $4=stop_reason $5=last_msg
    jq -nc --arg sid "$1" --arg aid "$2" --arg atype "$3" --arg reason "$4" --arg msg "$5" \
        '{hook_event_name:"SubagentStop",session_id:$sid,agent_id:$aid,agent_type:$atype,stop_reason:$reason,last_assistant_message:$msg}'
}

echo "── Background-watchdog regression (IMP-198) ──"

# 1. Normal stop (stop_reason=end_turn, no marker text) → NOT abnormal, no
#    stderr note, one clean log line.
reset_logs
OUT=$(stop_payload "sess-1" "a1" "backend-agent" "end_turn" "All good." | bash "$WATCHDOG" 2>"$SCRATCH/stderr1")
ABNORMAL=$(jq -r '.abnormal' "$CLAUDE_SUBAGENT_STOPS_LOG")
STDERR_LEN=$(wc -c < "$SCRATCH/stderr1" | tr -d ' ')
if [ "$ABNORMAL" = "false" ] && [ "$STDERR_LEN" -eq 0 ]; then
    ok "normal stop (end_turn, clean message) is not abnormal, no stderr note"
else
    bad "normal stop is not abnormal, no stderr note" "abnormal=false, stderr empty" "abnormal=$ABNORMAL, stderr_len=$STDERR_LEN"
fi

# 2. max_tokens stop_reason → abnormal
reset_logs
stop_payload "sess-1" "a2" "control-agent" "max_tokens" "still working" | bash "$WATCHDOG" >/dev/null 2>"$SCRATCH/stderr2"
ABNORMAL=$(jq -r '.abnormal' "$CLAUDE_SUBAGENT_STOPS_LOG")
[ "$ABNORMAL" = "true" ] && [ -s "$SCRATCH/stderr2" ] \
    && ok "max_tokens stop_reason is abnormal (+ stderr note)" \
    || bad "max_tokens stop_reason is abnormal" "abnormal=true, stderr non-empty" "abnormal=$ABNORMAL"

# 3. Rate-limit marker in last_assistant_message (stop_reason itself normal) → abnormal
reset_logs
stop_payload "sess-1" "a3" "control-agent" "end_turn" "Error: rate_limit exceeded, retry later" | bash "$WATCHDOG" >/dev/null 2>/dev/null
ABNORMAL=$(jq -r '.abnormal' "$CLAUDE_SUBAGENT_STOPS_LOG")
[ "$ABNORMAL" = "true" ] \
    && ok "rate-limit marker in last message is abnormal even with stop_reason=end_turn" \
    || bad "rate-limit marker triggers abnormal" "true" "$ABNORMAL"

# 4. Preview capped at 160 chars regardless of message length
reset_logs
LONGMSG=$(printf 'x%.0s' $(seq 1 300))
stop_payload "sess-1" "a4" "t" "end_turn" "$LONGMSG" | bash "$WATCHDOG" >/dev/null 2>/dev/null
PREVIEW_LEN=$(jq -r '.preview | length' "$CLAUDE_SUBAGENT_STOPS_LOG")
[ "$PREVIEW_LEN" -eq 160 ] \
    && ok "preview is capped at 160 chars (input was 300)" \
    || bad "preview capped at 160 chars" "160" "$PREVIEW_LEN"

# 5. background-agent-check.sh: 0 open (dispatch count == stop count) → silent
reset_logs
T30=$(ts_minutes_ago 30)
T5=$(ts_minutes_ago 5)
printf '{"ts":"%s","session_id":"sess-5","tool":"Task","subagent_type":"x"}\n' "$T30" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-5","tool":"Task","subagent_type":"y"}\n' "$T5"  >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-5","agent_id":"a1","agent_type":"x","stop_reason":"end_turn","abnormal":false,"preview":""}\n' "$T30" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
printf '{"ts":"%s","session_id":"sess-5","agent_id":"a2","agent_type":"y","stop_reason":"end_turn","abnormal":false,"preview":""}\n' "$T5"  >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-5"}' | bash "$CHECKER" 2>"$SCRATCH/stderr5")
if [ -z "$OUT" ]; then
    ok "0 open dispatches (dispatched==stopped) → silent"
else
    bad "0 open dispatches → silent" "(nothing)" "$OUT"
fi

# 6. Open but YOUNG (below the staleness threshold) → still silent
reset_logs
printf '{"ts":"%s","session_id":"sess-6","tool":"Task","subagent_type":"x"}\n' "$T5" >> "$CLAUDE_DISPATCH_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-6"}' | bash "$CHECKER" 2>/dev/null)
if [ -z "$OUT" ]; then
    ok "open dispatch younger than threshold → silent"
else
    bad "open dispatch younger than threshold → silent" "(nothing)" "$OUT"
fi

# 7. Open AND older than threshold → fires with correct N and M
reset_logs
T45=$(ts_minutes_ago 45)
printf '{"ts":"%s","session_id":"sess-7","tool":"Task","subagent_type":"control-agent"}\n' "$T45" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-7","tool":"Task","subagent_type":"backend-agent"}\n' "$T45" >> "$CLAUDE_DISPATCH_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-7"}' | bash "$CHECKER" 2>/dev/null)
EXPECT_SUB="2 background troop(s) with no stop signal for"
if printf '%s' "$OUT" | grep -qF "$EXPECT_SUB" && printf '%s' "$OUT" | grep -qE "for (4[4-6]) min \(IMP-198\)"; then
    ok "open+stale fires with correct N=2 and M≈45 min"
else
    bad "open+stale fires with correct N/M" "'⏳ 2 background troop(s) ... for ~45 min (IMP-198) ...'" "$OUT"
fi

# 8. Recent (within 60 min) abnormal stop → its own line with the preview,
#    surfaced independently of the open/stale check above.
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-8","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-8","agent_id":"a9","agent_type":"control-agent","stop_reason":"max_tokens","abnormal":true,"preview":"quota exhausted mid-turn"}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-8"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "quota exhausted mid-turn"; then
    ok "abnormal stop within 60 min surfaces its preview"
else
    bad "abnormal stop within 60 min surfaces its preview" "line containing 'quota exhausted mid-turn'" "$OUT"
fi

# 9. Empty stdin → both hooks exit 0, no output, nothing written
reset_logs
OUT_W=$(printf '' | bash "$WATCHDOG" 2>&1); RC_W=$?
OUT_C=$(printf '' | bash "$CHECKER" 2>&1); RC_C=$?
if [ "$RC_W" -eq 0 ] && [ -z "$OUT_W" ] && [ "$RC_C" -eq 0 ] && [ -z "$OUT_C" ]; then
    ok "empty stdin: both hooks exit 0 with no output"
else
    bad "empty stdin: both hooks exit 0 silently" "rc=0/0, empty/empty" "rc=$RC_W/$RC_C, out='$OUT_W'/'$OUT_C'"
fi

# ── Bonus coverage (beyond the required 9) ─────────────────────────────────

# 10. Malformed (non-JSON) stdin → exit 0, no crash, no log write
reset_logs
BEFORE=$(wc -l < "$CLAUDE_SUBAGENT_STOPS_LOG" 2>/dev/null || echo 0)
OUT=$(printf 'not-json-at-all{{{' | bash "$WATCHDOG" 2>&1); RC=$?
AFTER=$(wc -l < "$CLAUDE_SUBAGENT_STOPS_LOG" 2>/dev/null || echo 0)
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$AFTER" -eq "$BEFORE" ]; then
    ok "malformed stdin (non-JSON) exits 0 without writing a log line"
else
    bad "malformed stdin exits 0 silently" "rc=0, no new line" "rc=$RC, before=$BEFORE after=$AFTER"
fi

# 11. Abnormal stop OLDER than 60 min must NOT be surfaced (Line 2 has a window)
reset_logs
T90=$(ts_minutes_ago 90)
printf '{"ts":"%s","session_id":"sess-11","agent_id":"a1","agent_type":"x","stop_reason":"max_tokens","abnormal":true,"preview":"ancient quota hit"}\n' "$T90" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
printf '{"ts":"%s","session_id":"sess-11","tool":"Task","subagent_type":"x"}\n' "$T90" >> "$CLAUDE_DISPATCH_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-11"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "ancient quota hit"; then
    bad "abnormal stop older than 60 min is NOT surfaced" "no mention of 'ancient quota hit'" "$OUT"
else
    ok "abnormal stop older than 60 min is not surfaced (60-min window respected)"
fi

# 12. UserPromptSubmit event wraps the same finding as valid JSON
#     hookSpecificOutput.additionalContext (not plain stdout).
reset_logs
T45=$(ts_minutes_ago 45)
printf '{"ts":"%s","session_id":"sess-12","tool":"Task","subagent_type":"x"}\n' "$T45" >> "$CLAUDE_DISPATCH_LOG"
OUT=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"sess-12","prompt":"weiter"}' | bash "$CHECKER" 2>/dev/null)
CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && printf '%s' "$CTX" | grep -qF "background troop(s) with no stop signal"; then
    ok "UserPromptSubmit emits valid JSON with the finding in additionalContext"
else
    bad "UserPromptSubmit emits valid JSON additionalContext" "valid JSON, context contains finding" "$OUT"
fi

# ── M22/A8 three-state classification (2026-09-23) ─────────────────────────
# Cases (a)–(e) as specified in A8. All exercise subagent-watchdog.sh with an
# EXPLICITLY MISSING stop_reason key (not just an empty string) to match the
# real payload shape (1,515/1,515 live rows have no stop_reason at all).

# 13 (a). No stop_reason key + non-empty last message → status=normal,
#         abnormal=false, no 💀.
reset_logs
OUT=$(jq -nc '{hook_event_name:"SubagentStop",session_id:"sess-13",agent_id:"a13",agent_type:"t",last_assistant_message:"Report delivered."}' \
    | bash "$WATCHDOG" 2>"$SCRATCH/stderr13")
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
ABNORMAL=$(jq -r '.abnormal' "$CLAUDE_SUBAGENT_STOPS_LOG")
SRP=$(jq -r '.stop_reason_present' "$CLAUDE_SUBAGENT_STOPS_LOG")
STDERR_LEN=$(wc -c < "$SCRATCH/stderr13" | tr -d ' ')
if [ "$STATUS" = "normal" ] && [ "$ABNORMAL" = "false" ] && [ "$SRP" = "false" ] && [ "$STDERR_LEN" -eq 0 ]; then
    ok "(a) missing stop_reason + normal text -> status=normal, no 💀"
else
    bad "(a) missing stop_reason + normal text -> normal" "status=normal abnormal=false stop_reason_present=false stderr=0" "status=$STATUS abnormal=$ABNORMAL stop_reason_present=$SRP stderr_len=$STDERR_LEN"
fi

# 14 (b). No stop_reason key + empty last message → status=unknown,
#         abnormal=false (compat field), no 💀 — the case that must NOT
#         resurrect the old 1,515/1,515 alarm noise.
reset_logs
OUT=$(jq -nc '{hook_event_name:"SubagentStop",session_id:"sess-14",agent_id:"a14",agent_type:"t",last_assistant_message:""}' \
    | bash "$WATCHDOG" 2>"$SCRATCH/stderr14")
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
ABNORMAL=$(jq -r '.abnormal' "$CLAUDE_SUBAGENT_STOPS_LOG")
STDERR_LEN=$(wc -c < "$SCRATCH/stderr14" | tr -d ' ')
if [ "$STATUS" = "unknown" ] && [ "$ABNORMAL" = "false" ] && [ "$STDERR_LEN" -eq 0 ]; then
    ok "(b) missing stop_reason + empty text -> status=unknown, no 💀"
else
    bad "(b) missing stop_reason + empty text -> unknown, no 💀" "status=unknown abnormal=false stderr=0" "status=$STATUS abnormal=$ABNORMAL stderr_len=$STDERR_LEN"
fi

# 15 (c). No stop_reason key + rate-limit marker in the message ->
#         status=abnormal, 💀 fires.
reset_logs
OUT=$(jq -nc '{hook_event_name:"SubagentStop",session_id:"sess-15",agent_id:"a15",agent_type:"t",last_assistant_message:"Error 429 rate limit hit"}' \
    | bash "$WATCHDOG" 2>"$SCRATCH/stderr15")
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
if [ "$STATUS" = "abnormal" ] && [ -s "$SCRATCH/stderr15" ]; then
    ok "(c) missing stop_reason + rate-limit marker -> status=abnormal, 💀 fires"
else
    bad "(c) missing stop_reason + rate-limit marker -> abnormal" "status=abnormal, stderr non-empty" "status=$STATUS"
fi

# 16 (d). Explicit stop_reason=max_tokens -> status=abnormal (same scenario
#         as case 2 above; restated here to keep the A8 (a)-(e) set together
#         and self-contained under one comment block).
reset_logs
stop_payload "sess-16" "a16" "t" "max_tokens" "still working" | bash "$WATCHDOG" >/dev/null 2>"$SCRATCH/stderr16"
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
[ "$STATUS" = "abnormal" ] && [ -s "$SCRATCH/stderr16" ] \
    && ok "(d) stop_reason=max_tokens -> status=abnormal" \
    || bad "(d) stop_reason=max_tokens -> abnormal" "status=abnormal" "status=$STATUS"

# 17 (e). Explicit stop_reason=end_turn -> status=normal (restated from case
#         1 for A8 completeness).
reset_logs
stop_payload "sess-17" "a17" "t" "end_turn" "done" | bash "$WATCHDOG" >/dev/null 2>"$SCRATCH/stderr17"
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
STDERR_LEN=$(wc -c < "$SCRATCH/stderr17" | tr -d ' ')
if [ "$STATUS" = "normal" ] && [ "$STDERR_LEN" -eq 0 ]; then
    ok "(e) stop_reason=end_turn -> status=normal, no 💀"
else
    bad "(e) stop_reason=end_turn -> normal" "status=normal, stderr=0" "status=$STATUS stderr_len=$STDERR_LEN"
fi

# 18. Explicit non-empty, non-"end_turn" stop_reason with an OTHERWISE empty
#     last message must still be abnormal, not unknown (unknown requires
#     stop_reason ABSENT, not merely a message-less abnormal reason).
reset_logs
stop_payload "sess-18" "a18" "t" "refusal" "" | bash "$WATCHDOG" >/dev/null 2>"$SCRATCH/stderr18"
STATUS=$(jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG")
[ "$STATUS" = "abnormal" ] && [ -s "$SCRATCH/stderr18" ] \
    && ok "(bonus) explicit non-end_turn stop_reason + empty message -> abnormal, not unknown" \
    || bad "(bonus) explicit stop_reason + empty message -> abnormal" "status=abnormal" "status=$STATUS"

# ── background-agent-check.sh: status-aware alarm selection (M22/A8) ───────

# 19. NEW-style row: status="abnormal" (written by the patched watchdog) ->
#     still surfaced as Line 2, keyed on status, not on the raw abnormal
#     boolean alone.
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-19","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-19","agent_id":"a19","agent_type":"control-agent","stop_reason":"","abnormal":true,"preview":"Error 429 rate limit hit","status":"abnormal","stop_reason_present":false}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-19"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "Error 429 rate limit hit"; then
    ok "(status-aware) new-style status=abnormal row is surfaced"
else
    bad "(status-aware) new-style status=abnormal row is surfaced" "line containing 'Error 429 rate limit hit'" "$OUT"
fi

# 20. NEW-style row: status="unknown", legacy abnormal=false -> NOT
#     surfaced (matches subagent-watchdog.sh's own compat mapping, but
#     asserted independently here in case the two drift).
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-20","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-20","agent_id":"a20","agent_type":"control-agent","stop_reason":"","abnormal":false,"preview":"","status":"unknown","stop_reason_present":false}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-20"}' | bash "$CHECKER" 2>/dev/null)
if [ -z "$OUT" ]; then
    ok "(status-aware) new-style status=unknown row is NOT surfaced"
else
    bad "(status-aware) new-style status=unknown row is NOT surfaced" "(nothing)" "$OUT"
fi

# 21. OLD-style row (no status field): abnormal=true, empty stop_reason, NO
#     marker in the preview -> historical noise MUST NOT resurface. This is
#     the exact shape of 1,515/1,515 pre-M22 log rows.
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-21","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-21","agent_id":"a21","agent_type":"control-agent","stop_reason":"","abnormal":true,"preview":"Reading connect() in MailWorkspace.swift"}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-21"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "Reading connect()"; then
    bad "(status-aware) old-style abnormal:true, empty stop_reason, no marker -> NOT surfaced" "no mention of the preview" "$OUT"
else
    ok "(status-aware) old-style abnormal:true, empty stop_reason, no marker is NOT surfaced (no resurrected noise)"
fi

# 22. OLD-style row (no status field) but WITH a real explicit stop_reason
#     (e.g. max_tokens, logged before M22 shipped) -> still surfaced; the
#     fallback re-derivation must not throw the baby out with the bathwater.
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-22","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-22","agent_id":"a22","agent_type":"control-agent","stop_reason":"max_tokens","abnormal":true,"preview":"quota exhausted mid-turn"}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-22"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "quota exhausted mid-turn"; then
    ok "(status-aware) old-style row with explicit non-end_turn stop_reason is still surfaced"
else
    bad "(status-aware) old-style row with explicit stop_reason is still surfaced" "line containing 'quota exhausted mid-turn'" "$OUT"
fi

# ── IMP-229 (2026-09-27): numeric markers need error context ───────────────
# A planning-agent that delivered a complete report was flagged 💀 abnormal
# because its report contained the character count "529" in a table. The
# marker expression now requires error context around 429/529.

watchdog_status() {  # $1=session $2=last message (no stop_reason key) -> prints status
    reset_logs
    jq -nc --arg sid "$1" --arg msg "$2" \
        '{hook_event_name:"SubagentStop",session_id:$sid,agent_id:"a-imp229",agent_type:"t",last_assistant_message:$msg}' \
        | bash "$WATCHDOG" >/dev/null 2>"$SCRATCH/stderr-imp229"
    jq -r '.status' "$CLAUDE_SUBAGENT_STOPS_LOG"
}

# 23 (a). Character count "529" in a finished report -> normal, no 💀.
STATUS=$(watchdog_status "sess-23" "removed 529 chars, net −200")
STDERR_LEN=$(wc -c < "$SCRATCH/stderr-imp229" | tr -d ' ')
if [ "$STATUS" = "normal" ] && [ "$STDERR_LEN" -eq 0 ]; then
    ok "(IMP-229 a) 'removed 529 chars, net −200' -> normal, no 💀"
else
    bad "(IMP-229 a) bare 529 as a count -> normal" "status=normal stderr=0" "status=$STATUS stderr_len=$STDERR_LEN"
fi

# 24 (b). Real overload error line -> abnormal.
STATUS=$(watchdog_status "sess-24" "API Error: 529 overloaded")
[ "$STATUS" = "abnormal" ] && [ -s "$SCRATCH/stderr-imp229" ] \
    && ok "(IMP-229 b) 'API Error: 529 overloaded' -> abnormal, 💀 fires" \
    || bad "(IMP-229 b) 'API Error: 529 overloaded' -> abnormal" "status=abnormal" "status=$STATUS"

# 25 (c). "status 429" -> abnormal.
STATUS=$(watchdog_status "sess-25" "status 429")
[ "$STATUS" = "abnormal" ] \
    && ok "(IMP-229 c) 'status 429' -> abnormal" \
    || bad "(IMP-229 c) 'status 429' -> abnormal" "status=abnormal" "status=$STATUS"

# 26 (d). API error type identifier -> abnormal.
STATUS=$(watchdog_status "sess-26" "Error: rate_limit_error")
[ "$STATUS" = "abnormal" ] \
    && ok "(IMP-229 d) 'Error: rate_limit_error' -> abnormal" \
    || bad "(IMP-229 d) 'Error: rate_limit_error' -> abnormal" "status=abnormal" "status=$STATUS"

# 27 (e). Pre-M22 row (no status field), empty stop_reason, preview = the
#         (a) text -> NOT alarm-worthy in background-agent-check.sh.
reset_logs
T10=$(ts_minutes_ago 10)
printf '{"ts":"%s","session_id":"sess-27","tool":"Task","subagent_type":"planning-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-27","agent_id":"a27","agent_type":"planning-agent","stop_reason":"","abnormal":true,"preview":"removed 529 chars, net −200"}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-27"}' | bash "$CHECKER" 2>/dev/null)
if [ -z "$OUT" ]; then
    ok "(IMP-229 e) pre-M22 row with bare '529' count is NOT surfaced"
else
    bad "(IMP-229 e) pre-M22 row with bare '529' count is NOT surfaced" "(nothing)" "$OUT"
fi

# 28. Pre-M22 row with a REAL error in the preview is still surfaced (the
#     narrowed expression must not blind the fallback path).
reset_logs
printf '{"ts":"%s","session_id":"sess-28","tool":"Task","subagent_type":"control-agent"}\n' "$T10" >> "$CLAUDE_DISPATCH_LOG"
printf '{"ts":"%s","session_id":"sess-28","agent_id":"a28","agent_type":"control-agent","stop_reason":"","abnormal":true,"preview":"API Error: 529 {\\"type\\":\\"overloaded_error\\"}"}\n' "$T10" >> "$CLAUDE_SUBAGENT_STOPS_LOG"
OUT=$(printf '{"hook_event_name":"Stop","session_id":"sess-28"}' | bash "$CHECKER" 2>/dev/null)
if printf '%s' "$OUT" | grep -qF "a28"; then
    ok "(IMP-229) pre-M22 row with 'API Error: 529 … overloaded_error' is still surfaced"
else
    bad "(IMP-229) pre-M22 row with a real API error is still surfaced" "line naming a28" "$OUT"
fi

# 29. Real log shapes that were false positives (2026-09-27 measurement):
#     table cell, line range, commit hash, identifier, prose -> all normal.
FP_FAILS=""
for msg in '| `domain-docs-convention.md` | 529 | 707 | +178 |' \
           'Reading ledger entries 3010-3529' \
           'commit 3529ad5 (context.md)' \
           'inspecting default_config and rate_limit_configs values' \
           'Added rate limiting and API error handling; storage quota field added'; do
    S=$(watchdog_status "sess-29" "$msg")
    [ "$S" = "normal" ] || FP_FAILS="$FP_FAILS [$msg -> $S]"
done
[ -z "$FP_FAILS" ] \
    && ok "(IMP-229) 5 observed/prose false-positive shapes -> all normal" \
    || bad "(IMP-229) false-positive shapes -> normal" "all normal" "$FP_FAILS"

# 30. Parity: both hooks carry the byte-identical expression.
RE_W=$(grep -m1 "^ABNORMAL_MARKER_RE=" "$WATCHDOG")
RE_C=$(grep -m1 "^ABNORMAL_MARKER_RE=" "$CHECKER")
if [ -n "$RE_W" ] && [ "$RE_W" = "$RE_C" ]; then
    ok "(IMP-229) ABNORMAL_MARKER_RE is byte-identical in both hooks"
else
    bad "(IMP-229) ABNORMAL_MARKER_RE identical in both hooks" "identical, non-empty" "watchdog='$RE_W' checker='$RE_C'"
fi

echo "──────────────────────────────────────"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
