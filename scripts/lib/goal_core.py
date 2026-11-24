"""Goal tracking core (IMP-289): one state file per session, measured pace, Cockpit feed.

A goal has milestones and atomic issues with estimates in minutes. The remaining time is
the open estimate scaled by the measured pace: wall-clock / estimated minutes of the issues
already done in this goal (clamped to 0.2..5), and before the first one is done the median
pace of earlier sessions. Deviations (detours, added or dropped work, files outside the declared scope)
are recorded and stay visible until they are acknowledged. Nothing here calls a model.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import statistics
import time
from fnmatch import fnmatch
from pathlib import Path
from typing import Any

SIZE_MIN = {"S": 5.0, "M": 15.0, "L": 40.0}
SID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
State = dict[str, Any]


class GoalError(Exception):
    """A request that cannot be carried out on the current goal state."""


def now() -> float:
    """Current time; CLAUDE_GOAL_NOW pins it for the regression suite."""
    fixed = os.environ.get("CLAUDE_GOAL_NOW")
    return float(fixed) if fixed else time.time()


def goal_dir() -> Path:
    return Path(os.environ.get("CLAUDE_GOAL_DIR") or Path.home() / ".claude" / "global-observation" / "goals")


def state_path(session: str) -> Path:
    if not SID_RE.match(session):
        raise GoalError(f"invalid session id: {session!r}")
    return goal_dir() / f"{session}.json"


def load(session: str) -> State:
    path = state_path(session)
    if not path.exists():
        return {"version": 1, "session": session, "gen": 0, "cwd": "", "goal": None, "milestones": [],
                "issues": [], "deviations": [], "touched": {}, "baseline": None, "feed": {}}
    return json.loads(path.read_text(encoding="utf-8"))


def save(state: State) -> None:
    path = state_path(state["session"])
    path.parent.mkdir(parents=True, exist_ok=True)
    state["updated_at"] = now()
    tmp = path.with_name(f"{path.name}.tmp{os.getpid()}")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def _cwd_pointer(cwd: str) -> Path:
    return goal_dir() / "by-cwd" / hashlib.sha256(cwd.encode("utf-8")).hexdigest()[:16]


def session_for_cwd(cwd: str) -> str | None:
    """The session that last set a goal in this directory (for calls without --session)."""
    pointer = _cwd_pointer(cwd)
    return pointer.read_text(encoding="utf-8").strip() if pointer.exists() else None


def one_line(text: str, limit: int) -> str:
    return " ".join(str(text).split())[:limit]


def find_issue(state: State, issue_id: str) -> dict[str, Any]:
    for item in state["issues"]:
        if item["id"] == issue_id:
            return item
    raise GoalError(f"unknown issue: {issue_id}")


def open_issues(state: State) -> list[dict[str, Any]]:
    return [i for i in state["issues"] if i["status"] in ("pending", "active")]


def deviate(state: State, kind: str, text: str, issue_id: str | None = None) -> None:
    state["deviations"].append({"ts": now(), "kind": kind, "text": one_line(text, 300),
                                "issue": issue_id, "acked": False})


def seed(state: State, text: str, cwd: str) -> bool:
    """Write the goal seed of a new prompt. Returns False when an open goal was kept."""
    if state["goal"] and open_issues(state):
        deviate(state, "new-prompt", f"new prompt while the goal is open: {text}")
        state["deviations"][-1]["acked"] = True  # the user's own input: a note, never raised at the stop
        return False
    state.update(gen=state.get("gen", 0) + 1, cwd=cwd, milestones=[], issues=[], deviations=[], touched={},
                 baseline=None, goal={"text": one_line(text, 200), "seed": True, "set_at": now()})
    _remember_cwd(state["session"], cwd)
    return True


def _remember_cwd(session: str, cwd: str) -> None:
    pointer = _cwd_pointer(cwd)
    pointer.parent.mkdir(parents=True, exist_ok=True)
    pointer.write_text(session, encoding="utf-8")


def _new_issue(raw: dict[str, Any], origin: str) -> dict[str, Any]:
    issue_id = str(raw.get("id") or "").strip()
    if not issue_id:
        raise GoalError("every issue needs an id")
    est = raw.get("est_min")
    if est is None:
        size = str(raw.get("size") or "").upper()
        if size not in SIZE_MIN:
            raise GoalError(f"issue {issue_id}: est_min (minutes) or size S/M/L is required")
        est = SIZE_MIN[size]
    est = float(est)
    if not 0 < est < 100000:  # also refuses NaN and infinity
        raise GoalError(f"issue {issue_id}: est_min must be a positive number of minutes")
    paths = [raw["paths"]] if isinstance(raw.get("paths"), str) else raw.get("paths") or []
    return {"id": issue_id, "title": one_line(raw.get("title") or issue_id, 160), "milestone": raw.get("milestone"),
            "est_min": est, "paths": [str(p) for p in paths], "status": "pending",
            "started_at": None, "done_at": None, "actual_min": None, "origin": origin,
            # Machine time (suite, build, deploy): counts with its plain estimate, never enters the pace.
            "fixed": bool(raw.get("fixed"))}


def plan(state: State, spec: dict[str, Any], cwd: str) -> None:
    """Set the goal sentence, milestones and atomic issues. A second plan is a recorded replan."""
    raw_issues = spec.get("issues") or []
    if not raw_issues:
        raise GoalError("a plan needs at least one issue")
    old = {i["id"]: i for i in state["issues"]}
    issues = [_new_issue(r, "plan") for r in raw_issues]
    if len({i["id"] for i in issues}) != len(issues):
        raise GoalError("issue ids must be unique")
    for item in issues:  # keep what was already measured for an issue that survives the replan
        if item["id"] in old and old[item["id"]]["status"] in ("active", "done"):
            item.update({k: old[item["id"]][k] for k in ("status", "started_at", "done_at", "actual_min")})
    if old:
        deviate(state, "replan", f"plan replaced: {len(old)} issue(s) before, {len(issues)} after")
    else:
        state["baseline"] = {"issues": len(issues), "est_min": sum(i["est_min"] for i in issues)}
    text = spec.get("goal") or (state["goal"] or {}).get("text") or "goal"
    state["goal"] = {"text": one_line(text, 200), "seed": False, "set_at": now()}
    state["milestones"] = [{"id": str(m.get("id")), "title": one_line(m.get("title") or "", 120)}
                           for m in spec.get("milestones") or []]
    state["issues"] = issues
    state["cwd"] = state.get("cwd") or cwd
    state["gen"] = state.get("gen") or 1
    _remember_cwd(state["session"], state["cwd"])


def start(state: State, issue_id: str) -> None:
    item = find_issue(state, issue_id)
    if item["status"] in ("done", "dropped"):
        raise GoalError(f"issue {issue_id} is already {item['status']}")
    item["status"] = "active"
    item["started_at"] = item["started_at"] or now()


def done(state: State, issue_id: str) -> None:
    item = find_issue(state, issue_id)
    if item["status"] in ("dropped", "done"):  # a second done would write the pace history twice
        raise GoalError(f"issue {issue_id} is already {item['status']}")
    item["status"], item["done_at"] = "done", now()
    if item["started_at"]:  # an issue that was never started has no measured duration
        item["actual_min"] = round((item["done_at"] - item["started_at"]) / 60, 2)
    if item["actual_min"] and not item.get("fixed"):  # wall-clock from start to done; idle time counts
        with (goal_dir() / "velocity.jsonl").open("a", encoding="utf-8") as history:
            history.write(json.dumps({"ts": item["done_at"], "est_min": item["est_min"],
                                      "actual_min": item["actual_min"]}) + "\n")


def drop(state: State, issue_id: str, why: str) -> None:
    item = find_issue(state, issue_id)
    item["status"] = "dropped"
    deviate(state, "scope-drop", f"{issue_id} {item['title']}: {why}", issue_id)


def add(state: State, raw: dict[str, Any], why: str, detour: bool) -> None:
    item = _new_issue(raw, "detour" if detour else "added")
    if any(i["id"] == item["id"] for i in state["issues"]):
        raise GoalError(f"issue id already used: {item['id']}")
    state["issues"].append(item)
    deviate(state, "detour" if detour else "scope-add", f"{item['id']} {item['title']}: {why}", item["id"])


def ack(state: State) -> int:
    pending = [d for d in state["deviations"] if not d["acked"]]
    for entry in pending:
        entry["acked"] = True
    return len(pending)


def touch(state: State, file_path: str) -> None:
    """Record a written file; flag it once when it lies outside every declared issue path."""
    cwd = state.get("cwd") or ""
    inside = bool(cwd) and (file_path + "/").startswith(cwd.rstrip("/") + "/")
    rel = file_path[len(cwd.rstrip("/")) + 1:] if inside else file_path
    entry = state["touched"].setdefault(rel, {"n": 0, "first": now(), "flagged": False})
    entry["n"], entry["last"] = entry["n"] + 1, now()
    declared = [p for i in state["issues"] if i["status"] != "dropped" for p in i["paths"]]
    if inside and declared and not entry["flagged"] and not any(fnmatch(rel, p) for p in declared):
        entry["flagged"] = True
        deviate(state, "undeclared-file", f"{rel} was written but lies outside every declared issue path")


def prior_pace() -> float:
    """Median actual/estimate ratio of the last 50 measured issues of earlier goals (1.0 without history)."""
    history = goal_dir() / "velocity.jsonl"
    if not history.exists():
        return 1.0
    ratios: list[float] = []
    for line in history.read_text(encoding="utf-8").splitlines()[-50:]:
        try:
            rec = json.loads(line)
            ratios.append(float(rec["actual_min"]) / float(rec["est_min"]))
        except (ValueError, KeyError, TypeError, ZeroDivisionError):
            continue  # ALLOWED: a damaged history line only shrinks the sample of the prior
    return min(max(statistics.median(ratios), 0.2), 5.0) if ratios else 1.0


def metrics(state: State) -> dict[str, Any]:
    """Progress, pace and time to goal from the estimates and the measured durations."""
    live = [i for i in state["issues"] if i["status"] != "dropped"]
    measured = [i for i in live if i["status"] == "done" and i["actual_min"] and not i.get("fixed")]
    est_done = sum(i["est_min"] for i in measured)
    # Clamped like the prior: the duration is wall-clock, one idle hour must not rule the whole goal.
    pace = min(max(sum(i["actual_min"] for i in measured) / est_done, 0.2), 5.0) if est_done else prior_pace()
    total = sum(i["est_min"] for i in live)
    done_est = sum(i["est_min"] for i in live if i["status"] == "done")
    remaining = 0.0
    for item in live:
        scaled = item["est_min"] * (1.0 if item.get("fixed") else pace)
        if item["status"] == "pending":
            remaining += scaled
        elif item["status"] == "active":
            elapsed = (now() - item["started_at"]) / 60
            remaining += max(scaled - elapsed, 0.1 * scaled)
    is_open = bool(open_issues(state))
    return {"total_est": total, "done_est": done_est, "pct": round(100 * done_est / total) if total else 0,
            "pace": round(pace, 2), "measured": len(measured), "remaining_min": round(remaining, 1),
            "eta_ts": now() + remaining * 60 if is_open else None, "open": len(open_issues(state)),
            "done": sum(1 for i in live if i["status"] == "done"), "issues": len(live),
            "unacked": sum(1 for d in state["deviations"] if not d["acked"]), "baseline": state.get("baseline")}
