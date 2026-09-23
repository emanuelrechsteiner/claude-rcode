"""Historical Signals v2 — Claude JSONL → SQLite adapter."""

import json
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

RCODE_MARKERS = re.compile(
    r"(\.rcode|/issue|/phase-gate|/decompose|/brainstorm|PROJECT-STATUS\.md)"
)


def _read_jsonl(path: Path):
    """Yield each valid JSON line from a JSONL file. Skip malformed lines."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _derive_session_id(entries, jsonl_path: Path) -> str:
    """Find sessionId from any assistant turn; fallback to filename stem."""
    for e in entries:
        if e.get("type") == "assistant" and e.get("sessionId"):
            return e["sessionId"]
    return jsonl_path.stem


def _detect_rcode(jsonl_path: Path) -> bool:
    """Content scan for R.Code markers."""
    try:
        with open(jsonl_path, "r", encoding="utf-8", errors="replace") as f:
            for chunk in iter(lambda: f.read(64 * 1024), ""):
                if RCODE_MARKERS.search(chunk):
                    return True
    except OSError:
        return False
    return False


def _now_iso() -> str:
    return (
        datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    )


def extract_session_into_db(
    jsonl_path: Path, conn: sqlite3.Connection, source: str = "active"
) -> str:
    """Extract one session-level row. Returns session_id."""
    entries = list(_read_jsonl(jsonl_path))
    if not entries:
        return ""

    session_id = _derive_session_id(entries, jsonl_path)
    timestamps = [e.get("timestamp") for e in entries if e.get("timestamp")]
    started_at = min(timestamps) if timestamps else None
    ended_at = max(timestamps) if timestamps else None
    rcode = 1 if _detect_rcode(jsonl_path) else 0
    n_turns = len(entries)

    conn.execute(
        """
        INSERT OR REPLACE INTO sessions
            (session_id, jsonl_path, cwd, started_at, ended_at,
             rcode, source, n_turns, ingested_at)
        VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?)
    """,
        (
            session_id,
            str(jsonl_path),
            started_at,
            ended_at,
            rcode,
            source,
            n_turns,
            _now_iso(),
        ),
    )
    conn.commit()
    return session_id


# Intent keyword maps (extracted from v1 historical-signals SKILL)
INTENT_FIX = re.compile(
    r"\b(fix|bug|hotfix|repair|broken|crash|error|fail|issue|fehler|behoben|behebe|repariere|kaputt|defekt|wirft)",
    re.IGNORECASE,
)
INTENT_REFACTOR = re.compile(
    r"\b(refactor|restructure|cleanup|extract|simplif|reorganiz|umstrukturier|aufrau|verein|verschön)",
    re.IGNORECASE,
)
INTENT_FEATURE = re.compile(
    r"\b(add|implement|creat|new|build|feature|entwickl|develop|baue|hinzuf|implementi|erstell)",
    re.IGNORECASE,
)

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

LOCAL_CMD_BOILERPLATE = re.compile(r"<local-command-(caveat|stdout)>|<command-name>")

# IMP-039: filter system-injected prompts (auto-compaction summaries + system reminders)
SYSTEM_INJECTION = re.compile(
    r"<system-reminder>|"
    r"Your task is to create a detailed summary of the conversation"
)


def _extract_user_text(entry: dict) -> str:
    """Pull user-typed text from a 'user' entry. Skip tool_result and boilerplate."""
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        parts = [
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        text = " ".join(parts)
    else:
        return ""
    if not text or LOCAL_CMD_BOILERPLATE.search(text):
        return ""
    if SYSTEM_INJECTION.search(text):
        return ""
    return text.strip()


def _classify_intent(text: str) -> str:
    """Map a user prompt to intent bucket. Default 'edit'."""
    if not text:
        return "edit"
    if INTENT_FIX.search(text):
        return "fix"
    if INTENT_REFACTOR.search(text):
        return "refactor"
    if INTENT_FEATURE.search(text):
        return "feature"
    return "edit"


def extract_tool_uses(
    jsonl_path: Path, conn: sqlite3.Connection, session_id: str
) -> int:
    """Walk a session, populate tool_uses + prompts tables. Returns count of tool_uses."""
    entries = list(_read_jsonl(jsonl_path))

    # First pass: collect all user prompts (user-typed text + last-prompt entries)
    prompts_seen = []  # list of (entry_index, ts, text, source_type)
    for i, e in enumerate(entries):
        text = ""
        source_type = ""
        if e.get("type") == "last-prompt" and e.get("lastPrompt"):
            text = e["lastPrompt"].strip()
            source_type = "last_prompt"
        elif e.get("type") == "user":
            text = _extract_user_text(e)
            source_type = "user_message"
        if text:
            prompts_seen.append((i, e.get("timestamp"), text, source_type))

    # Insert deduped prompts (first occurrence wins).
    # Map each occurrence's entry index → the prompt_id we should use for it.
    prompt_id_by_index = {}
    text_to_prompt_id = {}
    for idx, ts, text, src in prompts_seen:
        if text in text_to_prompt_id:
            prompt_id_by_index[idx] = text_to_prompt_id[text]
            continue
        cursor = conn.execute(
            """
            INSERT INTO prompts (session_id, ts, source_type, text, text_length)
            VALUES (?, ?, ?, ?, ?)
            """,
            (session_id, ts, src, text, len(text)),
        )
        pid = cursor.lastrowid
        text_to_prompt_id[text] = pid
        prompt_id_by_index[idx] = pid

    # Helper: most-recent prompt-id at or before a given entry index
    def _prompt_id_before(idx: int):
        best = None
        for prev_idx in prompt_id_by_index:
            if prev_idx <= idx:
                best = prompt_id_by_index[prev_idx]
        return best

    # Helper: text of the prompt that gave us prompt_id (for intent classification)
    def _prompt_text_for_id(pid):
        if pid is None:
            return ""
        row = conn.execute("SELECT text FROM prompts WHERE id = ?", (pid,)).fetchone()
        return row[0] if row else ""

    # Second pass: extract tool_uses
    count = 0
    for i, e in enumerate(entries):
        if e.get("type") != "assistant":
            continue
        content = e.get("message", {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            tool_name = block.get("name", "")
            tool_input = block.get("input", {}) or {}
            tool_use_uuid = block.get("id")
            ts = e.get("timestamp")

            prompt_id = _prompt_id_before(i)
            intent = _classify_intent(_prompt_text_for_id(prompt_id))

            file_path = tool_input.get("file_path") or tool_input.get("notebook_path")
            command = tool_input.get("command") if tool_name == "Bash" else None

            conn.execute(
                """
                INSERT OR IGNORE INTO tool_uses
                    (session_id, tool_use_uuid, ts, tool_name, tool_input_json,
                     intent, prompt_id, file_path, command)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    tool_use_uuid,
                    ts,
                    tool_name,
                    json.dumps(tool_input, ensure_ascii=False),
                    intent,
                    prompt_id,
                    file_path,
                    command,
                ),
            )
            count += 1
    conn.commit()
    return count


