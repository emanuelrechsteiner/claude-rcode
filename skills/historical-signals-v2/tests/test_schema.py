"""Test that schema.sql creates the expected tables and columns."""

import sqlite3
from pathlib import Path

SCHEMA_PATH = Path(__file__).parent.parent / "scripts" / "schema.sql"


def test_schema_creates_all_tables():
    """Loading schema.sql into a fresh DB should create 6 named tables + schema_version."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA_PATH.read_text())
    cursor = conn.execute(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    tables = [row[0] for row in cursor.fetchall()]
    expected = [
        "cursor_ai_commits",
        "edits",
        "prompts",
        "schema_version",
        "sessions",
        "tool_results",
        "tool_uses",
    ]
    assert tables == expected, f"Got {tables}, expected {expected}"
    conn.close()


def test_schema_records_version():
    """schema_version table should contain a single row with version='2.0.0'."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA_PATH.read_text())
    cursor = conn.execute("SELECT version FROM schema_version")
    rows = cursor.fetchall()
    assert len(rows) == 1
    assert rows[0][0] == "2.0.0"
    conn.close()
