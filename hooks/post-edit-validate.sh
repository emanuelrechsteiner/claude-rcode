#!/bin/bash
# Post-edit validation hook — stripped 2026-05-26 to EOF-stray-char check ONLY.
#
# Previously ran tsc + eslint per-edit (expensive: 5-30s × N edits).
# Those checks moved to stop-batched-checks.sh (Layer 2 of the Quality
# Trinity) which runs them ONCE per Stop event with bounded retries
# and time budget. This script now only does the cheap (<10ms) EOF
# stray-character check that catches the classic "1" incomplete-edit bug.
#
# Returns exit 2 if stray digit at EOF detected.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit early if no file path provided
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" == "null" ]]; then
    exit 0
fi

# Only check code/markup files (skip binary/images/data)
case "$FILE_PATH" in
    *.ts|*.tsx|*.js|*.jsx|*.py|*.swift|*.sh|*.rb|*.go|*.rs|*.kt|*.cs|*.cpp|*.c|*.h|*.hpp|*.java|*.md|*.css|*.html|*.json|*.yaml|*.yml|*.toml) ;;
    *) exit 0 ;;
esac

# Skip if file doesn't exist (might have been deleted)
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Stray character at EOF check (the classic "1" bug from incomplete edits)
LAST_CHAR=$(tail -c 2 "$FILE_PATH" 2>/dev/null | head -c 1)
if [[ "$LAST_CHAR" =~ ^[0-9]$ ]]; then
    LAST_LINE=$(tail -1 "$FILE_PATH" 2>/dev/null)
    if [[ "$LAST_LINE" =~ ^[0-9]+$ ]]; then
        echo "⚠️  Stray character '$LAST_LINE' detected at EOF in $FILE_PATH" >&2
        echo "    Likely an incomplete edit artifact." >&2
        exit 2
    fi
fi

# All checks passed (silent — Stop-batch will report aggregate findings)
exit 0
