#!/usr/bin/env bash
# Stop hook — appends session-end summary to self-critique.jsonl for later meta-observer analysis.
# Added 2026-05-26 per Wave 4 of MIGRATION-PLAN.md v3.
# Reason: KB cluster 05 — "agents self-report friction" pattern (PostHog / Cursor / Danilo Campos).
# This is OBJECTIVE-metadata-only — no LLM call. Actual self-critique comes from meta-observer
# skill on demand, reading these logs.

set -euo pipefail

LOG="$HOME/.claude/global-observation/self-critique.jsonl"
mkdir -p "$(dirname "$LOG")"

SESSION_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CWD="$(pwd)"

# IMP-082: read the Stop-hook JSON (this hook ignored stdin entirely before) so
# recent_edits can be a REAL per-session count instead of a tail-1000 proxy that
# saturated at 1000 in 51% of records. Fallback to the old proxy if no session id.
HOOK_INPUT=$(cat 2>/dev/null || printf '{}')
SID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || printf '')

SIGNALS="$HOME/.claude/global-observation/signals.jsonl"
if [ -f "$SIGNALS" ] && [ -n "$SID" ]; then
  EDITS_LAST_HOUR=$(grep -F "\"session_id\":\"$SID\"" "$SIGNALS" 2>/dev/null \
    | grep -cE '"tool":"(Edit|Write)"' | tr -d '\n')
  [[ "$EDITS_LAST_HOUR" =~ ^[0-9]+$ ]] || EDITS_LAST_HOUR=0
elif [ -f "$SIGNALS" ]; then
  EDITS_LAST_HOUR=$(tail -1000 "$SIGNALS" 2>/dev/null \
    | grep -cE '"tool":"(Edit|Write)"' | tr -d '\n')
  [[ "$EDITS_LAST_HOUR" =~ ^[0-9]+$ ]] || EDITS_LAST_HOUR=0
else
  EDITS_LAST_HOUR=0
fi

# Git context (best-effort)
if git rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
  UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | xargs || echo 0)
else
  BRANCH="not-a-git-repo"
  UNCOMMITTED=0
fi

# Append JSONL line — ONE physical line per record. Sanitize counts to bare
# integers, then build the object with jq so it is always single-line and
# correctly escaped. Fall back to a hand-built single line only if jq is absent.
UF=${UNCOMMITTED//[!0-9]/}; UF=${UF:-0}
RE=${EDITS_LAST_HOUR//[!0-9]/}; RE=${RE:-0}
if command -v jq >/dev/null 2>&1; then
  jq -nc \
    --arg ts "$SESSION_END" \
    --arg cwd "$CWD" \
    --arg branch "$BRANCH" \
    --arg sid "$SID" \
    --argjson uncommitted_files "$UF" \
    --argjson recent_edits "$RE" \
    '{ts:$ts,cwd:$cwd,branch:$branch,session_id:$sid,uncommitted_files:$uncommitted_files,recent_edits:$recent_edits}' \
    >> "$LOG"
else
  printf '{"ts":"%s","cwd":"%s","branch":"%s","uncommitted_files":%s,"recent_edits":%s}\n' \
    "$SESSION_END" "$CWD" "$BRANCH" "$UF" "$RE" >> "$LOG"
fi

# Output for visibility
echo "📝 Session-end log → $LOG (branch=$BRANCH uncommitted=$UNCOMMITTED edits=$EDITS_LAST_HOUR)"

# Heuristic: if there were many edits + still uncommitted, suggest /meta-observe
if [ "$UNCOMMITTED" -gt 5 ] && [ "$EDITS_LAST_HOUR" -gt 20 ]; then
  echo "   Note: $UNCOMMITTED uncommitted files with $EDITS_LAST_HOUR recent edits — run /meta-observe to extract patterns."
fi
