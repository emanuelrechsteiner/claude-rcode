#!/usr/bin/env bash
# prompt-turn-regression.sh — regression suite for hooks/lib/prompt-turn.sh (automated_turn)
# ─────────────────────────────────────────────────────────────────────────────
# One predicate behind the three UserPromptSubmit hooks that skip automated turns:
# parallel-analyze-prompt.sh, controller-first-prompt-gate.sh and knowledge-inject.sh (--prompt).
# A harness envelope counts only at the START of a prompt (after leading whitespace); a marker
# quoted in the middle of a user prompt is user content. Evidence (2026-11-10): 19 of 19 subagent
# hand-back prompts began with `<agent-message from="`.
#
# Usage:  bash hooks/tests/prompt-turn-regression.sh
# Exit:   0 = all assertions pass, 1 = failures listed on stdout.
set -u
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$TESTS_DIR/../lib/prompt-turn.sh"
PASS=0; FAIL=0; FAILURES=""

assert_eq() {  # description, expected, actual
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILURES="${FAILURES}  [$1] expected='$2' got='$3'\n"
    fi
}

# automated_says TEXT -> prints 1 when automated_turn matches TEXT, 0 otherwise (a fresh bash per call)
automated_says() {
    bash -c '. "$1" && if automated_turn "$2"; then printf 1; else printf 0; fi' _ "$LIB" "$1"
}

if [ ! -f "$LIB" ]; then
    printf 'FAIL: library missing: %s\n' "$LIB"
    exit 1
fi

# A) the five envelopes at the start of a prompt are automated turns
assert_eq "agent-message envelope at the start is automated" 1 "$(automated_says '<agent-message from="abc123">report')"
assert_eq "task-notification at the start is automated" 1 "$(automated_says '<task-notification> background job done')"
assert_eq "system-reminder at the start is automated" 1 "$(automated_says '<system-reminder> harness note')"
assert_eq "SYSTEM NOTIFICATION at the start is automated" 1 "$(automated_says '[SYSTEM NOTIFICATION - NOT USER INPUT] check finished')"
assert_eq "subagent hand-back at the start is automated" 1 "$(automated_says '[Subagent hand-back] Research finished')"

# B) leading whitespace before an envelope does not hide it
assert_eq "leading spaces before agent-message: automated" 1 "$(automated_says '   <agent-message from="x">report')"
assert_eq "leading newline before task-notification: automated" 1 "$(automated_says "$(printf '\n<task-notification> done')")"

# C) the measured shape: an agent-message envelope followed by a hand-back line
assert_eq "measured hand-back shape (agent-message line, then hand-back line): automated" 1 \
    "$(automated_says "$(printf '<agent-message from="abc123">\n[Subagent hand-back] The text below is the report')")"

# D) markers quoted in the middle of user text are user content
assert_eq "user asks why the hook misses <task-notification>: not automated" 0 \
    "$(automated_says 'Warum feuert der Hook bei <task-notification> nicht?')"
assert_eq "user quotes [Subagent hand-back] as a header: not automated" 0 \
    "$(automated_says 'Der Bericht enthielt [Subagent hand-back] als Kopfzeile')"
assert_eq "user quotes an agent-message tag mid-sentence: not automated" 0 \
    "$(automated_says 'Die Nachricht <agent-message from="x"> war leer')"
assert_eq "user quotes SYSTEM NOTIFICATION mid-text: not automated" 0 \
    "$(automated_says 'Ich habe [SYSTEM NOTIFICATION - NOT USER INPUT] kopiert')"
assert_eq "user quotes system-reminder after a slash command: not automated" 0 \
    "$(automated_says '/team-lead <system-reminder> erklaeren')"

# E) ordinary prompts and the empty prompt
assert_eq "empty prompt: not automated" 0 "$(automated_says '')"
assert_eq "ordinary task prompt: not automated" 0 "$(automated_says 'Füge bitte Tests hinzu')"
assert_eq "bare words agent-message without the angle bracket: not automated" 0 "$(automated_says 'agent-message from the team')"

echo "── prompt-turn-regression: $PASS passed, $FAIL failed ──"
if [ "$FAIL" -gt 0 ]; then
    printf "%b" "$FAILURES"
    exit 1
fi
exit 0
