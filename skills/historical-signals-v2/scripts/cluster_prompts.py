"""Batch-classify user prompts into intent clusters via Anthropic Haiku.

Optional / Task 2.6 of Phase X3. Costs ~$3-8 for ~6000 prompts.
Updates `prompts.cluster_label` in the historical-signals.db.
"""

import os
import sqlite3
import sys
import time
from pathlib import Path

try:
    from anthropic import Anthropic
except ImportError:
    print(
        "anthropic SDK required: pip install anthropic",
        file=sys.stderr,
    )
    sys.exit(1)

DB_PATH = Path.home() / ".claude/global-observation/historical-signals.db"

CLUSTER_PROMPT = """You are classifying short user prompts from a developer's
Claude Code sessions into categories. Classify each as ONE of:

1. NEW_FEATURE — request to add/build/implement something new
2. BUG_FIX — request to fix/debug/repair an existing bug
3. REFACTOR — request to clean up/extract/reorganize existing code
4. EXPLAIN — request for explanation/understanding/documentation
5. NAVIGATE — request to find/show/list something
6. OPS — git/deploy/install/setup tasks
7. PROSE — non-code writing (novel, blog, docs, brand)
8. CONFIG — settings/preferences/framework changes (~/.claude, .rcode, etc.)
9. RESEARCH — investigate/audit/learn-about something
10. OTHER — anything not above

Output ONLY the category name (uppercase), nothing else. No explanation."""


def classify_one(client, text: str) -> str:
    try:
        resp = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=20,
            system=CLUSTER_PROMPT,
            messages=[{"role": "user", "content": text}],
        )
        return resp.content[0].text.strip().upper()
    except Exception as e:
        print(f"  classify error: {e}", file=sys.stderr)
        return "OTHER"


def main():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print(
            "ANTHROPIC_API_KEY not set in env. Aborting.",
            file=sys.stderr,
        )
        sys.exit(1)

    client = Anthropic()
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT id, SUBSTR(text, 1, 800) FROM prompts "
        "WHERE text_length > 20 AND cluster_label IS NULL"
    ).fetchall()
    total = len(rows)
    print(f"{total} prompts to classify")

    for i, (pid, text) in enumerate(rows, 1):
        cat = classify_one(client, text)
        conn.execute(
            "UPDATE prompts SET cluster_label = ? WHERE id = ?",
            (cat, pid),
        )
        if i % 100 == 0:
            conn.commit()
            print(f"  {i}/{total} done")
            time.sleep(0.1)
    conn.commit()

    print("\nCluster distribution:")
    cur = conn.execute(
        """
        SELECT cluster_label, COUNT(*) FROM prompts
        WHERE cluster_label IS NOT NULL
        GROUP BY cluster_label ORDER BY COUNT(*) DESC
        """
    )
    for label, n in cur.fetchall():
        print(f"  {label}: {n}")


if __name__ == "__main__":
    main()
