#!/bin/bash
# Serena Write Gate — PreToolUse on mcp__serena__.* / mcp__plugin_serena_serena__.* (IMP-130)
# ─────────────────────────────────────────────────────────────────────────────
# WHY: The Write|Edit protection hooks match on tool NAMES. Serena's write
# tools (mcp__serena__replace_symbol_body etc.) never match, so before this
# gate existed they were globally disabled in ~/.serena/serena_config.yml
# ("a tool that looks protected but isn't is worse than a known gap",
# IMP-104/105). This gate closes the gap the honest way: it TRANSLATES each
# Serena write call into the (file_path, new_string) shape the native
# inspectors expect and DELEGATES to the very same scripts — no duplicated
# patterns that could drift.
#
# DESIGN CORNERSTONE — FAIL CLOSED:
#   * unknown tool suffix        → deny (use native Edit, or extend the contract here)
#   * unparseable stdin          → deny
#   * contract param missing     → deny (upstream param-name drift detection)
#   * inspector script missing   → deny (never "green without checking")
# The native inspectors are fail-open on missing params BY DESIGN (they see
# every Write|Edit). This gate can afford fail-closed because it knows the
# exact contract of every tool it admits.
#
# Delegation order matters: hard-blocking inspectors first, the recoverable
# "ask" (config-protection) LAST — so a user-approved ask cannot skip the
# secret/path checks that would have run after it.
#
# Consciously NOT delegated (documented gap, see rules/mcp-tool-usage.md):
#   * gateguard.sh / pretool-auto-read.sh — read-before-edit is enforced for
#     the native path; Serena's symbolic workflow reads symbols before editing
#     by construction, and serena-post-tool.sh records Serena reads into the
#     same tracker so a later NATIVE edit of that file is not blocked.
#   * controller-first-mutation-gate.sh — orchestration discipline, not file
#     safety; revisit if delegation metrics show Serena edits bypassing it.
#
# No bypass env var. A kill-switch here would be the same prompt-injection
# hole that CLAUDE_GATEGUARD_OFF was for the bash gate (IMP-119 lineage).
# If the gate misfires, fix the gate.
#
# Exit contract (PreToolUse): exit 0 + no output = allow;
#   exit 0 + permissionDecision JSON = deny/ask; exit 2 + stderr = block.
set -u

INPUT=$(cat)

TOOL_NAME=""
ABS=""

LOGF="$HOME/.claude/global-observation/serena-gate-log.jsonl"

log_decision() { # decision, detail
    mkdir -p "$(dirname "$LOGF")" 2>/dev/null || true
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg tool "${TOOL_NAME:-}" \
           --arg d "$1" --arg p "${ABS:-}" --arg x "${2:-}" \
           '{ts:$ts,tool:$tool,decision:$d,path:$p,detail:$x}' >>"$LOGF" 2>/dev/null || true
}

deny() { # reason — recoverable JSON deny, tells the model what to do instead
    log_decision "deny" "$1"
    local rj
    rj=$(printf '%s' "$1" | jq -Rs '.')
    cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$rj}}
JSON
    exit 0
}

# Fail-closed on garbage: if we cannot parse what we were asked to admit,
# we admit nothing.
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
    deny "serena-write-gate: stdin is not parseable JSON — fail-closed. Retry, or use native Edit/Write."
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty')
[ -n "$CWD" ] || CWD=$(pwd)

[ -n "$TOOL_NAME" ] || deny "serena-write-gate: tool_name missing — fail-closed."

# Not a Serena tool → not ours (other gates own it). Matcher should prevent this.
case "$TOOL_NAME" in
    mcp__serena__*|mcp__plugin_serena_serena__*) : ;;
    *) exit 0 ;;
esac

SUFFIX="${TOOL_NAME##*__}"

resolve_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "${CWD%/}" "$1" ;;
    esac
}

ti() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty"; }

REL=""
CONTENT=""

