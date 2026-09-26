#!/bin/bash
# dispatch-specialist-check.sh — IMP-159 (2026-08-24)
# ─────────────────────────────────────────────────────────────────────────────
# PreToolUse hook, matcher "Task|Agent". Enforces tool-discipline.md Rule 3
# ("specify subagent_type on every Agent call") with a RECOVERABLE ask, not a
# hard block — the user's explicit decision for IMP-159 (rationale requirement
# via hook, NOT a hard block).
#
# MEASURED PROBLEM (chat-corpus analysis, 296 coding transcripts, Aug 2026):
# subagent_type == "general-purpose" in 43.5-45.9% of Task dispatches (lower
# bound: 100/230 in the coding corpus). Rule 3's own baseline was 25%, target
# <5 unspecified per 30 days — the rate has RISEN since the rule was written.
# control-agent itself was dispatched via subagent_type ZERO times across 123
# framework sessions. Same-day comparison 2026-08-09, two unrelated projects:
# one dispatched 14/16 to named specialists -> 12/12 issues closed, 101 green
# tests, no escalation. The other dispatched 11/11 to general-purpose with
# symptom-titled prompts -> an escalation day, traced in the transcript to a
# subagent with no defined acceptance criterion substituting its own judgment
# for an explicit user instruction.
#
# WHY "ask", NOT "deny" (user's explicit instruction for IMP-159): a
# general-purpose dispatch is sometimes the right call — level/asset work,
# repo inventories, and other genuinely no-specialist-fits tasks exist. The
# rule (and this hook) cannot know which case is real; only the dispatching
# agent can. So the hook asks for a one-line rationale instead of refusing
# the dispatch outright. Native permissionDecision:"ask" is itself already
# recoverable (one-click y/n) — the second-attempt marker below exists for a
# stronger case: an unattended/headless run where no human is present to
# answer the ask, so the SAME dispatch must not deadlock forever on an
# unanswerable prompt.
#
# RATIONALE MARKER FORMAT (case-insensitive; a line beginning with, after
# optional leading whitespace, one of):
#   AGENTENWAHL: <reason>
#   AGENT-RATIONALE: <reason>
#   BEGRÜNDUNG AGENTENWAHL: <reason>   (also accepted without the umlaut:
#                                        BEGRUENDUNG AGENTENWAHL:)
# followed by >=15 characters of trimmed reason text on that line.
#
# SECOND-ATTEMPT MECHANIC — adapted from gateguard.sh, NOT directly
# transferable as-is: gateguard dedups on FILE PATH, a stable identity across
# repeated touches of the same target. A Task dispatch has no file-path
# equivalent; the closest analogue is the PROMPT TEXT ITSELF (unchanged text
# means "the agent is retrying the identical dispatch", changed text — e.g.
# now carrying an AGENTENWAHL line — means "a new attempt with new content,
# evaluate fresh"). So the dedup key here is sha1(subagent_type + "\n" +
# prompt), scoped per session under /tmp/dispatch-specialist-<sid>/. First
# occurrence of a given (subagent_type, prompt) pair without a rationale ->
# ask. An IDENTICAL retry of that exact pair within the same session ->
# passes silently ("allow-second-attempt") so an unanswerable ask in a
# headless/autonomous run cannot wedge the dispatch forever. This is the
# simplest safe variant per the task brief: same-session, same-prompt-hash
# passthrough — no cross-session or fuzzy-match leniency.
#
# ADVISORY, NOT A SECURITY GATE: fails OPEN (exit 0, silently) on unparseable
# stdin, missing jq, or missing hash tooling. Unlike guard-unsafe.sh (the
# CRITICAL floor against host destruction/exfiltration), a misclassification
# here costs at most one dispatch's worth of specialization discipline —
# never a correctness or safety property. A false block would be strictly
# worse than the discipline gap this hook exists to close.
#
# Opt-out: CLAUDE_DISPATCH_CHECK_OFF=1 (exit 0, logged as "allow-optout").
#
# Log: one jq-built JSON line per decision to
#   ~/.claude/global-observation/dispatch-specialist.log
# Fields: ts, session_id, decision, subagent_type, rationale_present,
# prompt_len, gp_count, rationale_snippet. Named specialists (subagent_type
# not "general-purpose"/empty) pass silently with NO log line — this hook
# exists to close the general-purpose gap, not to audit every dispatch (that
# is dispatch-capture.sh's job).
#
# ON rationale_snippet (IMP-213, 2026-09-21): the log carries the RATIONALE
# LINE ONLY, truncated to 200 chars — never the prompt. This is a deliberate,
# bounded exception to dispatch-capture.sh's "no prompt text" principle
# (untrusted + bulky), taken because the alternative proved worse: with only
# a rationale_present boolean, the gate's own effectiveness was unmeasurable,
# and a four-week formality gap (57 of 60 dispatches waved through on marker
# presence alone, 2026-08-24..09-21) stayed invisible the entire time.
#
# IMP-213 additions on top of the IMP-159 baseline:
#   (1) the rationale must NAME a roster specialist (or built-in Explore/Plan)
#       and reject it — "no specialist fits" is a claim ABOUT the specialists;
#   (2) from the 3rd GRANTED general-purpose dispatch per session
#       (CLAUDE_DISPATCH_GP_MAX, default 2) the hook asks regardless of the
#       rationale — past that point the pattern, not the single dispatch, is
#       the question. Refused attempts never consume the quota.
set -u

