#!/usr/bin/env bash
# git-identity-enforce-regression.sh - regression suite for hooks/git-identity-enforce.sh
# (PreToolUse on Bash). The shipped identities are placeholders, so the acting path
# is reached by putting the placeholder literal WORK_IDENTITY_PATTERN into a sandbox
# directory name; the hook matches the cwd case-insensitively. Every case uses a
# throwaway HOME and a throwaway git repo. The hook must always exit 0.
# Usage: bash hooks/tests/git-identity-enforce-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../git-identity-enforce.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; RC=0; OUT=""
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/git-identity-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
HOME_SB="$SANDBOX/home"
mkdir -p "$HOME_SB/.claude/global-observation"
SIG="$HOME_SB/.claude/global-observation/signals.jsonl"
PATH_SB="$(dirname "$(command -v git)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"

# run_gate <dir> <stdin-data> -> sets RC and OUT. The hook reads the cwd, so it runs inside <dir>.
run_gate() {
    OUT=$(cd "$1" && printf '%s' "$2" | env -i HOME="$HOME_SB" PATH="$PATH_SB" LC_ALL=C LANG=C \
        bash "$HOOK" 2>&1)
    RC=$?
}
bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
make_repo() {   # make_repo <dir>: git repo with the sample identity
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.name "Sample User"
    git -C "$1" config user.email "sample@example.invalid"
}
local_name()  { git -C "$1" config --local user.name; }
local_email() { git -C "$1" config --local user.email; }
sig_lines()   { if [[ -f "$SIG" ]]; then wc -l < "$SIG" | tr -d ' '; else echo 0; fi; }
sample_kept() { [[ "$(local_name "$1")" == "Sample User" ]] && [[ "$(local_email "$1")" == "sample@example.invalid" ]]; }
acted_local() { [[ "$(local_name "$1")" == "WORK_NAME" ]] && [[ "$(local_email "$1")" == "work@email.example" ]]; }

rc0()        { [[ "$RC" -eq 0 ]]; }
quiet_kept() { rc0 && [[ -z "$OUT" ]] && sample_kept "$1"; }
says()       { rc0 && [[ "$OUT" == *"$1"* ]]; }
sig_has()    { [[ -f "$SIG" ]] && grep -qF -- "$1" "$SIG"; }

check() {   # check <name> <command...>: PASS when the command succeeds
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS+1)); printf 'PASS  %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL  %s (rc=%s) %s\n' "$name" "$RC" "${OUT//$'\n'/ | }"
    fi
}

echo "-- git-identity-enforce.sh regression (IMP-276a) --"

# G1 quiet: a non-git Bash command, and a git-looking command on a non-Bash tool
G1="$SANDBOX/WORK_IDENTITY_PATTERN/g1"; make_repo "$G1"
run_gate "$G1" "$(bash_json 'ls -la')"
check "G1 non-git Bash command in the work path: silent, identity untouched" quiet_kept "$G1"
run_gate "$G1" '{"tool_name":"Read","tool_input":{"command":"git commit -m x"}}'
check "G1 git text on a non-Bash tool: silent, identity untouched" quiet_kept "$G1"

# G2 acting: git commit in the work path rewrites the local identity and logs it
G2="$SANDBOX/WORK_IDENTITY_PATTERN/g2"; make_repo "$G2"
run_gate "$G2" "$(bash_json 'git commit -m sample')"
check "G2 git commit in the work path: correction notice, exit 0" says "Identity auto-corrected"
check "G2 local identity rewritten to the work identity" acted_local "$G2"
check "G2 correction written to the signals log" sig_has '"new_email":"work@email.example"'

# G3 quiet: the identity already matches, so nothing is corrected or logged
G3="$SANDBOX/WORK_IDENTITY_PATTERN/g3"; make_repo "$G3"
git -C "$G3" config user.name "WORK_NAME"
git -C "$G3" config user.email "work@email.example"
SIG_BEFORE=$(sig_lines)
run_gate "$G3" "$(bash_json 'git commit -m sample')"
check "G3 identity already matches: silent, no new signal line" \
    bash -c '[[ -z "$1" && "$2" == "$3" ]]' _ "$OUT" "$(sig_lines)" "$SIG_BEFORE"

# G4 quiet: a path that matches no identity pattern is left alone (ambiguous context)
G4="$SANDBOX/ambiguous/g4"; make_repo "$G4"
run_gate "$G4" "$(bash_json 'git commit -m sample')"
check "G4 path matches no identity: silent, identity untouched" quiet_kept "$G4"

# G5 edge (named in the header): the correction is local only, the global config is never written
G5="$SANDBOX/WORK_IDENTITY_PATTERN/g5"; make_repo "$G5"
git config --file "$HOME_SB/.gitconfig" user.name "Global User"
git config --file "$HOME_SB/.gitconfig" user.email "global@example.invalid"
run_gate "$G5" "$(bash_json 'git commit -m sample')"
check "G5 correction is local: global config unchanged" \
    bash -c '[[ "$(git config --file "$1/.gitconfig" user.email)" == "global@example.invalid" && "$(git config --file "$1/.gitconfig" user.name)" == "Global User" ]]' _ "$HOME_SB"
check "G5 local repo still corrected" acted_local "$G5"

# G6 stdin: empty and malformed input are not Bash tool calls, so nothing changes
G6="$SANDBOX/WORK_IDENTITY_PATTERN/g6"; make_repo "$G6"
run_gate "$G6" ""
check "G6 empty stdin: exit 0, identity untouched" quiet_kept "$G6"
run_gate "$G6" "{not json"
check "G6 malformed stdin: exit 0, identity untouched" quiet_kept "$G6"

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then exit 0; fi
exit 1