case "$SUFFIX" in
    # ── Read/navigation tools: pass through fast ────────────────────────────
    activate_project|check_onboarding_performed|find_declaration|find_file|\
    find_implementations|find_referencing_symbols|find_symbol|get_current_config|\
    get_diagnostics_for_file|get_symbols_overview|initial_instructions|list_dir|\
    list_memories|onboarding|prepare_for_new_conversation|read_file|read_memory|\
    search_for_pattern|summarize_changes|switch_modes|restart_language_server|\
    get_active_project|think_about_collected_information|think_about_task_adherence|\
    think_about_whether_you_are_done)
        exit 0 ;;

    # ── Write tools with an explicit (path, content) contract ───────────────
    replace_symbol_body|insert_after_symbol|insert_before_symbol)
        REL=$(ti relative_path)
        CONTENT=$(ti body)
        [ -n "$REL" ]     || deny "serena-write-gate: $SUFFIX without relative_path — contract violation (param drift?). Use native Edit."
        [ -n "$CONTENT" ] || deny "serena-write-gate: $SUFFIX without body — contract violation (param drift?). Use native Edit."
        ;;
    replace_content)
        REL=$(ti relative_path)
        CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.repl // .tool_input.replacement // .tool_input.new_content // .tool_input.content // .tool_input.body // empty')
        [ -n "$REL" ]     || deny "serena-write-gate: replace_content without relative_path — contract violation. Use native Edit."
        [ -n "$CONTENT" ] || deny "serena-write-gate: replace_content without a recognized replacement param — contract violation (param drift?). Use native Edit."
        ;;
    create_text_file)
        REL=$(ti relative_path)
        CONTENT=$(ti content)
        [ -n "$REL" ]     || deny "serena-write-gate: create_text_file without relative_path — contract violation. Use native Write."
        [ -n "$CONTENT" ] || deny "serena-write-gate: create_text_file without content — contract violation. Use native Write."
        ;;
    rename_symbol)
        REL=$(ti relative_path)
        CONTENT=$(ti new_name)
        [ -n "$REL" ]     || deny "serena-write-gate: rename_symbol without relative_path — contract violation. Use native Edit."
        [ -n "$CONTENT" ] || deny "serena-write-gate: rename_symbol without new_name — contract violation."
        ;;
    safe_delete_symbol)
        REL=$(ti relative_path)
        [ -n "$REL" ] || deny "serena-write-gate: safe_delete_symbol without relative_path — contract violation. Use native Edit."
        ;;

    # ── Memory writers: map onto .serena/memories/<name>.md ─────────────────
    # Memory names must be plain slugs: a "/" or ".." would let the resolved
    # path escape .serena/memories/ (incl. Serena's "global/" prefix, which
    # writes OUTSIDE the project — refuse it here; use native Write for that).
    write_memory|edit_memory)
        NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.memory_name // .tool_input.memory_file_name // .tool_input.name // empty')
        CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.body // empty')
        [ -n "$NAME" ]    || deny "serena-write-gate: $SUFFIX without memory name — contract violation. Use native Write on .serena/memories/."
        case "$NAME" in */*|*..*) deny "serena-write-gate: memory name '$NAME' contains a path component — refusing path escape from .serena/memories/. Use native Write." ;; esac
        [ -n "$CONTENT" ] || deny "serena-write-gate: $SUFFIX without content — contract violation. Use native Write on .serena/memories/."
        REL=".serena/memories/${NAME%.md}.md"
        ;;
    delete_memory)
        NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.memory_name // .tool_input.memory_file_name // .tool_input.name // empty')
        [ -n "$NAME" ] || deny "serena-write-gate: delete_memory without memory name — contract violation."
        case "$NAME" in */*|*..*) deny "serena-write-gate: memory name '$NAME' contains a path component — refusing path escape from .serena/memories/." ;; esac
        REL=".serena/memories/${NAME%.md}.md"
        ;;
    rename_memory)
        NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.memory_name // .tool_input.old_name // .tool_input.name // empty')
        [ -n "$NAME" ] || deny "serena-write-gate: rename_memory without source memory name — contract violation."
        case "$NAME" in */*|*..*) deny "serena-write-gate: memory name '$NAME' contains a path component — refusing path escape from .serena/memories/." ;; esac
        REL=".serena/memories/${NAME%.md}.md"
        CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_name // .tool_input.new_memory_name // empty')
        case "$CONTENT" in */*|*..*) deny "serena-write-gate: new memory name '$CONTENT' contains a path component — refusing path escape." ;; esac
        ;;

    # ── Permanently refused through this door ───────────────────────────────
    replace_in_files)
        deny "serena-write-gate: replace_in_files touches MULTIPLE files in one call and cannot be mapped onto the single-file inspectors. Use native Edit with replace_all per file." ;;
    execute_shell_command)
        deny "serena-write-gate: shell execution must go through the Bash tool and its gates, never through the MCP door." ;;

    # ── Fail-closed default: whatever we did not model, we do not admit ─────
    *)
        deny "serena-write-gate: unknown Serena tool '$SUFFIX' — fail-closed. Use the native equivalent, or extend the gate's contract (hooks/serena-write-gate.sh) + regression suite first." ;;
esac

ABS=$(resolve_path "$REL")

