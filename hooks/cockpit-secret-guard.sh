#!/bin/bash
# cockpit-secret-guard.sh - PreToolUse guard (Bash|Grep|Glob|Read) that stops the
# AGENT's tool calls from reading the Cockpit launch token.
#
# Threat: the Cockpit launch token now lives only in terminal scrollback, tmux
# history and the browser (spec: cockpit docs/superpowers/specs/2026-10-06-web-view.md,
# "Residual exposure"). permissions.deny cannot cover that: deny rules match the
# command PREFIX and do not expand "~", so `tmux -L x capture-pane -p`,
# `env tmux capture-pane`, `bash -c "tmux capture-pane -p"`, `command tmux save-buffer -`,
# `cat $HOME/.claude/cockpit/web-*.out` and a python one-liner all pass them.
#
# Denies (exit 2):
#   A  tmux capture-pane|pipe-pane|save-buffer|show-buffer|list-buffers|choose-buffer
#      (+ aliases and unique prefixes) at command position, through env prefixes,
#      wrappers (command/exec/env/xargs/watch/find -exec ...), -L/-S/-f options,
#      `\;` sequences, bash -c / sh -c / eval / $(...) / backticks / heredocs.
#      display-message and list-* -F only with a metadata-only format (allow-list).
#   B  any reference to ~/.claude/cockpit/web-* (HOME/~/absolute/${HOME}, globs,
#      brace lists, variables, cd/pushd + relative word, python/node/perl code),
#      also as Read/Grep/Glob path, glob or pattern fields.
#   C  environment dumps of the cockpit server: ps E/e and /proc/*/environ, only
#      when the command also names server.ts or cockpit.
# Allows: everything else, incl. tmux list-sessions/list-panes/send-keys/new-session,
#   events-*.jsonl, dashboard.log, status-*.json, config/*, and commands that only
#   MENTION these words as quoted data (git commit -m "...", echo, grep patterns).
#
# HONEST LIMITS: a deterministic best-effort tripwire against the agent's tool
# calls, not a sandbox. A same-uid process can still reach the token through
# terminal scrollback outside tmux, other windows' history or the browser, and a
# python/node one-liner that builds the path or the tmux command from string
# pieces, a script file, a function or an alias defeats any pattern guard. The
# permissions.deny entries stay as second layer (they are effective for the Read
# tool itself).
#
# KNOWN OPEN CLASSES (state of 2026-10-06; found by automated security review and by
# reading the code, NOT yet probed one by one, so each is a likely bypass until a
# probe says otherwise). The guard keeps this list instead of claiming closure:
#   1  shell evaluation modelled differently from bash: brace sequences cut at 16
#      items, ${var...} substitutions beyond the plain forms, $(( )) bodies not
#      inspected, `for` bound to the first item only, printf and `read` modelling
#   2  programs with built-in command execution treated as harmless data programs
#      (git and man options, awk/sed program text, find -path globs) and wrapper
#      prefixes (env, timeout, nice, ...) whose real target is not resolved
#   3  copy/link destination assumed to be the last operand (-t / --target-directory)
#   4  path spellings not canonicalised (/private/..., /proc/<pid>/task/.../environ)
#   5  interpreter code that builds a path from pieces without naming it literally,
#      and interpreter copy/link of the whole directory
#   6  other processes: debugger/tracer attach to the Cockpit server, MCP tools
#      outside read-like names
# Posture decision still open: ASK by default when a command names the Cockpit
# directory and cannot be classified as harmless (owner offered the choice 2026-10-06,
# chose to commit the tripwire first). The real defence is the one-shot token file
# and the short life of the token, not this guard.
#
# Override: NOT a self-service bypass. A prompt-injected agent can type any inline
# token, so `CLAUDE_GUARD_OVERRIDE=1 ` as the FIRST token of the Bash command only
# turns the deny into a native permissionDecision:"ask" (a real user prompt; exit 0,
# logged as COCKPIT-GUARD-OVERRIDE-ASK). Never an allow on the token alone. The
# ORIGINAL command string is always scanned as received (no prefix stripping, so no
# parser differential between scanned and executed text); the token is just one more
# leading NAME=value word to the scanner.
# Read/Grep/Glob have no inline token and stay hard denies. Denials are logged with
# secret-looking arguments redacted.
# Failure policy: fail-OPEN (stderr WARNING + log) only for empty/unparseable hook
# JSON and a missing scanner (python3 or the lib file). Anything caused by the
# command itself fails CLOSED: too long (> 64 KB), nesting/tokenizer errors, any
# scanner exception or crash on a parsed call all DENY ("too complex to inspect").
# Exit codes: 0 = allow (or ask JSON on stdout), 2 = block.

