#!/bin/bash
# controller-first-subagent-flag.sh — IMP-090 (2026-07-15, Controller-First Enforcement)
# ─────────────────────────────────────────────────────────────────────────────
# SubagentStop hook. When a finished subagent's `agent_type` (A6-confirmed: the
# frontmatter `name` field of the spawned subagent) is "control-agent", writes
# the session-scoped controller-ran flag that controller-first-mutation-gate.sh
# reads to unlock further mutations for the REST OF THE SESSION (GRAFT-G1's
# documented restlücke: the flag is a one-time, session-wide unlock — it does
# not re-arm for a thematically new mutation later in the same session).
#
# Schema (mirrors subagent-lock-release.sh):
#   { hook_event_name: "SubagentStop", session_id, agent_id, agent_type,
#     stop_reason, ... }
#
# Fail-open: if session_id is missing/unparseable, exit 0 without writing
# anything — a guessed session id could set the flag under the WRONG session
# and silently unlock mutations there. This is a "do nothing when unsure" no-op,
# not error-masking (nothing was required to succeed here).
#
# Known restlücke (documented in the meta-proposal): if control-agent is ever
# renamed, agent_type drifts silently and this hook stops firing for it.
set -u

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

[ -n "$SESSION_ID" ] || exit 0
[ "$AGENT_TYPE" = "control-agent" ] || exit 0

STATE_DIR="/tmp/controller-first-$SESSION_ID"
mkdir -p "$STATE_DIR" 2>/dev/null || true
: > "$STATE_DIR/controller-ran" 2>/dev/null || true

LOG="$HOME/.claude/global-observation/controller-first.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '{"ts":"%s","event":"controller_ran_flag_set","session_id":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION_ID" >> "$LOG" 2>/dev/null || true

exit 0