# resolve_path() above joins $CWD (this session's working directory) with
# relative_path — but relative_path is relative to Serena's ACTIVE PROJECT,
# which a stateless bash hook has no synchronous way to query (Serena's
# in-process project state isn't visible outside its own MCP server process).
# When both happen to be the same directory (the common case: one project per
# session) resolution is correct by coincidence, not by construction. When
# they diverge, $ABS silently names a file that was never touched — the
# inspectors below would then check protections against a fiction, and the
# audit trail (signals.jsonl) would log a path nothing happened to. These six
# tool suffixes only ever operate on an ALREADY-EXISTING file (unlike
# create_text_file), so a missing file at $ABS is proof the assumed base
# directory is wrong — fail closed instead of trusting it. Residual gap this
# does not close: a same-named file that happens to exist under both the
# wrong $CWD-based path and the real project (checked against the wrong
# file, still silently) — narrow enough to document, not solve here.
case "$SUFFIX" in
    replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|rename_symbol|safe_delete_symbol)
        [ -f "$ABS" ] || deny "serena-write-gate: resolved path $ABS does not exist. relative_path='$REL' is relative to Serena's active project, which this hook cannot query directly — it assumed the session's working directory ($CWD) and got a nonexistent file, so that assumption is wrong. Activate Serena from a session whose cwd matches the active project, or use native Edit."
        ;;
esac

# Synthesize the native payload the inspectors understand.
# security-audit reads .new_string // .content; the others read .file_path.
PAYLOAD=$(jq -cn --arg fp "$ABS" --arg ns "$CONTENT" --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" \
    '{tool_name:"Edit", tool_input:{file_path:$fp, new_string:$ns}, session_id:$sid, agent_id:$aid}')

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WARNINGS=""

# Order: hard blockers first, recoverable "ask" (config-protection) LAST —
# an approved ask must not skip checks that would have run after it.
# vault-write-gate.sh (IMP-219) sits right after security-audit.sh: both are
# hard content-pattern blockers, and vault-write-gate must run BEFORE the
# recoverable config-protection ask for the same reason security-audit does.
for inspector in parallel-lock-check.sh file-protection.sh security-audit.sh vault-write-gate.sh config-protection.sh; do
    SCRIPT="$HOOKS_DIR/$inspector"
    if [ ! -x "$SCRIPT" ]; then
        deny "serena-write-gate: inspector $inspector missing/not executable at $HOOKS_DIR — fail-closed (a gate that cannot check must not wave through)."
    fi
    OUT_F=$(mktemp); ERR_F=$(mktemp)
    printf '%s' "$PAYLOAD" | "$SCRIPT" >"$OUT_F" 2>"$ERR_F"
    CODE=$?
    OUT=$(cat "$OUT_F"); ERR=$(cat "$ERR_F")
    rm -f "$OUT_F" "$ERR_F"

    if [ "$CODE" -ne 0 ]; then
        log_decision "block" "$inspector"
        printf '[serena-write-gate] %s blocked %s -> %s:\n%s\n' "$inspector" "$SUFFIX" "$ABS" "$ERR" >&2
        exit 2
    fi
    if printf '%s' "$OUT" | grep -q '"permissionDecision"'; then
        log_decision "forward" "$inspector"
        printf '%s\n' "$OUT"
        exit 0
    fi
    [ -n "$ERR" ] && WARNINGS="${WARNINGS}${ERR}
"
done

[ -n "$WARNINGS" ] && printf '%s' "$WARNINGS" >&2

# ── Multi-file writers get a recoverable ASK, not a silent allow ─────────────
# rename_symbol / safe_delete_symbol name ONE definition file in their input,
# but the LSP writes ALL reference sites (N files). The single-file inspectors
# above could only check the named file + the new identifier. That residual is
# not silently waved through — the user confirms it (IMP-104's objection,
# answered honestly instead of ignored).
case "$SUFFIX" in
    rename_symbol|safe_delete_symbol)
        REL_DISPLAY=$(printf '%s' "$ABS" | sed "s|$HOME|~|")
        REASON="serena-write-gate: $SUFFIX on ${REL_DISPLAY} is REFERENCE-AWARE — the language server will also rewrite every reference site (N files not named in this call). The per-file inspectors checked only the definition file$( [ -n "$CONTENT" ] && printf ' and the new identifier' ). Confirm if the symbol's reference set is expected to span only normal project source files (no protected paths, no files claimed by a parallel agent)."
        log_decision "ask" "$SUFFIX multi-file"
        RJ=$(printf '%s' "$REASON" | jq -Rs '.')
        cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision": "ask","permissionDecisionReason":$RJ}}
JSON
        exit 0
        ;;
esac

log_decision "allow" "$SUFFIX"
exit 0