INPUT=$(cat)
[[ -z "$INPUT" ]] && exit 0
GUARD_LOG="${CLAUDE_GUARD_LOG:-$HOME/.claude/global-observation/guard-overrides.log}"
SCAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/cockpit_secret_scan.py"

log_line() { # decision, detail
    mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" >> "$GUARD_LOG" 2>/dev/null
}

classify() { printf '%s' "$1" | python3 -B "$SCAN" 2>/dev/null; }

if ! command -v python3 >/dev/null 2>&1 || [[ ! -f "$SCAN" ]]; then
    echo "WARNING: cockpit-secret-guard cannot run (python3 or $SCAN missing) - allowing UNCHECKED (fail-open)." >&2
    log_line "COCKPIT-GUARD-ERROR" "scanner unavailable"
    exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
OVERRIDE=0
if [[ "$COMMAND" =~ ^[[:space:]]*CLAUDE_GUARD_OVERRIDE=1[[:space:]]+ ]]; then
    OVERRIDE=1   # only flips DENY -> ask below; the scanned text is NEVER modified
fi

SCAN_OUT=$(classify "$INPUT")
IFS=$'\t' read -r VERDICT REASON SUMMARY <<< "$SCAN_OUT"

ask_json() { # reason -> native ask prompt on stdout (exit 0)
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
}

case "$VERDICT" in
    ALLOW) exit 0 ;;
    DENY) ;;
    ASK)
        log_line "COCKPIT-GUARD-ASK" "ask | $SUMMARY | $REASON"
        ask_json "cockpit-secret-guard: $REASON. This command may reach the Cockpit launch token and cannot be proven safe by pattern matching; approve this prompt only if you want the agent to run exactly this command."
        exit 0 ;;
    ERROR)
        echo "WARNING: cockpit-secret-guard got unparseable hook input (${REASON:-unknown}) - allowing UNCHECKED (fail-open)." >&2
        log_line "COCKPIT-GUARD-ERROR" "${REASON:-unparseable}"
        exit 0 ;;
    *)
        VERDICT=DENY
        REASON="command too complex to inspect (scanner crashed or gave no verdict); fail closed"
        SUMMARY="(scanner failure)" ;;
esac

if [[ "$OVERRIDE" == 1 ]]; then
    log_line "COCKPIT-GUARD-OVERRIDE-ASK" "ask | $SUMMARY | $REASON"
    jq -n --arg r "cockpit-secret-guard: $REASON. This command tries to reach the Cockpit launch token; the agent typed CLAUDE_GUARD_OVERRIDE=1 itself, which is not approval. Only the user can allow it: approve this prompt only if you want the agent to run exactly this command." '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $r
        }
    }'
    exit 0
fi

log_line "COCKPIT-GUARD-DENY" "$SUMMARY | $REASON"
{
    echo "BLOCKED: $REASON"
    echo "Rule: cockpit-secret-guard.sh - the agent must not read the Cockpit launch token."
    echo ""
    echo "──────────────────────────────────────────────────────────────"
    echo "DO NOT work around this block."
    echo "Specifically: do NOT achieve the same effect with a different"
    echo "tool or language (python/node/perl, another tmux spelling, a"
    echo "variable, a glob, a script file)."
    echo ""
    echo "Instead, STOP and do exactly this:"
    echo "  1. Tell the user, verbatim, the command you were about to run."
    echo "  2. Explain in one line what it would do and why you wanted it."
    echo "  3. Ask for explicit permission to proceed."
    echo ""
    echo "If the user approves, re-run the SAME command with"
    echo "  CLAUDE_GUARD_OVERRIDE=1  prepended: Claude Code then asks the user"
    echo "  once more (a real prompt; the token alone allows nothing)."
    echo "(Read/Grep/Glob calls have no inline override: use an approved Bash command.)"
    echo "──────────────────────────────────────────────────────────────"
} >&2
exit 2
