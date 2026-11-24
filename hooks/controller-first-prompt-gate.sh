#!/bin/bash
# controller-first-prompt-gate.sh — IMP-089/IMP-090 (2026-07-15, Controller-First Enforcement)
# ─────────────────────────────────────────────────────────────────────────────
# UserPromptSubmit hook. Fires on EVERY prompt (A6 Q1, verbatim from the
# meta-proposal: "UserPromptSubmit fires garantiert bei JEDEM Prompt, keine
# Matcher"). Detects substance using the VERBATIM predicates copied from
# parallel-analyze-prompt.sh (STRONG_TASK_RE / MEDIUM_TASK_RE / MULTI_HINT_RE /
# FILE_HINT_RE) so this hook and the parallel-dispatch nudge never disagree on
# what counts as "substantial".
#
# On a substantial prompt, this hook injects a SOFT additionalContext reminder
# recommending a controller step (/team-lead, a control-agent dispatch or an
# /issue-style command), once per session. Its only session file is the
# once-per-session marker: the substantial flag and the controller-ran check served
# the mutation gate, which was retired on 2026-11-10 (docs/adr/0011-controller-first-mutation-gate-retired.md).
#
# This hook NEVER blocks — no permissionDecision:"block"/"ask" is ever emitted.
# See ~/.claude/plans/meta-proposal-2026-07-15-controller-first-enforcement.md
# §IMP-090 L4(a).
#
# Opt-out: none by design (this hook only ever adds context, never blocks —
# there is nothing to opt out of that would change behavior for the user).
#
# Context diet (2026-11-10): automated turns (subagent hand-backs, task notifications, system text) are skipped
# before anything is set, and the reminder is emitted once per session (marker under
# ${TMPDIR:-/tmp}/claude-prompt-reminders/). Regression: hooks/tests/controller-first-regression.sh.
set -u

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$PROMPT" ] || exit 0

# Shared predicate (hooks/lib/prompt-turn.sh). Without the library no turn counts as automated: the pre-diet behaviour.
. "$(dirname "$0")/lib/prompt-turn.sh" 2>/dev/null || { automated_turn() { return 1; }; printf 'controller-first-prompt-gate: cannot load lib/prompt-turn.sh\n' >&2; }

# Automated turns are not user input: silent, nothing set.
if automated_turn "$PROMPT"; then exit 0; fi

PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ── Substance predicates — VERBATIM from parallel-analyze-prompt.sh ──────────
# (Do not edit these independently of that file — they must stay in lockstep
# so the two hooks agree on "substantial".)
# German aliases kept: the owner writes German (und/alle/jede etc.).
STRONG_TASK_RE='\b(build|baue?|create|erstelle?|implement|implementiere|refactor|refactore|migrate|migriere|port|portiere|convert|konvertiere|add|fuege|füge|extend|erweitere|develop|entwickle?)\b'
MEDIUM_TASK_RE='\b(fix|fixe|repariere|change|aendere|ändere|update|aktualisiere|write|schreibe?|rewrite|modify|modifiziere)\b'
MULTI_HINT_RE='\b([2-9]|[1-9][0-9]+|both|alle?|all|jede?|every|each|multiple|mehrere|several)\b|,.*,|\band\b|\bund\b'
FILE_HINT_RE='\.(ts|tsx|js|jsx|py|swift|rs|go|md|sh|css|html|json)\b|/(src|app|components|routes|pages|hooks|services|tests)/'

FIRE=0
echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$MEDIUM_TASK_RE" && echo "$PROMPT_LC" | grep -qE "$MULTI_HINT_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$FILE_HINT_RE" && echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE|$MEDIUM_TASK_RE" && FIRE=1

# Not substantial → silent, no context.
[ "$FIRE" = "1" ] || exit 0

# ── Session id ────────────────────────────────────────────────────────────────
# Sanitised before it becomes part of a path (the once-per-session marker below).
SAFE_SESS=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')

# Once per session: the reminder is emitted on the first substantial prompt only. Without a session id
# there is no marker, so the reminder repeats (the pre-diet behaviour).
ONCE_MARK=""
if [ -n "$SAFE_SESS" ]; then
  ONCE_MARK="${TMPDIR:-/tmp}/claude-prompt-reminders/$SAFE_SESS.controller-first-prompt-gate"
  if [ -e "$ONCE_MARK" ]; then
    exit 0
  fi
fi

REMINDER='[Controller-First — before this substantial task]
This task looks substantial (task pattern detected). Per delegate-by-default
(rules/foundation.md): start with a Controller step — /team-lead, a control-agent
dispatch or a matching /issue-style command — that reads the prompt, decomposes it,
and assigns model + effort per subagent BEFORE files are mutated. This is a SOFT reminder, not a block, shown once per session.'

# Mark the session as shown (first emission only); a failed marker is reported, the reminder still goes out.
if [ -n "$ONCE_MARK" ]; then
  mkdir -p "$(dirname "$ONCE_MARK")" && : > "$ONCE_MARK" || printf 'controller-first-prompt-gate: cannot write %s\n' "$ONCE_MARK" >&2
fi

jq -n --arg ctx "$REMINDER" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'
exit 0
