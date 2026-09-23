#!/bin/bash
# Serena Post-Tool Companion — PostToolUse on mcp__serena__.* (IMP-130)
# ─────────────────────────────────────────────────────────────────────────────
# The write-side twin of serena-write-gate.sh: after a Serena tool ran,
# feed the SAME downstream chain that native Edit/Write feeds —
#   * write tools  → auto-format.sh, post-edit-validate.sh, observation-capture.sh
#     (formatting, EOF stray-char check, the signals.jsonl logbook)
#   * read tools with an explicit relative_path → posttool-track-read.sh
#     (so a later NATIVE edit of a Serena-read file passes pretool-auto-read)
#
# PostToolUse cannot block; this script is fail-open by nature. The one
# exception: post-edit-validate's stray-char finding is propagated (exit 2 +
# stderr) so the model sees the defect immediately, same as on the native path.
set -u

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL_NAME" in
    mcp__serena__*|mcp__plugin_serena_serena__*) : ;;
    *) exit 0 ;;
esac

SUFFIX="${TOOL_NAME##*__}"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$(pwd)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

resolve_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "${CWD%/}" "$1" ;;
    esac
}

REL=""
case "$SUFFIX" in
    # Read tools that name a concrete file → record into the read tracker.
    get_symbols_overview|get_diagnostics_for_file|find_symbol|find_referencing_symbols|read_file)
        REL=$(printf '%s' "$INPUT" | jq -r '.tool_input.relative_path // empty' 2>/dev/null)
        [ -n "$REL" ] || exit 0   # project-wide search: no single file to record
        ABS=$(resolve_path "$REL")
        jq -cn --arg fp "$ABS" --arg sid "$SESSION_ID" \
            '{tool_name:"Read", tool_input:{file_path:$fp}, session_id:$sid}' \
            | "$HOOKS_DIR/posttool-track-read.sh" 2>/dev/null || true
        exit 0 ;;

    replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_content|\
    create_text_file|rename_symbol|safe_delete_symbol)
        REL=$(printf '%s' "$INPUT" | jq -r '.tool_input.relative_path // empty' 2>/dev/null)
        ;;
    write_memory|edit_memory|delete_memory|rename_memory)
        NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.memory_name // .tool_input.memory_file_name // .tool_input.name // empty' 2>/dev/null)
        [ -n "$NAME" ] && REL=".serena/memories/${NAME%.md}.md"
        ;;
    *) exit 0 ;;
esac

[ -n "$REL" ] || exit 0
ABS=$(resolve_path "$REL")

PAYLOAD=$(jq -cn --arg fp "$ABS" --arg sid "$SESSION_ID" \
    '{tool_name:"Edit", tool_input:{file_path:$fp}, session_id:$sid}')

# Formatting + logbook: fail-open (never noisy on the happy path).
printf '%s' "$PAYLOAD" | "$HOOKS_DIR/auto-format.sh"          >/dev/null 2>&1 || true
printf '%s' "$PAYLOAD" | "$HOOKS_DIR/observation-capture.sh"  >/dev/null 2>&1 || true

# EOF stray-char check: propagate a finding, same as the native path would.
ERR_F=$(mktemp)
if ! printf '%s' "$PAYLOAD" | "$HOOKS_DIR/post-edit-validate.sh" 2>"$ERR_F"; then
    cat "$ERR_F" >&2
    rm -f "$ERR_F"
    exit 2
fi
rm -f "$ERR_F"
exit 0
