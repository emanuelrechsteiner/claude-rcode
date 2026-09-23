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

# ── Ownership via BIND, not string equality (IMP-114, 2026-08-01) ─────────────
# This used to be `[ "$OWNER" = "$IDENTITY" ] && exit 0`. OWNER is the
# orchestrator's invented claim id ("pdispatch-<turn>-<unit>"); IDENTITY is the
# runtime's 17-hex agent id (or the session id on the main thread). The two
# identifier spaces never intersect, so the test could not succeed — and the
# fall-through is DENY. Measured directly on 2026-08-01: after a claim, the
# dispatched subagent AND the orchestrator were both denied their own file
# until TTL expiry. A claim was a self-inflicted denial of service, which is
# why write fan-outs were never usable in practice.
#
# `bind` resolves the join: first toucher within the claiming session takes
# ownership; a genuinely different agent still gets denied below.
if "$CLAIM" bind "$FILE_PATH" "$IDENTITY" "$SESSION_ID" >/dev/null 2>&1; then
    exit 0
fi
BOUND=$("$CLAIM" bind "$FILE_PATH" "$IDENTITY" "$SESSION_ID" 2>&1 >/dev/null || true)

# CONFLICT: locked by different agent. Deny with JSON.
REL_PATH=$(echo "$FILE_PATH" | sed "s|$HOME|~|")
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Parallel Lock Conflict: ${REL_PATH} is claimed as '${OWNER}' and already bound to a DIFFERENT running agent (${BOUND}; you are '${IDENTITY}'), valid until ${EXPIRES}.\n\nThis means two agents are genuinely targeting the same file — the collision this registry exists to catch. Do NOT just retry.\n\nOptions:\n  1. Wait for the other agent to finish (its SubagentStop now really does release — IMP-114).\n  2. If that agent is stuck: bash ~/.claude/scripts/parallel-claim.sh release '${FILE_PATH}' '${OWNER}'\n  3. Orchestrator cleanup of a whole dispatch: parallel-claim.sh release-session '${SESSION_ID}'\n  4. Bypass globally: CLAUDE_PARALLEL_LOCK_OFF=1 (only if you understand the risk)\n\nSee ~/.claude/scripts/parallel-claim.sh — the two identity spaces are documented at the top."
  }
}
JSON
exit 0
