# prompt-turn.sh — the shared "automated turn" predicate for the UserPromptSubmit hooks (context diet, 2026-11-10).
# Sourced by hooks/parallel-analyze-prompt.sh, hooks/controller-first-prompt-gate.sh and hooks/knowledge-inject.sh (--prompt).
# Evidence (2026-11-10): 19 of 19 subagent hand-back prompts in global-observation/parallel-prompts.jsonl begin with
# `<agent-message from="`; task notifications arrive as a block beginning `<task-notification>`.
# Regression: hooks/tests/prompt-turn-regression.sh.

# automated_turn TEXT: status 0 when TEXT, after leading whitespace, STARTS with a harness-generated
# envelope (subagent hand-back, task notification, system text). A marker later in the text is user content.
automated_turn() {
    local t="${1#"${1%%[![:space:]]*}"}"
    case "$t" in
        "<agent-message"*|"<task-notification>"*|"<system-reminder"*|"[SYSTEM NOTIFICATION - NOT USER INPUT]"*|"[Subagent hand-back]"*) return 0 ;;
    esac
    return 1
}
