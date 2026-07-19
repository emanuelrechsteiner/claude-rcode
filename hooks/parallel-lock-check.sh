#!/bin/bash
# Parallel Lock Check — Hook 5 of the Parallel Coordination System (2026-05-26)
# ──────────────────────────────────────────────────────────────────────────
# PreToolUse hook on Edit|Write. Before any edit, checks if the target file
# is locked by ANOTHER agent. If so, JSON-deny with informative message.
# If unlocked OR locked by SELF, allow.
#
# Identity resolution:
#   1. .agent_id from hook input (set by Claude Code in subagent contexts)
#   2. Fall back to .session_id (main thread)
#
# Bypass: CLAUDE_PARALLEL_LOCK_OFF=1
set -u

[ "${CLAUDE_PARALLEL_LOCK_OFF:-0}" = "1" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0

# Effective identity for lock ownership
IDENTITY="${AGENT_ID:-$SESSION_ID}"
[ -n "$IDENTITY" ] || exit 0  # No identity → can't enforce

CLAIM="${HOME}/.claude/scripts/parallel-claim.sh"
[ -x "$CLAIM" ] || exit 0  # Tool missing → no enforcement

# Check current lock status
STATUS=$("$CLAIM" check "$FILE_PATH" 2>/dev/null)
EXIT=$?

# exit 1 = unlocked/expired → ALLOW
[ "$EXIT" -ne 0 ] && exit 0

# Locked. Parse owner|expires
OWNER=$(echo "$STATUS" | awk -F'|' '{print $1}')
EXPIRES=$(echo "$STATUS" | awk -F'|' '{print $2}')

# Owned by self → ALLOW
[ "$OWNER" = "$IDENTITY" ] && exit 0

# CONFLICT: locked by different agent. Deny with JSON.
REL_PATH=$(echo "$FILE_PATH" | sed "s|$HOME|~|")
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Parallel Lock Conflict: ${REL_PATH} is currently claimed by agent '${OWNER}' (you are '${IDENTITY}'), valid until ${EXPIRES}.\n\nOptions:\n  1. Wait for the other agent to finish (its SubagentStop auto-releases).\n  2. If the other agent is stuck or you need this NOW, manually release:\n     bash ~/.claude/scripts/parallel-claim.sh release '${FILE_PATH}' '${OWNER}'\n  3. Bypass globally: CLAUDE_PARALLEL_LOCK_OFF=1 (use only if you understand the risk)\n\nThis is the Parallel Coordination layer preventing two agents from editing the same file simultaneously. See ~/.claude/scripts/parallel-claim.sh for the registry."
  }
}
JSON
exit 0
