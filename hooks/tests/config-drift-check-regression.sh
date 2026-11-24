#!/usr/bin/env bash
# config-drift-check-regression.sh - regression suite for the drift warner that
# the Stop chain registers (the file lives in scripts/, not hooks/).
# Every case uses a throwaway config repo and a throwaway HOME. The remote is a
# local bare repo, so no network is used. The hook must always exit 0.
# Usage: bash hooks/tests/config-drift-check-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../../scripts/config-drift-check.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0; RC=0; OUT=""
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/config-drift-test.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
HOME_SB="$SANDBOX/home"; mkdir -p "$HOME_SB"
PATH_SB="$(dirname "$(command -v git)"):/usr/bin:/bin"

# run_drift [VAR=value ...] -> sets RC and OUT. Uses CFG and STDIN_DATA (default: empty stdin)
run_drift() {
    OUT=$(printf '%s' "${STDIN_DATA-}" | env -i HOME="$HOME_SB" PATH="$PATH_SB" LC_ALL=C LANG=C \
        CLAUDE_CONFIG_DIR="$CFG" "$@" bash "$HOOK" 2>&1)
    RC=$?
}
# new_config <name> <origin yes|no> -> sets CFG to a sample config repo
new_config() {
    local base="$SANDBOX/$1"
    CFG="$base/config"
    mkdir -p "$CFG"
    git -C "$CFG" init -q
    git -C "$CFG" symbolic-ref HEAD refs/heads/main
    git -C "$CFG" config user.name "Sample User"
    git -C "$CFG" config user.email "sample@example.invalid"
    git -C "$CFG" config commit.gpgsign false
    printf 'sample = 1\n' > "$CFG/settings-sample.json"
    git -C "$CFG" add settings-sample.json
    git -C "$CFG" commit -q -m "sample: initial"
    if [[ "$2" == yes ]]; then
        git init -q --bare "$base/remote.git"
        git -C "$CFG" remote add origin "$base/remote.git"
        git -C "$CFG" push -q origin main
        git -C "$CFG" fetch -q origin
    fi
}
# old_stamp -> timestamp 10 days ago in touch -t form (BSD date first, GNU fallback)
old_stamp() { date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M; }

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

echo "-- config-drift-check regression (IMP-276a) --"

# D1 quiet: in sync with origin/main, nothing uncommitted
new_config d1 yes
run_drift
check "D1 in sync with origin/main: silent, exit 0" silent

# D2 acting: an uncommitted edit older than the 3-day default
new_config d2 yes
printf 'changed = 2\n' >> "$CFG/settings-sample.json"
touch -t "$(old_stamp)" "$CFG/settings-sample.json"
run_drift
check "D2 uncommitted edit older than 3 days: warned" says "uncommitted for >3d"
check "D2 the warning names the stale file" says "settings-sample.json"

# D3 acting: a local commit that was never pushed
new_config d3 yes
printf 'local = 3\n' > "$CFG/settings-sample.json"
git -C "$CFG" commit -q -am "sample: local change"
run_drift
check "D3 unpushed local commit: warned with the count" says "1 local commit(s) not on origin/main"

# D4 acting: no origin/main ref at all (soft warning, still exit 0)
new_config d4 no
run_drift
check "D4 no origin/main ref: soft warning, exit 0" says "soft warn"

# D5 edge (named in the header): a deleted tracked file cannot be mtime-aged, so it is not flagged
new_config d5 yes
rm -f "$CFG/settings-sample.json"
run_drift
check "D5 deleted tracked file: not flagged as stale, silent, exit 0" silent

# D6 stdin is ignored: malformed and empty input change nothing
new_config d6 yes
STDIN_DATA='{not json' run_drift
check "D6 malformed stdin: ignored, silent, exit 0" silent
STDIN_DATA='' run_drift
check "D6 empty stdin: ignored, silent, exit 0" silent

echo "------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then exit 0; fi
exit 1
