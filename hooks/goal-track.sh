#!/usr/bin/env bash
# goal-track.sh: keeps Cockpit card 4 current without a model turn (IMP-289, IMP-277).
#
# PostToolUse, Edit|Write|MultiEdit: records the written file and flags it once when it lies
#   inside the project but outside every declared issue path (deviation "undeclared-file").
#   Every other matched tool call refreshes the time to goal, at most every 30 s. A no-op in
#   a session without a goal.
# PreToolUse, Task|Agent: queues the dispatch with its title, type, model and effort (IMP-277).
# SubagentStart: the helper really started; the oldest queued dispatch of its type becomes a
#   running row on the card. SubagentStop: the row of that agent id is closed with its duration.
#   A dispatch that was denied never starts and its queue entry expires. The helper rows work
#   in a session without a goal as well.
# Silent on stdout (a PreToolUse hook must never look like a decision), always exit 0.
# Errors go to <goal dir>/errors.log. Opt-out: CLAUDE_GOAL_TRACKING=0.
set -u
INPUT=$(cat 2>/dev/null || true)
[ "${CLAUDE_GOAL_TRACKING:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
field() { printf '%s' "$INPUT" | jq -r "$1 // \"\"" 2>/dev/null; }
SID=$(field '.session_id') || exit 0
case "$SID" in ''|.*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
GOAL_DIR="${CLAUDE_GOAL_DIR:-$HOME/.claude/global-observation/goals}"
GOAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/goal.sh"
goal() { bash "$GOAL" --session "$SID" "$@" >/dev/null 2>>"$GOAL_DIR/errors.log" || true; }
case "$(field '.hook_event_name')" in
  PreToolUse)
    case "$(field '.tool_name')" in Task|Agent) ;; *) exit 0 ;; esac
    mkdir -p "$GOAL_DIR" 2>/dev/null || exit 0
    # --flag=value: a title that starts with a dash stays a value.
    goal agent-queue --title="$(field '.tool_input.description')" --type="$(field '.tool_input.subagent_type')" \
      --model="$(field '.tool_input.model')" --effort="$(field '.tool_input.effort')"
    ;;
  SubagentStart)
    AGENT_ID=$(field '.agent_id'); [ -n "$AGENT_ID" ] || exit 0
    mkdir -p "$GOAL_DIR" 2>/dev/null || exit 0
    goal agent-start --id="$AGENT_ID" --type="$(field '.agent_type')"
    ;;
  SubagentStop)
    AGENT_ID=$(field '.agent_id'); [ -n "$AGENT_ID" ] || exit 0
    [ -f "$GOAL_DIR/$SID.json" ] || exit 0
    goal agent-stop --id="$AGENT_ID"
    ;;
  *)
    [ -f "$GOAL_DIR/$SID.json" ] || exit 0
    # A state file that only carries helper rows has no goal: nothing to record or refresh.
    jq -e '.goal != null' "$GOAL_DIR/$SID.json" >/dev/null 2>&1 || exit 0
    FILE=$(field '.tool_input.file_path')
    if [ -n "$FILE" ]; then
      goal touch --file="$FILE"
    else
      # The card is refreshed at most every 30 s, and every refresh rewrites the state file:
      # its age answers the question without starting Python on every tool call (measured
      # 2026-11-11: 240 ms per call with the tool, 36 ms without).
      # GNU form first: there "stat -f" succeeds and prints file system text, not a time.
      MTIME=$(stat -c %Y "$GOAL_DIR/$SID.json" 2>/dev/null || stat -f %m "$GOAL_DIR/$SID.json" 2>/dev/null || echo 0)
      if [ $(( $(date +%s) - MTIME )) -ge 30 ]; then goal tick; fi
    fi
    ;;
esac
exit 0
