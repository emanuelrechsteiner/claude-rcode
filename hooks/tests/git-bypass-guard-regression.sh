#!/usr/bin/env bash
# Regression suite for hooks/git-bypass-guard.sh (IMP-240).
#
# Locks in: every git hook-bypass form blocks (exit 2); every negative control
# (quoted data, echo/grep/jq args, git log -n, push -n = dry-run, read-only
# config) passes; wrapper forms; single-use op-bound ack; TESTMODE; fail-open.
# HOME is redirected to a temp dir: nothing touches the real ~/.claude.
#
# Usage:  CLAUDE_HOOK=/path/to/git-bypass-guard.sh bash hooks/tests/git-bypass-guard-regression.sh
# Exit:   0 = all green, 1 = at least one red

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$HERE/../git-bypass-guard.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME/.claude/global-observation"
LOG="$HOME/.claude/global-observation/git-bypass-guard.log"
unset CLAUDE_GATE_TESTMODE

GREEN=0
RED=0
SID="gbg-$$-$RANDOM"
LAST_ERR=""

# run_hook <command> [session_id] -> sets RC and LAST_ERR
run_hook() {
    local cmd="$1" sid="${2:-$SID}"
    LAST_ERR=$(jq -nc --arg c "$cmd" --arg s "$sid" '{tool_input:{command:$c},session_id:$s}' \
        | bash "$HOOK" 2>&1 >/dev/null)
    RC=$?
}

pass() { echo "  ok    $1"; GREEN=$((GREEN + 1)); }
fail() { echo "  RED   $1 — $2"; RED=$((RED + 1)); }

expect() { # name expected-rc command [reason-substring required in stderr when blocking]
    run_hook "$3"
    if [[ "$RC" != "$2" ]]; then fail "$1" "expected rc=$2, got rc=$RC: $3 | $LAST_ERR"
    elif [[ -n "${4:-}" && "$LAST_ERR" != *"$4"* ]]; then fail "$1" "rc ok but reason lacks '$4': $LAST_ERR"
    else pass "$1 (rc=$RC)"; fi
}
block() { expect "$1" 2 "$2" "${3:---no-verify}"; }
allow() { expect "$1" 0 "$2"; }

NV='--no-verify on git'
echo "== blocked forms =="
block "commit --no-verify"            'git commit --no-verify -m x' "$NV commit"
block "commit -n"                     'git commit -n -m x' 'git commit -n'
block "commit -an cluster"            'git commit -an -m x' 'git commit -n'
block "commit -nm cluster"            'git commit -nm x' 'git commit -n'
block "commit -n after -m value"      'git commit -m "msg" -n' 'git commit -n'
block "push --no-verify"              'git push --no-verify origin main' "$NV push"
block "merge --no-verify"             'git merge --no-verify feature' "$NV merge"
block "pull --no-verify"              'git pull --no-verify' "$NV pull"
block "--no-verify prefix --no-verif" 'git commit --no-verif -m x' "$NV commit"
block "--no-verify= form"             'git commit --no-verify=1 -m x' "$NV commit"
block "--no-verify behind --"         'git commit -m x -- --no-verify' "$NV commit"
block "ANSI-C quoted flag"            "git commit \$'--no-verify' -m x" "$NV commit"
block "-C dir before subcommand"      'git -C /tmp/r commit -n' 'git commit -n'
block "--git-dir before subcommand"   'git --git-dir /tmp/r/.git commit --no-verify' "$NV commit"
block "-c core.hooksPath"             'git -c core.hooksPath=/dev/null commit -m x' 'core.hooksPath'
block "-c core.hookspath lowercase"   'git -c core.hookspath=/tmp push' 'core.hooksPath'
block "-ccore.hooksPath glued"        'git -ccore.hooksPath=/dev/null commit -m x' 'core.hooksPath'
block "config core.hooksPath set"     'git config core.hooksPath /tmp/hooks' 'core.hooksPath'
block "config --global hooksPath"     'git config --global core.hooksPath /dev/null' 'core.hooksPath'
block "config --unset hooksPath"      'git config --unset core.hooksPath' 'core.hooksPath'
block "config set (new style)"        'git config set core.hooksPath /x' 'core.hooksPath'
block "HUSKY=0 prefix"                'HUSKY=0 git commit -m x' 'HUSKY=0'
block "export HUSKY=0 then commit"    'export HUSKY=0; git commit -m x' 'HUSKY=0'
block "VAULT_PRECOMMIT_BYPASS reason" 'VAULT_PRECOMMIT_BYPASS=because git commit -m x' 'VAULT_PRECOMMIT_BYPASS'
block "VAULT_PRECOMMIT_BYPASS blank"  'VAULT_PRECOMMIT_BYPASS=" " git commit -m x' 'VAULT_PRECOMMIT_BYPASS'
block "VAULT_PRECOMMIT_BYPASS empty"  'VAULT_PRECOMMIT_BYPASS= git commit -m x' 'VAULT_PRECOMMIT_BYPASS'
block "VAULT bypass via env"          'env VAULT_PRECOMMIT_BYPASS=x git commit -m y' 'VAULT_PRECOMMIT_BYPASS'
block "VAULT bypass via export"       'export VAULT_PRECOMMIT_BYPASS=x && git commit -m y' 'VAULT_PRECOMMIT_BYPASS'
block "GIT_CONFIG_KEY hooksPath"      'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x git commit -m x' 'GIT_CONFIG_KEY_0'
block "after &&"                      'git add . && git commit --no-verify -m x' "$NV commit"
block "after newline"                 $'echo hi\ngit commit -n -m x' 'git commit -n'
block "command git"                   'command git commit -n' 'git commit -n'
block "backslash \\git"               '\git commit -n' 'git commit -n'
block "absolute /usr/bin/git"         '/usr/bin/git commit --no-verify' "$NV commit"
block "env wrapper"                   'env FOO=1 git commit --no-verify -m x' "$NV commit"
block "sudo wrapper"                  'sudo -u bob git push --no-verify' "$NV push"
block "sudo then env assignment"      'sudo HUSKY=0 git commit -m x' 'HUSKY=0'
block "nice -n 10"                    'nice -n 10 git commit -n' 'git commit -n'
block "timeout 30"                    'timeout 30 git commit -n' 'git commit -n'
block "timeout -k 5 30"               'timeout -k 5 30 git push --no-verify' "$NV push"
block "arch -arm64"                   'arch -arm64 git commit -n' 'git commit -n'
block "caffeinate"                    'caffeinate git commit -n' 'git commit -n'
block "stdbuf -oL"                    'stdbuf -oL git commit -n' 'git commit -n'
block "setsid"                        'setsid git commit -n' 'git commit -n'

