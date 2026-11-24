#!/usr/bin/env bash
# auto-format-regression.sh - regression suite for hooks/auto-format.sh
# (PostToolUse on Edit|Write). Covers: quiet paths that must never reach a
# formatter, prettier and ruff dispatch, argument-over-stdin input, a failing
# formatter never failing the hook, and empty or malformed stdin.
# Formatters are stubs first on PATH that only log their calls; nothing is formatted.
# Usage: bash hooks/tests/auto-format-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../auto-format.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; RC=0; OUT=""
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/auto-format-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
HOME_SB="$SANDBOX/home"; STUBS="$SANDBOX/stubs"; STUB_LOG="$SANDBOX/calls.log"
mkdir -p "$HOME_SB" "$STUBS"
# Only the stubs and the jq directory are on PATH, so no real formatter can run.
PATH_SB="$STUBS:$(dirname "$(command -v jq)"):/usr/bin:/bin"

for name in npx ruff black gofmt rustfmt; do
    cat > "$STUBS/$name" <<'STUB'
#!/bin/bash
printf '%s|%s|%s\n' "$(basename "$0")" "$(pwd -P)" "$*" >> "$STUB_LOG"
exit "${STUB_RC:-0}"
STUB
    chmod +x "$STUBS/$name"
done

# run_hook <stdin-data> [args...] -> sets RC and OUT; formatter calls land in STUB_LOG
run_hook() {
    local data="$1"; shift
    : > "$STUB_LOG"
    OUT=$(printf '%s' "$data" | env -i HOME="$HOME_SB" PATH="$PATH_SB" LC_ALL=C LANG=C \
        STUB_LOG="$STUB_LOG" STUB_RC="${STUB_RC:-0}" bash "$HOOK" "$@" 2>&1)
    RC=$?
}
edit_json() { jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p}}'; }
new_project() {   # new_project <name> -> project dir with package.json and src/
    local dir="$SANDBOX/$1"
    mkdir -p "$dir/src"
    printf '{"name":"sample-project"}\n' > "$dir/package.json"
    printf '%s\n' "$dir"
}

count()     { wc -l < "$STUB_LOG" | tr -d ' '; }
logged()    { grep -qF -- "$1" "$STUB_LOG"; }
absent()    { ! grep -qF -- "$1" "$STUB_LOG"; }
rc0()       { [[ "$RC" -eq 0 ]]; }
quiet()     { rc0 && [[ "$(count)" -eq 0 ]]; }
ok_and()    { rc0 && logged "$1"; }
ruff_only() { rc0 && logged "ruff|" && logged "|format --quiet $1" && absent "black|"; }

check() {   # check <name> <command...>: PASS when the command succeeds
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS+1)); printf 'PASS  %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL  %s (rc=%s calls=%s)\n' "$name" "$RC" "$(count)"
    fi
}

echo "-- auto-format.sh regression (IMP-276a) --"

# A1 quiet: a .txt file is not a formatted type
P=$(new_project txt-case); printf '{}\n' > "$P/.prettierrc"; printf 'notes\n' > "$P/notes.txt"
run_hook "$(edit_json "$P/notes.txt")"
check "A1 .txt file in a prettier project: exit 0, no formatter call" quiet

# A2 acting: a .ts file with a prettier config goes through npx prettier from the project root
P=$(new_project ts-case); printf '{}\n' > "$P/.prettierrc"; printf 'const a=1\n' > "$P/src/app.ts"
PP=$(cd "$P" && pwd -P)
run_hook "$(edit_json "$P/src/app.ts")"
check "A2 .ts with .prettierrc (stdin): prettier --write runs from the project root" \
    ok_and "npx|$PP|prettier --write $P/src/app.ts"

# A3 acting, argument route: $1 wins over stdin; ruff is preferred over black
P=$(new_project py-case); printf 'x = 1\n' > "$P/src/tool.py"
run_hook "" "$P/src/tool.py"
check "A3 .py (argument, not stdin): ruff format --quiet runs and black is skipped" \
    ruff_only "$P/src/tool.py"

# A4 quiet: no prettier key in package.json, and a file with no project root above it
P=$(new_project nokey-case); printf 'x\n' > "$P/src/a.ts"
run_hook "$(edit_json "$P/src/a.ts")"
check "A4 no prettier config in the project: no formatter call" quiet
mkdir -p "$SANDBOX/loose"; printf 'x\n' > "$SANDBOX/loose/b.ts"
run_hook "$(edit_json "$SANDBOX/loose/b.ts")"
check "A4 file with no package.json above it: no formatter call" quiet

# A5 edge (named in the header): a failing formatter never fails the hook
P=$(new_project fail-case); printf '{}\n' > "$P/.prettierrc"; printf 'x\n' > "$P/src/c.ts"
PP=$(cd "$P" && pwd -P)
STUB_RC=2 run_hook "$(edit_json "$P/src/c.ts")"
check "A5 prettier exits 2: hook still exits 0 and the call was made" \
    ok_and "npx|$PP|prettier --write $P/src/c.ts"

# A6 empty and malformed stdin: exit 0, nothing formatted
run_hook ""
check "A6 empty stdin: exit 0, no formatter call" quiet
run_hook "{not json"
check "A6 malformed stdin: exit 0, no formatter call" quiet

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then exit 0; fi
exit 1
