#!/bin/bash
# Governing-Path Guard — PreToolUse on Write|Edit|MultiEdit and Bash (IMP-239)
# ─────────────────────────────────────────────────────────────────────────────
# WHY: two-location rule (CLAUDE.md "Changing this configuration"): ${CLAUDE_LIVE_DIR:-~/.claude}
# is the LIVE install, only `claude-deploy` writes there. Until now this was
# prose only; an unattended `claude -p --dangerously-skip-permissions` run
# (scripts/routine-run.sh) could rewrite rules/agents/hooks/settings directly.
# This is a fence against ACCIDENTAL writes, not a wall against deliberate evasion.
#
# BLOCKS (exit 2) a write whose target resolves (case-insensitive, realpath of the
# parent, ~/$HOME expanded) into the live install AND is: rules/*.md (not
# *.local.md), agents/ skills/ commands/ hooks/ rcode/ scheduled-tasks/ scripts/
# cockpit/ output-styles/ templates/ docs/ (also the directory roots themselves),
# CLAUDE.md, settings.json, settings.framework.json, settings.local.json.
# Bash (parsed by hooks/lib/governing-path-classify.py, command position only):
# redirects, tee, sed -i, cp/mv/install, inside sh|bash|zsh -c, and
# `git [-C live] checkout|restore|apply|am|merge|pull|stash|reset|cherry-pick|rebase`.
# A Bash parse failure FAILS CLOSED when the raw text names a governed live path,
# or names a governed directory while it mentions or runs inside the live install.
# Known limits (rm/ln/dd, rsync, python writes, other variables, ...): see the
# header of the classifier. deploy-to-live.sh's internal `git pull` is invisible
# here: the hook sees only the outer `claude-deploy` command.
#
# OVERRIDE: CLAUDE_GOVERNING_WRITE_ACK=<sha256>, from the hook env or inline in
# the input. Signature: Bash = whitespace-collapsed command minus the token; file
# tools = path + newline + sha256 of the new content (so each edit needs its own
# approval). Single-use per session, op-bound, logged authorizer=user.
# CLAUDE_GATE_TESTMODE=1 exempts (logged).
# DEGRADED ANALYSIS (IMP-274): on missing jq/python3/classifier, bad JSON or a
# classifier crash a raw text match decides. Input that names a governed live path
# is BLOCKED (logged `analysis-failed`, even a read: the guard cannot tell);
# anything else is allowed (logged `failopen`, stderr NOTE; floor: file-protection.sh).
# The classifier never depends on a writable TMPDIR.
# Exit contract: 0 = allow, 2 = block.
set -u

INPUT=$(cat)
HOME_DIR="${HOME:-}"
LIVE_DIR="${CLAUDE_LIVE_DIR:-${HOME_DIR:-/nonexistent}/.claude}"
LOG="${CLAUDE_GOVERNING_LOG:-${HOME_DIR:-/nonexistent}/.claude/global-observation/governing-path-guard.log}"
CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/governing-path-classify.py"
GOV_NAMES='rules/|agents|skills|commands|hooks|rcode|scheduled-tasks|scripts|cockpit|output-styles|templates|docs|claude\.md|settings'
GIT_WRITE='checkout|restore|apply|am|merge|pull|stash|reset|cherry-pick|rebase'
HIT=""; PARSEFAIL=""; PYERR=""

