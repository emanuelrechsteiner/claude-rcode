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

# Release everything this agent held. Output goes to debug log (not surfaced
# to user unless verbose).
RESULT=$("$CLAIM" release-all "$AGENT_ID" 2>&1 || true)

# Log to observation pipeline for audit
LOG=$HOME/.claude/global-observation/parallel-coordination.jsonl
mkdir -p "$(dirname "$LOG")"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"ts":"%s","event":"subagent_release","agent_id":"%s","result":"%s"}\n' \
    "$TS" "$AGENT_ID" "$(echo "$RESULT" | sed 's/"/\\"/g')" >> "$LOG"

exit 0
