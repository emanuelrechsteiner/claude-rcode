#!/bin/bash
# mcp-agency-gate.sh — IMP-078 (2026-07-03, Fable-5 metareview)
# ──────────────────────────────────────────────────────────────
# Deterministic layer for the "MCP-Only ESCALATE Set" (docs/reference/agency-bands.md, MCP escalate set):
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
#   prod-flagged input escalates (per the cloud-cli-discipline skill).
# - Logged to global-observation/excessive-agency.log with gate:"mcp".
set -u

INPUT=$(cat 2>/dev/null || printf '{}')

# DEPENDENCY PREAMBLE — FAIL CLOSED (2026-11-06): without jq the tool name is
# unreadable, and the old TOOL="" → exit 0 let every MCP call through with no
# ESCALATE check. Deny with a native JSON decision that names the fix.
if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"mcp-agency-gate.sh cannot run: jq is not installed or not on PATH. The MCP ESCALATE layer is inactive, so MCP calls are refused until it is fixed. Fix: brew install jq. Tell the user which dependency is missing; do not route the MCP call around this gate."}}'
    exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || printf '')
case "$TOOL" in mcp__*) ;; *) exit 0 ;; esac

SUFFIX="${TOOL##*__}"
LOG_FILE="$HOME/.claude/global-observation/excessive-agency.log"

# Irreversible / external-comms / production-capable MCP tool suffixes.
# NOTE: execute_sql is intentionally NOT here — it is handled by the SQL-aware
# block below (read-only SELECT/WITH/EXPLAIN/SHOW = AUTO band, no blast radius;
# only write/DDL statements escalate). apply_migration stays: it is always a
# schema write.
ESCALATE_RE='^(apply_migration|deploy_edge_function|firebase_deploy|pause_project|restore_project|merge_branch|rebase_branch|reset_branch|delete_branch|merge_pull_request|execute_action|create_event|update_event|delete_event|respond_to_event)$'

ASK=0
REASON=""
if printf '%s' "$SUFFIX" | grep -qE "$ESCALATE_RE"; then
    ASK=1
    REASON="MCP-Only ESCALATE Set (docs/reference/agency-bands.md, MCP escalate set): '$SUFFIX' mutates production data, shared state, or communicates externally — requires explicit user approval even in YOLO mode."
fi

# SQL: classify by the STATEMENT, not the tool name. Only a statement POSITIVELY
# recognised as read-only is allowed silently (AUTO band): SELECT, WITH ... SELECT
# without write keywords, SHOW, EXPLAIN without ANALYZE/ANALYSE, VALUES. Everything
# else asks: write/DDL keywords, empty text, multi-statement text (a ';' before
# the final terminator) and any statement the classifier does not recognise
# (IMP-271a: fail safe to ask). Word-boundary matching via non-alnum→space
# normalization so column names like updated_at / created_at do NOT trigger.
WRITE_RE=' (INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE|MERGE|REINDEX|VACUUM|REPLACE|CLUSTER|COPY|CALL|REFRESH|COMMENT|SECURITY) '

# Functions that change state although the statement around them looks like a read
# (finding of the commit security review, 2026-11-11): sequences, session settings,
# backend control, advisory locks, replication, files, large objects, dblink. The list
# cannot know user-defined functions: rules/agency-bands.md keeps that as a judgment.
# Also listed: notifications, the try-forms of the advisory locks, and the two extension
# families whose whole purpose is a side effect (scheduler cron.*, HTTP senders http_*).
SIDE_EFFECT_FN='DBLINK[A-Z0-9_]*|SETVAL|NEXTVAL|SET_CONFIG|PG_TERMINATE_BACKEND|PG_CANCEL_BACKEND|PG_RELOAD_CONF|PG_ROTATE_LOGFILE|PG_SWITCH_WAL|PG_PROMOTE|PG_READ_FILE|PG_READ_BINARY_FILE|PG_LS_DIR|PG_STAT_RESET[A-Z0-9_]*|PG_ADVISORY_[A-Z0-9_]+|PG_TRY_ADVISORY_[A-Z0-9_]+|PG_NOTIFY|PG_CREATE_[A-Z0-9_]+|PG_DROP_[A-Z0-9_]+|PG_REPLICATION_[A-Z0-9_]+|PG_LOGICAL_[A-Z0-9_]+|PG_SLEEP[A-Z0-9_]*|LO_[A-Z0-9_]+|QUERY_TO_XML[A-Z0-9_]*|CRON\.[A-Z0-9_]+|HTTP_[A-Z0-9_]+'

