#!/bin/bash
# git-remote-check.sh — SessionStart warning: local work with nowhere to go
# ─────────────────────────────────────────────────────────────────────────────
# IMP-122 (2026-08-01). Generalises a concrete near-miss: the Projekt B project sat
# at 157 unpushed commits on a feature branch with ZERO git remotes and 12
# uncommitted paths, some untouched for 11 days — while being the single most
# active codebase in the observation window (769 signals, 53% of all activity).
# One disk failure would have taken all of it. Nothing in the framework noticed,
# because no check ever looked at whether a repo has anywhere to push to.
#
# Non-blocking by design (always exit 0), matching git-identity-check.sh and
# sandbox-guard.sh. Adding a remote is an ESCALATE-band, externally-visible act
# (agency-bands.md) — the user decides; this hook only makes the exposure
# visible while it is still cheap to fix.
#
# Cost: 3 local git plumbing calls, no network. Same order as the git config
# lookups git-identity-check.sh already does at every session start.
#
# Env:
#   CLAUDE_NOREMOTE_WARN_COMMITS   commit threshold (default 20)
#   CLAUDE_NOREMOTE_CHECK_OFF=1    disable entirely
set -u

[ "${CLAUDE_NOREMOTE_CHECK_OFF:-0}" = "1" ] && exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# A repo with no commits yet has nothing to lose — and `rev-list HEAD` would
# fail there. Mirrors the no-repo guard in git-identity-check.sh.
git rev-parse HEAD >/dev/null 2>&1 || exit 0

REMOTES=$(git remote 2>/dev/null | wc -l | tr -d ' ')
[ "$REMOTES" -gt 0 ] && exit 0     # has somewhere to push → not this hook's problem

THRESHOLD="${CLAUDE_NOREMOTE_WARN_COMMITS:-20}"
case "$THRESHOLD" in ''|*[!0-9]*) THRESHOLD=20 ;; esac

# `rev-list --count HEAD` exits non-zero on an unborn branch; already guarded
# above, but keep the fallback so the hook can never abort a session start.
COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo 0)
case "$COMMITS" in ''|*[!0-9]*) COMMITS=0 ;; esac

[ "$COMMITS" -lt "$THRESHOLD" ] && exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "?")

echo "⚠️  NO GIT REMOTE — this work exists only on this disk."
echo "    repo: $ROOT"
echo "    branch '$BRANCH' · $COMMITS commits · $DIRTY uncommitted path(s) · 0 remotes"
echo "    A single disk failure loses all of it. Committing does NOT protect against that."
echo "    Fix: create a repo and push, e.g."
echo "      gh repo create <owner>/<name> --private --source=. --push"
echo "    (Silence for this repo: CLAUDE_NOREMOTE_CHECK_OFF=1, or raise CLAUDE_NOREMOTE_WARN_COMMITS=$THRESHOLD)"

exit 0
