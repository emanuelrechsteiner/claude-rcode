#!/bin/bash
# sandbox-guard-regression.sh - regression suite for hooks/sandbox-guard.sh
# (SessionStart. Prints a soft warning when YOLO / auto-permission mode is on outside
# a known sandbox. Never blocks: exit 0 in every case. The hook ignores stdin.)
# Each case runs under env -i with a throwaway HOME, so the host environment and the
# real ~/.claude/settings.json are never read. The two system markers /.dockerenv and
# /run/.containerenv cannot be faked; when either exists on the host, the cases that
# need "no sandbox" are reported as skipped instead of run.
# Usage: bash hooks/tests/sandbox-guard-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../sandbox-guard.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sandbox-guard-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME/.claude"
HOST_SANDBOX=0
[[ -e /.dockerenv || -e /run/.containerenv ]] && HOST_SANDBOX=1

# set_settings <json-text|none>  writes the throwaway settings.json
set_settings() {
    if [[ "$1" == none ]]; then rm -f "$FAKE_HOME/.claude/settings.json"
    else printf '%s\n' "$1" > "$FAKE_HOME/.claude/settings.json"; fi
}
# run_hook <extra-env-assignments> <stdin-text> -> sets RC, OUT, ERR
run_hook() {
    OUT=$(printf '%s' "$2" | env -i HOME="$FAKE_HOME" PATH="$PATH" $1 bash "$HOOK" 2>"$WORK/err"); RC=$?
    ERR=$(cat "$WORK/err")
}
WARN="Sandbox-Guard: YOLO/auto-permission mode active but NOT in a known sandbox"
expect() {   # expect <name> <want-rc> <warn: yes|no>
    local ok=1
    [[ "$RC" -eq "$2" ]] || ok=0
    if [[ "$3" == yes ]]; then [[ "$OUT" == *"$WARN"* ]] || ok=0
    else [[ -z "$OUT" ]] || ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s want %s) out=%s err=%s\n' "$1" "$RC" "$2" "$OUT" "$ERR"
    fi
}
skip() { SKIP=$((SKIP+1)); printf '  skip %s (host has a container marker file)\n' "$1"; }

echo "-- sandbox-guard.sh regression --"

# Quiet path: YOLO flag explicitly false, no env marker -> no warning.
set_settings '{"skipDangerousModePermissionPrompt": false}'
run_hook "" ""
expect "YOLO flag false, no env: silent, rc 0" 0 no

# Acting path: skipDangerousModePermissionPrompt true outside a sandbox -> soft warning.
if [[ "$HOST_SANDBOX" -eq 0 ]]; then
    set_settings '{"skipDangerousModePermissionPrompt": true}'
    run_hook "" ""
    expect "YOLO in settings, no sandbox: warning, rc 0 (soft, not a block)" 0 yes
else skip "YOLO in settings: warning"; fi

# Acting path via env: CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS set, settings absent.
if [[ "$HOST_SANDBOX" -eq 0 ]]; then
    set_settings none
    run_hook "CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1" ""
    expect "YOLO via env var, no sandbox: warning, rc 0" 0 yes
else skip "YOLO via env var: warning"; fi

# Sandbox marker suppresses the warning even with YOLO on.
set_settings '{"skipDangerousModePermissionPrompt": true}'
run_hook "CLAUDE_YOLO_SANDBOX=1" ""
expect "YOLO with CLAUDE_YOLO_SANDBOX=1: silent, rc 0" 0 no

# Edge: second YOLO key (skipAutoPermissionPrompt) plus the CONTAINER marker -> silent.
set_settings '{"skipAutoPermissionPrompt": true}'
run_hook "CONTAINER=podman" ""
expect "skipAutoPermissionPrompt with CONTAINER marker: silent, rc 0" 0 no

# Stdin is ignored: empty and malformed JSON give the same warning, rc 0.
if [[ "$HOST_SANDBOX" -eq 0 ]]; then
    set_settings '{"skipDangerousModePermissionPrompt": true}'
    run_hook "" ""; RC_E=$RC; OUT_E=$OUT
    run_hook "" '{"hook_event_name": '
    if [[ "$RC_E" -eq 0 && "$RC" -eq 0 && "$OUT_E" == *"$WARN"* && "$OUT" == *"$WARN"* ]]; then
        PASS=$((PASS+1)); echo "  ok   empty and malformed stdin: same warning, rc 0"
    else
        FAIL=$((FAIL+1)); echo "  FAIL empty and malformed stdin: rc=$RC_E/$RC"
    fi
else skip "empty and malformed stdin: warning"; fi

echo "-- summary --"
echo "PASS: $PASS   FAIL: $FAIL   SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]]
