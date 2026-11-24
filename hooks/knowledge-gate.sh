#!/bin/bash
# knowledge-gate.sh — PreToolUse gate on Write|Edit|MultiEdit (IMP-267)
# ─────────────────────────────────────────────────────────────────────
# Asks an agent to consult the cross-project knowledge library (the mirror of
# the knowledge library, docs/OBSIDIAN.md Stage 3) before it edits. Basis:
# measured non-use of the lookup (2026-10-31).
#
# Evidence of a lookup is a per-identity record written by knowledge-record.sh
# (PostToolUse) to $STATE_DIR/record-<identity>.tsv. Identity is agent_id
# (subagents) or "main"; a parent's record never satisfies a subagent.
# Bash-less agents cannot run the lookup, so an auto-inject line (written by
# knowledge-inject.sh) satisfies them; their deny text asks for a Read or Grep
# of one mirror note instead of a Bash command.
# IMP-268: a lead-supplied line (knowledge-inject.sh, at SubagentStart, when the brief's KNOWLEDGE
# field cites notes or says none relevant) satisfies every agent type, Bash-less ones included:
# the parent's knowledge round, checked by knowledge-brief-check.sh, is the evidence, not the subagent.
#
# Mode CLAUDE_KNOWLEDGE_GATE: deny (default) | advisory | off.
# Denials 1-3 block in deny mode; the 4th attempt is allowed with an ESCALATION
# note (IMP-164: the repeated message must look different); from the 5th on the
# edit is allowed silently and logged with its count.
# Fail open: no library, no lookup script, or no writable state dir -> exit 0.
# The gate never runs the lookup itself: file tests only. The env.local.sh
# subshell runs only after the cheap checks (tool, mode, exempt paths).
# ─────────────────────────────────────────────────────────────────────
set -u
# Byte mode for awk, tr, sed and grep: record lines and paths may carry umlauts, and awk under a
# UTF-8 locale can abort on them (found 2026-11-01 in knowledge-record.sh). Nothing here needs characters.
export LC_ALL=C

LOG_FILE="${CLAUDE_KNOWLEDGE_GATE_LOG:-$HOME/.claude/global-observation/knowledge-gate.log}"
AGENTS_DIR="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
LOOKUP="${CLAUDE_KNOWLEDGE_LOOKUP:-$HOME/.claude/scripts/knowledge-lookup.sh}"
STATE_ROOT="${CLAUDE_KNOWLEDGE_STATE_ROOT:-/tmp}"
LOOKUP_CMD='bash ~/.claude/scripts/knowledge-lookup.sh --max 6 "<your own words>" --alt "<German/English translation>" --alt "<technical terms>"'

# CLAUDE_KNOWLEDGE_DIR: environment first, else ~/.claude/env.local.sh (subshell, -u/-e off).
resolve_kdir() {
    local kdir="${CLAUDE_KNOWLEDGE_DIR:-}"
    if [ -z "$kdir" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
        # shellcheck disable=SC1091
        kdir=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" )
    fi
    printf '%s' "${kdir%/}"
}

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
    printf 'knowledge-gate: hook input is not JSON; allowing (fail open)\n' >&2
    exit 0
fi
field() { printf '%s' "$INPUT" | jq -r "$1 // empty"; }

TOOL=$(field '.tool_name')
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
SESSION_ID=$(field '.session_id')
[ -n "$SESSION_ID" ] || exit 0
FILE_PATH=$(field '.tool_input.file_path')
# Identity and agent_type reach the deny text, the log and file names: keep only [A-Za-z0-9_:.-].
# Same sanitiser as knowledge-record.sh, so both hooks name the same record file. An agent_id
# that sanitises to nothing becomes "unknown-agent", never "main" (that would borrow main's record).
RAW_AGENT_ID=$(field '.agent_id')
AGENT_ID=$(printf '%s' "$RAW_AGENT_ID" | tr -cd 'A-Za-z0-9_:.-')
if [ -n "$RAW_AGENT_ID" ] && [ -z "$AGENT_ID" ]; then AGENT_ID=unknown-agent; fi
AGENT_TYPE=$(field '.agent_type' | tr -cd 'A-Za-z0-9_:.-')
IDENTITY=${AGENT_ID:-main}
SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_')
SAFE_ID=$(printf '%s' "$IDENTITY" | tr -c 'A-Za-z0-9_-' '_')
STATE_DIR="$STATE_ROOT/knowledge-gate-$SAFE_SID"
RECORD="$STATE_DIR/record-$SAFE_ID.tsv"

MODE="${CLAUDE_KNOWLEDGE_GATE:-deny}"
case "$MODE" in
    deny|advisory|off) ;;
    *) printf 'knowledge-gate: unknown CLAUDE_KNOWLEDGE_GATE=%s; using deny\n' "$MODE" >&2; MODE=deny ;;
