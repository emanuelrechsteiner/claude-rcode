#!/usr/bin/env python3
"""goal.py: goal tracking for a session (IMP-289). Model and pace: scripts/lib/goal_core.py.

Usage: goal.sh [--session <id>] <command> ...
  plan                       JSON on stdin: {"goal": "...", "milestones": [{"id", "title"}],
                             "issues": [{"id", "title", "milestone", "est_min" | "size": "S|M|L", "paths": [...],
                             "fixed": true for machine time such as a suite run, a build or a deploy}]}
  start <id> | done <id>     an issue begins / its check has passed
  add <id> <title> --est N --why W [--detour] [--milestone M]     work that was not in the plan
  drop <id> --why W          planned work that will not be done
  deviate <text> [--kind K]  a detour or scope change without an issue of its own
  ack                        the deviations were reported to the user
  status [--json]            goal, progress, pace, time to goal, scope growth, deviations
  seed --text T [--cwd D] | touch --file P | tick | stop-check    (called by the goal-* hooks)
  agent-queue --title T --type A --model M --effort E | agent-start --id I --type A | agent-stop --id I
                             helper rows on the card (IMP-277; called by goal-track.sh)
Without --session, the session that last set a goal in the current directory is used.
Exit: 0 ok, 1 refused (reason on stderr), 2 usage error.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import goal_agents as agents  # noqa: E402  (path set above)
import goal_core as core  # noqa: E402
import goal_feed as feed  # noqa: E402

NEEDS_STATE = ("touch", "tick", "stop-check")  # silent no-ops in a session without a goal file
AGENT_COMMANDS = ("agent-queue", "agent-start", "agent-stop")  # work without a goal as well
HOOK_COMMANDS = NEEDS_STATE + AGENT_COMMANDS
KINDS = ("detour", "scope-add", "scope-drop", "goal-change", "note")


def summary(m: dict[str, Any]) -> str:
    if not m["issues"]:
        return "goal: seed written, no plan yet"
    eta = f"ETA {feed.clock(m['eta_ts'])}, {m['remaining_min']:.0f} min left" if m["eta_ts"] else "done"
    line = f"goal: {m['done']}/{m['issues']} issues, {m['pct']}%, {eta}, pace x{m['pace']:g}"
    return line + (f", {m['unacked']} unreported deviation(s)" if m["unacked"] else "")


@contextlib.contextmanager
def locked(session: str) -> Iterator[None]:
    """One writer per session: the hooks and the CLI run at the same time when tool calls are
    parallel, and an unlocked load-modify-save would let the slower one erase the other's entry."""
    path = core.state_path(session).with_suffix(".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="goal.sh", description="Goal tracking: plan, progress, time to goal, deviations.")
    p.add_argument("--session", help="session id (default: the session that last set a goal in this directory)")
    sub = p.add_subparsers(dest="cmd", required=True)
    seed = sub.add_parser("seed")
    seed.add_argument("--text", required=True)
    seed.add_argument("--cwd", default=os.getcwd())
    sub.add_parser("plan")
    for name in ("start", "done"):
        sub.add_parser(name).add_argument("id")
    add = sub.add_parser("add")
    add.add_argument("id")
    add.add_argument("title")
    add.add_argument("--est", type=float)
    add.add_argument("--size")
    add.add_argument("--why", required=True)
    add.add_argument("--detour", action="store_true")
    add.add_argument("--fixed", action="store_true", help="machine time: not scaled by the pace")
    add.add_argument("--milestone")
    drop = sub.add_parser("drop")
    drop.add_argument("id")
    drop.add_argument("--why", required=True)
    dev = sub.add_parser("deviate")
    dev.add_argument("text")
    dev.add_argument("--kind", default="detour", choices=KINDS)
    sub.add_parser("ack")
    sub.add_parser("status").add_argument("--json", action="store_true")
    sub.add_parser("touch").add_argument("--file", required=True)
    sub.add_parser("tick")
    sub.add_parser("stop-check")
    queued = sub.add_parser("agent-queue")
    for flag in ("--title", "--type", "--model", "--effort"):
        queued.add_argument(flag, default="")
    for name in ("agent-start", "agent-stop"):
        helper = sub.add_parser(name)
        helper.add_argument("--id", required=True)
        helper.add_argument("--type", default="")
    return p


def run(args: argparse.Namespace, session: str, spec: Any = None) -> int:
    hook = args.cmd in HOOK_COMMANDS
    if args.cmd in NEEDS_STATE and not core.state_path(session).exists():
        return 0  # no goal in this session: the hooks stay silent
    state = core.load(session)
    if args.cmd == "status":
        m = core.metrics(state)
        print(json.dumps({"state": state, "metrics": m}, ensure_ascii=False, indent=1) if args.json
              else feed.status_text(state, m))
        return 0
    if args.cmd not in ("seed", "plan") + AGENT_COMMANDS and not state["goal"]:
        raise core.GoalError("no goal set in this session: run plan first")
    note = ""
    if args.cmd == "agent-queue":
        agents.queue(state, args.title, args.type, args.model, args.effort)
    elif args.cmd == "agent-start":
        agents.begin(state, args.id, args.type)
    elif args.cmd == "agent-stop":
        agents.end(state, args.id)
    elif args.cmd == "seed":
        if not core.seed(state, args.text, args.cwd):
            note = "goal: an open goal was kept; the new prompt is recorded as a deviation"
    elif args.cmd == "plan":
        core.plan(state, spec, os.getcwd())
    elif args.cmd == "start":
        core.start(state, args.id)
    elif args.cmd == "done":
        core.done(state, args.id)
    elif args.cmd == "add":
        raw = {"id": args.id, "title": args.title, "est_min": args.est, "size": args.size,
               "milestone": args.milestone, "fixed": args.fixed}
        core.add(state, raw, args.why, args.detour)
    elif args.cmd == "drop":
        core.drop(state, args.id, args.why)
    elif args.cmd == "deviate":
        core.deviate(state, args.kind, args.text)
    elif args.cmd == "ack":
        note = f"goal: {core.ack(state)} deviation(s) marked as reported"
    elif args.cmd == "touch":
        core.touch(state, args.file)
    elif args.cmd == "tick" and core.now() - state["feed"].get("last_sync", 0) < 30:
        return 0  # the card was refreshed less than 30 s ago
    elif args.cmd == "stop-check":
        reason = feed.stop_reason(state)
        core.save(state)
        if reason:
            print(reason)
        return 0
    m = core.metrics(state)
    feed.sync(state, m)
    core.save(state)
    if not hook:
        print(note or summary(m))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    session = args.session or core.session_for_cwd(os.getcwd())
    if not session:
        if args.cmd in HOOK_COMMANDS:
            return 0
        print("goal: no --session given and no goal was set in this directory", file=sys.stderr)
        return 1
    try:
        # The plan is read before the lock is taken: a stdin that never closes must not
        # hold the session's lock and stall every hook behind it.
        spec = json.load(sys.stdin) if args.cmd == "plan" else None
        with locked(session):
            return run(args, session, spec)
    except core.GoalError as err:
        print(f"goal: {err}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as err:
        print(f"goal: the input is not valid JSON: {err}", file=sys.stderr)
        return 1
    except (AttributeError, TypeError, ValueError) as err:
        if args.cmd != "plan":
            raise
        print(f"goal: the plan has the wrong shape: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
