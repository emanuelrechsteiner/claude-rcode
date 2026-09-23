"""Cursor SQLite cross-source ingest test."""

import sqlite3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from cursor_ingest import ingest_cursor

SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def _build_fake_cursor_db(path: Path):
    """Synthetic Cursor DB matching the real schema (no `model` column).

    The real ~/.cursor/ai-tracking/ai-code-tracking.db has per-source line
    counts (tabLines*, composerLines*, humanLines*, blankLines*) instead of
    a model column. v1/v2 AI percentages are stored as TEXT, scoredAt as INTEGER.
    """
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE scored_commits (
            commitHash TEXT NOT NULL,
            branchName TEXT NOT NULL,
            scoredAt INTEGER NOT NULL,
            linesAdded INTEGER,
            linesDeleted INTEGER,
            tabLinesAdded INTEGER,
            tabLinesDeleted INTEGER,
            composerLinesAdded INTEGER,
            composerLinesDeleted INTEGER,
            humanLinesAdded INTEGER,
            humanLinesDeleted INTEGER,
            blankLinesAdded INTEGER,
            blankLinesDeleted INTEGER,
            commitMessage TEXT,
            commitDate TEXT,
            v1AiPercentage TEXT,
            v2AiPercentage TEXT,
            PRIMARY KEY (commitHash, branchName)
        );
        INSERT INTO scored_commits VALUES
            ('abc123', 'main',         1765527693543, 100, 5, 0, 0, 75, 0, 25, 5, 0, 0, 'feat', '2026-04-30', '75.5', '80.0'),
            ('def456', 'feat/foo',     1765620000000,  50, 10, 5, 0, 30, 5, 15, 5, 0, 0, 'fix',  '2026-05-01', '60.0', '65.5');
        """
    )
    conn.commit()
    conn.close()


def test_cursor_ingest_creates_rows(tmp_path):
    src = tmp_path / "cursor.db"
    _build_fake_cursor_db(src)

    tgt = tmp_path / "historical.db"
    conn_tgt = sqlite3.connect(tgt)
    conn_tgt.executescript(SCHEMA.read_text())

    n = ingest_cursor(src, conn_tgt)
    assert n == 2

    rows = conn_tgt.execute(
        "SELECT commit_hash, v1_ai_percentage, v2_ai_percentage FROM cursor_ai_commits "
        "ORDER BY commit_hash"
    ).fetchall()
    # v1AiPercentage / v2AiPercentage are TEXT in source; we cast to REAL in target.
    assert rows == [("abc123", 75.5, 80.0), ("def456", 60.0, 65.5)]


def test_cursor_ingest_handles_empty_percentage(tmp_path):
    """Real data often has '' for v1/v2 percentages. Must become NULL, not error."""
    src = tmp_path / "cursor.db"
    conn_src = sqlite3.connect(src)
    conn_src.executescript(
        """
        CREATE TABLE scored_commits (
            commitHash TEXT NOT NULL,
            branchName TEXT NOT NULL,
            scoredAt INTEGER NOT NULL,
            linesAdded INTEGER,
            linesDeleted INTEGER,
            tabLinesAdded INTEGER,
            tabLinesDeleted INTEGER,
            composerLinesAdded INTEGER,
            composerLinesDeleted INTEGER,
            humanLinesAdded INTEGER,
            humanLinesDeleted INTEGER,
            blankLinesAdded INTEGER,
            blankLinesDeleted INTEGER,
            commitMessage TEXT,
            commitDate TEXT,
            v1AiPercentage TEXT,
            v2AiPercentage TEXT,
            PRIMARY KEY (commitHash, branchName)
        );
        INSERT INTO scored_commits VALUES
            ('empty1', 'main', 1765527693543, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '', '');
        """
    )
    conn_src.commit()
    conn_src.close()

    tgt = tmp_path / "historical.db"
    conn_tgt = sqlite3.connect(tgt)
    conn_tgt.executescript(SCHEMA.read_text())
    n = ingest_cursor(src, conn_tgt)
    assert n == 1
    row = conn_tgt.execute(
        "SELECT v1_ai_percentage, v2_ai_percentage FROM cursor_ai_commits"
    ).fetchone()
    assert row == (None, None)
