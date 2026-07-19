#!/bin/bash
# IMP-033 companion: track which files have been Read in this session.
# PostToolUse hook on Read; appends file_path to per-session track file.
set -u

INPUT="$(cat)"
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ "$TOOL" = "Read" ] || exit 0
[ -n "$SESSION_ID" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0

TRACK_FILE="/tmp/claude-reads-${SESSION_ID}.txt"
echo "$FILE_PATH" >> "$TRACK_FILE"
exit 0
