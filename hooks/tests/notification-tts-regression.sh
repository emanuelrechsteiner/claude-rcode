#!/usr/bin/env bash
# notification-tts-regression.sh - regression suite for hooks/notification-tts.sh
# (Notification event, opt-in via CLAUDE_NOTIFICATION_TTS=1). Covers: silence
# without opt-in, the logged line and spoken phrase, the phrase mapping, the generic
# fallback, the non-blocking background call, and empty or malformed stdin.
# A stub "say" first on PATH records its arguments; nothing is spoken.
# Usage: bash hooks/tests/notification-tts-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../notification-tts.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; RC=0; OUT=""
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/notification-tts-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
HOME_SB="$SANDBOX/home"; STUBS="$SANDBOX/stubs"
SAY_LOG="$SANDBOX/say.log"; OUT_FILE="$SANDBOX/hook-out.txt"
LOG_FILE="$HOME_SB/.claude/global-observation/notifications.jsonl"
mkdir -p "$HOME_SB" "$STUBS"
# Only the stubs and the jq directory are on PATH: the real say cannot run.
PATH_SB="$STUBS:$(dirname "$(command -v jq)"):/usr/bin:/bin"

for name in say afplay osascript terminal-notifier; do
    cat > "$STUBS/$name" <<'STUB'
#!/bin/bash
printf '%s|%s\n' "$(basename "$0")" "$*" >> "$STUB_LOG"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
exit 0
STUB
    chmod +x "$STUBS/$name"
done
RESOLVED=$(env -i PATH="$PATH_SB" bash -c 'command -v say')
if [[ "$RESOLVED" != "$STUBS/say" ]]; then
    echo "ERROR: say resolves to '$RESOLVED', not the stub; refusing to run" >&2; exit 1
fi

# run_notify <stdin-data> [VAR=value ...] -> sets RC and OUT. Output goes to a file so
# a backgrounded say cannot hold a pipe open.
run_notify() {
    local data="$1"; shift
    printf '%s' "$data" | env -i HOME="$HOME_SB" PATH="$PATH_SB" LC_ALL=C LANG=C \
        STUB_LOG="$SAY_LOG" "$@" bash "$HOOK" > "$OUT_FILE" 2>&1
    RC=$?
    OUT=$(< "$OUT_FILE")
}
fresh() { rm -rf "$HOME_SB/.claude"; rm -f "$SAY_LOG" "$OUT_FILE"; }
wait_say() {   # poll up to 5 s for the background say stub to log its call
    local i
    for i in $(seq 1 50); do
        [[ -s "$SAY_LOG" ]] && return 0
        sleep 0.1
    done
    return 1
}

rc0()       { [[ "$RC" -eq 0 ]]; }
spoke()     { rc0 && wait_say && [[ "$(< "$SAY_LOG")" == "$1" ]]; }
logged()    { [[ -f "$LOG_FILE" ]] && grep -qF -- "$1" "$LOG_FILE"; }
untouched() { rc0 && [[ ! -e "$LOG_FILE" && ! -s "$SAY_LOG" ]]; }
generic_spoken() { spoke "say|-v Alex Claude notification"; }
missing_type_ok() { generic_spoken && logged '"type":"unknown"'; }
spoken_and_logged() { generic_spoken && [[ -s "$LOG_FILE" ]]; }

check() {   # check <name> <command...>: PASS when the command succeeds
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS+1)); printf 'PASS  %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL  %s (rc=%s) %s\n' "$name" "$RC" "${OUT//$'\n'/ | }"
    fi
}

echo "-- notification-tts.sh regression (IMP-276a) --"

# N1 quiet: without the opt-in the hook exits before logging or speaking
fresh
run_notify '{"notification_type":"permission_prompt","message":"x"}'
check "N1 opt-in unset: exit 0, no log line, no say call" untouched
fresh
run_notify '{"notification_type":"permission_prompt","message":"x"}' CLAUDE_NOTIFICATION_TTS=0
check "N1 opt-in set to 0: exit 0, no log line, no say call" untouched

# N2 acting: opt-in logs the event and speaks the permission phrase
fresh
run_notify '{"notification_type":"permission_prompt","message":"Approve edit"}' CLAUDE_NOTIFICATION_TTS=1
check "N2 opt-in: exit 0 and the JSON line carries type and message" \
    logged '"type":"permission_prompt","message":"Approve edit"'
check "N2 opt-in: say is called with the permission phrase" spoke "say|-v Alex Permission needed"

# N3 phrase mapping for the other named notification classes
for pair in "idle_prompt|Claude is idle" "auth_success|Authenticated" "elicitation_dialog|Input required"; do
    ntype="${pair%%|*}"; phrase="${pair#*|}"
    fresh
    run_notify "{\"notification_type\":\"$ntype\",\"message\":\"m\"}" CLAUDE_NOTIFICATION_TTS=1
    check "N3 $ntype is spoken as: $phrase" spoke "say|-v Alex $phrase"
done

# N4 fallback: an unknown type gets the generic phrase; a missing type is logged as unknown
fresh
run_notify '{"notification_type":"brand_new_type","message":"m"}' CLAUDE_NOTIFICATION_TTS=1
check "N4 unknown type: generic phrase" spoke "say|-v Alex Claude notification"
fresh
run_notify '{"message":"no type field"}' CLAUDE_NOTIFICATION_TTS=1
check "N4 missing type: logged as unknown and spoken generically" missing_type_ok

# N5 edge (named in the header): say runs in the background, so the hook returns while it still sleeps
fresh
SECONDS=0
run_notify '{"notification_type":"idle_prompt","message":"m"}' CLAUDE_NOTIFICATION_TTS=1 STUB_SLEEP=6
ELAPSED=$SECONDS
check "N5 say sleeps 6 s: hook returns in under 3 s" test "$ELAPSED" -lt 3
check "N5 the say call still happens in the background" spoke "say|-v Alex Claude is idle"

# N6 stdin: empty and malformed input still exit 0 and still log a line
fresh
run_notify '' CLAUDE_NOTIFICATION_TTS=1
check "N6 empty stdin: exit 0, a line is logged, generic phrase spoken" spoken_and_logged
fresh
run_notify '{not json' CLAUDE_NOTIFICATION_TTS=1
check "N6 malformed stdin: exit 0, a line is logged, generic phrase spoken" spoken_and_logged

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then exit 0; fi
exit 1