echo "== wrapper forms =="
block "bash -c"                       'bash -c "git commit --no-verify -m x"' "$NV commit"
block "sh -c single quotes"           "sh -c 'git push --no-verify'" "$NV push"
block "eval"                          'eval "git commit --no-verify -m x"' "$NV commit"
block "command substitution"          'echo $(git commit --no-verify -m x)' "$NV commit"
block "echo piped into sh"            'echo "git commit --no-verify" | sh' "$NV commit"
block "heredoc fed to bash"           $'bash <<EOF\ngit commit --no-verify\nEOF' "$NV commit"
block "here-string into bash"         'bash <<< "git commit -n"' 'git commit -n'
block "cat heredoc piped to bash"     $'cat <<\'EOF\' | bash\ngit commit -n\nEOF' 'git commit -n'
block "heredoc+apostrophe, flag after" $'git commit -m "$(cat <<\'EOF\'\nfix don\'t\nEOF\n)" --no-verify' "$NV commit"

echo "== negative controls =="
allow "plain commit"                  'git commit -m "fix: thing"'
allow "heredoc+apostrophe commit (everyday form)" $'git commit -m "$(cat <<\'EOF\'\nfix don\'t\nEOF\n)"'
allow "heredoc+apostrophe, trailing flags ok" $'git commit -m "$(cat <<\'EOF\'\nfix don\'t\nEOF\n)" --amend'
allow "git log -n"                    'git log -n 5 --oneline'
allow "git tag -n"                    'git tag -n'
allow "git clean -n"                  'git clean -n'
allow "git stash list -n"             'git stash list -n 3'
allow "push -n is dry-run"            'git push -n origin main'
allow "pull -n is --no-stat"          'git pull -n'
allow "commit -m message 'n'"         'git commit -m n'
allow "commit -m -n (message is -n)"  'git commit -m -n'
allow "commit -am message"            'git commit -am "no-verify docs"'
allow "echo mention"                  'echo "git commit --no-verify"'
allow "printf mention"                "printf '%s\n' 'use git commit --no-verify'"
allow "grep mention"                  'grep -rn "no-verify" hooks/'
allow "jq mention"                    "jq -r '.x' <<< 'git commit --no-verify'"
allow "git log --grep no-verify"      'git log --grep no-verify'
allow "commit message mentions flag"  'git commit -m "block --no-verify bypass"'
allow "heredoc body to cat"           $'cat <<EOF\ngit commit --no-verify\nEOF'
allow "config --get hooksPath"        'git config --get core.hooksPath'
allow "config bare read"              'git config core.hooksPath'
allow "config --global --list"        'git config --global --list'
allow "config other key set"          'git config user.name "X"'
allow "-c other key"                  'git -c user.name=X commit -m x'
allow "-c hooksPath on status"        'git -c core.hooksPath=/x status'
allow "HUSKY=0 npm install"           'HUSKY=0 npm install'
allow "HUSKY=1 git commit"            'HUSKY=1 git commit -m x'
allow "nice without git"              'nice -n 10 make'

