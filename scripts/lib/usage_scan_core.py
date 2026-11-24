"""Pure helpers for the usage scan: timestamp parsing, window filter and record scanning.

The scan reads Claude Code transcript records (JSON Lines). A record counts
only when its own ``timestamp`` lies inside the window; file modification
times are never consulted. Only names, counts and window bounds leave this
module and its counters: prompt text, tool input values and file contents are
read for the fields named in ``usage_scan_counts`` and then discarded.
"""

from __future__ import annotations

import datetime as dt
import json
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any

from usage_scan_counts import ScanTotals, UsageCounts

DEFAULT_DAYS = 30
UTC = dt.timezone.utc


@dataclass(frozen=True)
class Window:
    """Closed time window ``[start, end]`` compared against record timestamps."""

    start: dt.datetime
    end: dt.datetime

    def contains(self, moment: dt.datetime) -> bool:
        """Return True when ``moment`` lies inside the window (both ends inclusive).

        Args:
            moment: An aware datetime.

        Returns:
            Whether the instant lies in ``[start, end]``.
        """
        return self.start <= moment <= self.end


def ensure_utc(moment: dt.datetime) -> dt.datetime:
    """Return ``moment`` as an aware UTC datetime; naive values are read as UTC.

    Args:
        moment: A naive or timezone-aware datetime.

    Returns:
        The same instant in UTC.
    """
    if moment.tzinfo is None:
        return moment.replace(tzinfo=UTC)
    return moment.astimezone(UTC)


def parse_iso(value: str) -> dt.datetime:
    """Parse an ISO 8601 date or timestamp; a trailing ``Z`` means UTC.

    Args:
        value: A date such as ``2026-10-12`` or a timestamp such as
            ``2026-11-11T12:00:00Z``.

    Returns:
        An aware UTC datetime. A date means midnight UTC.

    Raises:
        ValueError: When ``value`` is not an ISO date or timestamp.
    """
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return ensure_utc(dt.datetime.fromisoformat(text))


def build_window(
    now: dt.datetime, days: int | None = None, since: dt.datetime | None = None
) -> Window:
    """Build the scan window ending at ``now``.

    Args:
        now: The window end (inclusive).
        days: Length of the window in days. Used when ``since`` is None;
            defaults to ``DEFAULT_DAYS``.
        since: Explicit window start. Takes the place of ``days``.

    Returns:
        The window.

    Raises:
        ValueError: When both ``days`` and ``since`` are given, when ``days``
            is not positive, or when the start lies after ``now``.
    """
    if days is not None and since is not None:
        raise ValueError("give either days or since, not both")
    end = ensure_utc(now)
    if since is not None:
        start = ensure_utc(since)
    else:
        length = DEFAULT_DAYS if days is None else days
        if length <= 0:
            raise ValueError("days must be a positive integer")
        start = end - dt.timedelta(days=length)
    if start > end:
        raise ValueError("window start lies after the window end")
    return Window(start=start, end=end)


def record_timestamp(rec: Mapping[str, Any]) -> dt.datetime | None:
    """Return the record's own timestamp as aware UTC, or None when absent or invalid.

    Args:
        rec: One decoded transcript record.

    Returns:
        The timestamp, or None when the field is missing or not ISO 8601.
    """
    value = rec.get("timestamp")
    if not isinstance(value, str):
        return None
    try:
        return parse_iso(value)
    except ValueError:
        return None


def tool_use_blocks(rec: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    """Return the ``tool_use`` content blocks of an assistant record.

    Args:
        rec: One decoded transcript record.

    Returns:
        The tool_use blocks, or an empty list for any other record shape.
    """
    if rec.get("type") != "assistant":
        return []
    message = rec.get("message")
    content = message.get("content") if isinstance(message, Mapping) else None
    if not isinstance(content, list):
        return []
    return [
        block
        for block in content
        if isinstance(block, Mapping) and block.get("type") == "tool_use"
    ]


class Scanner:
    """Accumulates counts over the transcript lines of one window."""

    def __init__(self, window: Window) -> None:
        """Create an empty scanner.

        Args:
            window: The window that decides which records count.
        """
        self.window = window
        self.counts = UsageCounts()
        self.totals = ScanTotals()
        self._seen_ids: set[str] = set()

    def start_file(self) -> None:
        """Record that one transcript file is being scanned."""
        self.totals.files_scanned += 1

    def feed_lines(self, lines: Iterable[str]) -> None:
        """Feed the lines of one transcript file.

        Args:
            lines: Raw lines of a JSON Lines file.
        """
        for line in lines:
            self.feed_line(line)

    def feed_line(self, line: str) -> None:
        """Feed one raw line; a malformed line is counted and skipped.

        A blank line is ignored. A line that is not a JSON object counts as
        malformed. A tool_use block whose id was already counted inside the
        window counts as a duplicate and is not counted again.

        Args:
            line: One raw line of a JSON Lines file.
        """
        text = line.strip()
        if not text:
            return
        try:
            rec = json.loads(text)
        except ValueError:
            self.totals.malformed_lines_skipped += 1
            return
        if not isinstance(rec, dict):
            self.totals.malformed_lines_skipped += 1
            return
        moment = record_timestamp(rec)
        if moment is None or not self.window.contains(moment):
            return
        self.totals.records_in_window += 1
        for block in tool_use_blocks(rec):
            block_id = block.get("id")
            if isinstance(block_id, str) and block_id:
                if block_id in self._seen_ids:
                    self.totals.duplicate_tool_use_skipped += 1
                    continue
                self._seen_ids.add(block_id)
            self.totals.tool_use_blocks += 1
            self.counts.count_block(block)

    def report(self) -> dict[str, Any]:
        """Return the full result as a plain dict (names, counts and bounds only).

        Returns:
            Keys ``window``, ``totals``, ``tools``, ``mcp_servers``, ``skills``
            and ``agents``.
        """
        return {
            "window": {
                "start": self.window.start.isoformat(),
                "end": self.window.end.isoformat(),
            },
            "totals": self.totals.to_dict(),
            **self.counts.to_dict(),
        }
