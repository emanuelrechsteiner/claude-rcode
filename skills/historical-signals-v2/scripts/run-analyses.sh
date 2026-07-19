#!/bin/bash
# Phase X3 — run all Phase 2 analyses (Tasks 2.1–2.5) against the populated DB.
# Outputs go to ~/claude-framework-consolidation/02-triage/x3-findings/*.txt
set -u
DB="$HOME/.claude/global-observation/historical-signals.db"
OUT="$HOME/claude-framework-consolidation/02-triage/x3-findings"
SCRIPTS="$HOME/.claude/skills/historical-signals-v2/scripts"
mkdir -p "$OUT"

[ -s "$DB" ] || { echo "ERROR: DB missing or empty: $DB" >&2; exit 1; }

echo "=== Phase X3 analyses ==="
sqlite3 "$DB" "SELECT 'sessions:    '||COUNT(*) FROM sessions UNION ALL
               SELECT 'tool_uses:   '||COUNT(*) FROM tool_uses UNION ALL
               SELECT 'tool_results:'||COUNT(*) FROM tool_results UNION ALL
               SELECT 'edits:       '||COUNT(*) FROM edits UNION ALL
               SELECT 'prompts:     '||COUNT(*) FROM prompts"
echo ""

# ----- Task 2.1: Bash command aggregation -----
{
    echo "# Task 2.1 — Bash command aggregation"
    echo ""
    echo "## Top 30 commands by leading word"
    sqlite3 "$DB" -header -column "
        SELECT
            SUBSTR(command, 1, INSTR(command || ' ', ' ') - 1) AS cmd,
            COUNT(*) AS n,
            COUNT(DISTINCT session_id) AS sessions
        FROM tool_uses
        WHERE tool_name = 'Bash' AND command IS NOT NULL
        GROUP BY cmd
        ORDER BY n DESC
        LIMIT 30
    "
    echo ""
    echo "## Top 20 failing commands (by command head)"
    sqlite3 "$DB" -header -column "
        SELECT
            SUBSTR(tu.command, 1, 60) AS cmd_head,
            COUNT(*) AS n_fails
        FROM tool_uses tu
        JOIN tool_results tr ON tr.tool_use_id = tu.id
        WHERE tu.tool_name = 'Bash' AND tr.is_error = 1
        GROUP BY cmd_head
        ORDER BY n_fails DESC
        LIMIT 20
    "
} > "$OUT/01-bash-commands.txt"
echo "✓ 01-bash-commands.txt"

# ----- Task 2.2: Tool-use sequences -----
{
    echo "# Task 2.2 — Tool-use sequences"
    echo ""
    echo "## Pairs of consecutive tool_uses (tool_a, err_a, tool_b, err_b)"
    sqlite3 "$DB" -header -column < "$SCRIPTS/q-sequences.sql"
    echo ""
    echo "## fail → edit → re-test triples (Bash fail → Edit/Write → Bash err)"
    sqlite3 "$DB" -header -column "
        WITH numbered AS (
            SELECT tu.id, tu.session_id, tu.ts, tu.tool_name, tr.is_error,
                ROW_NUMBER() OVER (PARTITION BY tu.session_id ORDER BY tu.ts) AS rn
            FROM tool_uses tu
            LEFT JOIN tool_results tr ON tr.tool_use_id = tu.id
        ),
        triples AS (
            SELECT
                a.tool_name AS s1, a.is_error AS e1,
                b.tool_name AS s2,
                c.tool_name AS s3, c.is_error AS e3
            FROM numbered a
            JOIN numbered b ON b.session_id = a.session_id AND b.rn = a.rn + 1
            JOIN numbered c ON c.session_id = a.session_id AND c.rn = a.rn + 2
            WHERE a.tool_name = 'Bash'
              AND a.is_error = 1
              AND b.tool_name IN ('Edit', 'Write', 'MultiEdit')
              AND c.tool_name = 'Bash'
        )
        SELECT e1, s2, e3, COUNT(*) AS n
        FROM triples
        GROUP BY e1, s2, e3
        ORDER BY n DESC
    "
} > "$OUT/02-sequences.txt"
echo "✓ 02-sequences.txt"

