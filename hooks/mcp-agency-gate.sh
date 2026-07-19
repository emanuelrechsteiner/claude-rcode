#!/bin/bash
# mcp-agency-gate.sh — IMP-078 (2026-07-03, Fable-5 metareview)
# ──────────────────────────────────────────────────────────────
# Deterministic layer for the "MCP-Only ESCALATE Set" (autonomy-arbiter.md):
# the bash excessive-agency-gate cannot see MCP tool calls, so production-capable
# writes (SQL, migrations, deploys, external comms) were guarded ONLY by prose
# rules the model must remember. This hook fires on PreToolUse matcher `mcp__.*`
# and routes irreversible-class MCP tools through the NATIVE permission prompt
# via permissionDecision:"ask" — a real user y/n, no token machinery needed.
#
# Design notes:
# - Classified by tool-name SUFFIX (server names are per-connector UUIDs).
# - "ask", not "deny": the user can approve in one click; in headless runs an
#   unanswerable ask fails safe.
# - Read-only / reversible / notify-no-one MCP tools pass silently (AUTO band).
# - deploy_to_vercel: preview deploys are SOFT-ACK (allowed + note); only a
#   prod-flagged input escalates (per cloud-cli-discipline.md).
# - Logged to global-observation/excessive-agency.log with gate:"mcp".
set -u

INPUT=$(cat 2>/dev/null || printf '{}')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || printf '')
case "$TOOL" in mcp__*) ;; *) exit 0 ;; esac

SUFFIX="${TOOL##*__}"
LOG_FILE="$HOME/.claude/global-observation/excessive-agency.log"

# Irreversible / external-comms / production-capable MCP tool suffixes.
ESCALATE_RE='^(apply_migration|execute_sql|deploy_edge_function|firebase_deploy|pause_project|restore_project|merge_branch|rebase_branch|reset_branch|delete_branch|merge_pull_request|execute_action|create_event|update_event|delete_event|respond_to_event)$'

ASK=0
REASON=""
if printf '%s' "$SUFFIX" | grep -qE "$ESCALATE_RE"; then
    ASK=1
    REASON="MCP-Only ESCALATE Set (autonomy-arbiter.md): '$SUFFIX' mutates production data, shared state, or communicates externally — requires explicit user approval even in YOLO mode."
fi

# Vercel deploy: preview = SOFT-ACK (allow, note), prod = ask.
if [ "$SUFFIX" = "deploy_to_vercel" ]; then
    if printf '%s' "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null | grep -qiE 'prod'; then
        ASK=1
        REASON="Production Vercel deploy via MCP — irreversible/externally visible; preview deploys pass without prompt."
    else
        echo "NOTE: preview deploy via MCP (SOFT-ACK band) — reversible, proceeding; prod deploys require y/n." >&2
        exit 0
    fi
fi

if [ "$ASK" = "1" ]; then
    printf '{"ts":"%s","gate":"mcp","tool":"%s","band":"ESCALATE","decision":"ask","cwd":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "$(pwd)" >> "$LOG_FILE" 2>/dev/null || true
    jq -n --arg r "$REASON" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $r
        }
    }'
    exit 0
fi

exit 0
