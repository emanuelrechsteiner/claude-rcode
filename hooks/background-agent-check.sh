#!/bin/bash
# background-agent-check.sh — UserPromptSubmit + Stop hook (IMP-198, 2026-09-09)
# ─────────────────────────────────────────────────────────────────────────────
# Companion to subagent-watchdog.sh. That hook records every SubagentStop into
# subagent-stops.jsonl; this one pairs those records against dispatch-capture.jsonl
# (the existing PreToolUse/Task|Agent meter, IMP-115) for the CURRENT session and
# says out loud when dispatches are outnumbering stops for longer than a
# threshold — the exact gap that let a quota-stalled troop sit silent for 7h10m
# on 2026-09-01 before a human noticed ("weiter" / "why does this take so
# insanly long").
#
# PAIRING IS BY COUNT, NOT BY IDENTITY. dispatch-capture.jsonl has no agent_id
# field — PreToolUse fires BEFORE the runtime assigns one, so a Task/Agent
# dispatch and its eventual SubagentStop cannot be joined 1:1. What this script
# computes instead:
#   open      = max(0, dispatched_count_this_session - stopped_count_this_session)
#   oldest_ts = the (stopped_count)-th dispatch timestamp, ascending
#               (assumes agents tend to finish roughly in dispatch order —
#               a heuristic, not a guarantee; see the honesty note in the
#               task report)
# This is coarse on purpose: it is the only pairing the two logs' existing
# schemas support without changing dispatch-capture.sh (out of scope here).
#
# Registered under BOTH events (settings.json). Claude Code's base hook schema
# always carries hook_event_name (CLAUDE_CODE_CONFIGURATION_MANUAL.md §7.6), so
# one script tells the two events apart and formats accordingly:
#   - UserPromptSubmit → JSON hookSpecificOutput.additionalContext
#     (established pattern: parallel-analyze-prompt.sh, controller-first-prompt-gate.sh)
#   - anything else (Stop) → plain stdout lines
#     (established pattern: session-end-check.sh)
#
# ALARM-WORTHY SELECTION (M22/A8, 2026-09-23): subagent-watchdog.sh now
# writes a `status` field (normal|abnormal|unknown) alongside the legacy
# `abnormal` boolean — see its header for why the old boolean alone fired on
# every single row (1,515/1,515 rows had an empty stop_reason, all
# abnormal:true). Line 2 below therefore keys on `status == "abnormal"` for
# any row that HAS a `status` field. Rows written by the pre-M22 watchdog
# never have that field; for those, the old blanket `abnormal:true` cannot
# be trusted (it is the exact historical noise this fix removes), so they
# are re-classified on read from their own stop_reason/preview instead: only
# alarm-worthy if stop_reason is explicit and != "end_turn", or the preview
# carries a rate-limit/quota/overload marker. A pre-M22 row with an empty
# stop_reason and no marker — the overwhelming majority of the historical
# log — is therefore NOT alarm-worthy any more, even though it still reads
# abnormal:true on disk.
#
# WHAT THIS DOES NOT SEE (honesty note, per the task brief):
#   - A troop that is alive but simply doing nothing (no SubagentStop, no
#     dispatch imbalance) — there is no liveness signal to check against.
#   - A subagent process that dies WITHOUT ever firing SubagentStop (a crash
#     below the hook layer) looks identical to "still running" here, not to
#     "stopped abnormally" — it only inflates `open`, on the same timer as a
#     merely-slow-but-healthy agent.
#   - Two dispatches racing to finish out of order will misassign WHICH
#     dispatch is "the oldest open one" (see the count-not-identity note
#     above) — the AGE reported can be wrong by however much re-ordering
#     actually happened, though `open` itself (a pure count) is not affected.
#
# Always exits 0. Never blocks. Reads at most the last 500 lines of each log
# (tail) to keep cost bounded regardless of log size.
set -u

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

command -v jq >/dev/null 2>&1 || exit 0

HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID" ] || exit 0

DISPATCH_LOG="${CLAUDE_DISPATCH_LOG:-$HOME/.claude/global-observation/dispatch-capture.jsonl}"
STOPS_LOG="${CLAUDE_SUBAGENT_STOPS_LOG:-$HOME/.claude/global-observation/subagent-stops.jsonl}"

STALE_MIN="${CLAUDE_BG_STALE_MIN:-20}"
case "$STALE_MIN" in ''|*[!0-9]*) STALE_MIN=20 ;; esac

# Missing files → nothing to pair against → silent (not an error: a session
# with zero dispatches so far never created either log).
[ -f "$DISPATCH_LOG" ] || exit 0
[ -f "$STOPS_LOG" ] || exit 0

NOW_EPOCH=$(date -u +%s)

DISPATCH_TAIL=$(tail -n 500 "$DISPATCH_LOG" 2>/dev/null)
STOPS_TAIL=$(tail -n 500 "$STOPS_LOG" 2>/dev/null)

# `-R` + `fromjson?` parses each line independently — one malformed line
# (partial write, mid-append truncation) drops out silently instead of
# aborting the whole read.
DISPATCH_TS=$(printf '%s\n' "$DISPATCH_TAIL" | jq -R -r --arg sid "$SESSION_ID" \
    'fromjson? | select(type=="object") | select(.session_id == $sid) | (.ts // empty)' \
    2>/dev/null | sort)
DISPATCH_COUNT=0
[ -n "$DISPATCH_TS" ] && DISPATCH_COUNT=$(printf '%s\n' "$DISPATCH_TS" | grep -c .)

