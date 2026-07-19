-- Tool-use sequences: pairs of consecutive tool_uses per session, with errors flagged
WITH numbered AS (
    SELECT
        tu.id, tu.session_id, tu.ts, tu.tool_name, tu.command, tu.file_path,
        tr.is_error,
        ROW_NUMBER() OVER (PARTITION BY tu.session_id ORDER BY tu.ts) AS rn
    FROM tool_uses tu
    LEFT JOIN tool_results tr ON tr.tool_use_id = tu.id
),
pairs AS (
    SELECT
        a.session_id,
        a.tool_name AS tool_a,
        a.is_error AS err_a,
        b.tool_name AS tool_b,
        b.is_error AS err_b,
        a.ts AS ts_a
    FROM numbered a
    JOIN numbered b ON b.session_id = a.session_id AND b.rn = a.rn + 1
)
SELECT
    tool_a, err_a, tool_b, err_b, COUNT(*) AS n
FROM pairs
GROUP BY tool_a, err_a, tool_b, err_b
ORDER BY n DESC
LIMIT 50;
