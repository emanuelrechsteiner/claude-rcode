"""Counters for the usage scan: tool names, MCP servers, skills, agent types and models.

Only names and counts are stored. A tool input is read for the fields named
below (``skill``, ``subagent_type``, ``model``) and never kept.
"""

from __future__ import annotations

import collections
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

MCP_PATTERN = re.compile(r"^mcp__(.+?)__")
AGENT_TOOLS = ("Agent", "Task")
UNSET = "(unset)"
INHERIT = "inherit"


def _name_or_unset(value: Any) -> str:
    """Return ``value`` when it is a non-empty string, else the unset marker.

    Args:
        value: A raw field value from a transcript record.

    Returns:
        The string itself, or ``UNSET``.
    """
    return value if isinstance(value, str) and value else UNSET


def _ranked(counter: collections.Counter[str]) -> dict[str, int]:
    """Return counter entries ordered by count (descending), then name.

    Args:
        counter: Any name-to-count mapping.

    Returns:
        A plain dict in ranked order.
    """
    ordered = sorted(counter.items(), key=lambda item: (-item[1], item[0]))
    return dict(ordered)


@dataclass
class UsageCounts:
    """Counters per tool name, MCP server, skill, and agent type and model."""

    tools: collections.Counter[str] = field(default_factory=collections.Counter)
    mcp_servers: collections.Counter[str] = field(default_factory=collections.Counter)
    skills: collections.Counter[str] = field(default_factory=collections.Counter)
    agent_pairs: collections.Counter[tuple[str, str]] = field(
        default_factory=collections.Counter
    )

    def count_block(self, block: Mapping[str, Any]) -> None:
        """Count one tool_use block by its name and, for some tools, its input fields.

        Args:
            block: A tool_use content block. Only the ``name`` field and, for
                the Skill, Agent and Task tools, the ``skill``, ``subagent_type``
                and ``model`` input fields are read. A missing model counts as
                ``inherit``.
        """
        name = _name_or_unset(block.get("name"))
        self.tools[name] += 1
        match = MCP_PATTERN.match(name)
        if match:
            self.mcp_servers[match.group(1)] += 1
        raw_input = block.get("input")
        args: Mapping[str, Any] = raw_input if isinstance(raw_input, Mapping) else {}
        if name == "Skill":
            self.skills[_name_or_unset(args.get("skill"))] += 1
        elif name in AGENT_TOOLS:
            model = args.get("model")
            model_name = model if isinstance(model, str) and model else INHERIT
            pair = (_name_or_unset(args.get("subagent_type")), model_name)
            self.agent_pairs[pair] += 1

    def to_dict(self) -> dict[str, Any]:
        """Return the counters as ranked plain dicts for JSON output.

        Returns:
            Keys ``tools``, ``mcp_servers``, ``skills`` and ``agents``; the
            last holds ``by_type`` and ``by_type_and_model``.
        """
        by_type: collections.Counter[str] = collections.Counter()
        by_type_and_model: dict[str, collections.Counter[str]] = {}
        for (agent_type, model), count in self.agent_pairs.items():
            by_type[agent_type] += count
            by_type_and_model.setdefault(agent_type, collections.Counter())[model] += count
        return {
            "tools": _ranked(self.tools),
            "mcp_servers": _ranked(self.mcp_servers),
            "skills": _ranked(self.skills),
            "agents": {
                "by_type": _ranked(by_type),
                "by_type_and_model": {
                    agent_type: _ranked(models)
                    for agent_type, models in sorted(by_type_and_model.items())
                },
            },
        }


@dataclass
class ScanTotals:
    """Totals over one scan run."""

    files_scanned: int = 0
    records_in_window: int = 0
    tool_use_blocks: int = 0
    malformed_lines_skipped: int = 0
    duplicate_tool_use_skipped: int = 0

    def to_dict(self) -> dict[str, int]:
        """Return the totals as a plain dict.

        Returns:
            The five totals keyed by name.
        """
        return {
            "files_scanned": self.files_scanned,
            "records_in_window": self.records_in_window,
            "tool_use_blocks": self.tool_use_blocks,
            "malformed_lines_skipped": self.malformed_lines_skipped,
            "duplicate_tool_use_skipped": self.duplicate_tool_use_skipped,
        }
