#!/bin/bash
# postbash-failure-recovery-regression.sh - regression suite for hooks/postbash-failure-recovery.sh
# (PostToolUseFailure on Bash prints a recovery prompt; the legacy PostToolUse path
# fires only on stderr/stdout error patterns; every other input is silent. Always exit 0.)
# The hook hard-codes its diagnostic log to /tmp/postbash-hook.log and cannot be
# redirected without editing it. The suite reads only the bytes it appends and
# restores the file to its earlier size on exit. Nothing else is written.
# Usage: bash hooks/tests/postbash-failure-recovery-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../postbash-failure-recovery.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/postbash-test.XXXXXX")
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME"

LOG=/tmp/postbash-hook.log
LOG_EXISTED=0; [[ -f "$LOG" ]] && LOG_EXISTED=1
log_size() { if [[ -f "$LOG" ]]; then wc -c < "$LOG" | tr -d ' '; else echo 0; fi; }
LOG_SIZE0=$(log_size)

cleanup() {
    if [[ "$LOG_EXISTED" -eq 1 ]]; then
        head -c "$LOG_SIZE0" "$LOG" > "$WORK/keep" 2>/dev/null && cat "$WORK/keep" > "$LOG"
    else
        rm -f "$LOG"
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# run_hook <stdin-text> -> sets RC, OUT (stdout), ERR (stderr); remembers log offset
run_hook() {
    LOG_MARK=$(log_size)
    OUT=$(printf '%s' "$1" | HOME="$FAKE_HOME" bash "$HOOK" 2>"$WORK/err"); RC=$?
    ERR=$(cat "$WORK/err")
}
new_log() { tail -c +$((LOG_MARK+1)) "$LOG" 2>/dev/null; }
expect() {   # expect <name> <want-rc> <stdout-substring>  (empty substring = silent)
    local ok=1
    [[ "$RC" -eq "$2" ]] || ok=0
    if [[ -z "$3" ]]; then [[ -z "$OUT" ]] || ok=0; else [[ "$OUT" == *"$3"* ]] || ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s want %s) out=%s err=%s\n' "$1" "$RC" "$2" "$OUT" "$ERR"
    fi
}
ev() {   # ev <hook_event_name> <tool_name> <tool_response-json>
    jq -nc --arg e "$1" --arg t "$2" --argjson r "$3" \
        '{hook_event_name:$e,tool_name:$t,tool_response:$r}'
}

echo "-- postbash-failure-recovery.sh regression --"

# Acting path: a Bash failure (non-zero exit) prints the three-point recovery prompt and logs FIRED.
run_hook "$(ev PostToolUseFailure Bash '{"stdout":"","stderr":"boom","interrupted":false}')"
expect "PostToolUseFailure non-zero exit: recovery prompt, rc 0" 0 "Bash command failed (non-zero exit)"
[[ "$(new_log)" == *"FIRED event=PostToolUseFailure reason=non-zero exit"* ]] \
    && { PASS=$((PASS+1)); echo "  ok   same run logs FIRED line"; } \
    || { FAIL=$((FAIL+1)); echo "  FAIL same run logs FIRED line: $(new_log)"; }

# Acting path, interrupted branch: a timeout is reported as interrupted/timeout.
run_hook "$(ev PostToolUseFailure Bash '{"stdout":"","stderr":"","interrupted":true}')"
expect "PostToolUseFailure interrupted: reason interrupted/timeout" 0 "Bash command failed (interrupted/timeout)"

# Quiet path: a successful Bash call under PostToolUse prints nothing and logs no FIRED line.
run_hook "$(ev PostToolUse Bash '{"stdout":"ok","stderr":"","interrupted":false}')"
expect "PostToolUse success: silent, rc 0" 0 ""
[[ "$(new_log)" != *"FIRED"* ]] \
    && { PASS=$((PASS+1)); echo "  ok   success run logs no FIRED line"; } \
    || { FAIL=$((FAIL+1)); echo "  FAIL success run logs no FIRED line"; }

# Edge named in the header: legacy PostToolUse path uses the stderr error pattern.
run_hook "$(ev PostToolUse Bash '{"stdout":"","stderr":"rm: x: permission denied","interrupted":false}')"
expect "legacy PostToolUse stderr pattern: fires (stderr error pattern)" 0 "Bash command failed (stderr error pattern)"

# Non-Bash tool: the hook exits before any output, even on a failure event.
run_hook "$(ev PostToolUseFailure Edit '{"interrupted":false}')"
expect "non-Bash tool on failure event: silent, rc 0" 0 ""

# Empty stdin and malformed JSON: rc 0, silent, no hang (stdin closes at end of pipe).
run_hook ""
RC_EMPTY=$RC; OUT_EMPTY=$OUT
run_hook '{"tool_name": "Bash", '
if [[ "$RC_EMPTY" -eq 0 && -z "$OUT_EMPTY" && "$RC" -eq 0 && -z "$OUT" ]]; then
    PASS=$((PASS+1)); echo "  ok   empty and malformed stdin: rc 0, silent"
else
    FAIL=$((FAIL+1)); echo "  FAIL empty and malformed stdin: rc=$RC_EMPTY/$RC out=$OUT_EMPTY/$OUT"
fi

echo "-- summary --"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
