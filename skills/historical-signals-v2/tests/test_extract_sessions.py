"""Session-level extraction tests."""

import sqlite3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract import extract_session_into_db

FIXTURE = Path(__file__).parent / "fixtures" / "sample_session.jsonl"
SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    return conn


def test_session_row_created():
    conn = make_db()
    extract_session_into_db(FIXTURE, conn, source="active")
    cursor = conn.execute("SELECT session_id, source, n_turns FROM sessions")
    rows = cursor.fetchall()
    assert len(rows) == 1
    assert rows[0][0] == "test-session-1"
    assert rows[0][1] == "active"
    assert rows[0][2] == 9  # total entries in fixture


def test_session_timestamps():
    conn = make_db()
    extract_session_into_db(FIXTURE, conn, source="active")
    cursor = conn.execute("SELECT started_at, ended_at FROM sessions")
    started, ended = cursor.fetchone()
    assert started == "2026-05-24T10:00:00Z"
    assert ended == "2026-05-24T10:00:20Z"


def test_session_rcode_false():
    conn = make_db()
    extract_session_into_db(FIXTURE, conn, source="active")
    cursor = conn.execute("SELECT rcode FROM sessions")
    assert cursor.fetchone()[0] == 0  # no rcode markers in fixture
