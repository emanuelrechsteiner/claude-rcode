#!/bin/bash
# knowledge-brief-check.sh — PreToolUse gate on Task|Agent: the KNOWLEDGE field of a brief (IMP-268)
# ─────────────────────────────────────────────────────────────────────────────
# The decision is kb_decide in hooks/lib/knowledge-brief.sh; knowledge-inject.sh asks the same function,
# and the denial counter key comes from kb_counter_key there too.
# Rules: marker KNOWLEDGE:/WISSEN: in capitals outside fences, the last one wins; block under 4000 bytes.
# cited: every note resolves inside the mirror (no .., no symlink), one verbatim excerpt (30+ bytes) matches.
# none: a sets: clause and two knowledge-agent runs (distinct agent ids) in the window.
# unavailable: 20 bytes of reason and one knowledge-agent dispatch in the window.
# DENY, not ask: the omission is the lead's own. Modes CLAUDE_KNOWLEDGE_BRIEF: deny | advisory | off.
# Denials 1-3 block, 4 escalates, 5+ pass and are logged; advisory adds the cause as "attempt N".
# Every fail-open path writes a log line. Log: CLAUDE_KNOWLEDGE_BRIEF_LOG, TSV: ts, session, subagent, verdict, event, detail.
# ─────────────────────────────────────────────────────────────────────────────
set -u
# Byte mode for every text tool: the brief may carry umlauts.
export LC_ALL=C

STATE_ROOT="${CLAUDE_KNOWLEDGE_STATE_ROOT:-/tmp}"
LOG_FILE="${CLAUDE_KNOWLEDGE_BRIEF_LOG:-$HOME/.claude/global-observation/knowledge-brief.log}"
MODE="${CLAUDE_KNOWLEDGE_BRIEF:-deny}"
WINDOW="${CLAUDE_KNOWLEDGE_BRIEF_WINDOW:-1800}"
LIB_FILE="$(dirname "$0")/lib/knowledge-brief.sh"
SESSION_ID="" SUBAGENT="" SUB_LOG="-" DESCRIPTION="" PROMPT="" VERDICT="-"

# CLAUDE_KNOWLEDGE_DIR: environment first, else ~/.claude/env.local.sh (subshell, -u/-e off).
resolve_kdir() {
    local kdir="${CLAUDE_KNOWLEDGE_DIR:-}"
    if [ -z "$kdir" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
        # shellcheck disable=SC1091
        kdir=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" )
    fi
    printf '%s' "${kdir%/}"
}

emit_deny() {  # <reason>
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
}

emit_context() {  # <additionalContext>
    jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
}

tab_free() { printf '%s' "$1" | tr '\t\r\n' '   '; }

# log_raw <session> <subagent> <verdict> <event> <detail>: one TSV line; a failing log never fails the hook.
log_raw() {
    local line
    line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(tab_free "${1:--}")" \
        "$(tab_free "${2:--}")" "$(tab_free "${3:--}")" "$(tab_free "$4")" "$(tab_free "$5")")
    { mkdir -p "$(dirname "$LOG_FILE")" && printf '%s\n' "$line" >> "$LOG_FILE"; } 2>/dev/null \
        || printf 'knowledge-brief: cannot write log %s\n' "$LOG_FILE" >&2
}

log_event() {  # <event> <detail>: a log line for this dispatch, with the current verdict
    log_raw "$SESSION_ID" "$SUB_LOG" "$VERDICT" "$1" "$2"
}

log_once() {  # <verdict> <event> <detail> <marker-suffix>: first occurrence per session
    local marker="$STATE_DIR/brief-once-$4"
    [ -e "$marker" ] && return 0
    : > "$marker" 2>/dev/null
    log_raw "$SESSION_ID" "$SUB_LOG" "$1" "$2" "$3"
}

fail_open() {  # <event> <note>: a stderr note, a log line, and a silent allow
    printf 'knowledge-brief: %s; allowing (fail open)\n' "$2" >&2
    log_raw "$SESSION_ID" "$SUB_LOG" "$VERDICT" "$1" "$2"
    exit 0
}

allow() {  # <event> <detail>: logs the verdict and lets the dispatch through
    log_event "$1" "$2"
    exit 0
}

deny_text() {  # <denial count> <cause>
    local label="denial $1 of 3"
    if [ "$MODE" = advisory ]; then label="attempt $1"; fi
    printf '%s' "Knowledge brief (IMP-268): the dispatch to $SUB_SHOW carries no valid KNOWLEDGE field ($label). Run the knowledge round first: spawn knowledge-agent (haiku, low) with 2–4 keyword sets for this unit, judge the verbatim excerpts, then put ONE of these in the brief: KNOWLEDGE (lead-supplied): sets: \"...\" | \"...\"; <path>.md L<a>–<b>: \"<verbatim excerpt>\"  |  KNOWLEDGE: none relevant after 2 searches — sets: ...  |  KNOWLEDGE: unavailable — <reason>. $2"
}

refuse() {  # <cause>: counts this denial, then denies, escalates or stays silent
    local cause="$1" key previous text count
    key=$(kb_counter_key "$SUBAGENT" "$DESCRIPTION" "$PROMPT") || key=""
    [ -n "$key" ] || fail_open no-hash "no sha1 tool or hash failed"
    COUNT_FILE="$STATE_DIR/brief-denials-$key"
    previous=$(cat "$COUNT_FILE" 2>/dev/null || printf '0')
    case "$previous" in
        ''|*[!0-9]*) log_event counter-reset "$COUNT_FILE held a non-number; reset to 0"
            printf 'knowledge-brief: corrupt denial counter %s; resetting to 0\n' "$COUNT_FILE" >&2; previous=0 ;;
    esac
    count=$((previous + 1))
    { printf '%s\n' "$count" > "$COUNT_FILE"; } 2>/dev/null || fail_open counter-unwritable "cannot write $COUNT_FILE"
    if [ "$MODE" = deny ] && [ "$count" -gt 3 ]; then
        log_event escalation "denial $count, allowed; $cause"
        if [ "$count" -eq 4 ]; then
            emit_context "ESCALATION (knowledge brief, IMP-268): dispatch allowed after 3 denials without a valid KNOWLEDGE field for $SUB_SHOW; this is logged."
        fi
        exit 0
    fi
    text=$(deny_text "$count" "$cause")
    if [ "$MODE" = deny ]; then
        log_event deny "denial $count of 3; $cause"
        emit_deny "$text"
    else
        log_event advisory "attempt $count; $cause"
        emit_context "$text"
    fi
    exit 0
}

