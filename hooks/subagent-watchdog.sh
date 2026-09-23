#!/bin/bash
# subagent-watchdog.sh — SubagentStop hook (IMP-198, 2026-09-09; three-state
# classification added 2026-09-23, M22/A8)
# ─────────────────────────────────────────────────────────────────────────────
# A control-agent troop hit the model quota limit at 11:32 and went silent.
# Nobody noticed until 16:42 ("weiter") and 17:04 ("Why does this task take
# so insanly long?") — 7h10m of dead air with zero signal. There is no
# documented deterministic "troop died" event; SubagentStop fires on EVERY
# subagent end (normal or not) with a stop_reason that is at best a coarse
# proxy (documented values: "end_turn"|"max_tokens"|...; no dedicated
# rate-limit/quota reason is documented). This hook turns that coarse signal
# into an observable record + an immediate stderr note, so the pairing hook
# (background-agent-check.sh) has something to react to within the SAME
# session instead of the human noticing hours later.
#
# MEASUREMENT (M22, 2026-09-23): the original rule ("missing stop_reason also
# counts as abnormal") fired on every single logged row. The task brief cites
# 1,494/1,494 rows with an empty stop_reason, all flagged abnormal, at the
# time the defect was found. Re-verified independently against the live log
# on 2026-09-23 (`jq -r '.stop_reason'` / `.abnormal` over
# ~/.claude/global-observation/subagent-stops.jsonl, now 1,515 rows — the log
# kept growing between the two measurements): still 1,515/1,515 rows with an
# empty stop_reason and 1,515/1,515 flagged abnormal:true. Of those rows,
# 267/1,515 (~18%) also had a completely empty last-message preview — the
# real SubagentStop payload as delivered by this Claude Code build does not
# carry a `stop_reason` field at all, so "missing stop_reason" said nothing
# by itself about whether a stop was actually a problem.
#
# THREE-STATE CLASSIFICATION (M22/A8, replaces the old two-state rule):
#   abnormal — an EXPLICIT stop_reason is present and != "end_turn" (e.g.
#              "max_tokens"), OR the last message carries a rate-limit /
#              quota / overload marker. Only this state prints the 💀 line.
#   unknown  — stop_reason is absent AND the last message is empty. Logged
#              only, never alarmed: with stop_reason structurally absent
#              from this payload, an empty tail is most likely a normal
#              structured-output return (the ~18% above), not a stalled
#              troop — alarming on it would recreate the exact
#              1,515/1,515 noise this fix removes. The staleness check in
#              background-agent-check.sh (dispatch-vs-stop count aged past a
#              threshold) remains the net for an actually-silent death.
#   normal   — everything else (stop_reason absent but a real last message
#              exists, or stop_reason == "end_turn").
# The boolean `abnormal` field is KEPT for compatibility (= status ==
# "abnormal"); `status` and `stop_reason_present` are new fields so schema
# drift (a future Claude Code build that DOES send stop_reason) stays
# measurable without re-deriving it from the boolean.
#
# Schema (mirrors subagent-lock-release.sh / controller-first-subagent-flag.sh,
# both already reading this event in this repo):
#   { hook_event_name: "SubagentStop", session_id, agent_id, agent_type,
#     stop_reason: "end_turn"|"max_tokens"|..., last_assistant_message, ... }
#
# HONESTY NOTE (per the task brief): this schema is corroborated by two other
# hooks already shipping against SubagentStop in this repo (above), not by a
# live-fired event captured during this task — no subagent stop could be
# triggered from inside this sandboxed work session to confirm the raw JSON
# byte-for-byte. If `last_assistant_message` or `stop_reason` ever rename,
# this hook silently degrades to status "unknown" (empty stop_reason + empty
# last message) rather than erroring — report that drift if session-end
# diagnostics ever show status:"unknown" spiking after a Claude Code update.
#
# Deliberately NO full message logged — same doctrine as dispatch-capture.sh:
# the last assistant message is untrusted + can be bulky. Only a 160-char
# preview is kept.
#
# ALWAYS exits 0. This hook observes; it must never block a subagent's own
# termination.
set -u

INPUT=$(cat 2>/dev/null || true)
LOG="${CLAUDE_SUBAGENT_STOPS_LOG:-$HOME/.claude/global-observation/subagent-stops.jsonl}"

# Fail-open on empty/unparseable stdin.
[ -n "$INPUT" ] || exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# No session_id → cannot be paired against dispatch-capture.jsonl later, and a
# guessed session would attribute the record to the WRONG session (same
# fail-open rationale as controller-first-subagent-flag.sh). Do nothing.
[ -n "$SESSION_ID" ] || exit 0

AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
STOP_REASON=$(printf '%s' "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null)
LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# ── Three-state classification (M22/A8, 2026-09-23) ────────────────────────
# STOP_REASON is already "" whenever the field is missing/null/empty (the
# `.stop_reason // empty` extraction above collapses all three) — which is
# exactly what lets "stop_reason_present" answer "was there ever an explicit
# value at all", independent of what that value was.
STOP_REASON_PRESENT=false
[ -n "$STOP_REASON" ] && STOP_REASON_PRESENT=true

LAST_MSG_LC=$(printf '%s' "$LAST_MSG" | tr '[:upper:]' '[:lower:]')
ABNORMAL_MARKER_RE='rate_limit|rate limit|quota|overloaded|429|529|too many requests|api error'
MARKER_HIT=false
printf '%s' "$LAST_MSG_LC" | grep -qE "$ABNORMAL_MARKER_RE" && MARKER_HIT=true

ABNORMAL=false
if [ "$STOP_REASON_PRESENT" = "true" ] && [ "$STOP_REASON" != "end_turn" ]; then
    ABNORMAL=true
fi
[ "$MARKER_HIT" = "true" ] && ABNORMAL=true

# "empty" = nothing but whitespace, so a message of only spaces/newlines
# still counts as empty for the unknown-state check below.
LAST_MSG_EMPTY=false
[ -z "$(printf '%s' "$LAST_MSG" | tr -d '[:space:]')" ] && LAST_MSG_EMPTY=true

STATUS="normal"
if [ "$ABNORMAL" = "true" ]; then
    STATUS="abnormal"
elif [ "$STOP_REASON_PRESENT" = "false" ] && [ "$LAST_MSG_EMPTY" = "true" ]; then
    STATUS="unknown"
fi

# 160-char preview only — never the full message (untrusted + bulky).
PREVIEW=$(printf '%s' "$LAST_MSG" | cut -c1-160)

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE" \
    --arg stop_reason "$STOP_REASON" \
    --argjson abnormal "$ABNORMAL" \
    --arg preview "$PREVIEW" \
    --arg status "$STATUS" \
    --argjson stop_reason_present "$STOP_REASON_PRESENT" \
    '{ts:$ts,session_id:$session_id,agent_id:$agent_id,agent_type:$agent_type,stop_reason:$stop_reason,abnormal:$abnormal,preview:$preview,status:$status,stop_reason_present:$stop_reason_present}' \
    >> "$LOG" 2>/dev/null || true

# Only "abnormal" prints — "unknown" is logged silently by design (see the
# header rationale: alarming on an absent stop_reason recreated the
# 1,515/1,515 noise this fix removes).
if [ "$STATUS" = "abnormal" ]; then
    printf '💀 Hintergrundtrupp %s/%s endete abnormal (%s): %s\n' \
        "${AGENT_TYPE:-unknown}" "${AGENT_ID:-unknown}" "${STOP_REASON:-unknown}" "$PREVIEW" >&2
fi

exit 0
