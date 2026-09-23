#!/bin/bash
# Subagent Lock Release — Auto-release locks when subagent finishes (2026-05-26)
# ──────────────────────────────────────────────────────────────────────────
# SubagentStop hook. Whenever a subagent finishes, releases ALL file locks
# that subagent held. Prevents lock-leaks from agents that forgot to release.
#
# Schema (per Claude Code docs):
#   { hook_event_name: "SubagentStop", agent_id: "...", agent_type: "...",
#     stop_reason: "end_turn|max_tokens", ... }
set -u

INPUT=$(cat 2>/dev/null || true)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$AGENT_ID" ] || exit 0

CLAIM="${HOME}/.claude/scripts/parallel-claim.sh"
[ -x "$CLAIM" ] || exit 0

# Release everything this agent held.
#
# IMP-114 (2026-08-01): $AGENT_ID is the runtime's 17-hex id, while locks are
# claimed under the orchestrator's "pdispatch-<turn>-<unit>" label. release-all
# compared only the latter, so this call matched nothing — 3,212 of 3,212
# recorded releases said "released 0 locks" and TTL-steal was the only thing
# that ever freed a lock. release-all now matches either identity space, and
# parallel-lock-check.sh binds this harness id onto the lock on first touch.
RESULT=$("$CLAIM" release-all "$AGENT_ID" 2>&1 || true)

# IMP-140 (2026-08-22): this hook fires on EVERY SubagentStop — whether or not
# that subagent ever held a lock. Because non-write dispatches vastly outnumber
# write fan-outs, "released 0 locks" dominated the coordination log: measured
# 4,349 subagent_release records against 10 claim records (99.8% noise),
# burying the one signal (parallel-by-default.md) this log exists to answer.
# The lock RELEASE itself (release-all above) is unchanged — only what gets
# WRITTEN to the log changes. cmd_release_all's stdout is always the literal
# "released N locks for <agent>" (scripts/parallel-claim.sh), so N is parsed
# with a builtin pattern match — no extra subprocess on the hot SubagentStop
# path. N>0 (a real release — signal) is always logged. N==0 (no-op) is
# sampled 1-in-20, mirroring the AUTO-band sampling in
# excessive-agency-gate.sh, so the no-op path still proves it fires without
# drowning the log. Set CLAUDE_LOCK_RELEASE_SAMPLE=1 for full logging
# (debugging) or 0 to disable no-op logging entirely.
RELEASED_N=0
case "$RESULT" in
    "released "[0-9]*" locks"*)
        _rest="${RESULT#released }"
        RELEASED_N="${_rest%% *}"
        ;;
esac
case "$RELEASED_N" in ''|*[!0-9]*) RELEASED_N=0 ;; esac

LOG="${CLAUDE_COORD_LOG:-$HOME/.claude/global-observation/parallel-coordination.jsonl}"

# Built with jq so a lock path or agent id containing a quote/backslash cannot
# produce an unparseable line (the same defect that made web-fetch-gate.log
# 0/41 readable — see IMP-117).
if [ "$RELEASED_N" -gt 0 ] 2>/dev/null; then
    mkdir -p "$(dirname "$LOG")"
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg agent_id "$AGENT_ID" \
           --arg result "$RESULT" \
        '{ts:$ts,event:"subagent_release",agent_id:$agent_id,result:$result}' \
        >> "$LOG" 2>/dev/null || true
else
    _sample_rate="${CLAUDE_LOCK_RELEASE_SAMPLE:-20}"
    case "$_sample_rate" in
        ''|*[!0-9]*) _sample_rate=20 ;;   # non-numeric → fall back, never crash the hook
    esac
    if [ "$_sample_rate" -gt 0 ] 2>/dev/null && [ $(( RANDOM % _sample_rate )) -eq 0 ]; then
        mkdir -p "$(dirname "$LOG")"
        jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
               --arg agent_id "$AGENT_ID" \
               --arg result "$RESULT" \
               --argjson sample_rate "$_sample_rate" \
            '{ts:$ts,event:"subagent_release",agent_id:$agent_id,result:$result,sampled:1,sample_rate:$sample_rate}' \
            >> "$LOG" 2>/dev/null || true
    fi
fi

exit 0
