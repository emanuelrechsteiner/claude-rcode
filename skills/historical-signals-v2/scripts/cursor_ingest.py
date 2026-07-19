"""Ingest Cursor's ai-tracking SQLite into the v2 historical-signals DB.

The real Cursor schema (~/.cursor/ai-tracking/ai-code-tracking.db) lacks a
`model` column; instead it splits line counts across tabLines*/composerLines*/
humanLines*/blankLines* and stores v1/v2 AI percentages as TEXT (often empty).
We copy what we have and leave `model` and `workspace_root` NULL in the target.
"""

import sqlite3
import sys
from pathlib import Path


def _to_float_or_none(v):
    """Source v1/v2AiPercentage is TEXT and may be ''/None — cast safely."""
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def ingest_cursor(cursor_db_path: Path, target_conn: sqlite3.Connection) -> int:
    """Read scored_commits from Cursor DB → cursor_ai_commits in v2 DB."""
    src = sqlite3.connect(cursor_db_path)
    rows = src.execute(
        """
        SELECT commitHash, branchName, scoredAt, linesAdded, linesDeleted,
               v1AiPercentage, v2AiPercentage
        FROM scored_commits
        """
    ).fetchall()
    src.close()

    count = 0
    for r in rows:
        commit_hash, branch_name, scored_at, lines_added, lines_deleted, v1, v2 = r
        target_conn.execute(
            """
            INSERT OR REPLACE INTO cursor_ai_commits
                (commit_hash, branch_name, scored_at, lines_added, lines_deleted,
                 v1_ai_percentage, v2_ai_percentage, model, workspace_root)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL)
            """,
            (
                commit_hash,
                branch_name,
                str(scored_at) if scored_at is not None else None,
                lines_added or 0,
                lines_deleted or 0,
                _to_float_or_none(v1),
                _to_float_or_none(v2),
            ),
        )
        count += 1
    target_conn.commit()
    return count


def main():
    if len(sys.argv) != 2:
        print("usage: cursor_ingest.py <target-historical-signals.db>", file=sys.stderr)
        sys.exit(1)
    target_path = Path(sys.argv[1])
    src_path = Path.home() / ".cursor/ai-tracking/ai-code-tracking.db"
    conn = sqlite3.connect(target_path)
    n = ingest_cursor(src_path, conn)
    print(f"Ingested {n} Cursor commits into {target_path}")


if __name__ == "__main__":
    main()
