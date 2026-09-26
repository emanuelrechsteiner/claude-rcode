#!/bin/bash
# Regression suite for hooks/git-state-check.sh
#
# Cause (2026-08-02, live finding): Check 2 caught `git rebase --abort` too,
# found the conflicts an abort was about to remove, and blocked with
# exit 2 — the hook barred the emergency exit from exactly the state it is
# meant to prevent. Making it worse, all messages went to stdout, so the
# blocker appeared with no reason at all ("No stderr output").
#
# This suite locks in both properties AND the protection that must
# remain: --continue and commit must still block on open conflicts.
#
# Usage:  bash hooks/tests/git-state-check-regression.sh
# Exit:    0 = all cases green, 1 = at least one case red

set -uo pipefail

HOOK="${CLAUDE_HOOK:-$HOME/.claude/hooks/git-state-check.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

GREEN=0
RED=0

# Calls the hook with a command. Returns "<rc>|<stdout>|<stderr>".
call_hook() {
    local cmd="$1"
    local out err rc
    out=$(mktemp); err=$(mktemp)
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$HOOK" >"$out" 2>"$err"
    rc=$?
    printf '%s|%s|%s' "$rc" "$(tr '\n' ' ' <"$out")" "$(tr '\n' ' ' <"$err")"
    rm -f "$out" "$err"
}

check_rc() {
    local name="$1" cmd="$2" expected="$3"
    local result rc
    result=$(call_hook "$cmd"); rc="${result%%|*}"
    if [[ "$rc" == "$expected" ]]; then
        echo "  ok    $name (rc=$rc)"; ((GREEN++))
    else
        echo "  RED   $name — expected rc=$expected, got rc=$rc"; ((RED++))
    fi
}

# ── Set up a working tree with a conflict ────────────────────────────────────
REPO="$WORK/repo"
mkdir -p "$REPO" && cd "$REPO" || exit 1
git init -q . 2>/dev/null
git config user.email "test@example.invalid"
git config user.name "Regression Test"
printf 'one\n' > file.txt
git add file.txt && git commit -q -m "base"
git checkout -q -b branch
printf 'two\n' > file.txt && git commit -qam "branch"
git checkout -q - 2>/dev/null || git checkout -q master 2>/dev/null || git checkout -q main
printf 'three\n' > file.txt && git commit -qam "trunk"
git merge branch >/dev/null 2>&1   # creates the conflict — return value irrelevant

if [[ -z "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "ERROR: test setup did not produce a conflict — suite is inconclusive." >&2
    exit 1
fi
echo "Test setup: open conflict in $(git diff --name-only --diff-filter=U | tr '\n' ' ')"
echo ""

echo "── Emergency exits MUST be let through (the fixed bug) ──"
check_rc "git rebase --abort"        "git rebase --abort"        0
check_rc "git merge --abort"         "git merge --abort"         0
check_rc "git rebase --skip"         "git rebase --skip"         0
check_rc "git rebase --quit"         "git rebase --quit"         0
check_rc "git cherry-pick --abort"   "git cherry-pick --abort"   0

echo ""
echo "── Protection MUST be preserved ──"
check_rc "git rebase --continue with a conflict" "git rebase --continue"       2
check_rc "git commit with a conflict"            "git commit -m 'anyway'"      2
check_rc "git push with a conflict"              "git push origin main"        2

echo ""
echo "── Reason must be on STDERR, not on stdout ──"
result=$(call_hook "git commit -m x")
stdout_part="${result#*|}"; stdout_part="${stdout_part%%|*}"
stderr_part="${result##*|}"
if [[ -n "${stderr_part// /}" ]]; then
    echo "  ok    reason present on stderr"; ((GREEN++))
else
    echo "  RED   stderr empty — blocker without a reason (the second finding)"; ((RED++))
fi
if [[ -z "${stdout_part// /}" ]]; then
    echo "  ok    stdout stays empty"; ((GREEN++))
else
    echo "  RED   stdout carries text: '${stdout_part}'"; ((RED++))
fi

echo ""
echo "── Non-git commands and a clean tree ──"
check_rc "npm test (not git)" "npm test" 0
check_rc "git status (not in the check list)" "git status" 0
git merge --abort >/dev/null 2>&1
check_rc "git commit in a clean tree" "git commit -m 'clean'" 0

echo ""
echo "═══════════════════════════════════════════"
echo "  green: $GREEN · red: $RED"
[[ $RED -eq 0 ]] && { echo "  ALL CASES GREEN"; exit 0; }
echo "  SUITE RED"; exit 1
