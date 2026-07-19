#!/bin/bash
# Phase X3 batch ingestion driver.
#
# Default: scans only ~/.claude/projects/ for *.jsonl session files.
# Optional: set CLAUDE_HISTORICAL_SOURCES to a colon-separated list of additional
# directories to recursively ingest (useful for archived session dumps on external
# volumes). Each path is scanned independently and merged into the same DB.
set -u
DB="$HOME/.claude/global-observation/historical-signals.db"
EXTRACT="$HOME/.claude/skills/historical-signals-v2/scripts/extract.py"

# Truncate (idempotent re-run)
rm -f "$DB"

# Initialize schema
python3 "$EXTRACT" --db "$DB" --init-schema

# Always include the standard active-sessions directory first.
ACTIVE_DIR="$HOME/.claude/projects"

# Build active-session list.
LIST_ACTIVE="/tmp/x3-active-$$"
trap "rm -f $LIST_ACTIVE /tmp/x3-extra-*-$$" EXIT
find "$ACTIVE_DIR" -name "*.jsonl" -type f -mindepth 2 2>/dev/null > "$LIST_ACTIVE"

COUNT_ACTIVE=$(wc -l < "$LIST_ACTIVE")
echo "Active sessions: $COUNT_ACTIVE files ($ACTIVE_DIR)"

# Optional extra sources via CLAUDE_HISTORICAL_SOURCES (colon-separated).
EXTRA_LISTS=()
if [ -n "${CLAUDE_HISTORICAL_SOURCES:-}" ]; then
    IFS=':' read -ra SRC_DIRS <<< "$CLAUDE_HISTORICAL_SOURCES"
    idx=0
    for src in "${SRC_DIRS[@]}"; do
        [ -z "$src" ] && continue
        if [ ! -d "$src" ]; then
            echo "[warn] extra source not found, skipping: $src" >&2
            continue
        fi
        list="/tmp/x3-extra-${idx}-$$"
        find "$src" -name "*.jsonl" -type f 2>/dev/null > "$list"
        cnt=$(wc -l < "$list")
        echo "Extra source [$idx]: $cnt files ($src)"
        EXTRA_LISTS+=("$list")
        idx=$((idx + 1))
    done
fi

START=$(date +%s)

# Ingest active sessions.
i=0
while IFS= read -r f; do
    i=$((i + 1))
    python3 "$EXTRACT" --db "$DB" --source active "$f" >/dev/null 2>&1 || \
        echo "[skip active: $(basename "$f")]" >&2
    if [ $((i % 100)) -eq 0 ]; then
        echo "  [active $i/$COUNT_ACTIVE] tool_uses so far: $(sqlite3 "$DB" 'SELECT COUNT(*) FROM tool_uses')"
    fi
done < "$LIST_ACTIVE"

# Ingest extra sources.
for list in "${EXTRA_LISTS[@]}"; do
    src_count=$(wc -l < "$list")
    j=0
    while IFS= read -r f; do
        j=$((j + 1))
        python3 "$EXTRACT" --db "$DB" --source historical_dump "$f" >/dev/null 2>&1 || \
            echo "[skip extra: $(basename "$f")]" >&2
        if [ $((j % 50)) -eq 0 ]; then
            echo "  [extra $j/$src_count] tool_uses so far: $(sqlite3 "$DB" 'SELECT COUNT(*) FROM tool_uses')"
        fi
    done < "$list"
done

ELAPSED=$(($(date +%s) - START))
echo ""
echo "=== Summary ==="
echo "Runtime: ${ELAPSED}s"
echo "DB: $DB ($(du -h "$DB" | cut -f1))"
sqlite3 "$DB" "SELECT 'sessions:', COUNT(*) FROM sessions UNION ALL
               SELECT 'tool_uses:', COUNT(*) FROM tool_uses UNION ALL
               SELECT 'tool_results:', COUNT(*) FROM tool_results UNION ALL
               SELECT 'edits:', COUNT(*) FROM edits UNION ALL
               SELECT 'prompts:', COUNT(*) FROM prompts"
