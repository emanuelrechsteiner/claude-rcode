#!/bin/bash
# knowledge-record.sh — PostToolUse hook for the knowledge gate (IMP-267)
# ─────────────────────────────────────────────────────────────────────
# Writes the evidence that knowledge-gate.sh reads, one TSV line per event:
#   Bash            a knowledge-lookup.sh INVOKED at command position, with a
#                   keyword, --stack or --alt (not --help)     -> agent-lookup
#   Read/Grep/Glob  a path (or Glob pattern) under <KDIR>/mirror -> mirror-read
# Record file: $CLAUDE_KNOWLEDGE_STATE_ROOT/knowledge-gate-<session>/record-<identity>.tsv
# Identity = agent_id (subagents) or "main". The lookup's exit status is not read:
# a zero-hit run counts as a lookup. Prints nothing; always exits 0.
# IMP-268: a lookup by a knowledge-agent (agent_type from the input, else the agent-type-<id>
# marker that knowledge-inject.sh writes) also appends "<ts>\t<agent id>" to knowledge-agent-lookups,
# the proof knowledge-brief-check.sh reads for a "none relevant" verdict.
# ─────────────────────────────────────────────────────────────────────
set -u
# Byte mode for every text tool: the command text may carry umlauts, and awk under a UTF-8
# locale aborts on them ("towc: multibyte conversion failure"), which left a lookup unrecorded
# in the acceptance run of 2026-11-01. Same fix as scripts/knowledge-lookup.sh.
export LC_ALL=C

STATE_ROOT="${CLAUDE_KNOWLEDGE_STATE_ROOT:-/tmp}"

# CLAUDE_KNOWLEDGE_DIR: environment first, else ~/.claude/env.local.sh (subshell, -u/-e off).
resolve_kdir() {
    local kdir="${CLAUDE_KNOWLEDGE_DIR:-}"
    if [ -z "$kdir" ] && [ -f "$HOME/.claude/env.local.sh" ]; then
        # shellcheck disable=SC1091
        kdir=$( set +u +e; . "$HOME/.claude/env.local.sh" >/dev/null 2>&1; printf '%s' "${CLAUDE_KNOWLEDGE_DIR:-}" )
    fi
    printf '%s' "${kdir%/}"
}