# load_lib: sources the shared parser; a missing parser is logged once and fails open.
load_lib() {
    if [ ! -f "$LIB_FILE" ]; then
        log_once - parser-missing "$LIB_FILE" parser-missing
        printf 'knowledge-brief: parser %s missing; allowing (fail open)\n' "$LIB_FILE" >&2
        return 1
    fi
    # shellcheck disable=SC1090,SC1091
    . "$LIB_FILE"
}

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
    printf 'knowledge-brief: jq missing; allowing (fail open)\n' >&2
    log_raw - - - jq-missing "jq is not installed; the gate cannot read the hook input"
    exit 0
fi
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || fail_open not-json "hook input is not JSON"

# One jq call; fields joined by \001. The prompt comes last because it may contain anything.
SEP=$'\001'
FIELDS=$(printf '%s' "$INPUT" | jq -r 'def ti: (.tool_input | if type == "object" then . else {} end);
    [(.tool_name // ""), (.session_id // ""), (ti.subagent_type // ""), (ti.description // ""), (ti.prompt // "")] | join("\u0001")') \
    || fail_open fields-unreadable "cannot read the hook fields"
TOOL=${FIELDS%%"$SEP"*}; REST=${FIELDS#*"$SEP"}
SESSION_ID=${REST%%"$SEP"*}; REST=${REST#*"$SEP"}
SUBAGENT=${REST%%"$SEP"*}; REST=${REST#*"$SEP"}
DESCRIPTION=${REST%%"$SEP"*}; PROMPT=${REST#*"$SEP"}

case "$TOOL" in Task|Agent) ;; *) exit 0 ;; esac
SUB_LOG=$(tab_free "$SUBAGENT"); [ -n "$SUB_LOG" ] || SUB_LOG=-
SUB_SHOW=$(printf '%s' "$SUBAGENT" | tr -d '\000-\037' | cut -c1-80)
[ -n "$SUB_SHOW" ] || SUB_SHOW="(no subagent_type)"
if [ -z "$SESSION_ID" ]; then log_raw - "$SUB_LOG" - no-session "empty session_id; the gate has no state to key"; exit 0; fi

case "$MODE" in
    deny|advisory|off) ;;
    *) log_raw "$SESSION_ID" "$SUB_LOG" - mode-fallback "CLAUDE_KNOWLEDGE_BRIEF=$MODE is unknown; using deny"
       printf 'knowledge-brief: unknown CLAUDE_KNOWLEDGE_BRIEF=%s; using deny\n' "$MODE" >&2; MODE=deny ;;
esac
case "$WINDOW" in
    ''|*[!0-9]*) log_raw "$SESSION_ID" "$SUB_LOG" - window-fallback "CLAUDE_KNOWLEDGE_BRIEF_WINDOW=$WINDOW is not a number; using 1800"
       printf 'knowledge-brief: CLAUDE_KNOWLEDGE_BRIEF_WINDOW=%s is not a number; using 1800\n' "$WINDOW" >&2; WINDOW=1800 ;;
esac

SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_')
STATE_DIR="$STATE_ROOT/knowledge-gate-$SAFE_SID"
if ! { mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"; } 2>/dev/null; then
    fail_open state-dir "cannot create state dir $STATE_DIR"
fi

if [ "$SUBAGENT" = knowledge-agent ]; then
    load_lib || exit 0
    kb_mark_dispatch "$STATE_DIR" || {
        printf 'knowledge-brief: cannot record the knowledge-agent dispatch in %s\n' "$STATE_DIR" >&2
        log_event mark-failed "knowledge-agent dispatch not recorded"
    }
    log_once - exempt-knowledge-agent "the knowledge-agent is the search itself" exempt-knowledge-agent
    exit 0
fi
if [ "$MODE" = off ]; then
    log_once - off "CLAUDE_KNOWLEDGE_BRIEF=off" off
    exit 0
fi
KDIR=$(resolve_kdir)
if [ -z "$KDIR" ] || [ ! -f "$KDIR/mirror/README.md" ]; then
    log_once - library-missing "KDIR=${KDIR:-unset}" library-missing
    exit 0
fi
load_lib || exit 0

BLOCK=$(kb_block "$PROMPT") || BLOCK=""
DECISION=$(kb_decide "$BLOCK" "$KDIR" "$STATE_DIR" "$WINDOW")
DEC_KIND=${DECISION%% *}; DEC_REST=${DECISION#* }
VERDICT=${DEC_REST%% *}; CAUSE=${DEC_REST#* }
case "$DEC_KIND" in
    allow)
        case "$VERDICT" in
            cited) allow allow-cited "$CAUSE" ;;
            none) allow allow-none "$CAUSE" ;;
            unavailable) allow allow-unavailable "$CAUSE" ;;
        esac ;;
    deny) refuse "$CAUSE" ;;
    *) fail_open decision-error "kb_decide returned no decision" ;;
esac
fail_open decision-error "unexpected decision: $DECISION"
