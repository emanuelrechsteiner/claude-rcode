#!/bin/bash
# IMP-033: PreToolUse hook on Edit/Write — block if file not yet Read in session.
# Evidence: "File has not been read yet" fired 89 times across 78 sessions in 30-day window.
# Per tool-discipline.md Rule 1: Read before Edit or Write on existing files.
set -u

INPUT="$(cat)"
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0
[ -n "$SESSION_ID" ] || exit 0

TRACK_FILE="/tmp/claude-reads-${SESSION_ID}.txt"

# Write on a non-existing file = creating new file = no prior Read needed.
# IMP-093: also register the path in TRACK_FILE right here. The Write itself
# establishes full knowledge of the file's content, so a same-session
# follow-up Edit of this exact path must not be spuriously blocked for "not
# Read". Evidence: A2 forensics found 10/16 (62.5%) read-before-edit blocks
# on 2026-07-12 were this exact Write-then-immediately-blocked-Edit pattern
# on a file the agent had JUST created. Mirrors posttool-track-read.sh's
# append-only contract on the same TRACK_FILE.
if [ "$TOOL" = "Write" ] && [ ! -e "$FILE_PATH" ]; then
    echo "$FILE_PATH" >> "$TRACK_FILE"
    exit 0
fi

# Allow if file is in this session's Reads list
if [ -f "$TRACK_FILE" ] && grep -Fxq "$FILE_PATH" "$TRACK_FILE"; then
    exit 0
fi

# IMP-096: diagnose retry-loops. A SECOND block on the SAME file within
# <2min in the SAME session means the previous block wasn't actually fixed —
# the agent is retrying blindly instead of Reading the exact blocked path.
# Evidence: A1 found a 5-block/90s loop on one file in session 77b3a7dd.
# Surface the session's recently-tracked paths so the agent can see whether
# it Read a DIFFERENT path (relative vs. absolute, symlink, typo) instead of
# this exact one. BLOCK_LOG is a per-session /tmp file (same privacy/lifetime
# envelope as TRACK_FILE — never written to a shared log).
BLOCK_LOG="/tmp/claude-block-log-${SESSION_ID}.txt"
NOW_EPOCH=$(date -u +%s)
REPEAT_DIAG=""
if [ -f "$BLOCK_LOG" ] && command -v awk >/dev/null 2>&1; then
    LAST_EPOCH=$(awk -F'\t' -v want="$FILE_PATH" '$2==want{ts=$1} END{print ts+0}' "$BLOCK_LOG" 2>/dev/null)
    [ "$LAST_EPOCH" -ge 0 ] 2>/dev/null || LAST_EPOCH=0
    if [ "$LAST_EPOCH" -gt 0 ] && [ $(( NOW_EPOCH - LAST_EPOCH )) -lt 120 ]; then
        KNOWN_READS="(none tracked yet in this session)"
        if [ -f "$TRACK_FILE" ]; then
            KNOWN_READS=$(tail -5 "$TRACK_FILE" | sed 's/^/      - /')
        fi
        REPEAT_DIAG="
DIAGNOSIS (IMP-096): this is a REPEATED block on the same file within 2
minutes — retrying the same Edit/Write will not fix it. Paths actually
tracked as Read/Written in this session (most recent 5):
${KNOWN_READS}
If '$FILE_PATH' is not in that list verbatim (check relative-vs-absolute,
symlink, or typo differences), Read the EXACT path above, then retry."
    fi
fi
printf '%s\t%s\n' "$NOW_EPOCH" "$FILE_PATH" >> "$BLOCK_LOG"

# IMP-075: emit a first-class error event into signals.jsonl so the
# tool-discipline Rule-1 KPI ("read-before-edit blocks per 30d", baseline 89)
# is measurable from the signal stream instead of ad-hoc transcript mining.
SIG_FILE="$HOME/.claude/global-observation/signals.jsonl"
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cwd "$(pwd)" \
       --arg file "$FILE_PATH" --arg tool "$TOOL" --arg sid "$SESSION_ID" \
       '{ts:$ts,cwd:$cwd,intent:"error",error:"read-before-edit-block",file:$file,tool:$tool,session_id:$sid}' \
       >> "$SIG_FILE" 2>/dev/null || true

cat >&2 <<MSG
BLOCKED: '$FILE_PATH' has not been Read in this session.
Per tool-discipline.md Rule 1, you must Read a file before Edit or Write modifies it.
Read the file first, then retry the $TOOL.${REPEAT_DIAG}
MSG
exit 2
