#!/bin/bash
# Pre-Flight Prompt Hook — UserPromptSubmit (rebuilt 2026-06-04)
# ──────────────────────────────────────────────────────────────
# Fires on task-shaped prompts. Injects a COMPACT pre-flight reminder:
#   1. pick a specialized subagent   (wish #5)
#   2. consider an agent swarm        (wish #6 — Workflow tool / parallel-dispatch)
#   3. [conditional] fetch Context7 docs first if a library is mentioned (wish #2)
#
# Replaces the older verbose parallel-only reminder. Filename kept for
# settings.json continuity (registered under UserPromptSubmit).
#
# Schema: { prompt, session_id, transcript_path, cwd, permission_mode, ... }
# Output: JSON with hookSpecificOutput.additionalContext
# Opt-out: CLAUDE_PARALLEL_AUTO_SUGGEST=0
set -u

[ "${CLAUDE_PARALLEL_AUTO_SUGGEST:-1}" = "0" ] && exit 0

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
[ -n "$PROMPT" ] || exit 0

PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ── Task-shape detection (EN + DE) ──
# German aliases kept: the owner writes German (und/alle/jede/keine parallel).
STRONG_TASK_RE='\b(build|baue?|create|erstelle?|implement|implementiere|refactor|refactore|migrate|migriere|port|portiere|convert|konvertiere|add|fuege|füge|extend|erweitere|develop|entwickle?)\b'
MEDIUM_TASK_RE='\b(fix|fixe|repariere|change|aendere|ändere|update|aktualisiere|write|schreibe?|rewrite|modify|modifiziere)\b'
MULTI_HINT_RE='\b([2-9]|[1-9][0-9]+|both|alle?|all|jede?|every|each|multiple|mehrere|several)\b|,.*,|\band\b|\bund\b'
FILE_HINT_RE='\.(ts|tsx|js|jsx|py|swift|rs|go|md|sh|css|html|json)\b|/(src|app|components|routes|pages|hooks|services|tests)/'

FIRE=0
echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$MEDIUM_TASK_RE" && echo "$PROMPT_LC" | grep -qE "$MULTI_HINT_RE" && FIRE=1
echo "$PROMPT_LC" | grep -qE "$FILE_HINT_RE" && echo "$PROMPT_LC" | grep -qE "$STRONG_TASK_RE|$MEDIUM_TASK_RE" && FIRE=1

# Hard skip tokens (user opted out for this prompt) + don't recurse into dispatch
case "$PROMPT_LC" in
    *"--no-preflight"*|*"--no-parallel"*|*"skip parallel"*|*"keine parallel"*) exit 0 ;;
    *"pdispatch-"*) exit 0 ;;
esac

# Not task-shaped → silent
[ "$FIRE" = "1" ] || exit 0

# ── Context7 trigger (wish #2): explicit library name OR integration verb ──
LIB_RE='\b(react|next\.?js|vue|svelte|angular|tailwind|prisma|supabase|firebase|stripe|express|fastapi|django|flask|swiftui|swiftdata|combine|zustand|redux|vite|webpack|playwright|vitest|jest|pytest|openai|anthropic|langchain|drizzle|trpc|graphql|apollo)\b'
INTEG_RE='\b(integr|integriere|sdk|npm install|pip install|uvx add|cargo add)\b'
CTX7=0
echo "$PROMPT_LC" | grep -qE "$LIB_RE" && CTX7=1
echo "$PROMPT_LC" | grep -qE "$INTEG_RE" && CTX7=1

# ── Build compact reminder ──
# IMP-077 (2026-07-03): point 2 aligned with IMP-055. The old text ("and wait
# for confirmation") injected the pre-IMP-055 policy into EVERY task prompt,
# undoing the 2026-06-21 auto-dispatch decision via recency bias. Now:
# auto-dispatch when reversible+disjoint; y/n ONLY for ESCALATE-band ops
# or scope that cannot be proven disjoint (rules/parallel-by-default.md).
REMINDER='[Pre-Flight — before starting this task]
1. PICK A SUBAGENT: Delegate to a specialized agent instead of doing everything yourself — control-agent for 3+ domains, otherwise backend-/testing-/ui-/research-/code-reviewer-agent or similar. Do it yourself only if none fits.
2. CHECK FOR A SWARM: For 2+ independent units (disjoint files, no A→B chain) → AUTO-DISPATCH in parallel with a one-line note (Workflow tool for complex orchestration, otherwise /parallel-dispatch). Confirmation (y/n) ONLY when ESCALATE-band ops are involved or file-disjointness cannot be proven — see rules/parallel-by-default.md. Otherwise sequential.'

if [ "$CTX7" = "1" ]; then
    REMINDER="$REMINDER
3. DOCS FIRST: The prompt names a library/integration → fetch current docs via Context7 (mcp__context7-keyed__resolve-library-id → query-docs) or /find-docs BEFORE writing code. Do not integrate from memory."
fi

REMINDER="$REMINDER

Opt-out for this session: export CLAUDE_PARALLEL_AUTO_SUGGEST=0"

# Log for observability
LOG="$HOME/.claude/global-observation/parallel-prompts.jsonl"
mkdir -p "$(dirname "$LOG")"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROMPT_SAMPLE=$(printf '%s' "$PROMPT" | head -c 100 | sed 's/"/\\"/g')
printf '{"ts":"%s","fired":1,"ctx7":%s,"prompt_sample":"%s"}\n' "$TS" "$CTX7" "$PROMPT_SAMPLE" >> "$LOG"

# Emit JSON per UserPromptSubmit protocol
jq -n --arg ctx "$REMINDER" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'
exit 0
