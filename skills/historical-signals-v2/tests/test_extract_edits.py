"""Edit-diff extraction tests."""

import sqlite3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract import (
    extract_session_into_db,
    extract_tool_uses,
    extract_tool_results,
    extract_edits,
)

FIXTURE = Path(__file__).parent / "fixtures" / "sample_session.jsonl"
SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    return conn


def test_one_edit_row():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    extract_tool_results(FIXTURE, conn, sid)
    extract_edits(FIXTURE, conn, sid)
    n = conn.execute("SELECT COUNT(*) FROM edits").fetchone()[0]
    assert n == 1


def test_edit_lengths():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    extract_tool_results(FIXTURE, conn, sid)
    extract_edits(FIXTURE, conn, sid)
    row = conn.execute("""
        SELECT file_path, edit_type, old_string_len, new_string_len, is_rewrite
        FROM edits
    """).fetchone()
    assert row[0] == "/tmp/test.ts"
    assert row[1] == "edit"
    assert row[2] == 3  # "foo"
    assert row[3] == 3  # "bar"
    assert row[4] == 0  # not a rewrite
