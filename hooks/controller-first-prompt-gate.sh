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
# On a substantial prompt, this hook:
#   1. ALWAYS writes the session-scoped substantial-flag
#        /tmp/controller-first-<session_id>/substantial
#      (read by controller-first-mutation-gate.sh — the deterministic backstop).
#   2. Injects a SOFT additionalContext reminder recommending a Controller-First
#      dispatch (control-agent / an /issue-style command) — UNLESS a
#      controller-ran flag is already present for this session, in which case
#      it stays silent (no need to re-nudge).
#
# This hook NEVER blocks — no permissionDecision:"block"/"ask" is ever emitted.
# See ~/.claude/plans/meta-proposal-2026-07-15-controller-first-enforcement.md
# §IMP-090 L4(a). The hard backstop lives in controller-first-mutation-gate.sh.
#
# Opt-out: none by design (this hook only ever adds context, never blocks —
# there is nothing to opt out of that would change behavior for the user).
set -u

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$PROMPT" ] || exit 0

PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ── Substance predicates — VERBATIM from parallel-analyze-prompt.sh ──────────
# (Do not edit these independently of that file — they must stay in lockstep
# so the two hooks agree on "substantial".)
STRONG_TASK_RE='\b(build|baue?|create|erstelle?|implement|implementiere|refactor|refactore|migrate|migriere|port|portiere|convert|konvertiere|add|fuege|füge|extend|erweitere|develop|entwickle?)\b'
MEDIUM_TASK_RE='\b(fix|fixe|repariere|change|aendere|ändere|update|aktualisiere|write|schreibe?|rewrite|modify|modifiziere)\b'
MULTI_HINT_RE='\b([2-9]|[1-9][0-9]+|both|alle?|all|jede?|every|each|multiple|mehrere|several)\b|,.*,|\band\b|\bund\b'
FILE_HINT_RE='\.(ts|tsx|js|jsx|py|swift|rs|go|md|sh|css|html|json)\b|/(src|app|components|routes|pages|hooks|services|tests)/'

FIRE=0
echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$MEDIUM_TASK_RE" && echo "$PROMPT_LC" | grep -qE "$MULTI_HINT_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$FILE_HINT_RE" && echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE|$MEDIUM_TASK_RE" && FIRE=1

# Not substantial → silent, no flag, no context.
[ "$FIRE" = "1" ] || exit 0

# ── Session state ─────────────────────────────────────────────────────────────
SESS="${SESSION_ID:-${CLAUDE_SESSION_ID:-$PPID}}"
STATE_DIR="/tmp/controller-first-$SESS"
mkdir -p "$STATE_DIR" 2>/dev/null || true
: > "$STATE_DIR/substantial" 2>/dev/null || true

# A controller step already ran this session → mutation-gate is already
# unlocked; no need to nudge again.
if [ -f "$STATE_DIR/controller-ran" ]; then
  exit 0
fi

REMINDER='[Controller-First — vor dieser substanziellen Aufgabe]
Diese Aufgabe wirkt substanziell (Task-Muster erkannt). Per Controller-First-Enforcement
(rules/foundation.md; IMP-089/090): starte mit einem Controller-Schritt — control-agent-
Dispatch oder ein passendes /issue-artiges Command — der den Prompt liest, dekomponiert
und je Subagent Modell + Aufwand zuweist, BEVOR Dateien mutiert werden. Dies ist ein
SOFT-Hinweis, kein Block; controller-first-mutation-gate.sh prüft denselben Zustand
deterministisch bei Write/Edit/klassifiziertem Bash (Modus: CLAUDE_CONTROLLER_GATE_MODE,
Default "note").'

jq -n --arg ctx "$REMINDER" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'
exit 0
