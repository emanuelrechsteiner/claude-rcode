#!/bin/bash
# Line Limit Check Hook — PostToolUse on Edit/Write
# Warns when a source file exceeds 400 lines (per ~/.claude/rules/code-quality.md).
# Ported from ~/.cursor/hooks/line-limit-check.sh on 2026-05-24.
# Cursor threshold was 150 (legacy); Claude Code threshold is 400 per project rule.
# Non-blocking — exits 0 always, warns via stderr.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file → nothing to check
[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Only check source files; skip docs, configs, generated files
EXT="${FILE_PATH##*.}"
case "$EXT" in
    ts|tsx|js|jsx|py|swift|kt|rs|go|rb|java|cs|cpp|c|h|hpp) ;;
    *) exit 0 ;;
esac

# Skip generated / vendored paths
if [[ "$FILE_PATH" =~ /node_modules/ ]] || \
   [[ "$FILE_PATH" =~ /\.next/ ]] || \
   [[ "$FILE_PATH" =~ /dist/ ]] || \
   [[ "$FILE_PATH" =~ /build/ ]] || \
   [[ "$FILE_PATH" =~ /vendor/ ]] || \
   [[ "$FILE_PATH" =~ \.generated\. ]]; then
    exit 0
fi

LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')
LINE_COUNT=${LINE_COUNT:-0}

# IMP-050: threshold lowered 400→250, env-configurable via CLAUDE_LINE_LIMIT.
THRESHOLD=${CLAUDE_LINE_LIMIT:-250}

if [ "$LINE_COUNT" -gt "$THRESHOLD" ]; then
    LOG=~/.claude/global-observation/refactor-needed.log
    mkdir -p "$(dirname "$LOG")"
    TS=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TS] $FILE_PATH = $LINE_COUNT lines (threshold $THRESHOLD)" >> "$LOG"
    echo "⚠️  $(basename "$FILE_PATH") = $LINE_COUNT lines (> $THRESHOLD). Consider splitting." >&2
fi

exit 0