# ----- Task 2.3: Error pattern extraction -----
{
    echo "# Task 2.3 — Error patterns"
    echo ""
    echo "## Top 30 recurring error output heads"
    sqlite3 "$DB" -header -column "
        SELECT
            SUBSTR(output_summary, 1, 80) AS error_head,
            COUNT(*) AS n,
            COUNT(DISTINCT tool_use_id) AS distinct_calls
        FROM tool_results
        WHERE is_error = 1
        GROUP BY error_head
        ORDER BY n DESC
        LIMIT 30
    "
    echo ""
    echo "## Error rate per tool (only tools with ≥50 calls)"
    sqlite3 "$DB" -header -column "
        SELECT
            tu.tool_name,
            COUNT(*) AS calls,
            SUM(COALESCE(tr.is_error, 0)) AS errors,
            ROUND(100.0 * SUM(COALESCE(tr.is_error, 0)) / COUNT(*), 1) AS err_pct
        FROM tool_uses tu
        LEFT JOIN tool_results tr ON tr.tool_use_id = tu.id
        GROUP BY tu.tool_name
        HAVING calls >= 50
        ORDER BY err_pct DESC
    "
    echo ""
    echo "## Files with most errors"
    sqlite3 "$DB" -header -column "
        SELECT
            tu.file_path,
            COUNT(*) AS error_count
        FROM tool_uses tu
        JOIN tool_results tr ON tr.tool_use_id = tu.id
        WHERE tr.is_error = 1 AND tu.file_path IS NOT NULL
        GROUP BY tu.file_path
        ORDER BY error_count DESC
        LIMIT 20
    "
} > "$OUT/03-errors.txt"
echo "✓ 03-errors.txt"

# ----- Task 2.4: Co-edit graph -----
{
    echo "# Task 2.4 — Co-edit graph"
    echo ""
    echo "## Top co-edited file pairs (within same session, ≥3 sessions)"
    sqlite3 "$DB" -header -column "
        WITH pairs AS (
            SELECT
                e1.file_path AS file_a,
                e2.file_path AS file_b,
                tu1.session_id
            FROM edits e1
            JOIN tool_uses tu1 ON tu1.id = e1.tool_use_id
            JOIN edits e2 ON e2.id > e1.id
            JOIN tool_uses tu2 ON tu2.id = e2.tool_use_id
            WHERE tu1.session_id = tu2.session_id
              AND e1.file_path < e2.file_path
              AND e1.file_path != ''
              AND e2.file_path != ''
        )
        SELECT
            file_a, file_b, COUNT(DISTINCT session_id) AS sessions, COUNT(*) AS co_edits
        FROM pairs
        GROUP BY file_a, file_b
        HAVING sessions >= 3
        ORDER BY co_edits DESC
        LIMIT 25
    "
    echo ""
    echo "## Top project roots by edit volume"
    echo "(Directory-pair query dropped: SQLite has no last-slash function;"
    echo " the file-pair query above already surfaces architectural neighbors.)"
    sqlite3 "$DB" -header -column "
        SELECT
            -- Extract first 4 path components as 'project root'
            CASE
                WHEN file_path LIKE '/Users/%' THEN
                    REPLACE(REPLACE(REPLACE(REPLACE(file_path,
                        SUBSTR(file_path, INSTR(file_path, '/') + 1), ''),
                        SUBSTR(file_path, INSTR(file_path, '/') + 1), ''), '/', ''), '', file_path)
                ELSE file_path
            END AS sample_path,
            COUNT(*) AS edits,
            COUNT(DISTINCT tu.session_id) AS sessions
        FROM edits e
        JOIN tool_uses tu ON tu.id = e.tool_use_id
        WHERE file_path != ''
        GROUP BY file_path
        ORDER BY edits DESC
        LIMIT 15
    "
} > "$OUT/04-co-edits.txt"
echo "✓ 04-co-edits.txt"

# ----- Task 2.5: Diff-size distribution -----
{
    echo "# Task 2.5 — Diff-size distribution"
    echo ""
    echo "## Edit-type distribution"
    sqlite3 "$DB" -header -column "
        SELECT
            edit_type,
            COUNT(*) AS n,
            ROUND(AVG(new_string_len), 0) AS avg_new_len,
            ROUND(AVG(old_string_len), 0) AS avg_old_len,
            SUM(is_rewrite) AS rewrites,
            ROUND(100.0 * SUM(is_rewrite) / COUNT(*), 1) AS rewrite_pct
        FROM edits
        GROUP BY edit_type
    "
    echo ""
    echo "## Top 20 files by total characters written"
    sqlite3 "$DB" -header -column "
        SELECT
            file_path,
            COUNT(*) AS edits,
            SUM(new_string_len) AS total_chars_written,
            SUM(is_rewrite) AS rewrites
        FROM edits
        WHERE file_path != ''
        GROUP BY file_path
        ORDER BY total_chars_written DESC
        LIMIT 20
    "
    echo ""
    echo "## Per-session rewrite-heaviness (≥10 edits, top 15 by rewrite%)"
    sqlite3 "$DB" -header -column "
        SELECT
            s.session_id,
            s.cwd,
            COUNT(e.id) AS edits,
            SUM(e.is_rewrite) AS rewrites,
            ROUND(100.0 * SUM(e.is_rewrite) / COUNT(e.id), 1) AS rewrite_pct
        FROM sessions s
        JOIN tool_uses tu ON tu.session_id = s.session_id
        JOIN edits e ON e.tool_use_id = tu.id
        GROUP BY s.session_id
        HAVING edits >= 10
        ORDER BY rewrite_pct DESC
        LIMIT 15
    "
} > "$OUT/05-diff-sizes.txt"
echo "✓ 05-diff-sizes.txt"

echo ""
echo "Done. Findings in $OUT/"
ls -la "$OUT"
