"""Tool-result extraction tests."""

import sqlite3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract import extract_session_into_db, extract_tool_uses, extract_tool_results

FIXTURE = Path(__file__).parent / "fixtures" / "sample_session.jsonl"
SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    return conn


def test_three_tool_results():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    extract_tool_results(FIXTURE, conn, sid)
    n = conn.execute("SELECT COUNT(*) FROM tool_results").fetchone()[0]
    assert n == 3


def test_first_result_is_error():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    extract_tool_results(FIXTURE, conn, sid)
    row = conn.execute("""
        SELECT tr.is_error, tr.output_summary
        FROM tool_results tr
        JOIN tool_uses tu ON tu.id = tr.tool_use_id
        WHERE tu.tool_use_uuid = 'toolu_test1'
    """).fetchone()
    assert row[0] == 1
    assert "FAIL" in row[1]


def test_third_result_pass():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    extract_tool_results(FIXTURE, conn, sid)
    row = conn.execute("""
        SELECT tr.is_error, tr.output_summary
        FROM tool_results tr
        JOIN tool_uses tu ON tu.id = tr.tool_use_id
        WHERE tu.tool_use_uuid = 'toolu_test3'
    """).fetchone()
    assert row[0] == 0
    assert "PASS" in row[1]