append() {  # <kind> <detail>
    local detail
    detail=$(printf '%s' "$2" | tr '\t\r\n' '   ')
    { mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"; } 2>/dev/null
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$detail" 2>/dev/null >> "$RECORD" \
        || printf 'knowledge-record: cannot write %s\n' "$RECORD" >&2
}

note_knowledge_lookup() {  # IMP-268: "<ts>\t<agent id>" for a knowledge-agent search, mode 0600
    local file="$STATE_DIR/knowledge-agent-lookups"
    if ! ( umask 077 && printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT_ID" >> "$file" ) 2>/dev/null; then
        printf 'knowledge-record: cannot write %s\n' "$file" >&2
    fi
    chmod 600 "$file" 2>/dev/null || true
}

u8_head() {  # <text>: the first 120 bytes, minus a trailing partial UTF-8 sequence (LC_ALL=C cuts bytes)
    printf '%s' "$1" | awk '
        BEGIN { for (i = 128; i < 192; i++) cont[sprintf("%c", i)] = 1
                for (i = 192; i < 224; i++) need[sprintf("%c", i)] = 2
                for (i = 224; i < 240; i++) need[sprintf("%c", i)] = 3
                for (i = 240; i < 248; i++) need[sprintf("%c", i)] = 4 }
        { s = s (NR > 1 ? "\n" : "") $0 }
        END { s = substr(s, 1, 120); n = length(s); i = n
              while (i > 0 && (substr(s, i, 1) in cont)) i--
              if (i > 0 && (substr(s, i, 1) in need) && n - i + 1 < need[substr(s, i, 1)]) s = substr(s, 1, i - 1)
              printf "%s", s }'
}

# Awk program: exit 0 when the command on stdin INVOKES knowledge-lookup.sh with a usage that counts.
# unquote: quotes are dropped and escaped characters (\" \; ...) are masked, so quoted or escaped text
#   stays one word and cannot open a quote or start a segment; separators inside quotes are masked too.
# heredoc: a line opening <<WORD, <<'WORD', <<"WORD" or <<-WORD starts a body that runs to the
#   terminator line; the body is data and is dropped before splitting.
# invokes: each segment (cut at ; & | ( ) and newlines) loses leading VAR=value assignments and
#   wrappers (bash/sh with -x/-e/-u/-v, timeout [n], env, sudo, time [-p], command [-p], exec,
#   nice [-n N]); the next word must be a path ending in knowledge-lookup.sh; a bare usage error
#   (only options such as --max N) does not count: a positional keyword, --stack or --alt is needed.
# SQ is passed with -v because a single quote cannot appear in this program.
# shellcheck disable=SC2016
INVOKES_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); return s }
function heredoc(line,   re, w) {  # sets HD_WORD and HD_DASH when the line opens a heredoc
    HD_WORD = ""; HD_DASH = 0
    re = "(^|[^<])<<-?[ \t]*[\"" SQ "]?[A-Za-z_][A-Za-z0-9_]*[\"" SQ "]?"
    if (!match(line, re)) return 0
    w = substr(line, RSTART, RLENGTH)
    HD_DASH = (w ~ /<<-/)
    sub(/^.*<<-?[ \t]*/, "", w)
    gsub("[\"" SQ "]", "", w)
    HD_WORD = w
    return 1
}
function invokes(seg,   t, nt, i, moved, j) {
    seg = trim(seg)
    nt = split(seg, t, /[ \t]+/)
    i = 1; moved = 1
    while (moved && i <= nt) {
        moved = 0
        if (t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; moved = 1 }
        else if (t[i] == "bash" || t[i] == "sh") {
            i++; moved = 1
            while (i <= nt && t[i] ~ /^-[xeuv]+$/) i++
        }
        else if (t[i] == "timeout") {
            i++; moved = 1
            if (i <= nt && t[i] ~ /^[0-9.]+[smhd]?$/) i++
        }
        else if (t[i] == "env" || t[i] == "sudo") {
            i++; moved = 1
            while (i <= nt && (t[i] ~ /^-/ || t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
        }
        else if (t[i] == "time" || t[i] == "command") {
            i++; moved = 1
            while (i <= nt && t[i] == "-p") i++
        }
        else if (t[i] == "exec") { i++; moved = 1 }
        else if (t[i] == "nice") {
            i++; moved = 1
            if (i <= nt && t[i] == "-n") i += 2
            else if (i <= nt && t[i] ~ /^-[0-9]+$/) i++
        }
    }
    if (!(i <= nt && t[i] ~ /(^|\/)knowledge-lookup\.sh$/)) return 0
    for (j = i + 1; j <= nt; j++) {
        if (t[j] == "--stack" || t[j] == "--alt") return 1
        if (t[j] ~ /^--(max|kind|project|set|questions)$/) { j++; continue }
        if (t[j] ~ /^[0-9&]*[<>]/) { if (t[j] ~ /^[0-9&]*[<>]+$/) j++; continue }
        if (t[j] ~ /^-/) continue
        return 1
    }
    return 0
}
function unquote(s,   i, c, q, out) {
    q = ""; out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\" && q != SQ && i < length(s)) {
            i++; c = substr(s, i, 1)
            out = out ((c ~ /[;&|()\n \t"]/ || c == SQ) ? "_" : c)
            continue
        }
        if (q != "") {
            if (c == q) q = ""
            else if (c ~ /[;&|() \t\n]/) out = out "_"
            else out = out c
        } else if (c == "\"" || c == SQ) q = c
        else if (c ~ /[;&|()\n]/) out = out "\n"
        else out = out c
    }
    return out
}
{ L[++nl] = $0 }
END {
    term = ""; dash = 0; body = ""
    for (j = 1; j <= nl; j++) {
        if (term != "") {
            cmp = L[j]
            if (dash) sub(/^\t+/, "", cmp)
            if (cmp == term) term = ""
            continue
        }
        body = body L[j] "\n"
        if (heredoc(L[j])) { term = HD_WORD; dash = HD_DASH }
    }
    n = split(unquote(body), segs, "\n")
    for (k = 1; k <= n; k++) if (invokes(segs[k])) exit 0
    exit 1
}'

# Prefilter on the raw input: nothing can be recorded unless a lookup or a mirror path is mentioned.
INPUT=$(cat)
case "$INPUT" in *knowledge-lookup.sh*|*/mirror*) ;; *) exit 0 ;; esac

# One jq call: session, tool, agent, agent type, path candidate (path, else Glob pattern), command.
# Fields are joined by \001; the command is last because it may contain newlines.
SEP=$'\001'
FIELDS=$(printf '%s' "$INPUT" | jq -r '[(.session_id // ""), (.tool_name // ""), (.agent_id // ""), (.agent_type // ""), (.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""), (.tool_input.command // "")] | join("\u0001")') \
    || { printf 'knowledge-record: hook input is not JSON; nothing recorded\n' >&2; exit 0; }
SESSION_ID=${FIELDS%%"$SEP"*}; REST=${FIELDS#*"$SEP"}
TOOL=${REST%%"$SEP"*}; REST=${REST#*"$SEP"}
AGENT_ID=${REST%%"$SEP"*}; REST=${REST#*"$SEP"}
RAW_TYPE=${REST%%"$SEP"*}; REST=${REST#*"$SEP"}
P=${REST%%"$SEP"*}; CMD=${REST#*"$SEP"}
[ -n "$SESSION_ID" ] || exit 0
# Same sanitiser as knowledge-gate.sh (see there): identical record file names on both sides.
RAW_AGENT_ID=$AGENT_ID
AGENT_ID=$(printf '%s' "$RAW_AGENT_ID" | tr -cd 'A-Za-z0-9_:.-')
if [ -n "$RAW_AGENT_ID" ] && [ -z "$AGENT_ID" ]; then AGENT_ID=unknown-agent; fi

SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_')
SAFE_ID=$(printf '%s' "${AGENT_ID:-main}" | tr -c 'A-Za-z0-9_-' '_')
STATE_DIR="$STATE_ROOT/knowledge-gate-$SAFE_SID"
RECORD="$STATE_DIR/record-$SAFE_ID.tsv"
# agent_type: the input's field, else the marker knowledge-inject.sh wrote at SubagentStart (IMP-268).
AGENT_TYPE=$(printf '%s' "$RAW_TYPE" | tr -cd 'A-Za-z0-9_:.-')
MARKER="$STATE_DIR/agent-type-$SAFE_ID"
if [ -z "$AGENT_TYPE" ] && [ -n "$RAW_AGENT_ID" ] && [ -f "$MARKER" ]; then
    AGENT_TYPE=$(head -n 1 "$MARKER" 2>/dev/null | tr -cd 'A-Za-z0-9_:.-')
fi

case "$TOOL" in
    Bash)
        case "$CMD" in *knowledge-lookup.sh*) ;; *) exit 0 ;; esac
        # --help counts as a usage query only as a separate token (whitespace or the ends of the command).
        if printf '%s' "$CMD" | LC_ALL=C grep -Eq '(^|[[:space:]])--help([[:space:]]|$)'; then exit 0; fi
        if printf '%s' "$CMD" | awk -v SQ="'" "$INVOKES_AWK"; then
            append agent-lookup "$(u8_head "$CMD")"
            if [ "$AGENT_TYPE" = knowledge-agent ] && [ -n "$AGENT_ID" ]; then note_knowledge_lookup; fi
        fi ;;
    Read|Grep|Glob)
        case "$P" in *mirror*) ;; *) exit 0 ;; esac
        KDIR=$(resolve_kdir)
        [ -n "$KDIR" ] || exit 0
        case "$P" in
            "$KDIR/mirror"|"$KDIR/mirror"/*) append mirror-read "$P" ;;
        esac ;;
esac
exit 0
