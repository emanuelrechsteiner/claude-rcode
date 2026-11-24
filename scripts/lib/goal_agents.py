"""Goal tracking: helper rows on Cockpit card 4 (IMP-277).

A dispatch is queued with its title, type, model and effort when the Agent tool is called.
The start event of a helper carries only its id and type, so it takes the newest queued
entry of that type and becomes a running row; the stop event ends the row of that id.
A queued entry that never starts (a denied dispatch) expires after QUEUE_TTL seconds; until
then a helper that has no entry of its own could take it, so the pairing is a best effort.
"""
from __future__ import annotations

from typing import Any

from goal_core import State, now, one_line

QUEUE_TTL = 300.0
KEEP_FINISHED = 30
UNKNOWN = {"title": "(started without a recorded dispatch)", "model": "default", "effort": "default"}


def _fresh(state: State) -> list[dict[str, Any]]:
    return [q for q in state.get("agent_queue", []) if now() - q["ts"] < QUEUE_TTL]


def queue(state: State, title: str, agent_type: str, model: str, effort: str) -> None:
    """Remember what a dispatch asked for until its helper really starts."""
    pending = _fresh(state)
    pending.append({"ts": now(), "title": one_line(title or "(no title)", 80), "type": agent_type or "default",
                    "model": model or "default", "effort": effort or "default"})
    state["agent_queue"] = pending[-50:]


def begin(state: State, agent_id: str, agent_type: str) -> None:
    """A helper started: bind the oldest queued dispatch of its type to the agent id."""
    agents: list[dict[str, Any]] = state.setdefault("agents", [])
    if any(a["id"] == agent_id for a in agents):
        return
    pending = _fresh(state)
    # Newest first: a dispatch that was denied and sent again leaves an older entry behind.
    # A dispatch without a type was queued as "default" and fits a helper of any type.
    match = (next((q for q in reversed(pending) if q["type"] == (agent_type or "default")), None)
             or next((q for q in reversed(pending) if q["type"] == "default"), None))
    if match:
        pending.remove(match)
    state["agent_queue"] = pending
    info = match or UNKNOWN
    state["agent_seq"] = state.get("agent_seq", 0) + 1
    agents.append({"n": state["agent_seq"], "id": agent_id, "type": agent_type or "default", "title": info["title"],
                   "model": info["model"], "effort": info["effort"], "started_at": now(), "ended_at": None})


def end(state: State, agent_id: str) -> None:
    """A helper stopped: close its row and keep only the newest finished rows."""
    agents: list[dict[str, Any]] = state.get("agents", [])
    for agent in agents:
        if agent["id"] == agent_id and agent["ended_at"] is None:
            agent["ended_at"] = now()
    finished = [a for a in agents if a["ended_at"] is not None]
    dropped = {a["n"] for a in finished[:-KEEP_FINISHED]} if len(finished) > KEEP_FINISHED else set()
    state["agents"] = [a for a in agents if a["n"] not in dropped]


def rows(state: State) -> list[tuple[str, str, str]]:
    """Card rows as (id, subject, status): one per helper, running or finished.

    The card lists rows in the order they were created. The row id carries the goal's
    generation, so a new goal creates its helper rows again, behind its summary rows.
    """
    prefix = f"g{state.get('gen', 0)}-" if state.get("goal") else ""
    out: list[tuple[str, str, str]] = []
    for agent in state.get("agents", []):
        row_id = f"{prefix}a{agent['n']}"
        text = f"HELPER · {agent['type']} · {agent['title']} · {agent['model']}/{agent['effort']}"
        if agent["ended_at"] is None:
            out.append((row_id, f"{text} · running {max(0.0, (now() - agent['started_at']) / 60):.0f}m", "in_progress"))
        else:
            took = round((agent["ended_at"] - agent["started_at"]) / 60, 1)
            out.append((row_id, f"{text} · took {took:g}m", "completed"))
    return out
