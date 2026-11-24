#!/usr/bin/env bash
# goal-prompt.sh: UserPromptSubmit (IMP-289). Every task prompt gets a goal on the Cockpit.
#
# On a non-automated prompt of at least CLAUDE_GOAL_MIN_WORDS words (default 8) the hook
# writes a goal seed (the start of the prompt, one line) through scripts/goal.sh, which also
# feeds Cockpit card 4, and tells the model how to turn the seed into a plan with atomic
# issues and minute estimates. While a goal with open issues exists, a new prompt keeps it
# and is kept as a note in the deviation list ("new-prompt", never raised at the stop: it is
# the user's own input). Automated turns (hand-backs, task notifications) and short prompts
# are ignored.
# Opt-out: CLAUDE_GOAL_TRACKING=0. Always exits 0: a failure costs the seed, never the prompt.
set -u
INPUT=$(cat 2>/dev/null || true)
[ "${CLAUDE_GOAL_TRACKING:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/prompt-turn.sh
. "$HERE/lib/prompt-turn.sh"
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null) || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
[ -n "$PROMPT" ] || exit 0
case "$SID" in ''|.*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
automated_turn "$PROMPT" && exit 0
WORDS=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
[ "${WORDS:-0}" -ge "${CLAUDE_GOAL_MIN_WORDS:-8}" ] || exit 0
GOAL="$HERE/../scripts/goal.sh"
[ -f "$GOAL" ] || exit 0
GOAL_DIR="${CLAUDE_GOAL_DIR:-$HOME/.claude/global-observation/goals}"
mkdir -p "$GOAL_DIR" 2>/dev/null || exit 0
# The text is cut in Python (character-safe); the shell only bounds the argument size.
# The --flag=value form keeps a value that starts with a dash from being read as an option.
OUT=$(bash "$GOAL" --session "$SID" seed --cwd="${CWD:-$PWD}" --text="${PROMPT:0:2000}" 2>>"$GOAL_DIR/errors.log") || exit 0
case "$OUT" in
  *"open goal was kept"*)
    printf '[Goal tracking] A goal with open issues exists; this prompt was noted on the goal. If it changes the goal, send a new plan first (bash ~/.claude/scripts/goal.sh --session %s plan; a replan is a recorded deviation); if it continues the goal, go on. Status: bash ~/.claude/scripts/goal.sh --session %s status\n' "$SID" "$SID"
    ;;
  *)
    cat <<EOF
[Goal tracking] A goal seed for this prompt is on Cockpit card 4. Before the first change:
1. Plan: bash ~/.claude/scripts/goal.sh --session $SID plan <<'JSON'
{"goal":"<one sentence>","milestones":[{"id":"M1","title":"..."}],"issues":[{"id":"I1","title":"...","milestone":"M1","est_min":10,"paths":["src/*"]}]}
JSON
   Atomic issues with honest minutes; paths = the files an issue may touch; "fixed":true for machine time (suite, build, deploy). Milestones follow research, plan, develop, test, deploy; leave a stage out only with a reason.
2. goal.sh --session $SID start <id> when an issue begins, done <id> when its check has passed.
3. A detour, added or dropped work: goal.sh add | drop | deviate BEFORE doing it. Unreported deviations are raised when the turn ends.
EOF
    ;;
esac
exit 0
