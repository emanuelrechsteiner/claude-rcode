#!/usr/bin/env bash
# git-remote-check-regression.sh - regression suite for hooks/git-remote-check.sh
# (SessionStart, non-blocking warner). Covers: silence below the commit threshold,
# the warning at the threshold, silence when a remote exists, the opt-out switch,
# unborn and non-repo directories, and malformed or empty stdin. Each repo is a
# throwaway directory with no remote unless the case adds a local bare one.
# The hook must always exit 0.
# Usage: bash hooks/tests/git-remote-check-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../git-remote-check.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; RC=0; OUT=""
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/git-remote-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
HOME_SB="$SANDBOX/home"; mkdir -p "$HOME_SB"
PATH_SB="$(dirname "$(command -v git)"):/usr/bin:/bin"

# run_check <dir> [VAR=value ...] -> sets RC and OUT. The hook runs with <dir> as cwd.
run_check() {
    local dir="$1"; shift
    OUT=$(cd "$dir" && printf '%s' "${STDIN_DATA-}" | env -i HOME="$HOME_SB" PATH="$PATH_SB" \
        LC_ALL=C LANG=C "$@" bash "$HOOK" 2>&1)
    RC=$?
}
# make_repo <dir> <commits> <remote yes|no>: sample repo with N empty commits
make_repo() {
    local dir="$1" i
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" symbolic-ref HEAD refs/heads/main
    git -C "$dir" config user.name "Sample User"
    git -C "$dir" config user.email "sample@example.invalid"
    git -C "$dir" config commit.gpgsign false
    for ((i = 1; i <= $2; i++)); do
        git -C "$dir" commit -q --allow-empty -m "sample: commit $i"
    done
    if [[ "$3" == yes ]]; then
        git init -q --bare "$dir.remote.git"
        git -C "$dir" remote add origin "$dir.remote.git"
    fi
}

rc0()    { [[ "$RC" -eq 0 ]]; }
silent() { rc0 && [[ -z "$OUT" ]]; }
says()   { rc0 && [[ "$OUT" == *"$1"* ]]; }

check() {   # check <name> <command...>: PASS when the command succeeds
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS+1)); printf 'PASS  %s\n' "$name"
    else
        FAIL=$((FAIL+1)); printf 'FAIL  %s (rc=%s) %s\n' "$name" "$RC" "${OUT//$'\n'/ | }"
    fi
}

echo "-- git-remote-check.sh regression (IMP-276a) --"

# R1 quiet: no remote, but below the default 20-commit threshold
make_repo "$SANDBOX/r1" 3 no
run_check "$SANDBOX/r1"
check "R1 no remote, 3 commits (below threshold): silent, exit 0" silent

# R2 acting: no remote at exactly the threshold, with two uncommitted paths
make_repo "$SANDBOX/r2" 20 no
: > "$SANDBOX/r2/draft-a.txt"; : > "$SANDBOX/r2/draft-b.txt"
run_check "$SANDBOX/r2"
check "R2 no remote at threshold (20 commits): NO GIT REMOTE warning, exit 0" says "NO GIT REMOTE"
check "R2 warning reports the commits, the dirty paths and zero remotes" \
    bash -c '[[ "$1" == *"20 commits"* && "$1" == *"2 uncommitted path(s)"* && "$1" == *"0 remotes"* ]]' _ "$OUT"

# R3 quiet: a remote is configured, so the warning does not apply
make_repo "$SANDBOX/r3" 20 yes
run_check "$SANDBOX/r3"
check "R3 remote configured with 20 commits: silent, exit 0" silent

# R4 opt-out: the exposed repo from R2 is silenced by CLAUDE_NOREMOTE_CHECK_OFF=1
run_check "$SANDBOX/r2" CLAUDE_NOREMOTE_CHECK_OFF=1
check "R4 opt-out on the exposed repo: silent, exit 0" silent

# R5 edge (named in the header): nothing to lose without commits, even at threshold 0; a non-repo is silent
make_repo "$SANDBOX/r5" 0 no
run_check "$SANDBOX/r5" CLAUDE_NOREMOTE_WARN_COMMITS=0
check "R5 unborn repo at threshold 0: silent, exit 0" silent
mkdir -p "$SANDBOX/not-a-repo"
run_check "$SANDBOX/not-a-repo" CLAUDE_NOREMOTE_WARN_COMMITS=0
check "R5 directory outside any repo at threshold 0: silent, exit 0" silent

# R6 stdin is ignored: malformed and empty input still give the same warning
STDIN_DATA='{not json' run_check "$SANDBOX/r2"
check "R6 malformed stdin: still warns, exit 0" says "NO GIT REMOTE"
STDIN_DATA='' run_check "$SANDBOX/r2"
check "R6 empty stdin: still warns, exit 0" says "NO GIT REMOTE"

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then exit 0; fi
exit 1
