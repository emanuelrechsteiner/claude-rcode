#!/usr/bin/env python3
"""Silent-fallback detector for hooks/security-audit.sh (IMP-271b).

Enforces rules/fail-loud.md on the incoming text of one Write or Edit call.
The text arrives on stdin; the target file path is the only argument.

Detected patterns:
  - Python: a handler for a bare except, Exception or BaseException (optional
    "as <name>") whose body is only pass, continue or return None.
  - JS/TS: an empty catch block, a catch block that only returns null, and an
    empty .catch() callback (empty body or null, optional unused parameter).

Override: "# ALLOWED: <reason>" (Python) or "// ALLOWED: <reason>" (JS/TS) with
a non-empty reason on the handler line or on the line directly above it.
Exempt paths (tests, fixtures, mocks, *.test.*, *.spec.*, conftest.py) pass.

Output: one line per hit, "PATTERN<TAB>offending line" (line cut to 120
characters). Exit 0 when clean or exempt, 3 on a hit. Any other exit is an
error, which the caller treats as fail-closed.
"""

import os
import re
import sys

HIT_EXIT = 3
MAX_CHARS = 120
JS_EXTENSIONS = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs")
PY_FALLBACK = ("pass", "continue", "return None")
PY_HANDLER = re.compile(
    r"^\s*except\s*(?:(?:Exception|BaseException)\s*(?:as\s+[A-Za-z_]\w*)?)?\s*:(.*)$"
)
PY_MARKER = re.compile(r"#\s*ALLOWED:\s*\S")
JS_MARKER = re.compile(r"//\s*ALLOWED:\s*\S")
JS_PARAM = r"\(\s*[A-Za-z_$][\w$]*\s*\)"
JS_PATTERNS = (
    (
        "JS/TS empty catch block",
        re.compile(r"\bcatch\s*(?:" + JS_PARAM + r")?\s*\{\s*\}"),
    ),
    (
        "JS/TS catch returns null",
        re.compile(r"\bcatch\s*(?:" + JS_PARAM + r")?\s*\{\s*return\s+null\s*;?\s*\}"),
    ),
    (
        "JS/TS empty .catch callback",
        re.compile(
            r"\.catch\(\s*\(\s*(?:[A-Za-z_$][\w$]*)?\s*\)\s*=>\s*(?:\{\s*\}|null)\s*\)"
        ),
    ),
)
EXEMPT_PARTS = ("/tests/", "/test/", "__tests__", "/fixtures/", "/mocks/")
PY_NAME = "Python silent except (pass, continue or return None)"


def is_exempt(path):
    """Return True when the path is a test, fixture or mock file."""
    norm = "/" + path.replace("\\", "/")
    base = os.path.basename(path)
    if any(part in norm for part in EXEMPT_PARTS):
        return True
    return ".test." in base or ".spec." in base or base == "conftest.py"


def indent_of(line):
    """Return the count of leading spaces and tabs."""
    return len(line) - len(line.lstrip(" \t"))


def is_blank_or_comment(line):
    """Return True for lines that carry no statement."""
    stripped = line.strip()
    return stripped == "" or stripped.startswith("#")


def code_of(text):
    """Return the text before any '#' comment, stripped."""
    return text.split("#", 1)[0].strip()


def marker_near(lines, index, marker):
    """Return True when the marker is on the line or on the line directly above."""
    if marker.search(lines[index]):
        return True
    return index > 0 and marker.search(lines[index - 1]) is not None


def py_body(lines, index, rest):
    """Return the single body statement of a handler, or '' when it is not one.

    Args:
        lines: All lines of the incoming text.
        index: Index of the handler line.
        rest: Text after the colon on the handler line.

    Returns:
        The one statement of the body, or '' when the body is empty or has more
        than one statement.
    """
    inline = code_of(rest)
    if inline:
        return inline
    base = indent_of(lines[index])
    nxt = index + 1
    while nxt < len(lines) and is_blank_or_comment(lines[nxt]):
        nxt += 1
    if nxt >= len(lines) or indent_of(lines[nxt]) <= base:
        return ""
    after = nxt + 1
    while after < len(lines) and is_blank_or_comment(lines[after]):
        after += 1
    if after < len(lines) and indent_of(lines[after]) > base:
        return ""
    return code_of(lines[nxt])


def python_hits(lines):
    """Return (line index, pattern name, line) for each silent Python handler."""
    hits = []
    for index, line in enumerate(lines):
        match = PY_HANDLER.match(line)
        if match is None:
            continue
        if py_body(lines, index, match.group(1)) not in PY_FALLBACK:
            continue
        if marker_near(lines, index, PY_MARKER):
            continue
        hits.append((index, PY_NAME, line))
    return hits


def js_hits(text, lines):
    """Return (line index, pattern name, line) for each silent JS/TS fallback."""
    hits = []
    for name, pattern in JS_PATTERNS:
        for match in pattern.finditer(text):
            index = text.count("\n", 0, match.start())
            if marker_near(lines, index, JS_MARKER):
                continue
            hits.append((index, name, lines[index]))
    return hits


def main(argv):
    """Run the detector; return the process exit code."""
    if len(argv) != 2:
        sys.stderr.write("usage: silent_fallback_detect.py <file_path> < text\n")
        return 1
    path = argv[1]
    if is_exempt(path):
        return 0
    text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    lines = text.split("\n")
    if path.endswith(".py"):
        found = python_hits(lines)
    elif path.endswith(JS_EXTENSIONS):
        found = js_hits(text, lines)
    else:
        return 0
    found.sort(key=lambda hit: hit[0])
    out = "".join(
        f"{name}\t{line.strip()[:MAX_CHARS]}\n" for _, name, line in found
    )
    sys.stdout.buffer.write(out.encode("utf-8"))
    return HIT_EXIT if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