esac

if ! { mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"; } 2>/dev/null; then
    printf 'knowledge-gate: cannot create state dir %s; allowing (fail open)\n' "$STATE_DIR" >&2
    exit 0
fi

log_event() {  # <event> <detail>
    local ts detail session
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    detail=$(printf '%s' "$2" | tr '\t\r\n' '   ')
    session=$(printf '%s' "$SESSION_ID" | tr '\t\r\n' '   ')
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$session" "$IDENTITY" "${AGENT_TYPE:--}" "$1" "$detail" 2>/dev/null >> "$LOG_FILE" \
        || printf 'knowledge-gate: cannot write log %s\n' "$LOG_FILE" >&2
}

log_once() {  # <event> <detail> <marker-suffix>: first occurrence per session (and identity)
    local marker="$STATE_DIR/once-$3"
    [ -e "$marker" ] && return 0
    : > "$marker" 2>/dev/null
    log_event "$1" "$2"
}

if [ "$MODE" = off ]; then
    log_once off "CLAUDE_KNOWLEDGE_GATE=off" off
    exit 0
fi

[ -n "$FILE_PATH" ] || exit 0

has_dotdot() {  # <path>: a ".." segment means the location is not what it names, so never exempt
    case "$1" in */../*|*/..|../*|..) return 0 ;; esac
    return 1
}

is_static_exempt() {  # <path>: exempt without knowing where the library is
    has_dotdot "$1" && return 1
    case "$1" in
        /tmp/*|/private/tmp/*|/var/folders/*) return 0 ;;
    esac
    if [ -n "${TMPDIR:-}" ]; then
        case "$1" in "${TMPDIR%/}"/*) return 0 ;; esac
    fi
    case "$1" in
        */.rcode/*|*/.git/*) return 0 ;;
        "$HOME"/.claude/plans/*|"$HOME"/.claude/global-observation/*) return 0 ;;
        */NOTES.md|*/BRAINSTORM.md|*/TODO.md|*/SCRATCH.md|*/draft-*.md) return 0 ;;
        */test/fixtures/*|*/__fixtures__/*|*/__snapshots__/*) return 0 ;;
    esac
    return 1
}

if is_static_exempt "$FILE_PATH"; then
    [ "${CLAUDE_KNOWLEDGE_GATE_VERBOSE:-0}" = 1 ] && log_event exempt "$FILE_PATH"
    exit 0
fi

KDIR=$(resolve_kdir)
if [ -n "$KDIR" ] && ! has_dotdot "$FILE_PATH"; then
    case "$FILE_PATH" in
        "$KDIR"/*)
            [ "${CLAUDE_KNOWLEDGE_GATE_VERBOSE:-0}" = 1 ] && log_event exempt "$FILE_PATH"
            exit 0 ;;
    esac
fi

if [ -z "$KDIR" ] || [ ! -f "$KDIR/mirror/README.md" ] || [ ! -f "$LOOKUP" ]; then
    log_once library-missing "KDIR=${KDIR:-unset} LOOKUP=$LOOKUP" library-missing
    exit 0
fi

record_has() {  # <kind>
    [ -f "$RECORD" ] && awk -F '\t' -v k="$1" '$2 == k { found = 1; exit } END { exit !found }' "$RECORD"
}

is_bashless() {  # <agent_type>: 0 when agents/<type>.md declares a tools list without Bash (same rule as knowledge-inject.sh)
    local type="$1" file verdict
    [ "$IDENTITY" = main ] && return 1
    case "$type" in ''|*..*|*[!A-Za-z0-9_:-]*) return 1 ;; esac
    file="$AGENTS_DIR/$type.md"
    [ -f "$file" ] || return 1
    verdict=$(awk '
        function tok(t) {
            gsub(/^[ \t]+|[ \t,]+$/, "", t); sub(/^"/, "", t); sub(/"$/, "", t)
            if (t ~ /^Bash([ (]|$)/) hasbash = 1
            if (t != "") present = 1
        }
        NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---" { exit }
        /^tools:/ {
            intools = 1; line = substr($0, 7); gsub(/[][]/, "", line)
            n = split(line, parts, ","); for (p = 1; p <= n; p++) tok(parts[p])
            next
        }
        intools && /^[ \t]*-[ \t]/ { item = $0; sub(/^[ \t]*-[ \t]*/, "", item); tok(item); next }
        intools && /^[^ \t]/ { intools = 0 }
        END { if (present && !hasbash) print "bashless" }' "$file")
    [ "$verdict" = bashless ]
}

