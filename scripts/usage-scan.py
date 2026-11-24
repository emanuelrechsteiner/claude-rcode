#!/usr/bin/env python3
"""Usage scan over Claude Code transcripts: tool use inside a time window (IMP-279).

Scans every ``*.jsonl`` file under ``--root`` at any depth, so sub-agent
transcripts in nested directories are included. A tool_use block counts when
the timestamp of its record lies inside the window; file modification times
are never used. Output holds only names, counts and window bounds: no prompt
text, no tool input values, no file contents. A malformed line is counted, not
printed.

Usage:
    scripts/usage-scan.py [--root DIR] [--days N | --since DATE] [--now TS]
                          [--format json|md] [--out FILE]

Exit: 0 on success, 2 on usage or read/write errors.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any

LIB_DIR = Path(__file__).resolve().parent / "lib"
sys.path.insert(0, str(LIB_DIR))

from usage_scan_core import (  # noqa: E402  (import after the lib path is set)
    DEFAULT_DAYS,
    Scanner,
    build_window,
    parse_iso,
)


class ScanError(Exception):
    """A transcript could not be read, or the output could not be written."""


def default_root() -> Path:
    """Return the default transcript root: ``<home>/.claude/projects``."""
    return Path.home() / ".claude" / "projects"


def scan_root(root: Path, scanner: Scanner) -> None:
    """Feed every ``*.jsonl`` file under ``root`` (any depth) into ``scanner``.

    Args:
        root: Directory to walk.
        scanner: Accumulator that applies the window filter.

    Raises:
        ScanError: When a transcript file cannot be opened or read.
    """
    for path in sorted(root.rglob("*.jsonl")):
        if not path.is_file():
            continue
        scanner.start_file()
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                scanner.feed_lines(handle)
        except OSError as exc:
            name = path.relative_to(root)
            raise ScanError(f"cannot read transcript {name}: {exc.strerror}") from exc


def render_json(report: dict[str, Any]) -> str:
    """Render the report as indented JSON."""
    return json.dumps(report, indent=2, ensure_ascii=False) + "\n"


def _section(title: str, counts: dict[str, int]) -> list[str]:
    """Render one ranked name-to-count section as Markdown lines."""
    body = [f"- {name}: {count}" for name, count in counts.items()] or ["- none"]
    return ["", f"## {title}", ""] + body


def render_markdown(report: dict[str, Any]) -> str:
    """Render the report as Markdown."""
    window = report["window"]
    lines = [
        "# Usage scan (names, counts and window bounds only)",
        "",
        f"Window: {window['start']} to {window['end']} (record timestamps, inclusive).",
        "",
        "## Totals",
        "",
    ]
    lines += [f"- {key}: {value}" for key, value in report["totals"].items()]
    lines += _section("Tools", report["tools"])
    lines += _section("MCP servers", report["mcp_servers"])
    lines += _section("Skills", report["skills"])
    lines += ["", "## Agent types", ""]
    by_type = report["agents"]["by_type"]
    by_type_and_model = report["agents"]["by_type_and_model"]
    if not by_type:
        lines.append("- none")
    for agent_type, total in by_type.items():
        lines.append(f"- {agent_type}: {total}")
        lines += [f"  - model {model}: {n}" for model, n in by_type_and_model[agent_type].items()]
    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(
        description="Count Claude Code tool use in a time window (names and counts only)."
    )
    parser.add_argument("--root", type=Path, default=None,
                        help="transcript root (default: ~/.claude/projects)")
    window = parser.add_mutually_exclusive_group()
    window.add_argument("--days", type=_positive_int, default=None,
                        help=f"window length in days (default {DEFAULT_DAYS})")
    window.add_argument("--since", type=_iso_type, default=None,
                        help="window start as an ISO date or timestamp (UTC)")
    parser.add_argument("--now", type=_iso_type, default=None,
                        help="window end as an ISO timestamp (default: current UTC)")
    parser.add_argument("--format", choices=("json", "md"), default="md",
                        help="output format (default md)")
    parser.add_argument("--out", type=Path, default=None,
                        help="write to this file instead of stdout")
    return parser


def _positive_int(value: str) -> int:
    """argparse type: a positive integer."""
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected a positive integer") from exc
    if number <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return number


def _iso_type(value: str) -> dt.datetime:
    """argparse type: an ISO date or timestamp, read as UTC."""
    try:
        return parse_iso(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected an ISO date or timestamp") from exc


def run(args: argparse.Namespace) -> str:
    """Run the scan and return the rendered output.

    Args:
        args: Parsed command-line arguments.

    Returns:
        The report in the requested format.

    Raises:
        ScanError: When the root is not a directory or a transcript cannot be read.
    """
    root = args.root if args.root is not None else default_root()
    if not root.is_dir():
        raise ScanError("transcript root is not a directory")
    now = args.now if args.now is not None else dt.datetime.now(dt.timezone.utc)
    try:
        window = build_window(now, days=args.days, since=args.since)
    except ValueError as exc:
        raise ScanError(str(exc)) from exc
    scanner = Scanner(window)
    scan_root(root, scanner)
    report = scanner.report()
    return render_json(report) if args.format == "json" else render_markdown(report)


def main(argv: list[str] | None = None) -> int:
    """Entry point.

    Args:
        argv: Argument list; defaults to ``sys.argv[1:]``.

    Returns:
        Process exit code: 0 on success, 2 on error.
    """
    args = build_parser().parse_args(argv)
    try:
        text = run(args)
    except ScanError as exc:
        print(f"usage-scan: error: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"usage-scan: error: cannot walk root: {exc.strerror}", file=sys.stderr)
        return 2
    if args.out is None:
        sys.stdout.write(text)
        return 0
    try:
        args.out.write_text(text, encoding="utf-8")
    except OSError as exc:
        print(f"usage-scan: error: cannot write output: {exc.strerror}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
