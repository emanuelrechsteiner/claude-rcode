#!/bin/bash
# post-edit-validate-regression.sh - regression suite for hooks/post-edit-validate.sh
# (PostToolUse Edit|Write. Exit 2 when a bare stray number line sits at EOF of a
# code/markup file; exit 0 otherwise, including on empty or malformed stdin.)
# Runs in a throwaway HOME and project dir; nothing outside them is written.
# Not covered: a file whose last line is a bare digit WITHOUT a trailing newline,
# because the hook inspects the second-to-last byte (see the suite report).
# Usage: bash hooks/tests/post-edit-validate-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../post-edit-validate.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/post-edit-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$WORK/home"; PROJ="$WORK/project"
mkdir -p "$FAKE_HOME" "$PROJ"

# run_hook <file_path> -> sets RC and ERR (stderr of the hook)
run_hook() {
    local json
    json=$(jq -n --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p}}')
    ERR=$(printf '%s' "$json" | HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null)
    RC=$?
}
expect() {   # expect <name> <want-rc> [stderr-substring]
    if [[ "$RC" -eq "$2" ]] && { [[ -z "${3:-}" ]] || [[ "$ERR" == *"$3"* ]]; }; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s want %s) %s\n' "$1" "$RC" "$2" "$ERR"
    fi
}

echo "-- post-edit-validate.sh regression --"

# Quiet path: a clean code file, newline-terminated, is silent and allowed.
printf 'const x = 1;\n' > "$PROJ/clean.ts"
run_hook "$PROJ/clean.ts"
expect "clean .ts file: silent allow (rc 0)" 0
[[ -z "$ERR" ]] || { FAIL=$((FAIL+1)); echo "  FAIL clean .ts file: stderr not empty: $ERR"; }

# Acting path: a bare number line at EOF is reported and blocks with rc 2.
printf 'const x = 1;\n1\n' > "$PROJ/stray.ts"
run_hook "$PROJ/stray.ts"
expect "stray '1' line at EOF: rc 2 with message" 2 "Stray character '1' detected at EOF"

# Edge: a digit line in the middle of the file is not EOF damage.
printf '1\nconst x = 2;\n' > "$PROJ/middle.ts"
run_hook "$PROJ/middle.ts"
expect "digit line not at EOF: allowed (rc 0)" 0

# Edge: a file type outside the checked extension list is skipped.
printf 'x\n1\n' > "$PROJ/notes.txt"
run_hook "$PROJ/notes.txt"
expect "unchecked extension (.txt) with stray digit: skipped (rc 0)" 0

# Empty stdin: no file path, exit 0.
ERR=$(printf '' | HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null); RC=$?
expect "empty stdin: exit 0" 0

# Malformed JSON on stdin: jq cannot read a path, exit 0, no hang.
ERR=$(printf '{"tool_input": ' | HOME="$FAKE_HOME" bash "$HOOK" 2>&1 >/dev/null); RC=$?
expect "malformed JSON on stdin: exit 0" 0

echo "-- summary --"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