log_line() { # decision authorizer target sig
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    printf '[%s] decision=%s authorizer=%s target=%s sig=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$1" "${2:-none}" "$(printf '%s' "$3" | tr '\n' ' ')" "${4:-}" >>"$LOG" 2>/dev/null || true
}
open_note() {
    log_line "failopen" "none" "$1"
    echo "governing-path-guard: NOTE — $1. Allowing (fail-open; floor is file-protection.sh)." >&2
    exit 0
}
# Raw floor (IMP-274): when the call cannot be analysed, a plain text match decides.
# It errs on the side of blocking: a read that names a governed live path blocks too.
raw_floor() { # prints what matched and returns 0 when the raw input points at a governed live path
    # Same rule as raw_hit in the classifier: the call mentions the live install or runs
    # inside it, AND names a governed directory or file or is a git write command.
    local txt cwd live cand mention=0 inside=0 what=""
    txt=$(printf '%s' "$INPUT" | tr '[:upper:]' '[:lower:]')
    cwd=$(printf '%s' "$txt" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
    # transcript_path always lies inside the live install and cwd is judged on its own:
    # neither field is evidence of a mention.
    txt=$(printf '%s' "$txt" | sed -E 's/"(transcript_path|cwd)"[[:space:]]*:[[:space:]]*"[^"]*"//g')
    live=$(printf '%s' "$LIVE_DIR" | tr '[:upper:]' '[:lower:]')
    case "$cwd/" in "$live"/*) inside=1 ;; esac
    for cand in "$live" '~/.claude' '$home/.claude' '${home}/.claude'; do
        if printf '%s' "$txt" | grep -qF -- "$cand"; then mention=1; break; fi
    done
    [ "$mention" = 1 ] || [ "$inside" = 1 ] || return 1
    if printf '%s' "$txt" | grep -qE "(^|[^[:alnum:]_.-])($GOV_NAMES)"; then what="a governed name"
    elif printf '%s' "$txt" | grep -qE "(^|[^[:alnum:]_])git([^[:alnum:]_]|\$)" \
        && printf '%s' "$txt" | grep -qE "(^|[^[:alnum:]_-])($GIT_WRITE)([^[:alnum:]_-]|\$)"; then what="a git write command"
    else return 1; fi
    if [ "$inside" = 1 ]; then printf '%s, run inside the live install' "$what"
    else printf '%s together with the live install' "$what"; fi
}
analysis_failed() { # reason: block when the raw input names a governed live path, else allow (logged)
    local m
    m=$(raw_floor) || open_note "$1"
    log_line "analysis-failed" "none" "$1"
    HIT="unanalysed call naming $m ($1)"
}

CAN_SIGN=1
if [ -z "$HOME_DIR" ]; then analysis_failed "HOME is not set"
elif ! command -v jq >/dev/null 2>&1; then CAN_SIGN=0; analysis_failed "jq not found, cannot inspect"
elif ! command -v python3 >/dev/null 2>&1; then analysis_failed "python3 not found, cannot parse"
elif [ ! -f "$CLASSIFIER" ]; then analysis_failed "classifier missing: $CLASSIFIER"
elif ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then CAN_SIGN=0; analysis_failed "stdin is not parseable JSON"
else
    # The stderr capture file is optional: a missing or unwritable TMPDIR must never
    # stop the classifier from running (IMP-274: 15 fail-opens in 90 days came from here).
    PYERR=$(mktemp "${TMPDIR:-/tmp}/gpg-err.XXXXXX" 2>/dev/null) || PYERR=$(mktemp /tmp/gpg-err.XXXXXX 2>/dev/null) || PYERR=""
    trap '[ -z "$PYERR" ] || rm -f "$PYERR"' EXIT
    if OUT=$(printf '%s' "$INPUT" | python3 "$CLASSIFIER" "$LIVE_DIR" 2>"${PYERR:-/dev/null}"); then
        PARSEFAIL=$(printf '%s\n' "$OUT" | grep -m1 '^PARSEFAIL' | cut -f2-)
        [ -z "$PARSEFAIL" ] || log_line "parse-fail" "none" "$PARSEFAIL"
        HIT=$(printf '%s\n' "$OUT" | grep -m1 '^HIT' | cut -f2-)
        if [ -z "$HIT" ]; then
            [ -z "$PARSEFAIL" ] || echo "governing-path-guard: NOTE — could not parse the command ($PARSEFAIL); it neither names nor runs inside the live install. Allowing." >&2
            exit 0
        fi
    else
        ERRTXT=""
        [ -z "$PYERR" ] || ERRTXT=$(tr '\n' ' ' <"$PYERR" | cut -c1-300)
        analysis_failed "classifier crashed: ${ERRTXT:-no stderr captured}"
    fi
fi

if [ "$CAN_SIGN" != 1 ]; then
    log_line "block" "none" "$HIT"
    echo "governing-path-guard: BLOCKED — $HIT. The call cannot be analysed and its text names a governed path of the LIVE install (two-location rule, CLAUDE.md \"Changing this configuration\"), so the guard fails closed. No override token can be computed until the cause is fixed." >&2
    exit 2
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
if [ -n "$CMD" ]; then
    SIGSRC=$(printf '%s' "$CMD" | sed -E 's/CLAUDE_GOVERNING_WRITE_ACK=[A-Fa-f0-9]+ *//g' | tr -s '[:space:]' ' ' | sed -E 's/^ +| +$//g')
else
    BODY=$(printf '%s' "$INPUT" | jq -r '[.tool_input.content, .tool_input.new_string, ((.tool_input.edits // [])[]?.new_string)] | map(select(. != null)) | join("\n")')
    SIGSRC="$HIT"$'\n'"$(printf '%s' "$BODY" | shasum -a 256 | cut -d' ' -f1)"
fi
SIG=$(printf '%s' "$SIGSRC" | shasum -a 256 | cut -d' ' -f1)

if [ "${CLAUDE_GATE_TESTMODE:-0}" = "1" ]; then
    log_line "testmode-exempt" "testmode" "$HIT" "$SIG"; exit 0
fi

TOKEN="${CLAUDE_GOVERNING_WRITE_ACK:-}"
[ -n "$TOKEN" ] || TOKEN=$(printf '%s' "$INPUT" | grep -oE 'CLAUDE_GOVERNING_WRITE_ACK=[A-Fa-f0-9]{64}' | head -1 | cut -d= -f2)
SESS=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
CONSUMED="${CLAUDE_GOVERNING_CONSUMED:-/tmp/governing-ack-consumed-${SESS:-$PPID}}"

if [ -n "$TOKEN" ]; then
    if [ "$TOKEN" != "$SIG" ]; then
        log_line "ack-mismatch" "none" "$HIT" "$SIG"
    elif grep -qx "$SIG" "$CONSUMED" 2>/dev/null; then
        log_line "ack-replay-block" "none" "$HIT" "$SIG"
        echo "governing-path-guard: BLOCKED — ack token already consumed (replay) for $HIT; ask the user for a fresh approval." >&2
        exit 2
    else
        printf '%s\n' "$SIG" >>"$CONSUMED"
        log_line "allow" "user" "$HIT" "$SIG"; exit 0
    fi
fi

log_line "block" "none" "$HIT" "$SIG"
echo "governing-path-guard: BLOCKED — $HIT is in the LIVE install (two-location rule, CLAUDE.md \"Changing this configuration\"): edit the workshop copy and run claude-deploy. Only after a user y/n: CLAUDE_GOVERNING_WRITE_ACK=$SIG (env for file tools, inline prefix for Bash)." >&2
exit 2
