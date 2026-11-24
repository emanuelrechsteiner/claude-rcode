"""Goal tracking: Cockpit feed, status text and the end-of-turn check (IMP-289).

The Cockpit already renders task events on card 4 (Workflows). This module writes the goal,
its issues and its deviations as such events into the session's event file, with the same
small-atomic-line and mkdir-lock protocol as the Cockpit's own sensor hook, so the card
shows goal, progress and time to goal without any change to the Cockpit and without a model.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any

import goal_agents
from goal_core import State, now, open_issues

ROW_STATUS = {"pending": "pending", "active": "in_progress", "done": "completed"}
MARK = {"pending": "·", "active": ">", "done": "x", "dropped": "-"}


def cockpit_dir() -> Path:
    return Path(os.environ.get("COCKPIT_DIR") or Path.home() / ".claude" / "cockpit")


def clock(ts: float) -> str:
    return time.strftime("%H:%M", time.localtime(ts))


def _time_row(state: State, m: dict[str, Any], finished: bool) -> str:
    """Time to goal first: the terminal card shows 26 characters of a row."""
    if m["issues"] == 0:
        return "no plan yet"
    if finished:
        ended = max((i["done_at"] or 0) for i in state["issues"]) or now()
        took = max(0.0, (ended - state["goal"]["set_at"]) / 60)
        return f"done {clock(ended)} · took {took:.0f}m · {m['done']} issues · pace x{m['pace']:g}"
    return (f"ETA {clock(m['eta_ts'])} · {m['remaining_min']:.0f}m · {m['pct']}% · pace x{m['pace']:g} · "
            f"{m['done']}/{m['issues']} issues")


def _step_row(state: State) -> tuple[str, str]:
    """The running issue with elapsed and estimated minutes first, else the next one."""
    running = [i for i in state["issues"] if i["status"] == "active"]
    if running:
        item = running[0]
        more = f" (+{len(running) - 1} more running)" if len(running) > 1 else ""
        elapsed = max(0.0, (now() - item["started_at"]) / 60)
        return f"{elapsed:.0f}m/{item['est_min']:g}m · {item['id']} {item['title'][:100]}{more}", "in_progress"
    waiting = [i for i in state["issues"] if i["status"] == "pending"]
    if waiting:
        return f"next: {waiting[0]['id']} {waiting[0]['title'][:100]} · est {waiting[0]['est_min']:g}m", "pending"
    return ("all issues done", "completed") if state["issues"] else ("no issue yet", "pending")


def _deviation_row(state: State) -> tuple[str, str]:
    """Count and newest deviation; yellow on the card while one is unreported.

    A follow-up prompt of the user is kept as a note in the list, it is not a deviation of the work.
    """
    own = [d for d in state["deviations"] if d["kind"] != "new-prompt"]
    total = len(own)
    if not total:
        return "no deviations", "completed"
    open_n = sum(1 for d in own if not d["acked"])
    last = own[-1]
    head = f"{total} deviation{'s' if total != 1 else ''} · " + (f"{open_n} open" if open_n else "reported")
    return f"{head} · {last['kind']}: {last['text'][:120]}", "in_progress" if open_n else "completed"


def rows(state: State, m: dict[str, Any]) -> list[tuple[str, str, str]]:
    """Card rows as (id, subject, status).

    The terminal card shows four rows of 26 characters and starts at the first unfinished
    row. The first four rows are therefore a fixed summary, created together and in this
    order: goal, time to goal, current step, deviations. One row per issue, deviation and
    helper follows for the wider views. A finished goal keeps only the summary.
    """
    if not state["goal"]:
        return goal_agents.rows(state)  # helpers of a session that has no goal yet (IMP-277)
    gen, goal = state.get("gen", 0), state["goal"] or {}
    finished = m["issues"] > 0 and m["eta_ts"] is None
    head = "completed" if finished else "in_progress"
    out = [(f"g{gen}-goal", f"GOAL {goal.get('text', '')[:160]}", head),
           (f"g{gen}-eta", _time_row(state, m, finished), head),
           (f"g{gen}-now", *_step_row(state)),
           (f"g{gen}-devs", *_deviation_row(state))]
    if finished:
        return out + [r for r in goal_agents.rows(state) if r[2] != "completed"]
    for item in state["issues"]:
        if item["status"] == "dropped":
            continue
        text = f"{item['id']} · {item['title'][:120]} · est {item['est_min']:g}m"
        if item["status"] == "active":
            text += f" · running {max(0.0, (now() - item['started_at']) / 60):.0f}m"
        elif item["status"] == "done" and item["actual_min"] is not None:
            text += f" · took {item['actual_min']:g}m"
        if item["origin"] != "plan":
            text = f"[{item['origin']}] {text}"
        out.append((f"g{gen}-{item['id']}", text, ROW_STATUS[item["status"]]))
    for n, dev in list(enumerate(state["deviations"]))[-20:]:  # the newest twenty: the card is no archive
        if dev["kind"] != "new-prompt":  # the user's follow-up prompt is a note, not a deviation row
            out.append((f"g{gen}-dev{n}", f"DEVIATION · {dev['kind']} · {dev['text'][:200]}", "completed"))
    return out + goal_agents.rows(state)


def _event(session: str, name: str, payload: dict[str, Any]) -> str:
    data = {"session_id": session, "hook_event_name": "GoalTracking", **payload}
    return json.dumps({"ts": int(now() * 1000), "event": name, "data": data}, ensure_ascii=False)


def sync(state: State, m: dict[str, Any]) -> int:
    """Append the events that bring card 4 up to date. Returns the number of lines written."""
    target = cockpit_dir()
    if not target.is_dir():
        return 0  # no Cockpit installed: the state file and `goal.sh status` still work
    session = state["session"]
    sent: dict[str, list[str]] = state["feed"].setdefault("rows", {})
    wanted = rows(state, m)
    lines: list[str] = []
    for row_id, subject, status in wanted:
        if row_id not in sent:
            lines.append(_event(session, "TaskCreated", {"task_id": row_id, "task_name": subject}))
            sent[row_id] = [subject, "pending"]
        if sent[row_id] != [subject, status]:
            lines.append(_event(session, "TaskUpdated",
                                {"tool_input": {"taskId": row_id, "status": status, "subject": subject}}))
            sent[row_id] = [subject, status]
    keep = {w[0] for w in wanted}
    for row_id in [r for r in sent if r not in keep]:
        lines.append(_event(session, "TaskUpdated", {"tool_input": {"taskId": row_id, "status": "deleted"}}))
        del sent[row_id]
    if lines:
        _append_locked(target, session, lines)
    state["feed"]["last_sync"] = now()
    return len(lines)


def _append_locked(target: Path, session: str, lines: list[str]) -> None:
    lock = target / f".lock-{session}"
    held = False
    for _ in range(50):  # same budget as the Cockpit's sensor: 50 x 20 ms, then write anyway
        try:
            lock.mkdir()
            held = True
            break
        except FileExistsError:
            time.sleep(0.02)
    if not held:
        try:
            lock.rmdir()  # the sensor's rule: a lock still held after 1 s is stale, its holder died
        except OSError:
            pass  # ALLOWED: another writer removed the stale lock first
    try:
        with (target / f"events-{session}.jsonl").open("a", encoding="utf-8") as events:
            events.write("".join(line + "\n" for line in lines))
    finally:
        if held:
            lock.rmdir()


def status_text(state: State, m: dict[str, Any]) -> str:
    """The goal as plain text: progress, pace, time to goal, scope growth, issues, deviations."""
    if not state["goal"]:
        return "no goal set for this session"
    out = [f"Goal: {state['goal']['text']}" + ("  (seed: no plan yet)" if state["goal"].get("seed") else "")]
    if m["issues"]:
        eta = f"ETA {clock(m['eta_ts'])} ({m['remaining_min']:.0f} min left)" if m["eta_ts"] else "done"
        source = f"{m['measured']} measured" if m["measured"] else "prior of earlier goals"
        out.append(f"Progress: {m['pct']}% ({m['done']} of {m['issues']} issues, {m['done_est']:g} of "
                   f"{m['total_est']:g} est. min) · pace x{m['pace']:g} ({source}) · {eta}")
    base = m["baseline"]
    if base and (base["issues"] != m["issues"] or base["est_min"] != m["total_est"]):
        out.append(f"Scope: planned {base['issues']} issues / {base['est_min']:g} min, now {m['issues']} issues / "
                   f"{m['total_est']:g} min ({m['issues'] - base['issues']:+d} / {m['total_est'] - base['est_min']:+g} min)")
    titles = {ms["id"]: ms["title"] for ms in state["milestones"]}
    seen: set[Any] = set()
    for item in state["issues"]:
        if item["milestone"] not in seen:
            seen.add(item["milestone"])
            if item["milestone"]:
                out.append(f"[{item['milestone']}] {titles.get(str(item['milestone']), '')}".rstrip())
        line = f"  {MARK[item['status']]} {item['id']} {item['title']} — est {item['est_min']:g}m"
        if item["status"] == "active":
            line += f", running {max(0.0, (now() - item['started_at']) / 60):.0f}m"
        elif item["actual_min"] is not None:
            line += f", took {item['actual_min']:g}m"
        if item["status"] == "dropped" or item["origin"] != "plan":
            line += f" [{item['status'] if item['status'] == 'dropped' else item['origin']}]"
        if item.get("fixed"):
            line += " [machine time]"
        out.append(line)
    if state["deviations"]:
        out.append(f"Deviations ({len(state['deviations'])}, {m['unacked']} unreported):")
        out += [f"  {'!' if not d['acked'] else ' '} {d['kind']}: {d['text']}" for d in state["deviations"]]
    return "\n".join(out)


def stop_reason(state: State) -> str:
    """Text for the Stop hook, or "" when nothing is unreported or it was already said for this state."""
    running = [i["id"] for i in state["issues"] if i["status"] == "active"]
    unacked = [d for d in state["deviations"] if not d["acked"]]
    if not running and not unacked:
        return ""
    key = hashlib.sha256(json.dumps([running, len(state["deviations"]), len(unacked)]).encode()).hexdigest()
    if state["feed"].get("stop_seen") == key:
        return ""
    state["feed"]["stop_seen"] = key
    parts = ["Goal tracking: before this turn ends, tell the user plainly what deviated from the goal and what is still open."]
    if unacked:
        shown = "; ".join(f"{d['kind']}: {d['text'][:110]}" for d in unacked[:5])
        parts.append(f"Unreported deviation(s) ({len(unacked)}): {shown}.")
    if running:
        parts.append(f"Issue(s) still marked as running: {', '.join(running)}.")
    pending = [f"{i['id']} ({i['est_min']:g}m)" for i in open_issues(state) if i["status"] == "pending"]
    if pending:
        parts.append(f"Not started: {', '.join(pending)}.")
    parts.append("Afterwards run goal.sh ack, and goal.sh done or drop for the running issues.")
    return " ".join(parts)
