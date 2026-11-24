#!/usr/bin/env bash
# goal-stop.sh: Stop (IMP-289). A turn does not end on an unreported deviation.
#
# When the session's goal has deviations that were not acknowledged, or issues still marked
# as running, the hook blocks the stop ONCE per state and lists them, so the model tells the
# user and closes the entries (goal.sh ack / done / drop). The same state never blocks
# twice, and a stop that already answers a stop hook (stop_hook_active) always passes.
# Pending issues alone never block: stopping mid-plan to ask the user is legitimate.
# Always exit 0; the block is the JSON decision on stdout. Opt-out: CLAUDE_GOAL_TRACKING=0.
set -u
INPUT=$(cat 2>/dev/null || true)
[ "${CLAUDE_GOAL_TRACKING:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
case "$SID" in ''|.*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
GOAL_DIR="${CLAUDE_GOAL_DIR:-$HOME/.claude/global-observation/goals}"
[ -f "$GOAL_DIR/$SID.json" ] || exit 0
jq -e '.goal != null' "$GOAL_DIR/$SID.json" >/dev/null 2>&1 || exit 0  # helper rows only, no goal
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
GOAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/goal.sh"
REASON=$(bash "$GOAL" --session "$SID" stop-check 2>>"$GOAL_DIR/errors.log") || exit 0
[ -n "$REASON" ] || exit 0
jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