echo "== ack token: op-bound, single-use, logged =="
CMD='git commit --no-verify -m "approved"'
run_hook "$CMD"
SIG=$(printf '%s' "$LAST_ERR" | grep -oE 'CLAUDE_GIT_BYPASS_ACK=[a-f0-9]{64}' | head -1 | cut -d= -f2)
[[ ${#SIG} -eq 64 ]] && pass "block message prints exact re-run ack line" || fail "ack line" "no sha in: $LAST_ERR"
[[ "$LAST_ERR" == *"pre-commit vault"* ]] && pass "message names the skipped gate" || fail "gate named" "$LAST_ERR"
expect "wrong ack mismatch re-blocks" 2 "CLAUDE_GIT_BYPASS_ACK=$(printf 'a%.0s' {1..64}) $CMD"
expect "valid ack allows once"        0 "CLAUDE_GIT_BYPASS_ACK=$SIG $CMD"
expect "replay of consumed ack blocks" 2 "CLAUDE_GIT_BYPASS_ACK=$SIG $CMD"
expect "ack does not transfer to other op" 2 "CLAUDE_GIT_BYPASS_ACK=$SIG git push --no-verify"
grep -q '"token":"consumed".*"authorizer":"user"' "$LOG" && pass "consume logged authorizer=user" || fail "log" "no consumed/user line in $LOG"
grep -q '"token":"replay"' "$LOG" && pass "replay logged" || fail "log" "no replay line"

echo "== testmode / fail-open =="
CLAUDE_GATE_TESTMODE=1 run_hook 'git commit --no-verify -m x'
[[ "$RC" == 0 ]] && pass "TESTMODE exempts" || fail "TESTMODE" "rc=$RC"
[[ -s "$HOME/.claude/global-observation/git-bypass-guard-test.log" ]] && pass "TESTMODE logged" || fail "TESTMODE log" "missing"
printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1; [[ $? == 0 ]] && pass "unparsable JSON fails open" || fail "fail-open JSON" "non-zero"
printf '{"tool_input":{"command":""}}' | bash "$HOOK" >/dev/null 2>&1; [[ $? == 0 ]] && pass "empty command fails open" || fail "fail-open empty" "non-zero"
printf '' | bash "$HOOK" >/dev/null 2>&1; [[ $? == 0 ]] && pass "empty stdin fails open" || fail "fail-open stdin" "non-zero"

echo "== degraded mode: never silent for git-shaped input =="
BIN="$WORK/bin"; mkdir -p "$BIN"
for t in bash jq date mkdir dirname grep head cut tr cat rm mktemp; do ln -sf "$(command -v $t)" "$BIN/$t"; done
degraded_run() { # name hook-path path-env command expect-ask(1/0)
    local out
    out=$(jq -nc --arg c "$4" '{tool_input:{command:$c},session_id:"deg"}' | PATH="$3" bash "$2" 2>/dev/null); local rc=$?
    if [[ "$5" == 1 && $rc == 0 && "$out" == *'"permissionDecision":"ask"'* ]]; then pass "$1 asks (native ask JSON)"
    elif [[ "$5" == 0 && $rc == 0 && -z "$out" ]]; then pass "$1 allows non-git silently-but-logged"
    else fail "$1" "rc=$rc out=$out"; fi
}
degraded_run "no python3, git command" "$HOOK" "$BIN" 'git commit --no-verify' 1
degraded_run "no python3, non-git command" "$HOOK" "$BIN" 'ls -la' 0
CRASHDIR="$WORK/crash"; mkdir -p "$CRASHDIR/lib"; cp "$HOOK" "$CRASHDIR/hook.sh"
printf 'raise RuntimeError("forced crash")\n' > "$CRASHDIR/lib/git-bypass-classify.py"
degraded_run "classifier crash, git command" "$CRASHDIR/hook.sh" "$PATH" 'git commit -n' 1
degraded_run "classifier crash, non-git command" "$CRASHDIR/hook.sh" "$PATH" 'ls -la' 0
grep -q 'forced crash' "$LOG" && pass "crash traceback logged" || fail "crash log" "no traceback in $LOG"
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"; for t in bash date mkdir dirname grep head cut tr cat rm mktemp python3; do ln -sf "$(command -v $t)" "$NOJQ/$t"; done
out=$(printf '{"tool_input":{"command":"git commit -n"}}' | PATH="$NOJQ" bash "$HOOK" 2>/dev/null)
[[ "$out" == *'"permissionDecision":"ask"'* ]] && pass "missing jq asks for git-shaped input" || fail "no jq" "out=$out"

echo ""
echo "Result: GREEN=$GREEN RED=$RED of $((GREEN + RED))"
[[ "$RED" -eq 0 ]] || exit 1
