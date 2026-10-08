#!/bin/bash
# Governing-Path Guard — PreToolUse on Write|Edit|MultiEdit and Bash (IMP-239)
# ─────────────────────────────────────────────────────────────────────────────
# WHY: two-location rule (CLAUDE.md "READ THIS FIRST"): ${CLAUDE_LIVE_DIR:-~/.claude}
# is the LIVE install, only `claude-deploy` writes there. Until now this was
# prose only; an unattended `claude -p --dangerously-skip-permissions` run
# (scripts/routine-run.sh) could rewrite rules/agents/hooks/settings directly.
# This is a fence against ACCIDENTAL writes, not a wall against deliberate evasion.
#
# BLOCKS (exit 2) a write whose target resolves (case-insensitive, realpath of the
# parent, ~/$HOME expanded) into the live install AND is: rules/*.md (not
# *.local.md), agents/ skills/ commands/ hooks/ rcode/ scheduled-tasks/ scripts/
# cockpit/ output-styles/ templates/ (also the directory roots themselves),
# CLAUDE.md, settings.json, settings.framework.json, settings.local.json.
# Bash (parsed by hooks/lib/governing-path-classify.py, command position only):
# redirects, tee, sed -i, cp/mv/install, inside sh|bash|zsh -c, and
# `git [-C live] checkout|restore|apply|am|merge|pull|stash|reset|cherry-pick|rebase`.
# A Bash parse failure FAILS CLOSED when the raw text names a governed live path.
# Known limits (rm/ln/dd, rsync, python writes, other variables, ...): see the
# header of the classifier. deploy-to-live.sh's internal `git pull` is invisible
# here: the hook sees only the outer `claude-deploy` command.
#
# OVERRIDE: CLAUDE_GOVERNING_WRITE_ACK=<sha256>, from the hook env or inline in
# the input. Signature: Bash = whitespace-collapsed command minus the token; file
# tools = path + newline + sha256 of the new content (so each edit needs its own
# approval). Single-use per session, op-bound, logged authorizer=user.
# CLAUDE_GATE_TESTMODE=1 exempts (logged). Fails OPEN (logged `failopen`, stderr
# NOTE) on missing jq/python3/classifier or bad JSON; the floor is file-protection.sh.
# Exit contract: 0 = allow, 2 = block.
set -u

INPUT=$(cat)
HOME_DIR="${HOME:-}"
LOG="${CLAUDE_GOVERNING_LOG:-${HOME_DIR:-/nonexistent}/.claude/global-observation/governing-path-guard.log}"
CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/governing-path-classify.py"

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
[ -n "$HOME_DIR" ] || open_note "HOME is not set"
command -v jq >/dev/null 2>&1 || open_note "jq not found, cannot inspect"
command -v python3 >/dev/null 2>&1 || open_note "python3 not found, cannot parse"
[ -f "$CLASSIFIER" ] || open_note "classifier missing: $CLASSIFIER"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || open_note "stdin is not parseable JSON"

PYERR=$(mktemp "${TMPDIR:-/tmp}/gpg-err.XXXXXX")
trap 'rm -f "$PYERR"' EXIT
OUT=$(printf '%s' "$INPUT" | python3 "$CLASSIFIER" "${CLAUDE_LIVE_DIR:-$HOME_DIR/.claude}" 2>"$PYERR") \
    || open_note "classifier crashed: $(tr '\n' ' ' <"$PYERR" | cut -c1-300)"

PARSEFAIL=$(printf '%s\n' "$OUT" | grep -m1 '^PARSEFAIL' | cut -f2-)
[ -z "$PARSEFAIL" ] || log_line "parse-fail" "none" "$PARSEFAIL"
HIT=$(printf '%s\n' "$OUT" | grep -m1 '^HIT' | cut -f2-)
if [ -z "$HIT" ]; then
    [ -z "$PARSEFAIL" ] || echo "governing-path-guard: NOTE — could not parse the command ($PARSEFAIL); no live governed path named. Allowing." >&2
    exit 0
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
echo "governing-path-guard: BLOCKED — $HIT is in the LIVE install (two-location rule, CLAUDE.md): edit the workshop copy and run claude-deploy. Only after a user y/n: CLAUDE_GOVERNING_WRITE_ACK=$SIG (env for file tools, inline prefix for Bash)." >&2
exit 2