def extract_tool_results(
    jsonl_path: Path, conn: sqlite3.Connection, session_id: str
) -> int:
    """Walk a session, populate tool_results. Returns count."""
    entries = list(_read_jsonl(jsonl_path))
    count = 0
    for e in entries:
        if e.get("type") != "user":
            continue
        content = e.get("message", {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            tool_use_uuid = block.get("tool_use_id")
            if not tool_use_uuid:
                continue
            row = conn.execute(
                "SELECT id FROM tool_uses WHERE tool_use_uuid = ? AND session_id = ?",
                (tool_use_uuid, session_id),
            ).fetchone()
            if not row:
                continue
            tool_use_id = row[0]

            raw_content = block.get("content", "")
            if isinstance(raw_content, list):
                raw_content = " ".join(
                    b.get("text", "")
                    for b in raw_content
                    if isinstance(b, dict) and b.get("type") == "text"
                )
            output = str(raw_content) if raw_content else ""
            output_length = len(output)
            summary = output[:500]
            is_error = 1 if block.get("is_error") else 0

            conn.execute(
                """
                INSERT INTO tool_results
                    (tool_use_id, ts, is_error, output_summary, output_length)
                VALUES (?, ?, ?, ?, ?)
                """,
                (tool_use_id, e.get("timestamp"), is_error, summary, output_length),
            )
            count += 1
    conn.commit()
    return count


def extract_edits(jsonl_path: Path, conn: sqlite3.Connection, session_id: str) -> int:
    """Walk tool_uses for edit-class tools and populate edits table. Returns count."""
    rows = conn.execute(
        """
        SELECT id, tool_name, tool_input_json, file_path
        FROM tool_uses
        WHERE session_id = ?
          AND tool_name IN ('Edit', 'Write', 'MultiEdit', 'NotebookEdit')
        """,
        (session_id,),
    ).fetchall()
    count = 0
    for row in rows:
        tu_id, tool_name, input_json, file_path = row
        try:
            inp = json.loads(input_json) if input_json else {}
        except json.JSONDecodeError:
            inp = {}

        if tool_name == "Edit":
            old_s = inp.get("old_string", "") or ""
            new_s = inp.get("new_string", "") or ""
            is_rewrite = 1 if not old_s else 0
            conn.execute(
                """
                INSERT INTO edits (tool_use_id, file_path, edit_type,
                    old_string_len, new_string_len, is_rewrite)
                VALUES (?, ?, 'edit', ?, ?, ?)
                """,
                (tu_id, file_path or "", len(old_s), len(new_s), is_rewrite),
            )
            count += 1
        elif tool_name == "Write":
            content = inp.get("content", "") or ""
            conn.execute(
                """
                INSERT INTO edits (tool_use_id, file_path, edit_type,
                    old_string_len, new_string_len, is_rewrite)
                VALUES (?, ?, 'write', 0, ?, 1)
                """,
                (tu_id, file_path or "", len(content)),
            )
            count += 1
        elif tool_name == "MultiEdit":
            edits_list = inp.get("edits", []) or []
            for ed in edits_list:
                old_s = ed.get("old_string", "") or ""
                new_s = ed.get("new_string", "") or ""
                is_rewrite = 1 if not old_s else 0
                conn.execute(
                    """
                    INSERT INTO edits (tool_use_id, file_path, edit_type,
                        old_string_len, new_string_len, is_rewrite)
                    VALUES (?, ?, 'multi_edit', ?, ?, ?)
                    """,
                    (tu_id, file_path or "", len(old_s), len(new_s), is_rewrite),
                )
                count += 1
        elif tool_name == "NotebookEdit":
            new_s = inp.get("new_source", "") or ""
            conn.execute(
                """
                INSERT INTO edits (tool_use_id, file_path, edit_type,
                    old_string_len, new_string_len, is_rewrite)
                VALUES (?, ?, 'notebook', 0, ?, 1)
                """,
                (tu_id, file_path or "", len(new_s)),
            )
            count += 1
    conn.commit()
    return count


def ingest_file(jsonl_path: Path, conn: sqlite3.Connection, source: str = "active"):
    """One-shot ingest: sessions → tool_uses → tool_results → edits."""
    sid = extract_session_into_db(jsonl_path, conn, source=source)
    if not sid:
        return 0, 0, 0
    n_uses = extract_tool_uses(jsonl_path, conn, sid)
    extract_tool_results(jsonl_path, conn, sid)
    n_edits = extract_edits(jsonl_path, conn, sid)
    return 1, n_uses, n_edits


def main():
    import argparse

    p = argparse.ArgumentParser(description="Historical signals v2 ingest")
    p.add_argument("--db", required=True, help="SQLite DB path")
    p.add_argument("--source", default="active", choices=["active", "improvment_dump"])
    p.add_argument(
        "--init-schema", action="store_true", help="Initialize schema in the DB"
    )
    p.add_argument("files", nargs="*", help="JSONL files to ingest")
    args = p.parse_args()

    db_path = Path(args.db).expanduser()
    conn = sqlite3.connect(db_path)

    if args.init_schema:
        schema_path = Path(__file__).parent / "schema.sql"
        conn.executescript(schema_path.read_text())
        print(f"Schema initialized at {db_path}")
        return

    n_sessions = n_uses = n_edits = 0
    for f in args.files:
        s, u, e = ingest_file(Path(f), conn, source=args.source)
        n_sessions += s
        n_uses += u
        n_edits += e
    print(f"Ingested {n_sessions} sessions, {n_uses} tool_uses, {n_edits} edits")


if __name__ == "__main__":
    main()
