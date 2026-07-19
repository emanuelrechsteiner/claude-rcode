"""Tool-use-level extraction tests."""

import sqlite3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract import extract_session_into_db, extract_tool_uses

FIXTURE = Path(__file__).parent / "fixtures" / "sample_session.jsonl"
SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def make_db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    return conn


def test_three_tool_uses_extracted():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    rows = conn.execute("SELECT tool_name FROM tool_uses ORDER BY ts").fetchall()
    assert [r[0] for r in rows] == ["Bash", "Edit", "Bash"]


def test_intent_inferred_from_prompt():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    rows = conn.execute("SELECT intent FROM tool_uses ORDER BY ts").fetchall()
    # All three tool uses follow "Bitte fix den Bug" → intent=fix
    assert all(r[0] == "fix" for r in rows)


def test_command_denormalized_for_bash():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    rows = conn.execute(
        "SELECT tool_name, command FROM tool_uses WHERE tool_name='Bash'"
    ).fetchall()
    assert len(rows) == 2
    assert all(r[1] == "npm test" for r in rows)


def test_file_path_denormalized_for_edit():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    row = conn.execute(
        "SELECT file_path FROM tool_uses WHERE tool_name='Edit'"
    ).fetchone()
    assert row[0] == "/tmp/test.ts"


def test_prompts_table_populated():
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    rows = conn.execute("SELECT text, source_type FROM prompts").fetchall()
    # Dedup by text within a session: one prompt row even though both user
    # message and last-prompt entry have the same text.
    assert len(rows) == 1
    assert "fix den Bug" in rows[0][0]


def test_tool_uses_linked_to_prompt():
    """All 3 tool_uses should link to the single deduped prompt."""
    conn = make_db()
    sid = extract_session_into_db(FIXTURE, conn, source="active")
    extract_tool_uses(FIXTURE, conn, sid)
    rows = conn.execute("SELECT DISTINCT prompt_id FROM tool_uses").fetchall()
    assert len(rows) == 1
    assert rows[0][0] is not None
