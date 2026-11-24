#!/bin/bash
# session-handoff-write-regression.sh - regression suite for hooks/session-handoff-write.sh
# (Stop hook, always exit 0. Writes <git-root>/.rcode/handoff-<UTC date>-<session8>.md
# only when .rcode/ exists AND (a commit landed in the last 4 h OR 3+ signals today).
# Idempotent: refreshes the file, appends one pointer line to agent-log.md, keeps a
# single "handoff-*.md" line in .rcode/.gitignore. CLAUDE_AUTO_HANDOFF=0 disables it.)
# Every case runs in a fresh throwaway HOME and git project. Git fixtures run with the
# throwaway HOME so the real global git config is never read.
# Usage: bash hooks/tests/session-handoff-write-regression.sh   Exit: 0 pass, 1 fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CLAUDE_HOOK:-$SCRIPT_DIR/../session-handoff-write.sh}"
[[ -f "$HOOK" ]] || { echo "ERROR: hook not found: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
TODAY=$(date -u +%Y-%m-%d)
N=0

# new_case: fresh HOME and git repo on branch feat-x; optional commit
new_case() {   # new_case <commit: yes|no>
    N=$((N+1)); CASE="$WORK/c$N"
    FAKE_HOME="$CASE/home"; PROJ="$CASE/proj"
    mkdir -p "$FAKE_HOME/.claude/global-observation" "$PROJ"
    fgit() { env -i HOME="$FAKE_HOME" PATH="$PATH" git "$@"; }
    fgit init -q "$PROJ" && fgit -C "$PROJ" symbolic-ref HEAD refs/heads/feat-x
    if [[ "$1" == yes ]]; then
        fgit -C "$PROJ" -c user.name=test -c user.email=test@example.invalid \
            commit -q --allow-empty -m init
    fi
    SIGF="$FAKE_HOME/.claude/global-observation/signals.jsonl"
}
add_signal_today() { printf '{"ts":"%sT10:00:00Z","tool":"Edit"}\n' "$TODAY" >> "$SIGF"; }
# run_hook <stdin-text> [extra-env] -> sets RC, OUT, ERR; runs inside $PROJ
run_hook() {
    OUT=$(printf '%s' "$1" | (cd "$PROJ" && env -i HOME="$FAKE_HOME" PATH="$PATH" ${2:-} bash "$HOOK") 2>"$CASE/err"); RC=$?
    ERR=$(cat "$CASE/err")
}
stop_json() { jq -nc --arg s "$1" --arg c "$PROJ" '{session_id:$s,cwd:$c}'; }
pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL %s (rc=%s out=%s err=%s)\n' "$1" "$RC" "$OUT" "$ERR"; }

echo "-- session-handoff-write.sh regression --"

# Acting path: commit + .rcode/ -> handoff named with date and session8; pointer appended once.
new_case yes; mkdir -p "$PROJ/.rcode"; printf '# agent log\n' > "$PROJ/.rcode/agent-log.md"
HF="$PROJ/.rcode/handoff-$TODAY-abcdef12.md"
HF_NAME="handoff-$TODAY-abcdef12.md"   # the hook writes the realpath (/private/var on macOS), so match the name
run_hook "$(stop_json abcdef123456)"
if [[ "$RC" -eq 0 && -f "$HF" ]] \
   && grep -q "^# Handoff: $TODAY — session abcdef12" "$HF" \
   && grep -q "abcdef123456" "$HF" \
   && [[ "$(grep -cF "$HF_NAME" "$PROJ/.rcode/agent-log.md")" -eq 1 ]]; then
    pass "commit + .rcode: handoff file written, pointer appended, rc 0"
else fail "commit + .rcode: handoff file written, pointer appended, rc 0"; fi

# Idempotent: a second run refreshes the file, adds no second pointer, keeps one .gitignore line.
run_hook "$(stop_json abcdef123456)"
if [[ "$RC" -eq 0 && -f "$HF" \
   && "$(grep -cF "$HF_NAME" "$PROJ/.rcode/agent-log.md")" -eq 1 \
   && "$(grep -cx 'handoff-\*\.md' "$PROJ/.rcode/.gitignore")" -eq 1 ]]; then
    pass "second run: no duplicate pointer, single .gitignore entry"
else fail "second run: no duplicate pointer, single .gitignore entry"; fi

# Gate: no .rcode/ directory -> nothing written, even with a commit.
new_case yes
run_hook "$(stop_json abcdef123456)"
if [[ "$RC" -eq 0 && ! -e "$PROJ/.rcode" ]]; then
    pass "gate: no .rcode/ directory -> nothing written, rc 0"
else fail "gate: no .rcode/ directory -> nothing written, rc 0"; fi

# Gate threshold: no commit in 4 h -> 2 signals today stay silent; 3 signals today write.
new_case no; mkdir -p "$PROJ/.rcode"
add_signal_today; add_signal_today
run_hook "$(stop_json abcdef123456)"
QUIET_OK=0; [[ ! -e "$PROJ/.rcode/handoff-$TODAY-abcdef12.md" ]] && QUIET_OK=1
add_signal_today
run_hook "$(stop_json abcdef123456)"
if [[ "$QUIET_OK" -eq 1 && "$RC" -eq 0 && -f "$PROJ/.rcode/handoff-$TODAY-abcdef12.md" ]]; then
    pass "gate: 2 signals and no commit silent; 3 signals write"
else fail "gate: 2 signals and no commit silent; 3 signals write"; fi

# Opt-out: CLAUDE_AUTO_HANDOFF=0 writes nothing even with activity.
new_case yes; mkdir -p "$PROJ/.rcode"
run_hook "$(stop_json abcdef123456)" "CLAUDE_AUTO_HANDOFF=0"
if [[ "$RC" -eq 0 && -z "$(ls -A "$PROJ/.rcode")" ]]; then
    pass "CLAUDE_AUTO_HANDOFF=0: nothing written, rc 0"
else fail "CLAUDE_AUTO_HANDOFF=0: nothing written, rc 0"; fi

# Empty stdin and malformed JSON: session falls back to "unknown-session"; rc 0 both times.
new_case yes; mkdir -p "$PROJ/.rcode"
run_hook ""; RC_E=$RC
run_hook '{"session_id": '; RC_M=$RC
FB="$PROJ/.rcode/handoff-$TODAY-unknown-.md"
if [[ "$RC_E" -eq 0 && "$RC_M" -eq 0 && -f "$FB" ]] && grep -q "unknown-session" "$FB"; then
    pass "empty and malformed stdin: fallback session file written, rc 0"
else fail "empty and malformed stdin: fallback session file written, rc 0 (rc=$RC_E/$RC_M)"; fi

echo "-- summary --"
echo "PASS: $PASS   FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
