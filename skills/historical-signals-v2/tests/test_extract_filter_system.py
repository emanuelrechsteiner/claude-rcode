"""System-injected prompts should be filtered (IMP-039)."""

import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from extract import extract_session_into_db, extract_tool_uses  # noqa: E402

SCHEMA = Path(__file__).parent.parent / "scripts" / "schema.sql"


def make_db_and_fixture(tmp_path, user_text):
    """Build a minimal session JSONL with a single user message containing `user_text`."""
    jsonl = tmp_path / "s.jsonl"
    jsonl.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "type": "user",
                        "timestamp": "2026-05-25T10:00:00Z",
                        "message": {"role": "user", "content": user_text},
                    }
                ),
                json.dumps(
                    {
                        "type": "assistant",
                        "timestamp": "2026-05-25T10:00:05Z",
                        "sessionId": "s1",
                        "message": {
                            "role": "assistant",
                            "content": [
                                {
                                    "type": "tool_use",
                                    "id": "t1",
                                    "name": "Bash",
                                    "input": {"command": "echo hi"},
                                }
                            ],
                        },
                    }
                ),
            ]
        )
        + "\n"
    )
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    return jsonl, conn


def test_auto_compaction_summary_filtered(tmp_path):
    """'Your task is to create a detailed summary...' must NOT become a prompt row."""
    jsonl, conn = make_db_and_fixture(
        tmp_path,
        "Your task is to create a detailed summary of the conversation so far, "
        "paying close attention to the user's explicit requests.",
    )
    sid = extract_session_into_db(jsonl, conn)
    extract_tool_uses(jsonl, conn, sid)
    n = conn.execute("SELECT COUNT(*) FROM prompts").fetchone()[0]
    assert n == 0, "auto-compaction system prompt leaked into prompts table"


def test_system_reminder_filtered(tmp_path):
    """Messages containing '<system-reminder>' must NOT become prompt rows."""
    jsonl, conn = make_db_and_fixture(
        tmp_path,
        "<system-reminder>The task tools haven't been used recently.</system-reminder>",
    )
    sid = extract_session_into_db(jsonl, conn)
    extract_tool_uses(jsonl, conn, sid)
    n = conn.execute("SELECT COUNT(*) FROM prompts").fetchone()[0]
    assert n == 0


def test_normal_user_text_preserved(tmp_path):
    """Real user prompts MUST still be captured."""
    jsonl, conn = make_db_and_fixture(tmp_path, "Bitte fix den Bug in foo.ts")
    sid = extract_session_into_db(jsonl, conn)
    extract_tool_uses(jsonl, conn, sid)
    rows = conn.execute("SELECT text FROM prompts").fetchall()
    assert len(rows) == 1
    assert "fix den Bug" in rows[0][0]