# sql_verdict <statement> -> stdout: read | write | unknown
sql_verdict() {
    local q="$1" s prev body lead norm comment upper tail_free
    # The database ends a line comment at a carriage return as well as at a line feed. With
    # only the line feed known here, "-- note<CR>statement" would pass as one comment while
    # the database executes the statement: every check below sees one line-end form.
    q="${q//$'\r'/$'\n'}"
    s="$q"
    # Strip leading whitespace and leading SQL comments (-- line, /* block */).
    while :; do
        prev="$s"
        s="${s#"${s%%[![:space:]]*}"}"
        case "$s" in
            --*)
                if [[ "$s" == *$'\n'* ]]; then s="${s#*$'\n'}"; else s=""; fi ;;
            '/*'*)
                if [[ "$s" == *'*/'* ]]; then
                    # PostgreSQL nests block comments, this classifier does not: a second
                    # opener inside the comment means the database may end the comment later
                    # than we do and execute text we took for commented out. Ask.
                    comment="${s%%'*/'*}"
                    case "${comment#'/*'}" in *'/*'*) printf 'unknown'; return 0 ;; esac
                    s="${s#*'*/'}"
                else s=""; fi ;;
        esac
        [ "$s" = "$prev" ] && break
    done
    # Empty, whitespace-only or comment-only text: the pre-IMP-271a reason applies.
    [ -n "$s" ] || { printf 'write'; return 0; }
    norm=" $(printf '%s' "$q" | LC_ALL=C tr '[:lower:]' '[:upper:]' | LC_ALL=C tr -c 'A-Z0-9' ' ' | LC_ALL=C tr -s ' ') "
    if printf '%s' "$norm" | grep -qE "$WRITE_RE"; then printf 'write'; return 0; fi
    # A block comment inside the statement, or a stray terminator, can hide what the
    # database really executes (same nesting differential): ask.
    case "$s" in *'/*'*|*'*/'*) printf 'unknown'; return 0 ;; esac
    # A line comment that is followed by more statement text can separate a name from its
    # call or hide a token: only a comment on the last line is harmless. Ask otherwise.
    # Whitespace after that last comment line hides nothing and is dropped first.
    tail_free="${s%"${s##*[![:space:]]}"}"
    case "$tail_free" in *--*)
        case "${tail_free##*--}" in *$'\n'*) ;; *) tail_free="${tail_free%--*}" ;; esac ;;
    esac
    case "$tail_free" in *--*) printf 'unknown'; return 0 ;; esac
    # A read-shaped statement that calls a known side-effect function is not a read. The
    # match runs on one line: every whitespace class the database skips (space, tab, line
    # feed, carriage return, form feed, vertical tab) becomes a space.
    upper=$(printf '%s' "$q" | LC_ALL=C tr '[:lower:]' '[:upper:]' | LC_ALL=C tr '[:space:]' ' ')
    # A Unicode-escape form (U&"..." or U&'...') spells a name this classifier cannot read,
    # and a quoted name directly before a parenthesis is a call whose target it cannot
    # compare reliably (case, doubled quotes): ask.
    case "$upper" in *'U&"'*|*"U&'"*) printf 'unknown'; return 0 ;; esac
    if printf '%s' "$upper" | grep -qE '" *\('; then printf 'unknown'; return 0; fi
    # Identifier quotes are dropped and blanks around a schema dot closed, so "cron" . schedule
    # and cron.schedule are the same text for the match.
    upper=$(printf '%s' "$upper" | LC_ALL=C tr -d '"' | LC_ALL=C sed -E 's/ *\. */./g')
    if printf '%s' "$upper" | grep -qE "(^|[^A-Z0-9_])($SIDE_EFFECT_FN) *\("; then printf 'unknown'; return 0; fi
    # Multi-statement: any ';' left once the final terminator is removed.
    body="$s"
    while [ -n "$body" ]; do
        case "$body" in
            *[[:space:]]) body="${body%[[:space:]]}" ;;
            *';') body="${body%;}" ;;
            *) break ;;
        esac
    done
    case "$body" in *';'*) printf 'unknown'; return 0 ;; esac
    # The leading keyword must be the whole identifier: "SELECT(1)" is SELECT,
    # "SELECT_x(1)" and "(SELECT 1)" are not recognised.
    lead="${s%%[!A-Za-z0-9_]*}"
    lead=$(printf '%s' "$lead" | LC_ALL=C tr '[:lower:]' '[:upper:]')
    case "$lead" in
        SELECT|WITH|SHOW|VALUES|EXPLAIN) ;;
        *) printf 'unknown'; return 0 ;;
    esac
    case "$norm" in *" INTO "*|*" FOR "*) printf 'unknown'; return 0 ;; esac
    case "$lead" in
        WITH) case "$norm" in *" SELECT "*) ;; *) printf 'unknown'; return 0 ;; esac ;;
        EXPLAIN) case "$norm" in *" ANALYZE "*|*" ANALYSE "*) printf 'unknown'; return 0 ;; esac ;;
    esac
    printf 'read'
}

if [ "$SUFFIX" = "execute_sql" ]; then
    Q=$(printf '%s' "$INPUT" | jq -r '.tool_input.query // .tool_input.sql // ""' 2>/dev/null || printf '')
    VERDICT=$(sql_verdict "$Q")
    if [ "$VERDICT" = "read" ]; then
        printf '{"ts":"%s","gate":"mcp","tool":"%s","band":"AUTO","decision":"allow-read","cwd":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "$(pwd)" >> "$LOG_FILE" 2>/dev/null || true
        # Explicit allow so a read query passes WITHOUT a prompt even though the
        # supabase MCP server is not in settings.json permissions.allow. A bare
        # exit 0 would defer to the native default, which still prompts.
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "allow",
                permissionDecisionReason: "Read-only SQL (SELECT/WITH ... SELECT/SHOW/EXPLAIN without ANALYZE/VALUES) — no blast radius, AUTO band per agency-bands.md."
            }
        }'
        exit 0
    fi
    ASK=1
    if [ "$VERDICT" = "write" ]; then
        REASON="execute_sql contains a write/DDL statement (or query could not be read) — mutates data or schema; requires explicit approval even in YOLO mode."
    else
        REASON="execute_sql statement is not positively recognised as read-only (SELECT, WITH ... SELECT, SHOW, EXPLAIN without ANALYZE, VALUES; multi-statement text counts as unrecognised) — requires explicit approval even in YOLO mode."
    fi
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
