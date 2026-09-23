#!/bin/bash
# IMP-035: Post-Bash-failure recovery prompt
# Fires on PostToolUseFailure for Bash. Evidence: only 31 successful fail→edit→pass
# loops in 5 months despite 684 Bash failures.
#
# History:
#  - v1 (2026-05-24): registered as PostToolUse, checked .tool_response.exit_code
#    → never fired (PostToolUse is success-only; exit_code field doesn't exist).
#  - v2 (2026-05-25): switched to interrupted/stderr-pattern heuristic
#    → only caught edge cases (exit-0-with-error-output, timeouts).
#  - v3 (2026-05-25): re-registered under PostToolUseFailure (the dedicated
#    failure event, see Claude Code docs). Hook can now trust the event itself
#    as the failure signal; pattern heuristic kept as fallback for legacy
#    PostToolUse registration if ever re-enabled.
set -u

INPUT="$(cat)"
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Diagnostic log so we can verify the hook fires (IMP-035 live verification).
echo "[$(date '+%Y-%m-%d %H:%M:%S')] CALLED event=$EVENT tool=$TOOL bytes=${#INPUT}" >> /tmp/postbash-hook.log

[ "$TOOL" = "Bash" ] || exit 0

INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // ""')
STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""')
ERROR_MSG=$(echo "$INPUT" | jq -r '.tool_response.error // .error // ""')

FAILED=0
REASON="bash failure"

if [ "$EVENT" = "PostToolUseFailure" ]; then
  # Trusted failure signal — the harness already classified this as failed.
  FAILED=1
  if [ "$INTERRUPTED" = "true" ]; then
    REASON="interrupted/timeout"
  elif [ -n "$ERROR_MSG" ]; then
    REASON="harness error: ${ERROR_MSG:0:80}"
  else
    REASON="non-zero exit"
  fi
else
  # Legacy PostToolUse path: must heuristically detect failure since this event
  # is success-only in current Claude Code. Kept for defensive coverage.
  [ "$INTERRUPTED" = "true" ] && { FAILED=1; REASON="interrupted/timeout"; }
  if [ "$FAILED" = "0" ] && [ -n "$STDERR" ] && echo "$STDERR" | grep -qiE '(^|[^a-z])(error|fail|denied|not found|no such|cannot|command not found|permission denied|fatal)([^a-z]|$)'; then
    FAILED=1; REASON="stderr error pattern"
  fi
  if [ "$FAILED" = "0" ] && echo "$STDOUT" | grep -qiE '(no such file|command not found|permission denied|fatal error)'; then
    FAILED=1; REASON="stdout error pattern"
  fi
fi

[ "$FAILED" = "1" ] || exit 0

echo "[$(date '+%Y-%m-%d %H:%M:%S')] FIRED event=$EVENT reason=$REASON" >> /tmp/postbash-hook.log

cat <<MSG
⚠ Bash command failed ($REASON).
Before retrying, briefly verify:
  (a) what changed since the last passing run?
  (b) is the working directory still what you expect?
  (c) did the failure output point to a missing dependency or stale state?
MSG