LOG="${CLAUDE_DISPATCH_SPECIALIST_LOG:-$HOME/.claude/global-observation/dispatch-specialist.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log_line() {  # $1=decision $2=session_id $3=subagent_type $4=rationale_present $5=prompt_len $6=rationale_snippet $7=gp_count
  jq -n -c \
    --arg decision "$1" \
    --arg session "$2" \
    --arg subagent "$3" \
    --argjson rationale_present "${4:-false}" \
    --argjson prompt_len "${5:-0}" \
    --arg snippet "${6:-}" \
    --argjson gp_count "${7:-0}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      ts: $ts,
      session_id: (if $session == "" then null else $session end),
      decision: $decision,
      subagent_type: (if $subagent == "" then null else $subagent end),
      rationale_present: $rationale_present,
      prompt_len: $prompt_len,
      rationale_snippet: (if $snippet == "" then null else $snippet end),
      gp_count: $gp_count
    }' >> "$LOG" 2>/dev/null || true
}

INPUT=$(cat 2>/dev/null || printf '{}')

if [ "${CLAUDE_DISPATCH_CHECK_OFF:-0}" = "1" ]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
  log_line "allow-optout" "$SESSION_ID" "" "false" "0" "" "0"
  exit 0
fi

# Fail open — advisory hook, never a security gate (see header).
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in Task|Agent) ;; *) exit 0 ;; esac

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
PROMPT_LEN=${#PROMPT}

# Only fires for general-purpose or missing/empty subagent_type. All named
# specialists pass silently — no log line (see header).
if [ -n "$SUBAGENT" ] && [ "$SUBAGENT" != "general-purpose" ]; then
  exit 0
fi

# ── Roster of named specialists (live, never a hard-coded copy) ─────────
AGENTS_DIR="${CLAUDE_DISPATCH_AGENTS_DIR:-$HOME/.claude/agents}"
ROSTER=""
if [ -d "$AGENTS_DIR" ]; then
  ROSTER=$(ls "$AGENTS_DIR" 2>/dev/null | grep -E '\.md$' | sed 's/\.md$//' | sort)
fi
# Built-in agents have no definition file but are legitimate alternatives to
# weigh and reject, so they count as "named" for the substance check.
ROSTER="$ROSTER
Explore
Plan"
AGENT_LIST=$(printf '%s\n' "$ROSTER" | grep -v '^$' | paste -sd, - | sed 's/,/, /g')
[ -n "$AGENT_LIST" ] || AGENT_LIST="(no agent files found under $AGENTS_DIR)"

# ── Rationale detection ──────────────────────────────────────────────────
# German aliases kept: the owner writes German (AGENTENWAHL, BEGRUENDUNG/
# BEGRÜNDUNG AGENTENWAHL); AGENT-RATIONALE is the English equivalent.
MARKER_RE='^[[:space:]]*(AGENTENWAHL|AGENT-RATIONALE|BEGR(UE|Ü)NDUNG[[:space:]]+AGENTENWAHL)[[:space:]]*:.*'
MATCH=$(printf '%s' "$PROMPT" | grep -oiE "$MARKER_RE" 2>/dev/null | head -1)
RATIONALE_TEXT="${MATCH#*:}"
RATIONALE_TEXT=$(printf '%s' "$RATIONALE_TEXT" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
RATIONALE_LEN=${#RATIONALE_TEXT}
SNIPPET=$(printf '%s' "$RATIONALE_TEXT" | cut -c1-200)

HAS_RATIONALE=false
[ -n "$MATCH" ] && [ "$RATIONALE_LEN" -ge 15 ] && HAS_RATIONALE=true

# ── Substance check (IMP-213): the rationale must NAME a specialist ──────
# Measured gap: 57 of 60 general-purpose dispatches (2026-08-24..09-21) were
# waved through on mere marker presence — the gate collected a formality, not
# a decision. Requiring the rejected alternative to be named by its own name
# is the smallest mechanically checkable step up from "some text is present".
NAMES_SPECIALIST=false
if [ "$HAS_RATIONALE" = "true" ]; then
  HAY=$(printf '%s' "$RATIONALE_TEXT" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    NEEDLE=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')
    case "$HAY" in *"$NEEDLE"*) NAMES_SPECIALIST=true; break ;; esac
  done <<EOF
$ROSTER
EOF
fi

# ── Per-session state: retry marker AND granted counter ─────────────────
# Two separate tallies on purpose. The retry marker must record EVERY attempt
# (including refused ones) so an identical re-dispatch can pass and a headless
# run cannot deadlock. The escalation counter must record only GRANTED
# dispatches — the pattern worth limiting is general-purpose actually being
# used, not being attempted. Counting attempts would let two refusals burn the
# whole quota before the first legitimate dispatch (found by the regression
# suite on the first run of this build, 2026-09-21).
SESS="${SESSION_ID:-nosession}"
STATE_DIR="/tmp/dispatch-specialist-${SESS}"
RETRY_DIR="$STATE_DIR/attempts"
GRANT_DIR="$STATE_DIR/granted"
mkdir -p "$RETRY_DIR" "$GRANT_DIR" 2>/dev/null || true

HASHER=""
command -v shasum >/dev/null 2>&1 && HASHER="shasum"
[ -z "$HASHER" ] && command -v sha1sum >/dev/null 2>&1 && HASHER="sha1sum"

KEY=""
IS_RETRY=false
if [ -n "$HASHER" ]; then
  KEY=$(printf '%s\n%s' "$SUBAGENT" "$PROMPT" | "$HASHER" 2>/dev/null | awk '{print $1}')
  if [ -n "$KEY" ]; then
    if [ -f "$RETRY_DIR/$KEY" ]; then IS_RETRY=true; else touch "$RETRY_DIR/$KEY" 2>/dev/null || true; fi
  fi
fi

GRANTED_SO_FAR=$(ls -1 "$GRANT_DIR" 2>/dev/null | wc -l | tr -d ' ')
[ -n "$GRANTED_SO_FAR" ] || GRANTED_SO_FAR=0
GP_MAX="${CLAUDE_DISPATCH_GP_MAX:-2}"
# Position this dispatch would take if granted.
GP_COUNT=$((GRANTED_SO_FAR + 1))

mark_granted() {
  [ -n "$KEY" ] && touch "$GRANT_DIR/$KEY" 2>/dev/null || true
}

# ── Decision ─────────────────────────────────────────────────────────────
DENY_REASON=""
if [ "$HAS_RATIONALE" != "true" ]; then
  DENY_REASON="general-purpose without a rationale."
elif [ "$NAMES_SPECIALIST" != "true" ]; then
  DENY_REASON="The rationale does not name a specialist agent. tool-discipline.md Rule 3 permits general-purpose ONLY when no specialist fits — that is a claim ABOUT the specialists and must name and reject at least one of them."
elif [ "$GRANTED_SO_FAR" -ge "$GP_MAX" ]; then
  DENY_REASON="general-purpose dispatch #${GP_COUNT} in this session (threshold ${GP_MAX}). Past this point the individual dispatch is no longer the question, the pattern is: a series of general-purpose troops is almost always a skipped decomposition, not a series of genuine exceptions."
fi

if [ -z "$DENY_REASON" ]; then
  echo "NOTE: general-purpose with a supplied rationale (${GP_COUNT}/${GP_MAX}) — $(printf '%s' "$SNIPPET" | cut -c1-80)" >&2
  mark_granted
  log_line "allow-with-rationale" "$SESSION_ID" "$SUBAGENT" "$HAS_RATIONALE" "$PROMPT_LEN" "$SNIPPET" "$GP_COUNT"
  exit 0
fi

# Identical retry of the SAME dispatch passes — an unattended/headless run
# has nobody to answer the ask and must not deadlock (unchanged from IMP-159).
if [ "$IS_RETRY" = "true" ]; then
  mark_granted
  log_line "allow-second-attempt" "$SESSION_ID" "$SUBAGENT" "$HAS_RATIONALE" "$PROMPT_LEN" "$SNIPPET" "$GP_COUNT"
  exit 0
fi

REASON="${DENY_REASON} Measured state: general-purpose stood at 43.5-45.9% of all Task dispatches (chat analysis Aug 2026, 296 transcripts; baseline 25%), and 57 of 60 dispatches in the window 2026-08-24..09-21 got through solely on the presence of a rationale line. Available specialists: ${AGENT_LIST}. If none genuinely fits: 'AGENTENWAHL: <which specialist would come closest and why it does NOT fit>' (min. 15 characters, must include a name from the list) — the second attempt with an identical dispatch goes through without a re-ask."

log_line "ask" "$SESSION_ID" "$SUBAGENT" "$HAS_RATIONALE" "$PROMPT_LEN" "$SNIPPET" "$GP_COUNT"

jq -n --arg r "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $r
    }
}'
exit 0