if record_has agent-lookup || record_has mirror-read; then
    log_once allow-record "lookup or mirror read recorded" "allow-record-$SAFE_ID"
    exit 0
fi
if record_has lead-supplied; then
    log_once allow-lead-supplied "lead-supplied knowledge in the brief (IMP-268)" "allow-lead-supplied-$SAFE_ID"
    exit 0
fi
BASHLESS=0
if is_bashless "$AGENT_TYPE"; then BASHLESS=1; fi
if record_has auto-inject && [ "$BASHLESS" = 1 ]; then
    log_once allow-bashless "auto-inject, Bash-less agent_type=$AGENT_TYPE" "allow-bashless-$SAFE_ID"
    exit 0
fi

suggest_keywords() {  # <path>: up to 6 lowercase words, min 4 chars, from basename and two parent dirs
    local base parent grand keywords
    base=$(basename "$1"); base="${base%.*}"
    parent=$(basename "$(dirname "$1")")
    grand=$(basename "$(dirname "$(dirname "$1")")")
    keywords=$(printf '%s\n' "$base" "$parent" "$grand" \
        | tr '[:upper:]' '[:lower:]' | sed 's/[._-]/\n/g' \
        | grep -E '^[a-z][a-z0-9]{3,}$' | awk '!seen[$0]++' | head -n 6 | paste -sd, - | sed 's/,/, /g')
    printf '%s' "${keywords:-none derivable from the path}"
}

build_text() {  # <denial count> <bashless 0|1>
    local keywords
    keywords=$(suggest_keywords "$FILE_PATH")
    if [ "$2" = 1 ]; then
        printf '%s' "Knowledge gate (IMP-267): no library lookup is recorded for $IDENTITY (denial $1 of 3). You have no Bash tool: Read or Grep one note under $KDIR/mirror/ (for example the project's MEMORY.md or a note matching the keywords below) — that counts as your lookup. Then judge by the » lines, open only the top note's section. Suggested keywords from the target path: $keywords."
        return 0
    fi
    printf '%s' "Knowledge gate (IMP-267): no library lookup is recorded for $IDENTITY (denial $1 of 3). Before editing, run:
$LOOKUP_CMD
Then judge by the » lines, open only the top note's section. A Read of a note under $KDIR/mirror/ also counts, and so does a zero-hit run. Suggested keywords from the target path: $keywords."
}

emit_deny() {  # <reason>
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
}

emit_context() {  # <additionalContext>
    jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
}

COUNT_FILE="$STATE_DIR/denials-$SAFE_ID"
PREVIOUS=$(cat "$COUNT_FILE" 2>/dev/null || printf '0')
case "$PREVIOUS" in
    ''|*[!0-9]*) printf 'knowledge-gate: corrupt denial counter %s; resetting to 0\n' "$COUNT_FILE" >&2; PREVIOUS=0 ;;
esac
COUNT=$((PREVIOUS + 1))
if ! printf '%s\n' "$COUNT" > "$COUNT_FILE" 2>/dev/null; then
    printf 'knowledge-gate: cannot write %s; allowing (fail open)\n' "$COUNT_FILE" >&2
    exit 0
fi

if [ "$MODE" = deny ] && [ "$COUNT" -gt 3 ]; then
    log_event escalation "denial $COUNT, allowed: $FILE_PATH"
    if [ "$COUNT" -eq 4 ]; then
        emit_context "ESCALATION (knowledge gate, IMP-267): edit allowed after 3 denials without any library lookup for $IDENTITY; this is logged."
    fi
    exit 0
fi

TEXT=$(build_text "$COUNT" "$BASHLESS")
if [ "$MODE" = deny ]; then
    log_event deny "denial $COUNT of 3: $FILE_PATH"
    emit_deny "$TEXT"
else
    log_event advisory "denial $COUNT: $FILE_PATH"
    emit_context "$TEXT"
fi
exit 0