STOP_TS=$(printf '%s\n' "$STOPS_TAIL" | jq -R -r --arg sid "$SESSION_ID" \
    'fromjson? | select(type=="object") | select(.session_id == $sid) | (.ts // empty)' \
    2>/dev/null | sort)
STOP_COUNT=0
[ -n "$STOP_TS" ] && STOP_COUNT=$(printf '%s\n' "$STOP_TS" | grep -c .)

OPEN=$(( DISPATCH_COUNT - STOP_COUNT ))
[ "$OPEN" -lt 0 ] && OPEN=0

# ── Line 1: N dispatches outstanding, oldest one older than threshold ──────
LINE1=""
if [ "$OPEN" -gt 0 ]; then
    OLDEST_TS=$(printf '%s\n' "$DISPATCH_TS" | sed -n "$((STOP_COUNT + 1))p")
    if [ -n "$OLDEST_TS" ]; then
        OLDEST_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$OLDEST_TS" +%s 2>/dev/null || echo 0)
        if [ "$OLDEST_EPOCH" -gt 0 ] 2>/dev/null; then
            AGE_MIN=$(( (NOW_EPOCH - OLDEST_EPOCH) / 60 ))
            if [ "$AGE_MIN" -ge "$STALE_MIN" ]; then
                LINE1="⏳ ${OPEN} background troop(s) with no stop signal for ${AGE_MIN} min (IMP-198) — check TaskOutput/Monitor"
            fi
        fi
    fi
fi

# ── Line 2 (independent of Line 1): most recent abnormal stop in the last
#    60 minutes for THIS session, named with its preview ─────────────────
LINE2=""
# KEEP IDENTICAL to ABNORMAL_MARKER_RE in hooks/subagent-watchdog.sh — the
# rationale (IMP-229: bare 429/529 in a character count flagged a finished
# troop abnormal) lives there. Applied to the lowercased preview.
ABNORMAL_MARKER_RE='(^|[^a-z0-9_])rate[ _]limit(s|ed|_error|_exceeded)?([^a-z0-9_]|$)|(^|[^a-z0-9_])too many requests([^a-z0-9_]|$)|(^|[^a-z0-9_])overloaded(_error)?([^a-z0-9_]|$)|(^|[^a-z0-9_])quota[^a-z0-9]{0,3}(exceeded|exhausted|limit|reached)|(exceeded|exhausted)[a-z ]{0,25}quota|(^|[^a-z0-9_])api error[^a-z0-9]{0,3}([:(]|[45][0-9][0-9])|(error|status|http|code)[^a-z0-9]{0,15}(429|529)([^0-9]|$)|(^|[^0-9])(429|529)[^a-z0-9]{0,5}(too many|overloaded|rate[ _]limit)'
LATEST_ABNORMAL=$(printf '%s\n' "$STOPS_TAIL" | jq -R -c --arg sid "$SESSION_ID" --arg re "$ABNORMAL_MARKER_RE" '
    def is_alarm_worthy:
        if has("status") then
            .status == "abnormal"
        else
            # Pre-M22 row: no status field, so re-derive instead of trusting
            # the old blanket `abnormal` boolean (see the rationale above).
            (((.stop_reason // "") as $sr | ($sr != "" and $sr != "end_turn")))
            or
            (((.preview // "") | ascii_downcase
                | test($re)))
        end;
    fromjson? | select(type=="object") | select(.session_id == $sid) | select(is_alarm_worthy)
' 2>/dev/null | tail -1)
if [ -n "$LATEST_ABNORMAL" ]; then
    A_TS=$(printf '%s' "$LATEST_ABNORMAL" | jq -r '.ts // empty' 2>/dev/null)
    A_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$A_TS" +%s 2>/dev/null || echo 0)
    if [ "$A_EPOCH" -gt 0 ] 2>/dev/null; then
        A_AGE_MIN=$(( (NOW_EPOCH - A_EPOCH) / 60 ))
        if [ "$A_AGE_MIN" -ge 0 ] && [ "$A_AGE_MIN" -le 60 ]; then
            A_TYPE=$(printf '%s' "$LATEST_ABNORMAL" | jq -r '.agent_type // "unknown"' 2>/dev/null)
            A_ID=$(printf '%s' "$LATEST_ABNORMAL" | jq -r '.agent_id // "unknown"' 2>/dev/null)
            A_REASON=$(printf '%s' "$LATEST_ABNORMAL" | jq -r '.stop_reason // "unknown"' 2>/dev/null)
            A_PREVIEW=$(printf '%s' "$LATEST_ABNORMAL" | jq -r '.preview // ""' 2>/dev/null)
            LINE2="💀 Background troop ${A_TYPE}/${A_ID} ended abnormally (${A_REASON}) ${A_AGE_MIN} min ago: ${A_PREVIEW} (IMP-198)"
        fi
    fi
fi

[ -n "$LINE1" ] || [ -n "$LINE2" ] || exit 0

case "$HOOK_EVENT" in
    UserPromptSubmit)
        CTX="$LINE1"
        if [ -n "$LINE2" ]; then
            if [ -n "$CTX" ]; then CTX="$CTX
$LINE2"
            else
                CTX="$LINE2"
            fi
        fi
        jq -n --arg ctx "$CTX" \
            '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
        ;;
    *)
        [ -n "$LINE1" ] && printf '%s\n' "$LINE1"
        [ -n "$LINE2" ] && printf '%s\n' "$LINE2"
        ;;
esac

exit 0
